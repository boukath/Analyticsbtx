// lib/services/b2_cloud_service.dart

import 'dart:async';
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/foundation.dart';
import 'package:minio/minio.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:path/path.dart' as path;

class B2CloudService {
  static Minio? _minio;
  static String? _bucketName;
  static bool _isEnabled = false;

  // --- Auto-Sync Timer & Cache Variables ---
  static Timer? _autoSyncTimer;
  static bool _isAutoSyncing = false;
  static Set<String> _syncedFilesCache = {};

  // NEW: Variable to remember the last time we performed a scheduled sync
  static DateTime? _lastSyncTime;

  static final StreamController<String> _logController = StreamController<String>.broadcast();
  static Stream<String> get logStream => _logController.stream;

  static void log(String message) {
    final time = DateTime.now().toString().split('.').first;
    _logController.add("[$time] $message");
    debugPrint("B2 LOG: $message");
  }

  /// Initializes the B2 connection and starts the auto-sync timer
  static Future<void> initialize() async {
    final prefs = await SharedPreferences.getInstance();
    _isEnabled = prefs.getBool('b2_enabled') ?? false;

    // Load our smart cache of already uploaded files
    _syncedFilesCache = (prefs.getStringList('b2_synced_files_cache') ?? []).toSet();

    if (!_isEnabled) {
      log("⏸️ Cloud sync is disabled. Stopping auto-sync.");
      _autoSyncTimer?.cancel();
      return;
    }

    String endpoint = prefs.getString('b2_endpoint') ?? '';
    String accessKey = prefs.getString('b2_access_key') ?? '';
    String secretKey = prefs.getString('b2_secret_key') ?? '';
    _bucketName = (prefs.getString('b2_bucket') ?? '').toLowerCase();

    endpoint = endpoint.replaceAll('https://', '').replaceAll('http://', '');

    if (endpoint.isNotEmpty && accessKey.isNotEmpty && secretKey.isNotEmpty && _bucketName!.isNotEmpty) {
      try {
        _minio = Minio(
          endPoint: endpoint,
          accessKey: accessKey,
          secretKey: secretKey,
          useSSL: true,
        );
        log("✅ B2 Client Initialized. Ready to sync to '$_bucketName'.");

        // START THE BACKGROUND AUTOSYNC
        _startAutoSyncTimer();

      } catch (e) {
        log("❌ Initialization Error: $e");
      }
    } else {
      log("⚠️ Missing credentials. Please fill out all fields.");
    }
  }

  // --- OPTIMIZED: The Scheduled Background Timer ---
  static void _startAutoSyncTimer() {
    _autoSyncTimer?.cancel();
    if (_isEnabled) {
      log("⏱️ Scheduled Auto-Sync activated (Will upload only at 14:00 and 22:00 to optimize cloud costs).");

      // Wake up every 1 minute to check the clock
      _autoSyncTimer = Timer.periodic(const Duration(minutes: 1), (_) {
        DateTime now = DateTime.now();

        // Target hours: 14 (2 PM) and 22 (10 PM)
        bool isSyncHour = (now.hour == 14 || now.hour == 22);

        // Did we already sync during this specific hour today?
        bool alreadySyncedThisHour = _lastSyncTime != null &&
            _lastSyncTime!.hour == now.hour &&
            _lastSyncTime!.day == now.day &&
            _lastSyncTime!.month == now.month &&
            _lastSyncTime!.year == now.year;

        // If it's a target hour, and we haven't synced yet, DO IT!
        if (isSyncHour && !alreadySyncedThisHour) {
          log("⏳ Scheduled sync triggered for ${now.hour}:00...");
          _lastSyncTime = now; // Mark this hour as completed
          _runAutoSync();
        }
      });
    }
  }

  // --- The Auto-Sync Logic ---
  static Future<void> _runAutoSync() async {
    // Prevent overlapping
    if (_isAutoSyncing || !_isEnabled || _minio == null) return;

    _isAutoSyncing = true;

    try {
      final prefs = await SharedPreferences.getInstance();
      String savedFolder = prefs.getString('b2_sync_folder') ?? prefs.getString('saved_data_folder') ?? '';

      if (savedFolder.isEmpty) return; // No folder selected yet

      final dir = Directory(savedFolder);
      if (!await dir.exists()) return;

      // Scan all subfolders (sas1, sas2, etc)
      final files = dir.listSync(recursive: true)
          .whereType<File>()
          .where((f) => f.path.toLowerCase().endsWith('.scb'))
          .toList();

      int uploadedCount = 0;

      for (var file in files) {
        // Create a unique hash based on Path + Size.
        String cacheKey = "${file.path}_${file.lengthSync()}";

        if (!_syncedFilesCache.contains(cacheKey)) {
          // File is missing or was updated!
          bool success = await uploadScbFile(file, "AutoSync");
          if (success) {
            uploadedCount++;
          }
          // OPTIMIZED: Delay of 500ms prevents B2 rate limiting when syncing multiple stores
          await Future.delayed(const Duration(milliseconds: 500));
        }
      }

      if (uploadedCount > 0) {
        log("✅ Auto-Sync complete. Synced $uploadedCount new/updated files.");
      } else {
        log("✅ Auto-Sync complete. No new files needed uploading.");
      }

    } catch (e) {
      log("❌ Auto-Sync Error: $e");
    } finally {
      _isAutoSyncing = false;
    }
  }

  /// Tests the B2 connection
  static Future<bool> testConnection() async {
    if (_minio == null || _bucketName == null || _bucketName!.isEmpty) {
      log("❌ Cannot test: Please connect your credentials first.");
      return false;
    }
    try {
      final prefs = await SharedPreferences.getInstance();
      String folder1 = (prefs.getString('b2_folder1') ?? 'TEST_REGION').replaceAll(RegExp(r'[^a-zA-Z0-9\s_-]'), '').trim();
      String folder2 = (prefs.getString('b2_folder2') ?? 'TEST_STORE').replaceAll(RegExp(r'[^a-zA-Z0-9\s_-]'), '').trim();

      log("⏳ Generating test file...");
      String objectName = 'comptage/$folder1/$folder2/connection_test.txt';
      List<int> bytes = "Connection works!".codeUnits;
      Uint8List stream = Uint8List.fromList(bytes);

      log("☁️ Attempting to upload to bucket: '$_bucketName'...");
      await _minio!.putObject(_bucketName!, objectName, Stream.value(stream), size: stream.length);

      log("✅ TEST SUCCESS! File created at: $objectName");
      return true;
    } catch (e) {
      log("❌ TEST FAILED: $e");
      return false;
    }
  }

  /// Uploads the actual .scb file (Used by Live FTP, Auto-Sync, and Bulk Sync)
  static Future<bool> uploadScbFile(File file, String storeName) async {
    if (!_isEnabled || _minio == null || _bucketName == null) return false;

    try {
      final prefs = await SharedPreferences.getInstance();

      String folder1 = prefs.getString('b2_folder1') ?? 'Unknown';
      String folder2 = prefs.getString('b2_folder2') ?? 'Unknown';

      if (folder1.isEmpty) folder1 = 'Unknown_Region';
      if (folder2.isEmpty) folder2 = 'Unknown_Store';

      folder1 = folder1.replaceAll(RegExp(r'[^a-zA-Z0-9\s_-]'), '').trim();
      folder2 = folder2.replaceAll(RegExp(r'[^a-zA-Z0-9\s_-]'), '').trim();

      String cameraFolder = file.parent.path.split(Platform.pathSeparator).last;
      cameraFolder = cameraFolder.replaceAll(RegExp(r'[^a-zA-Z0-9\s_-]'), '').trim();

      String fileName = path.basename(file.path);
      String objectName = 'comptage/$folder1/$folder2/$cameraFolder/$fileName';

      log("☁️ Uploading $cameraFolder/$fileName...");

      final stream = file.openRead().cast<Uint8List>();
      final length = await file.length();

      await _minio!.putObject(_bucketName!, objectName, stream, size: length);

      // Save this successful upload to our smart cache
      String cacheKey = "${file.path}_$length";
      _syncedFilesCache.add(cacheKey);
      await prefs.setStringList('b2_synced_files_cache', _syncedFilesCache.toList());

      log("✅ Successfully synced: $objectName");
      return true;
    } catch (e) {
      log("❌ Upload Failed for ${path.basename(file.path)}: $e");
      return false;
    }
  }
}