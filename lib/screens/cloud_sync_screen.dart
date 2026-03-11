// lib/screens/cloud_sync_screen.dart

import 'dart:io';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:file_picker/file_picker.dart'; // NEW: For folder picking
import '../services/b2_cloud_service.dart';

class CloudSyncScreen extends StatefulWidget {
  const CloudSyncScreen({Key? key}) : super(key: key);

  @override
  State<CloudSyncScreen> createState() => _CloudSyncScreenState();
}

class _CloudSyncScreenState extends State<CloudSyncScreen> {
  bool _isEnabled = false;
  final TextEditingController _endpointCtrl = TextEditingController();
  final TextEditingController _bucketCtrl = TextEditingController();
  final TextEditingController _accessKeyCtrl = TextEditingController();
  final TextEditingController _secretKeyCtrl = TextEditingController();

  // Directory structure controllers
  final TextEditingController _folder1Ctrl = TextEditingController();
  final TextEditingController _folder2Ctrl = TextEditingController();

  // NEW: Local folder controller
  final TextEditingController _localFolderCtrl = TextEditingController();

  // Bulk sync state
  bool _isSyncingBulk = false;

  List<String> _consoleLogs = [];
  final ScrollController _scrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    _loadSettings();

    // Listen to the live log stream!
    B2CloudService.logStream.listen((logMessage) {
      if (mounted) {
        setState(() {
          _consoleLogs.add(logMessage);
          if (_consoleLogs.length > 100) _consoleLogs.removeAt(0); // Keep last 100 lines
        });

        // Auto-scroll to bottom
        Future.delayed(const Duration(milliseconds: 100), () {
          if (_scrollController.hasClients) {
            _scrollController.animateTo(
              _scrollController.position.maxScrollExtent,
              duration: const Duration(milliseconds: 200),
              curve: Curves.easeOut,
            );
          }
        });
      }
    });
  }

  Future<void> _loadSettings() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _isEnabled = prefs.getBool('b2_enabled') ?? false;
      _endpointCtrl.text = prefs.getString('b2_endpoint') ?? '';
      _bucketCtrl.text = prefs.getString('b2_bucket') ?? '';
      _accessKeyCtrl.text = prefs.getString('b2_access_key') ?? '';
      _secretKeyCtrl.text = prefs.getString('b2_secret_key') ?? '';

      _folder1Ctrl.text = prefs.getString('b2_folder1') ?? '';
      _folder2Ctrl.text = prefs.getString('b2_folder2') ?? '';

      // Load local sync folder (fallback to dashboard folder if b2_sync_folder is empty)
      _localFolderCtrl.text = prefs.getString('b2_sync_folder') ?? prefs.getString('saved_data_folder') ?? '';
    });
  }

  Future<void> _saveSettings() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('b2_enabled', _isEnabled);
    await prefs.setString('b2_endpoint', _endpointCtrl.text);
    await prefs.setString('b2_bucket', _bucketCtrl.text);
    await prefs.setString('b2_access_key', _accessKeyCtrl.text);
    await prefs.setString('b2_secret_key', _secretKeyCtrl.text);

    await prefs.setString('b2_folder1', _folder1Ctrl.text);
    await prefs.setString('b2_folder2', _folder2Ctrl.text);
    await prefs.setString('b2_sync_folder', _localFolderCtrl.text);

    B2CloudService.log("💾 Settings saved. Reconnecting...");
    await B2CloudService.initialize();

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Cloud Sync Settings Saved!'), backgroundColor: Colors.green),
      );
    }
  }

  // --- NEW: Open File Picker to select local folder ---
  Future<void> _pickLocalFolder() async {
    String? selectedDirectory = await FilePicker.platform.getDirectoryPath(
      dialogTitle: 'Select Local Data Folder to Sync',
    );

    if (selectedDirectory != null) {
      setState(() {
        _localFolderCtrl.text = selectedDirectory;
      });
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('b2_sync_folder', selectedDirectory);
      B2CloudService.log("📁 Local data source set to: $selectedDirectory");
    }
  }

  // --- UPDATED: Bulk Sync Logic ---
  Future<void> _syncAllHistoricalData() async {
    if (_isSyncingBulk) return;

    setState(() => _isSyncingBulk = true);

    try {
      // NOW WE USE THE FOLDER YOU CHOSE ON THIS SCREEN!
      String savedFolder = _localFolderCtrl.text.trim();

      if (savedFolder.isEmpty) {
        B2CloudService.log("❌ Cannot sync: Please browse and select a local data folder first.");
        setState(() => _isSyncingBulk = false);
        return;
      }

      final dir = Directory(savedFolder);
      if (!await dir.exists()) {
        B2CloudService.log("❌ Local data folder does not exist: $savedFolder");
        setState(() => _isSyncingBulk = false);
        return;
      }

      B2CloudService.log("🔄 Starting bulk synchronization from: $savedFolder");

      // Scans recursively to find sas1, sas2 folders inside!
      final files = dir.listSync(recursive: true)
          .whereType<File>()
          .where((f) => f.path.toLowerCase().endsWith('.scb'))
          .toList();

      if (files.isEmpty) {
        B2CloudService.log("⚠️ No .scb files found to upload in $savedFolder");
        setState(() => _isSyncingBulk = false);
        return;
      }

      B2CloudService.log("⏳ Found ${files.length} files. Uploading...");

      int successCount = 0;
      for (var file in files) {
        await B2CloudService.uploadScbFile(file, "BulkSync");
        successCount++;
        await Future.delayed(const Duration(milliseconds: 200));
      }

      B2CloudService.log("✅ Bulk sync complete! Uploaded $successCount / ${files.length} files.");

    } catch (e) {
      B2CloudService.log("❌ Bulk sync error: $e");
    } finally {
      if (mounted) setState(() => _isSyncingBulk = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF3F4F6),
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        iconTheme: const IconThemeData(color: Colors.black87),
        title: const Text('Backblaze B2 Cloud Sync', style: TextStyle(color: Colors.black87, fontWeight: FontWeight.bold)),
      ),
      body: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // LEFT SIDE: Settings Panel
          Expanded(
            flex: 1,
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(32),
              child: Container(
                padding: const EdgeInsets.all(32),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(16),
                  boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 15, offset: const Offset(0, 5))],
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(Icons.cloud_done, color: Colors.blue[700], size: 36),
                        const SizedBox(width: 16),
                        const Expanded(child: Text('Automatically mirror camera data to Backblaze B2.', style: TextStyle(color: Colors.black54))),
                      ],
                    ),
                    const SizedBox(height: 32),

                    SwitchListTile(
                      title: const Text('Enable Cloud Sync', style: TextStyle(fontWeight: FontWeight.bold)),
                      value: _isEnabled,
                      activeColor: Colors.blue[700],
                      onChanged: (val) => setState(() => _isEnabled = val),
                    ),
                    const Divider(height: 40),

                    _buildTextField('S3 Endpoint (e.g., s3.eu-central-003.backblazeb2.com)', _endpointCtrl),
                    _buildTextField('Bucket Name', _bucketCtrl),
                    _buildTextField('Application Key ID (Access Key)', _accessKeyCtrl),
                    _buildTextField('Application Key (Secret Key)', _secretKeyCtrl, isObscure: true),

                    const SizedBox(height: 24),
                    const Text('Cloud Directory Structure', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.blue)),
                    const SizedBox(height: 16),

                    _buildTextField('Folder 1 (e.g., Region or City)', _folder1Ctrl),
                    _buildTextField('Folder 2 (e.g., Store Name or Door)', _folder2Ctrl),

                    const SizedBox(height: 32),
                    Row(
                      children: [
                        Expanded(
                          child: SizedBox(
                            height: 50,
                            child: ElevatedButton.icon(
                              style: ElevatedButton.styleFrom(backgroundColor: Colors.blue[700], foregroundColor: Colors.white, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8))),
                              onPressed: _saveSettings,
                              icon: const Icon(Icons.save),
                              label: const Text('SAVE & CONNECT', style: TextStyle(fontWeight: FontWeight.bold)),
                            ),
                          ),
                        ),
                        const SizedBox(width: 16),
                        Expanded(
                          child: SizedBox(
                            height: 50,
                            child: ElevatedButton.icon(
                              style: ElevatedButton.styleFrom(backgroundColor: Colors.orange[600], foregroundColor: Colors.white, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8))),
                              onPressed: () => B2CloudService.testConnection(),
                              icon: const Icon(Icons.bolt),
                              label: const Text('TEST UPLOAD', style: TextStyle(fontWeight: FontWeight.bold)),
                            ),
                          ),
                        ),
                      ],
                    ),

                    const SizedBox(height: 24),
                    const Divider(),
                    const SizedBox(height: 24),

                    // --- NEW: LOCAL FOLDER SELECTOR ---
                    const Text('Local Data Source (For Bulk Sync)', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.blue)),
                    const SizedBox(height: 16),
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          child: _buildTextField('Select local directory containing .scb files', _localFolderCtrl),
                        ),
                        const SizedBox(width: 16),
                        SizedBox(
                          height: 54, // Match TextField height
                          child: ElevatedButton.icon(
                            style: ElevatedButton.styleFrom(
                                backgroundColor: Colors.grey[200],
                                foregroundColor: Colors.black87,
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8))
                            ),
                            onPressed: _pickLocalFolder,
                            icon: const Icon(Icons.folder_open),
                            label: const Text('BROWSE', style: TextStyle(fontWeight: FontWeight.bold)),
                          ),
                        ),
                      ],
                    ),

                    const SizedBox(height: 16),

                    // --- SYNCHRONIZE ALL BUTTON ---
                    SizedBox(
                      width: double.infinity,
                      height: 50,
                      child: ElevatedButton.icon(
                        style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.green[600],
                            foregroundColor: Colors.white,
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8))
                        ),
                        onPressed: _isSyncingBulk ? null : _syncAllHistoricalData,
                        icon: _isSyncingBulk
                            ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                            : const Icon(Icons.cloud_upload),
                        label: Text(
                            _isSyncingBulk ? 'SYNCHRONIZING DATA...' : 'SYNCHRONIZE ALL HISTORICAL DATA',
                            style: const TextStyle(fontWeight: FontWeight.bold)
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),

          // RIGHT SIDE: Diagnostics Terminal
          Expanded(
            flex: 1,
            child: Padding(
              padding: const EdgeInsets.only(top: 32, right: 32, bottom: 32),
              child: Container(
                decoration: BoxDecoration(
                  color: const Color(0xFF1E293B), // Dark slate console
                  borderRadius: BorderRadius.circular(16),
                  boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.1), blurRadius: 15, offset: const Offset(0, 5))],
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                      decoration: BoxDecoration(color: Colors.black.withOpacity(0.3), borderRadius: const BorderRadius.vertical(top: Radius.circular(16))),
                      child: Row(
                        children: [
                          const Icon(Icons.terminal, color: Colors.white54, size: 18),
                          const SizedBox(width: 8),
                          const Text('LIVE CLOUD DIAGNOSTICS', style: TextStyle(color: Colors.white54, fontWeight: FontWeight.bold, fontSize: 12)),
                          const Spacer(),
                          InkWell(
                            onTap: () => setState(() => _consoleLogs.clear()),
                            child: const Text('CLEAR', style: TextStyle(color: Colors.blueAccent, fontSize: 12, fontWeight: FontWeight.bold)),
                          )
                        ],
                      ),
                    ),
                    Expanded(
                      child: ListView.builder(
                        controller: _scrollController,
                        padding: const EdgeInsets.all(16),
                        itemCount: _consoleLogs.length,
                        itemBuilder: (context, index) {
                          String logMsg = _consoleLogs[index];
                          Color textColor = Colors.white70;

                          // Color coding for easier reading
                          if (logMsg.contains("✅")) textColor = Colors.greenAccent;
                          if (logMsg.contains("❌")) textColor = Colors.redAccent;
                          if (logMsg.contains("⚠️")) textColor = Colors.orangeAccent;
                          if (logMsg.contains("☁️") || logMsg.contains("⏳") || logMsg.contains("🔄") || logMsg.contains("📁")) textColor = Colors.lightBlueAccent;

                          return Padding(
                            padding: const EdgeInsets.only(bottom: 6),
                            child: Text(
                              logMsg,
                              style: TextStyle(color: textColor, fontFamily: 'Courier', fontSize: 13),
                            ),
                          );
                        },
                      ),
                    ),
                  ],
                ),
              ),
            ),
          )
        ],
      ),
    );
  }

  Widget _buildTextField(String label, TextEditingController controller, {bool isObscure = false}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: TextField(
        controller: controller,
        obscureText: isObscure,
        style: const TextStyle(color: Colors.black87, fontWeight: FontWeight.bold),
        decoration: InputDecoration(
          labelText: label,
          labelStyle: const TextStyle(color: Colors.black54),
          filled: true,
          fillColor: Colors.grey[100],
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide.none),
        ),
      ),
    );
  }
}