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
  String _statusMessage = "Ready to select a folder.";
  PolarisData? _extractedData; // 🚀 Hold the data to display it on screen!

  Future<void> _testPolarisParser() async {
    setState(() {
      _statusMessage = "📂 Opening Folder Picker...";
      _extractedData = null; // Reset data
    });

    // 1. Open the FOLDER picker instead of file picker
    String? selectedDirectory = await FilePicker.platform.getDirectoryPath();

    // 2. Check if a folder was selected
    if (selectedDirectory != null) {
      setState(() {
        _statusMessage = "✅ Folder selected:\n$selectedDirectory\n\nScanning for latest .sav file...";
      });

      // 3. Send the folder path to our service
      final polarisService = PolarisParserService();

      // 🚀 Use our new folder method!
      final result = await polarisService.processPolarisFolder(selectedDirectory);

      setState(() {
        if (result != null) {
          _statusMessage = "🎉 Success! Extracted the latest data:";
          _extractedData = result;
        } else {
          _statusMessage = "❌ No .sav files found in that folder, or parsing failed.";
        }
      });

    } else {
      // User canceled
      setState(() {
        _statusMessage = "❌ No folder selected.";
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    // Using your app's dark theme colors
    const Color bgDark = Color(0xFF0F172A);
    const Color cardDark = Color(0xFF1E293B);
    const Color accentCyan = Color(0xFF06B6D4);

    return Scaffold(
      backgroundColor: bgDark,
      appBar: AppBar(
        backgroundColor: bgDark,
        elevation: 0,
        title: const Text(
          'Polaris Auto-Scanner Test',
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
              const Icon(Icons.drive_folder_upload, size: 80, color: accentCyan),
              const SizedBox(height: 32),

              // Our Test Button
              ElevatedButton.icon(
                onPressed: _testPolarisParser,
                icon: const Icon(Icons.folder),
                label: const Text(
                  'Select Polaris Backup Folder',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                ),
                style: ElevatedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
                  backgroundColor: accentCyan,
                  foregroundColor: Colors.black,
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

              const SizedBox(height: 24),

              // 🚀 Display the results beautifully on the screen if we have them!
              if (_extractedData != null)
                Container(
                  padding: const EdgeInsets.all(24),
                  decoration: BoxDecoration(
                    color: cardDark,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: accentCyan.withOpacity(0.5)),
                  ),
                  child: Column(
                    children: [
                      Text(
                        _extractedData!.date ?? "Unknown Date",
                        style: const TextStyle(color: accentCyan, fontSize: 24, fontWeight: FontWeight.bold),
                      ),
                      const Divider(color: Colors.white24, height: 32),
                      _buildResultRow(Icons.payments, "Revenue", "${_extractedData!.chiffreAffaires.toStringAsFixed(2)} DZD"),
                      const SizedBox(height: 12),
                      _buildResultRow(Icons.receipt_long, "Tickets", "${_extractedData!.totalTickets}"),
                      const SizedBox(height: 12),
                      _buildResultRow(Icons.people, "Clients", "${_extractedData!.totalClients}"),
                    ],
                  ),
                )
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildResultRow(IconData icon, String label, String value) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Row(
          children: [
            Icon(icon, color: Colors.white54, size: 20),
            const SizedBox(width: 8),
            Text(label, style: const TextStyle(color: Colors.white54, fontSize: 16)),
          ],
        ),
        Text(value, style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold)),
      ],
    );
  }
}