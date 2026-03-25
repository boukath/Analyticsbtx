// lib/services/firebase_sync_service.dart

import 'dart:async';
import 'dart:convert'; // 🚀 Required for JSON decoding POS data
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/people_count.dart';
import '../core/data_aggregator.dart';
import 'folder_scanner_service.dart';

class FirebaseSyncService {
  static Timer? _scheduleTimer;

  // A dynamic map to track which specific times have been synced today
  static Map<String, bool> _syncedToday = {};
  // Track the current day to know when midnight happens
  static int _lastResetDay = DateTime.now().day;

  /// Starts the background clock to watch for dynamic scheduled times
  static void startScheduledSync(Future<void> Function() onSyncRequested) {
    _scheduleTimer?.cancel();
    debugPrint("🕒 FirebaseSyncService: Dynamic scheduled sync started.");

    // Check the time every 1 minute
    _scheduleTimer = Timer.periodic(const Duration(minutes: 1), (timer) async {
      final now = DateTime.now();

      // 🔄 MIDNIGHT RESET
      // If the day has changed, clear the memory of what was synced so it can run again today
      if (now.day != _lastResetDay) {
        _syncedToday.clear();
        _lastResetDay = now.day;
        debugPrint("🔄 FirebaseSyncService: Daily flags reset. Ready for today's syncs.");
      }

      // 🚀 LOAD CUSTOM TIMES
      final prefs = await SharedPreferences.getInstance();
      // Default to 14:00 and 22:00 if the user hasn't set anything up yet
      List<String> savedTimes = prefs.getStringList('sync_times') ?? ['14:00', '22:00'];

      // Check each saved time against the current clock
      for (String timeStr in savedTimes) {
        var parts = timeStr.split(':');
        if (parts.length == 2) {
          int targetHour = int.tryParse(parts[0]) ?? 0;
          int targetMinute = int.tryParse(parts[1]) ?? 0;

          // Has the clock passed this specific target time?
          bool isPastTarget = (now.hour > targetHour) || (now.hour == targetHour && now.minute >= targetMinute);

          // If we passed the time, AND we haven't synced for this specific time today, do it!
          if (isPastTarget && !(_syncedToday[timeStr] ?? false)) {
            _syncedToday[timeStr] = true; // Mark this specific time slot as done
            debugPrint("🚀 FirebaseSyncService: Auto-sync triggered for $timeStr window!");
            await onSyncRequested();
          }
        }
      }
    });
  }

  // 🚀 NEW HELPER: Formats SCB Date "DD/MM/YY" into Firebase Document Date "YYYY-MM-DD"
  static String _formatDateToIso(String dateStr) {
    try {
      var parts = dateStr.split('/');
      if (parts.length == 3) {
        int day = int.parse(parts[0]);
        int month = int.parse(parts[1]);
        int year = int.parse(parts[2]);
        if (year < 100) year += 2000;
        return "$year-${month.toString().padLeft(2, '0')}-${day.toString().padLeft(2, '0')}";
      }
      DateTime parsed = DateTime.parse(dateStr);
      return "${parsed.year}-${parsed.month.toString().padLeft(2, '0')}-${parsed.day.toString().padLeft(2, '0')}";
    } catch (e) {
      final now = DateTime.now();
      return "${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}";
    }
  }

  // =======================================================================
  // 🚀 NEW: THE FULL HISTORY SYNC FIX
  // This bypasses the UI and reads your whole 'comptage' folder directly!
  // =======================================================================
  static Future<void> syncFullFolderHistory(String folderPath) async {
    try {
      debugPrint("📁 Scanning entire folder for historical data: $folderPath");

      // 🚀 1. NEW: Grab POS data automatically from SharedPreferences!
      final prefs = await SharedPreferences.getInstance();
      Map<String, dynamic>? posDataForToday;
      bool enablePos = prefs.getBool('enable_pos_features') ?? true;

      if (enablePos) {
        final String? posJson = prefs.getString('pos_database');
        if (posJson != null) {
          final now = DateTime.now();
          // Match the exact format used in dashboard_windows.dart
          String todayKey = "${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}";

          Map<String, dynamic> fullPosDb = jsonDecode(posJson);
          if (fullPosDb.containsKey(todayKey)) {
            posDataForToday = fullPosDb[todayKey];
            debugPrint("🛒 Found POS data for today: $posDataForToday");
          }
        }
      }

      // 2. Read every single .scb file in the folder (and subfolders)
      FolderScannerService scanner = FolderScannerService();
      List<PeopleCount> allHistoricalData = await scanner.loadScbDataFromFolder(folderPath);

      if (allHistoricalData.isEmpty) {
        debugPrint("⚠️ No data found in the folder.");
        return;
      }

      // 3. Group the massive list of raw data by camera (doorName)
      Map<String, List<PeopleCount>> allDataPerDoor = {};
      for (var data in allHistoricalData) {
        allDataPerDoor.putIfAbsent(data.doorName, () => []);
        allDataPerDoor[data.doorName]!.add(data);
      }

      // 4. Pass ALL the data into our perfected upload logic!
      await uploadDailySummary(
        perDoorData: allDataPerDoor,
        totalIn: 0,  // The logic inside dynamically recalculates this anyway!
        totalOut: 0,
        posDataForToday: posDataForToday, // 🚀 FIXED: Now passing actual POS data!
      );

      debugPrint("✅ Full historical folder sync complete!");
    } catch (e) {
      debugPrint("❌ Failed to sync folder history: $e");
    }
  }

  // 🚀 FIXED: Now extracts the actual date from the data to support historical uploads!
  static Future<void> uploadDailySummary({
    required Map<String, List<PeopleCount>> perDoorData,
    required int totalIn,   // Kept to avoid breaking changes in other files calling this
    required int totalOut,
    required Map<String, dynamic>? posDataForToday,
  }) async {
    try {
      final prefs = await SharedPreferences.getInstance();

      // Sanitizing the client ID to prevent capitalization or space errors
      String rawClientId = prefs.getString('firebase_client_id') ?? '';
      String clientId = rawClientId.trim().replaceAll(' ', '_').toLowerCase();
      String brandName = prefs.getString('store_name') ?? 'Unknown Brand';
      String locationName = prefs.getString('store_location') ?? 'Unknown Location';

      if (clientId.isEmpty) return;

      String specificStoreId = "${brandName}_$locationName".replaceAll(' ', '_').toLowerCase();

      // =======================================================================
      // 🚀 CREATE PARENT DOCUMENTS
      // =======================================================================
      await FirebaseFirestore.instance
          .collection('clients')
          .doc(clientId)
          .set({
        'last_active': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));

      await FirebaseFirestore.instance
          .collection('clients').doc(clientId)
          .collection('stores').doc(specificStoreId)
          .set({
        'brand': brandName,
        'location': locationName,
        'last_active': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));

      // =======================================================================
      // 🚀 PROCESS HISTORICAL DATA
      // =======================================================================
      bool syncDetailedCameras = prefs.getBool('sync_individual_cameras') ?? false;

      // Map structure: payloadsByDate["2024-03-15"]["Camera Name"]["14:00"] = {'in': X, 'out': Y}
      Map<String, Map<String, Map<String, dynamic>>> payloadsByDate = {};
      Map<String, int> dailyTotalIn = {};
      Map<String, int> dailyTotalOut = {};

      if (syncDetailedCameras) {
        // 🔹 INDIVIDUAL CAMERAS MODE
        perDoorData.forEach((doorName, counts) {
          String niceCameraName = prefs.getString('camera_name_$doorName') ?? doorName.toUpperCase();
          var hourly = DataAggregator.aggregateByHour(counts);

          for (var item in hourly) {
            String docDate = _formatDateToIso(item.date); // Gets the exact historical date!

            payloadsByDate.putIfAbsent(docDate, () => {});
            payloadsByDate[docDate]!.putIfAbsent(niceCameraName, () => {});

            payloadsByDate[docDate]![niceCameraName]![item.time] = {
              'in': item.inCount,
              'out': item.outCount
            };

            dailyTotalIn[docDate] = (dailyTotalIn[docDate] ?? 0) + item.inCount;
            dailyTotalOut[docDate] = (dailyTotalOut[docDate] ?? 0) + item.outCount;
          }
        });
      } else {
        // 🔹 ALL DOORS MERGED MODE
        List<PeopleCount> allMergedData = [];
        perDoorData.forEach((doorName, counts) {
          allMergedData.addAll(counts);
        });

        var hourly = DataAggregator.aggregateByHour(allMergedData);
        for (var item in hourly) {
          String docDate = _formatDateToIso(item.date); // Gets the exact historical date!

          payloadsByDate.putIfAbsent(docDate, () => {});
          payloadsByDate[docDate]!.putIfAbsent('All Doors', () => {});

          payloadsByDate[docDate]!['All Doors']![item.time] = {
            'in': item.inCount,
            'out': item.outCount
          };

          dailyTotalIn[docDate] = (dailyTotalIn[docDate] ?? 0) + item.inCount;
          dailyTotalOut[docDate] = (dailyTotalOut[docDate] ?? 0) + item.outCount;
        }
      }

      final now = DateTime.now();
      String todayKey = "${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}";

      // =======================================================================
      // 🚀 UPLOAD TO FIREBASE BY DATE
      // =======================================================================
      // Loop through all discovered dates and push them to their own document!
      for (String dateDocKey in payloadsByDate.keys) {
        Map<String, dynamic> payload = {
          'date': dateDocKey,
          'last_updated': FieldValue.serverTimestamp(),
          'total_in': dailyTotalIn[dateDocKey] ?? 0, // Accurate total for this specific day
          'total_out': dailyTotalOut[dateDocKey] ?? 0,
          'cameras': payloadsByDate[dateDocKey],
        };

        // Only attach POS data if the document being written belongs to today
        if (dateDocKey == todayKey && posDataForToday != null) {
          payload['pos'] = {
            'ca': posDataForToday['ca'] ?? 0,
            'clients': posDataForToday['clients'] ?? 0,
            'articles': posDataForToday['articles'] ?? 0,
          };
        }

        // Push to Firebase under the correct Historical Date Document!
        await FirebaseFirestore.instance
            .collection('clients').doc(clientId)
            .collection('stores').doc(specificStoreId)
            .collection('daily_traffic').doc(dateDocKey)
            .set(payload, SetOptions(merge: true));
      }

      debugPrint("✅ FirebaseSyncService: Successfully synced historical data for ${payloadsByDate.length} days!");
    } catch (e) {
      debugPrint("❌ FirebaseSyncService: Failed to sync: $e");
    }
  }

  static void stopScheduledSync() {
    _scheduleTimer?.cancel();
  }
}