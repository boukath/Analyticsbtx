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

  // --- NEW: Live Log Stream ---
  static final StreamController<String> _logController = StreamController<String>.broadcast();
  static Stream<String> get logStream => _logController.stream;

  static void log(String message) {
    final time = DateTime.now().toString().split('.').first;
    _logController.add("[$time] $message");
    debugPrint("B2 LOG: $message");
  }

  /// Initializes the B2 connection
  static Future<void> initialize() async {
    final prefs = await SharedPreferences.getInstance();
    _isEnabled = prefs.getBool('b2_enabled') ?? false;

    if (!_isEnabled) {
      log("⏸️ Cloud sync is currently disabled.");
      return;
    }

    String endpoint = prefs.getString('b2_endpoint') ?? '';
    String accessKey = prefs.getString('b2_access_key') ?? '';
    String secretKey = prefs.getString('b2_secret_key') ?? '';
    _bucketName = prefs.getString('b2_bucket') ?? '';

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
      } catch (e) {
        log("❌ Initialization Error: $e");
      }
    } else {
      log("⚠️ Missing credentials. Please fill out all fields.");
    }
  }

  /// NEW: Test Connection function
  static Future<bool> testConnection() async {
    if (_minio == null || _bucketName == null || _bucketName!.isEmpty) {
      log("❌ Cannot test: Please Save & Connect your credentials first.");
      return false;
    }

    try {
      log("⏳ Generating test file...");
      String objectName = 'comptage/SYSTEM_TEST/connection_test.txt';

      // Create a tiny text file in memory
      List<int> bytes = "If you are reading this, your B2 connection is working perfectly!".codeUnits;
      Uint8List stream = Uint8List.fromList(bytes);

      log("☁️ Attempting to upload to bucket: '$_bucketName'...");

      await _minio!.putObject(
        _bucketName!,
        objectName,
        Stream.value(stream),
        size: stream.length,
      );

      log("✅ TEST SUCCESS! File created at: $objectName");
      return true;
    } catch (e) {
      log("❌ TEST FAILED. Error details:");
      log(e.toString());
      return false;
    }
  }

  /// Uploads the actual .scb file from the camera
  static Future<void> uploadScbFile(File file, String storeName) async {
    if (!_isEnabled || _minio == null || _bucketName == null) {
      log("⚠️ Upload skipped: B2 not connected or disabled.");
      return;
    }

    try {
      String fileName = path.basename(file.path);
      String safeStoreName = storeName.replaceAll(RegExp(r'[^a-zA-Z0-9\s]'), '').trim();
      String objectName = 'comptage/$safeStoreName/$fileName';

      log("☁️ Uploading $fileName...");

      final stream = file.openRead().cast<Uint8List>();
      final length = await file.length();

      await _minio!.putObject(
        _bucketName!,
        objectName,
        stream,
        size: length,
      );

      log("✅ Successfully synced: $objectName");
    } catch (e) {
      log("❌ Upload Failed for ${path.basename(file.path)}: $e");
    }
  }
}