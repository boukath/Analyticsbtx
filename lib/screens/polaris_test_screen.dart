// lib/screens/polaris_test_screen.dart

import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import '../services/polaris_parser_service.dart';

class PolarisTestScreen extends StatefulWidget {
  const PolarisTestScreen({super.key});

  @override
  State<PolarisTestScreen> createState() => _PolarisTestScreenState();
}

class _PolarisTestScreenState extends State<PolarisTestScreen> {
  // This variable holds the message we show on the screen
  String _statusMessage = "Ready to select a file.";

  Future<void> _testPolarisParser() async {
    setState(() {
      _statusMessage = "📂 Opening File Picker...";
    });

    // 1. Open the file picker
    FilePickerResult? result = await FilePicker.platform.pickFiles();

    // 2. Check if a file was selected
    if (result != null && result.files.single.path != null) {
      String selectedFilePath = result.files.single.path!;

      setState(() {
        _statusMessage = "✅ File selected:\n$selectedFilePath\n\nProcessing... Check your Debug Console!";
      });

      // 3. Send the file to our service
      final polarisService = PolarisParserService();
      await polarisService.processPolarisFile(selectedFilePath);

    } else {
      // User canceled
      setState(() {
        _statusMessage = "❌ No file selected.";
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    // Using your app's dark theme colors
    const Color bgDark = Color(0xFF0F172A);

    return Scaffold(
      backgroundColor: bgDark,
      appBar: AppBar(
        backgroundColor: bgDark,
        elevation: 0,
        title: const Text(
          'Polaris Parser Test',
          style: TextStyle(color: Colors.white),
        ),
        iconTheme: const IconThemeData(color: Colors.white),
      ),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.analytics_outlined, size: 80, color: Colors.blueAccent),
              const SizedBox(height: 32),

              // Our Test Button
              ElevatedButton.icon(
                onPressed: _testPolarisParser,
                icon: const Icon(Icons.folder_open),
                label: const Text(
                  'Select Polaris .sav File',
                  style: TextStyle(fontSize: 16),
                ),
                style: ElevatedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
                  backgroundColor: Colors.blueAccent,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
              ),

              const SizedBox(height: 32),

              // Status Text
              Text(
                _statusMessage,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: Colors.white70,
                  fontSize: 16,
                  height: 1.5,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}