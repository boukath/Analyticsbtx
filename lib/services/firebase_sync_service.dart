// lib/services/firebase_sync_service.dart

import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/people_count.dart';
import '../core/data_aggregator.dart'; // 🚀 Add this import

class FirebaseSyncService {
  static Timer? _scheduleTimer;

  // Flags to ensure we only sync exactly once per scheduled hour
  static bool _hasSynced14 = false;
  static bool _hasSynced22 = false;

  /// Starts the background clock to watch for 14:00 and 22:00
  static void startScheduledSync(Future<void> Function() onSyncRequested) {
    _scheduleTimer?.cancel();
    debugPrint("🕒 FirebaseSyncService: Scheduled sync started. Waiting for 14:00 and 22:00...");

    // Check the time every 1 minute
    _scheduleTimer = Timer.periodic(const Duration(minutes: 1), (timer) async {
      final now = DateTime.now();

      // Trigger at 2:00 PM (14:00)
      if (now.hour == 14 && now.minute == 0 && !_hasSynced14) {
        _hasSynced14 = true;
        debugPrint("🚀 FirebaseSyncService: 14:00 Sync Triggered!");
        await onSyncRequested();
      }
      // Trigger at 10:00 PM (22:00)
      else if (now.hour == 22 && now.minute == 0 && !_hasSynced22) {
        _hasSynced22 = true;
        debugPrint("🚀 FirebaseSyncService: 22:00 Sync Triggered!");
        await onSyncRequested();
      }

      // Reset the flags at midnight for the next day
      if (now.hour == 0) {
        _hasSynced14 = false;
        _hasSynced22 = false;
      }
    });
  }

  // 🚀 CHANGED: Accepts perDoorData instead of hourlyData
  static Future<void> uploadDailySummary({
    required Map<String, List<PeopleCount>> perDoorData,
    required int totalIn,
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
      // 🚀 THE FIX: Create the Parent Documents so they aren't "Ghosts"
      // =======================================================================

      // 1. Explicitly create/update the Client document
      await FirebaseFirestore.instance
          .collection('clients')
          .doc(clientId)
          .set({
        'last_active': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));

      // 2. Explicitly create/update the Store document inside the client
      await FirebaseFirestore.instance
          .collection('clients').doc(clientId)
          .collection('stores').doc(specificStoreId)
          .set({
        'brand': brandName,
        'location': locationName,
        'last_active': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));

      // =======================================================================

      final now = DateTime.now();
      String dateKey = "${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}";
      bool syncDetailedCameras = prefs.getBool('sync_individual_cameras') ?? false;

      // 🚀 NEW: Format the hourly traffic data for EACH individual camera
      Map<String, dynamic> camerasPayload = {};

      if (syncDetailedCameras) {
        // 🔹 PREMIUM MODE: Upload every camera individually
        perDoorData.forEach((doorName, counts) {
          Map<String, dynamic> hourlyMap = {};
          var hourly = DataAggregator.aggregateByHour(counts);
          for (var item in hourly) {
            hourlyMap[item.time] = {'in': item.inCount, 'out': item.outCount};
          }
          camerasPayload[doorName] = hourlyMap;
        });
      } else {
        // 🔹 STANDARD MODE: Merge everything to save Firebase space!
        List<PeopleCount> allMergedData = [];
        perDoorData.forEach((doorName, counts) {
          allMergedData.addAll(counts);
        });

        Map<String, dynamic> hourlyMap = {};
        var hourly = DataAggregator.aggregateByHour(allMergedData);
        for (var item in hourly) {
          hourlyMap[item.time] = {'in': item.inCount, 'out': item.outCount};
        }

        // Save it under a single generic key
        camerasPayload['All Doors'] = hourlyMap;
      }

      Map<String, dynamic> payload = {
        'date': dateKey,
        'last_updated': FieldValue.serverTimestamp(),
        'total_in': totalIn,
        'total_out': totalOut,
        'cameras': camerasPayload, // Pushing the optimized map!
      };

      if (posDataForToday != null) {
        payload['pos'] = {
          'ca': posDataForToday['ca'] ?? 0,
          'clients': posDataForToday['clients'] ?? 0,
          'articles': posDataForToday['articles'] ?? 0,
        };
      }

      // Finally, push the actual daily traffic data
      await FirebaseFirestore.instance
          .collection('clients').doc(clientId)
          .collection('stores').doc(specificStoreId)
          .collection('daily_traffic').doc(dateKey)
          .set(payload, SetOptions(merge: true));

      debugPrint("✅ FirebaseSyncService: Successfully synced multi-camera data!");
    } catch (e) {
      debugPrint("❌ FirebaseSyncService: Failed to sync: $e");
    }
  }

  static void stopScheduledSync() {
    _scheduleTimer?.cancel();
  }
}