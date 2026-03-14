// lib/services/firebase_sync_service.dart

import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/people_count.dart';

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

  /// Pushes the aggregated dashboard data to Firebase Firestore
  static Future<void> uploadDailySummary({
    required List<PeopleCount> hourlyData,
    required int totalIn,
    required int totalOut,
    required Map<String, dynamic>? posDataForToday,
  }) async {
    try {
      final prefs = await SharedPreferences.getInstance();

      String storeId = prefs.getString('firebase_store_id') ?? '';
      String brandName = prefs.getString('store_name') ?? 'Unknown Brand';
      String locationName = prefs.getString('store_location') ?? 'Unknown Location';

      if (storeId.isEmpty) {
        debugPrint("⚠️ FirebaseSyncService: No Firebase Store ID configured. Skipping sync.");
        return;
      }

      // --- 1. UPDATE THE PARENT STORE DOCUMENT (Metadata) ---
      // This ensures your Web Dashboard always knows the latest Brand and Location names
      await FirebaseFirestore.instance.collection('stores').doc(storeId).set({
        'brand': brandName,
        'location': locationName,
        'last_active_sync': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));


      // --- 2. FORMAT THE HOURLY TRAFFIC DATA ---
      final now = DateTime.now();
      String dateKey = "${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}";

      Map<String, dynamic> hourlyMap = {};
      for (var item in hourlyData) {
        hourlyMap[item.time] = {
          'in': item.inCount,
          'out': item.outCount,
        };
      }

      Map<String, dynamic> payload = {
        'date': dateKey,
        'last_updated': FieldValue.serverTimestamp(),
        'total_in': totalIn,
        'total_out': totalOut,
        'hourly_data': hourlyMap,
      };

      // --- 3. ADD POS DATA (If Available) ---
      if (posDataForToday != null) {
        payload['pos'] = {
          'ca': posDataForToday['ca'] ?? 0,
          'clients': posDataForToday['clients'] ?? 0,
          'articles': posDataForToday['articles'] ?? 0,
        };
      }

      // --- 4. UPLOAD TO DAILY TRAFFIC SUB-COLLECTION ---
      await FirebaseFirestore.instance
          .collection('stores')
          .doc(storeId)
          .collection('daily_traffic')
          .doc(dateKey)
          .set(payload, SetOptions(merge: true));

      debugPrint("✅ FirebaseSyncService: Successfully synced data for $dateKey ($brandName - $locationName)!");

    } catch (e) {
      debugPrint("❌ FirebaseSyncService: Failed to sync to Firestore: $e");
    }
  }

  static void stopScheduledSync() {
    _scheduleTimer?.cancel();
  }
}