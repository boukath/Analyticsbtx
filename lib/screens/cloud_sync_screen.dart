// lib/screens/cloud_sync_screen.dart

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
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
    });
  }

  Future<void> _saveSettings() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('b2_enabled', _isEnabled);
    await prefs.setString('b2_endpoint', _endpointCtrl.text);
    await prefs.setString('b2_bucket', _bucketCtrl.text);
    await prefs.setString('b2_access_key', _accessKeyCtrl.text);
    await prefs.setString('b2_secret_key', _secretKeyCtrl.text);

    B2CloudService.log("💾 Settings saved. Reconnecting...");
    await B2CloudService.initialize();

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Cloud Sync Settings Saved!'), backgroundColor: Colors.green),
      );
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
                    )
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
                          if (logMsg.contains("☁️") || logMsg.contains("⏳")) textColor = Colors.lightBlueAccent;

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