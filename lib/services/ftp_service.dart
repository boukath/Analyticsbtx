// lib/services/ftp_service.dart

import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
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

  // --- NEW: Live Metrics State ---
  static int _filesReceivedToday = 0;
  static int _bytesTransferredToday = 0;
  static final Map<String, DateTime> _lastCameraActivity = {};
  static int _currentDay = DateTime.now().day;
  static Timer? _metricsCleanupTimer;

  static final StreamController<Map<String, dynamic>> _metricsController = StreamController<Map<String, dynamic>>.broadcast();
  static Stream<Map<String, dynamic>> get metricsStream => _metricsController.stream;

  static void log(String message) {
    final time = DateTime.now().toString().split('.').first;
    _logController.add("[$time] $message");
    debugPrint("FTP LOG: $message");
  }

  // --- NEW: Metrics Logic ---
  static void _emitMetrics() {
    final now = DateTime.now();
    // Daily reset
    if (now.day != _currentDay) {
      _filesReceivedToday = 0;
      _bytesTransferredToday = 0;
      _lastCameraActivity.clear();
      _currentDay = now.day;
    }

    // Remove cameras that haven't sent a file in the last 15 minutes
    _lastCameraActivity.removeWhere((camera, lastSeen) => now.difference(lastSeen).inMinutes > 15);

    // Broadcast the fresh data to the UI
    _metricsController.add({
      'files': _filesReceivedToday,
      'bytes': _bytesTransferredToday,
      'activeCameras': _lastCameraActivity.length,
    });
  }

  static Future<void> _recordFileMetric(File file) async {
    try {
      _filesReceivedToday++;
      _bytesTransferredToday += await file.length();

      // The parent folder name is the camera name (e.g., "sas1")
      String cameraName = file.parent.path.split(Platform.pathSeparator).last;
      _lastCameraActivity[cameraName] = DateTime.now();

      _emitMetrics();
    } catch (e) {
      log("Error recording metrics: $e");
    }
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

  static Future<List<String>> getAllLocalIpAddresses() async {
    List<String> ips = [];
    try {
      for (var interface in await NetworkInterface.list()) {
        for (var addr in interface.addresses) {
          if (addr.type == InternetAddressType.IPv4 && !addr.isLoopback) {
            ips.add(addr.address);
          }
        }
      }
    } catch (e) {
      log("Error fetching IPs: $e");
    }
    if (ips.isEmpty) ips.add("127.0.0.1");
    return ips;
  }

  static Future<String> getLocalIpAddress() async {
    List<String> ips = await getAllLocalIpAddresses();

    for (String ip in ips) {
      if (ip.startsWith('192.168.') && !ip.startsWith('192.168.56.')) return ip;
      if (ip.startsWith('10.')) return ip;
      if (ip.startsWith('172.')) return ip;
    }
    return ips.first;
  }

  static Timer? _ipMonitorTimer;
  static bool _isAlertShowing = false;

  static void startIpMonitor(GlobalKey<NavigatorState> navKey) {
    _ipMonitorTimer?.cancel();

    _ipMonitorTimer = Timer.periodic(const Duration(seconds: 30), (timer) async {
      final prefs = await SharedPreferences.getInstance();
      String expectedIp = prefs.getString('ftp_ip') ?? '';

      if (expectedIp.isEmpty) return;

      List<String> actualIps = await getAllLocalIpAddresses();

      if (!actualIps.contains(expectedIp)) {
        String displayActualIp = actualIps.length == 1 && actualIps.first == "127.0.0.1"
            ? "DISCONNECTED (No Network)"
            : actualIps.join(", ");

        log("❌ CRITICAL: IP mismatch. Expected $expectedIp, but available IPs are: $displayActualIp");
        _showIpAlert(navKey, expectedIp, displayActualIp);
      }
    });
  }

  static void _showIpAlert(GlobalKey<NavigatorState> navKey, String expectedIp, String actualIp) {
    if (_isAlertShowing) return;

    final context = navKey.currentContext;
    if (context != null) {
      _isAlertShowing = true;
      showDialog(
        context: context,
        barrierDismissible: false,
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
                  "Current IP(s): \n$actualIp\n\n"
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

      // Start the metrics background cleanup timer
      _metricsCleanupTimer = Timer.periodic(const Duration(minutes: 1), (_) => _emitMetrics());

      _directoryWatcher = Directory(rootDirectory).watch(recursive: true).listen((event) async {
        if (event is! FileSystemCreateEvent && event is! FileSystemModifyEvent) return;

        String fileName = event.path.split(Platform.pathSeparator).last;

        if (!fileName.startsWith('.') && fileName.endsWith('.scb')) {
          log("📁 Camera uploading: $fileName");

          File uploadedFile = File(event.path);
          bool isComplete = await _waitForFileCompletion(uploadedFile);

          if (isComplete) {
            log("✅ Camera file received successfully: $fileName");
            // 🚀 Record the metric immediately after a successful receipt
            await _recordFileMetric(uploadedFile);
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
        _metricsCleanupTimer?.cancel();
        log("🛑 Server offline.");
      } catch (e) {
        log("❌ Error stopping FTP: $e");
      }
      _ftpServer = null;
    }
  }

  static Future<void> requestFirewallException() async {
    if (!Platform.isWindows) {
      log("Firewall configuration is only required on Windows.");
      return;
    }

    try {
      log("Requesting Windows Firewall exception...");
      String exePath = Platform.resolvedExecutable;
      String netshCommand = 'advfirewall firewall add rule name="Store Traffic Analytics FTP" dir=in action=allow program="$exePath" enable=yes';
      String psCommand = 'Start-Process netsh -ArgumentList \'$netshCommand\' -Verb RunAs -WindowStyle Hidden';

      var result = await Process.run('powershell', ['-Command', psCommand]);

      if (result.exitCode == 0) {
        log("✅ Firewall rule successfully added! FTP traffic is now allowed.");
      } else {
        log("❌ Failed to add firewall rule. User may have denied the Admin prompt.");
      }
    } catch (e) {
      log("❌ Error configuring firewall: $e");
    }
  }

  static bool get isRunning => _ftpServer != null;
}