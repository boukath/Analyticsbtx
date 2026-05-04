// lib/services/http_server_service.dart

import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';

class HttpServerService {
  static HttpServer? _server;
  static final StreamController<String> _logController = StreamController<String>.broadcast();

  // Expose the log stream so the UI can listen to it, exactly like the FTP service
  static Stream<String> get logStream => _logController.stream;

  static void log(String message) {
    final time = DateTime.now().toString().split('.').first;
    _logController.add("[$time] $message");
    debugPrint("HTTP LOG: $message");
  }

  /// Starts the HTTP Server to listen for camera POST requests
  static Future<void> startServer({
    required String rootDirectory,
    required int port,
  }) async {
    try {
      await stopServer(); // Ensure no previous instances are running
      log("Initializing HTTP Server...");

      // Bind to all available network interfaces so cameras can reach it
      _server = await HttpServer.bind(InternetAddress.anyIPv4, port);

      log("✅ HTTP Server active and listening on Port $port");
      log("📂 Target Directory: $rootDirectory");
      log("⏳ Waiting for camera HTTP connections...");

      // Listen for incoming requests continuously
      _server!.listen((HttpRequest request) {
        _handleRequest(request, rootDirectory);
      });
    } catch (e) {
      log("❌ Failed to start HTTP Server: $e");
    }
  }

  /// Processes individual incoming HTTP requests from the cameras
  static Future<void> _handleRequest(HttpRequest request, String rootDirectory) async {
    // We only want to accept POST requests, as the camera is pushing data
    if (request.method == 'POST') {
      try {
        // 1. Extract the camera folder name from the URL (e.g., "/sas1" becomes "sas1")
        String cameraFolder = request.uri.path.replaceAll('/', '').trim();
        if (cameraFolder.isEmpty) {
          cameraFolder = 'unknown_camera';
        }

        // 2. Ensure the specific camera subfolder exists
        Directory targetDir = Directory('$rootDirectory${Platform.pathSeparator}$cameraFolder');
        if (!await targetDir.exists()) {
          await targetDir.create(recursive: true);
        }

        // 3. 🚀 FIXED: Read the incoming bytes directly from the HttpRequest stream
        final List<int> bytes = [];
        await for (var chunk in request) {
          bytes.addAll(chunk);
        }

        // 4. Generate a unique filename (using a timestamp to prevent overwriting)
        String fileName = "${DateTime.now().millisecondsSinceEpoch}.scb";
        File file = File('${targetDir.path}${Platform.pathSeparator}$fileName');

        // 5. Save the data to the disk!
        await file.writeAsBytes(bytes);
        log("📥 Received file from URL '/$cameraFolder': $fileName");

        // 6. Send a success response back to the camera so it knows to stop trying
        request.response
          ..statusCode = HttpStatus.ok
          ..write('Data received successfully')
          ..close();

      } catch (e) {
        log("❌ Error processing incoming data: $e");
        request.response
          ..statusCode = HttpStatus.internalServerError
          ..close();
      }
    } else {
      // Reject GET or other request types
      request.response
        ..statusCode = HttpStatus.methodNotAllowed
        ..write('Only POST requests are supported')
        ..close();
    }
  }

  /// Safely shuts down the server
  static Future<void> stopServer() async {
    if (_server != null) {
      try {
        log("Stopping HTTP Server...");
        await _server!.close(force: true);
        _server = null;
        log("🛑 Server offline.");
      } catch (e) {
        log("❌ Error stopping HTTP: $e");
      }
    }
  }

  // Check if the server is currently running
  static bool get isRunning => _server != null;
}