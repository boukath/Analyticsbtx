// lib/services/ftp_service.dart

import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart'; // NEW: Required for the pop-up alert
import 'package:ftp_server/ftp_server.dart';
import 'package:ftp_server/file_operations/physical_file_operations.dart';
import 'package:ftp_server/server_type.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'b2_cloud_service.dart';

class FtpService {
  static FtpServer? _ftpServer;
  static StreamSubscription? _directoryWatcher;

  static final StreamController<String> _logController = StreamController<String>.broadcast();
  static Stream<String> get logStream => _logController.stream;

  static void log(String message) {
    final time = DateTime.now().toString().split('.').first;
    _logController.add("[$time] $message");
    debugPrint("FTP LOG: $message");
  }

  static Future<bool> _waitForFileCompletion(File file) async {
    int previousSize = -1;
    int stableCount = 0;
    int maxAttempts = 60;

    for (int i = 0; i < maxAttempts; i++) {
      if (!await file.exists()) return false;
      int currentSize = await file.length();
      if (currentSize == previousSize && currentSize > 0) {
        stableCount++;
        if (stableCount >= 3) return true;
      } else {
        stableCount = 0;
        previousSize = currentSize;
      }
      await Future.delayed(const Duration(milliseconds: 500));
    }
    return false;
  }

  // --- NEW: IP Security Monitor ---
  static Timer? _ipMonitorTimer;
  static bool _isAlertShowing = false;

  static void startIpMonitor(GlobalKey<NavigatorState> navKey) {
    _ipMonitorTimer?.cancel();

    // Check the IP address every 30 seconds
    _ipMonitorTimer = Timer.periodic(const Duration(seconds: 30), (timer) async {
      final prefs = await SharedPreferences.getInstance();
      String expectedIp = prefs.getString('ftp_ip') ?? '';

      // If no IP is saved yet, skip checking
      if (expectedIp.isEmpty) return;

      String actualIp = await getLocalIpAddress();

      // If the current IP doesn't match what the technician saved...
      if (actualIp != expectedIp) {
        String displayActualIp = actualIp == "127.0.0.1" ? "DISCONNECTED (No Network)" : actualIp;

        log("❌ CRITICAL: IP mismatch. Expected $expectedIp, got $displayActualIp");
        _showIpAlert(navKey, expectedIp, displayActualIp);
      }
    });
  }

  // --- NEW: Show Emergency Pop-up Dialog ---
  static void _showIpAlert(GlobalKey<NavigatorState> navKey, String expectedIp, String actualIp) {
    if (_isAlertShowing) return; // Prevent spamming multiple pop-ups

    final context = navKey.currentContext;
    if (context != null) {
      _isAlertShowing = true;
      showDialog(
        context: context,
        barrierDismissible: false, // Forces the user to click the button
        builder: (BuildContext c) {
          return AlertDialog(
            backgroundColor: const Color(0xFF1E293B),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16), side: const BorderSide(color: Colors.redAccent, width: 2)),
            title: const Row(
              children: [
                Icon(Icons.warning_amber_rounded, color: Colors.redAccent, size: 32),
                SizedBox(width: 12),
                Text("CRITICAL NETWORK ERROR", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
              ],
            ),
            content: Text(
              "The PC's IP Address has changed or network is disconnected!\n\n"
                  "Expected IP: $expectedIp\n"
                  "Current IP: $actualIp\n\n"
                  "Your cameras are currently BLIND and cannot send data to this software.\n\n"
                  "Please contact Boitex Info immediately to reconfigure your network.",
              style: const TextStyle(color: Colors.white70, fontSize: 16, height: 1.5),
            ),
            actions: [
              TextButton(
                onPressed: () {
                  _isAlertShowing = false;
                  Navigator.of(c).pop();
                },
                child: const Text("I UNDERSTAND", style: TextStyle(color: Colors.redAccent, fontWeight: FontWeight.bold, letterSpacing: 1)),
              ),
            ],
          );
        },
      );
    }
  }

  static Future<void> autoStart() async {
    final prefs = await SharedPreferences.getInstance();
    String? rootDir = prefs.getString('saved_data_folder');

    if (rootDir == null || rootDir.isEmpty) {
      log("⚠️ Auto-start skipped: No target directory configured.");
      return;
    }

    int port = prefs.getInt('ftp_port') ?? 2121;
    String user = prefs.getString('ftp_user') ?? "camera";
    String pass = prefs.getString('ftp_pass') ?? "password";

    log("🔄 Auto-starting FTP Server on boot...");
    await startServer(
      rootDirectory: rootDir,
      port: port,
      username: user,
      password: pass,
    );
  }

  static Future<void> startServer({
    required String rootDirectory,
    required int port,
    required String username,
    required String password,
  }) async {
    try {
      await stopServer();

      log("Initializing FTP Server...");
      log("Target Directory: $rootDirectory");

      final fileOps = PhysicalFileOperations(rootDirectory);

      _ftpServer = FtpServer(
        port,
        username: username,
        password: password,
        fileOperations: fileOps,
        serverType: ServerType.readAndWrite,
      );

      await _ftpServer!.startInBackground();
      log("✅ Server active and listening on Port $port");
      log("👤 Authenticating as user: '$username'");
      log("⏳ Waiting for camera connections...");

      _directoryWatcher = Directory(rootDirectory).watch(recursive: true).listen((event) async {
        if (event is! FileSystemCreateEvent && event is! FileSystemModifyEvent) return;

        String fileName = event.path.split(Platform.pathSeparator).last;

        if (!fileName.startsWith('.') && fileName.endsWith('.scb')) {
          log("📁 Camera uploading: $fileName");

          File uploadedFile = File(event.path);
          bool isComplete = await _waitForFileCompletion(uploadedFile);

          if (isComplete) {
            log("✅ File writing complete. Preparing for cloud sync...");
            await B2CloudService.uploadScbFile(uploadedFile, "LiveSync");
          } else {
            log("❌ File upload timed out or failed: $fileName");
          }
        }
      });

    } catch (e) {
      log("❌ Failed to start FTP Server: $e");
    }
  }

  static Future<void> stopServer() async {
    if (_ftpServer != null) {
      try {
        log("Stopping FTP Server...");
        _ftpServer!.stop();
        _directoryWatcher?.cancel();
        log("🛑 Server offline.");
      } catch (e) {
        log("❌ Error stopping FTP: $e");
      }
      _ftpServer = null;
    }
  }

  static Future<String> getLocalIpAddress() async {
    try {
      for (var interface in await NetworkInterface.list()) {
        for (var addr in interface.addresses) {
          if (addr.type == InternetAddressType.IPv4 && !addr.isLoopback) {
            return addr.address;
          }
        }
      }
    } catch (e) {
      return "127.0.0.1";
    }
    return "127.0.0.1";
  }

  static bool get isRunning => _ftpServer != null;
}