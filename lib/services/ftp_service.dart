// lib/services/ftp_service.dart

import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:ftp_server/ftp_server.dart';
import 'package:ftp_server/file_operations/physical_file_operations.dart';
import 'package:ftp_server/server_type.dart'; // NEW: Required for the ServerType setting

class FtpService {
  static FtpServer? _ftpServer;
  static StreamSubscription? _directoryWatcher;

  // A broadcast stream controller to send live logs to the UI console
  static final StreamController<String> _logController = StreamController<String>.broadcast();
  static Stream<String> get logStream => _logController.stream;

  /// Helper function to push logs to the UI
  static void log(String message) {
    final time = DateTime.now().toString().split('.').first; // Gets YYYY-MM-DD HH:MM:SS
    _logController.add("[$time] $message");
    debugPrint("FTP LOG: $message");
  }

  /// Starts the embedded FTP server with custom settings
  static Future<void> startServer({
    required String rootDirectory,
    required int port,
    required String username,
    required String password,
  }) async {
    try {
      await stopServer(); // Ensure any existing server is stopped first

      log("Initializing FTP Server...");
      log("Target Directory: $rootDirectory");

      final fileOps = PhysicalFileOperations(rootDirectory);

      _ftpServer = FtpServer(
        port,
        username: username,
        password: password,
        fileOperations: fileOps,
        serverType: ServerType.readAndWrite, // FIXED: Explicitly tell it to allow file uploads
      );

      await _ftpServer!.startInBackground();
      log("✅ Server active and listening on Port $port");
      log("👤 Authenticating as user: '$username'");
      log("⏳ Waiting for camera connections...");

      // Start watching the folder so we can log when the camera uploads a file!
      _directoryWatcher = Directory(rootDirectory).watch().listen((event) {
        String fileName = event.path.split(Platform.pathSeparator).last;
        // Ignore hidden files or temp files if you want
        if (!fileName.startsWith('.')) {
          // FIXED: Removed the .name property that was causing the build crash
          log("📁 File Activity: $fileName");
        }
      });

    } catch (e) {
      log("❌ Failed to start FTP Server: $e");
    }
  }

  /// Stops the FTP server and the folder watcher
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

  /// Gets the true local IP address
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

  /// Checks if server is currently running
  static bool get isRunning => _ftpServer != null;
}