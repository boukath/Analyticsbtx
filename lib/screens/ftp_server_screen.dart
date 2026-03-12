// lib/screens/ftp_server_screen.dart

import 'dart:ui';
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../services/ftp_service.dart';

class FtpServerScreen extends StatefulWidget {
  const FtpServerScreen({Key? key}) : super(key: key);

  @override
  State<FtpServerScreen> createState() => _FtpServerScreenState();
}

class _FtpServerScreenState extends State<FtpServerScreen> {
  final TextEditingController _ipController = TextEditingController();
  final TextEditingController _portController = TextEditingController();
  final TextEditingController _userController = TextEditingController();
  final TextEditingController _passController = TextEditingController();

  String _selectedDirectory = "No folder selected";
  bool _isRunning = false;
  List<String> _consoleLogs = [];

  final ScrollController _scrollController = ScrollController();

  // --- IP Security Monitor Variables ---
  Timer? _ipMonitorTimer;
  String _actualPhysicalIp = "";
  bool _isIpMismatch = false;
  bool _isAlertShowing = false;

  @override
  void initState() {
    super.initState();
    _initSettings();
    _isRunning = FtpService.isRunning;

    FtpService.logStream.listen((logMessage) {
      if (mounted) {
        setState(() {
          _consoleLogs.add(logMessage);
          if (_consoleLogs.length > 200) _consoleLogs.removeAt(0);
        });
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

    _startLocalIpMonitor();
  }

  @override
  void dispose() {
    _ipMonitorTimer?.cancel();
    _scrollController.dispose();
    _ipController.dispose();
    _portController.dispose();
    _userController.dispose();
    _passController.dispose();
    super.dispose();
  }

  void _startLocalIpMonitor() {
    _ipMonitorTimer = Timer.periodic(const Duration(seconds: 5), (timer) async {
      String currentIp = await FtpService.getLocalIpAddress();
      String expectedIp = _ipController.text.trim();

      if (mounted) {
        setState(() {
          _actualPhysicalIp = currentIp;
          _isIpMismatch = expectedIp.isNotEmpty && currentIp != expectedIp;
        });

        if (_isIpMismatch && !_isAlertShowing && _isRunning) {
          _showIpAlertDialog(expectedIp, currentIp);
        }
      }
    });
  }

  void _showIpAlertDialog(String expected, String actual) {
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
                Text("IP ADDRESS CHANGED!", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 18)),
              ],
            ),
            content: Text(
              "The computer's physical IP address has changed!\n\n"
                  "Expected IP (Saved): $expected\n"
                  "Current Network IP: ${actual == '127.0.0.1' ? 'DISCONNECTED' : actual}\n\n"
                  "Cameras will not be able to connect until this is fixed.",
              style: const TextStyle(color: Colors.white70, fontSize: 16, height: 1.5),
            ),
            actions: [
              TextButton(
                onPressed: () {
                  _isAlertShowing = false;
                  Navigator.of(c).pop();
                },
                child: const Text("DISMISS", style: TextStyle(color: Colors.cyanAccent, fontWeight: FontWeight.bold)),
              ),
              ElevatedButton(
                style: ElevatedButton.styleFrom(backgroundColor: Colors.redAccent, foregroundColor: Colors.white),
                onPressed: () async {
                  setState(() {
                    _ipController.text = actual;
                    _isIpMismatch = false;
                  });
                  final prefs = await SharedPreferences.getInstance();
                  await prefs.setString('ftp_ip', actual);

                  _isAlertShowing = false;
                  if (context.mounted) Navigator.of(c).pop();

                  FtpService.log("⚠️ IP Address updated by user to: $actual");
                },
                child: const Text("UPDATE SETTINGS", style: TextStyle(fontWeight: FontWeight.bold)),
              ),
            ],
          );
        }
    ).then((_) => _isAlertShowing = false);
  }

  Future<void> _initSettings() async {
    final prefs = await SharedPreferences.getInstance();

    // REMOVED AUTO-FETCH: It now ONLY loads exactly what is saved.
    String savedIp = prefs.getString('ftp_ip') ?? '';
    String? savedPath = prefs.getString('saved_data_folder');
    int savedPort = prefs.getInt('ftp_port') ?? 2121;
    String savedUser = prefs.getString('ftp_user') ?? "camera";
    String savedPass = prefs.getString('ftp_pass') ?? "password";

    setState(() {
      _ipController.text = savedIp;
      _portController.text = savedPort.toString();
      _userController.text = savedUser;
      _passController.text = savedPass;

      if (savedPath != null && savedPath.isNotEmpty) {
        _selectedDirectory = savedPath;
      }
    });
  }

  Future<void> _pickDirectory() async {
    String? folderPath = await FilePicker.platform.getDirectoryPath();
    if (folderPath != null) {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('saved_data_folder', folderPath);
      setState(() {
        _selectedDirectory = folderPath;
      });
      FtpService.log("Folder changed to: $folderPath");
    }
  }

  void _toggleServer() async {
    if (_isRunning) {
      await FtpService.stopServer();
      setState(() => _isRunning = false);
    } else {
      if (_selectedDirectory == "No folder selected") {
        FtpService.log("❌ Cannot start server: No directory selected.");
        return;
      }

      int port = int.tryParse(_portController.text) ?? 2121;

      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('ftp_ip', _ipController.text.trim());
      await prefs.setInt('ftp_port', port);
      await prefs.setString('ftp_user', _userController.text.trim());
      await prefs.setString('ftp_pass', _passController.text.trim());

      await FtpService.startServer(
        rootDirectory: _selectedDirectory,
        port: port,
        username: _userController.text.trim(),
        password: _passController.text.trim(),
      );
      setState(() => _isRunning = true);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0B0F19),
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.cyanAccent),
          onPressed: () => Navigator.pop(context),
        ),
        title: const Text('FTP SERVER CONFIGURATION', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16, letterSpacing: 1.5)),
      ),
      body: Stack(
        children: [
          Positioned(top: -100, right: -100, child: _buildGlowOrb(Colors.cyanAccent.withOpacity(0.1), 300)),
          Padding(
            padding: const EdgeInsets.all(32.0),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(flex: 1, child: _buildSettingsPanel()),
                const SizedBox(width: 32),
                Expanded(flex: 2, child: _buildLogConsole()),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSettingsPanel() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('CONNECTION SETTINGS', style: TextStyle(color: Colors.cyanAccent, fontWeight: FontWeight.bold)),
        const SizedBox(height: 16),

        if (_isIpMismatch)
          Container(
            padding: const EdgeInsets.all(12),
            margin: const EdgeInsets.only(bottom: 16),
            decoration: BoxDecoration(color: Colors.redAccent.withOpacity(0.2), borderRadius: BorderRadius.circular(8), border: Border.all(color: Colors.redAccent)),
            child: Row(
              children: [
                const Icon(Icons.error_outline, color: Colors.redAccent),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    "Network changed! Actual IP is currently ${_actualPhysicalIp == '127.0.0.1' ? 'DISCONNECTED' : _actualPhysicalIp}",
                    style: const TextStyle(color: Colors.redAccent, fontSize: 12, fontWeight: FontWeight.bold),
                  ),
                ),
              ],
            ),
          ),

        // --- NEW: IP Field with Auto-Detect Button ---
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(child: _buildTextField("Expected PC IP Address", _ipController)),
            const SizedBox(width: 12),
            Container(
              height: 56, // Matches the height of the TextField
              margin: const EdgeInsets.only(bottom: 16),
              child: ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.cyanAccent.withOpacity(0.1),
                  foregroundColor: Colors.cyanAccent,
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                      side: const BorderSide(color: Colors.cyanAccent, width: 1)
                  ),
                ),
                icon: const Icon(Icons.wifi_find),
                label: const Text("AUTO-DETECT", style: TextStyle(fontWeight: FontWeight.bold)),
                onPressed: () async {
                  String currentIp = await FtpService.getLocalIpAddress();
                  setState(() {
                    _ipController.text = currentIp;
                  });
                  FtpService.log("🔍 Auto-detected IP: $currentIp. (Click START SERVER to save)");
                },
              ),
            ),
          ],
        ),

        _buildTextField("Port", _portController),
        _buildTextField("FTP Username", _userController),
        _buildTextField("FTP Password", _passController),
        const SizedBox(height: 16),
        const Text('TARGET DIRECTORY', style: TextStyle(color: Colors.cyanAccent, fontWeight: FontWeight.bold)),
        const SizedBox(height: 8),
        InkWell(
          onTap: _pickDirectory,
          child: Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(color: Colors.white.withOpacity(0.05), borderRadius: BorderRadius.circular(8), border: Border.all(color: Colors.white24)),
            child: Row(
              children: [
                const Icon(Icons.folder, color: Colors.amberAccent),
                const SizedBox(width: 12),
                Expanded(child: Text(_selectedDirectory, style: const TextStyle(color: Colors.white70), overflow: TextOverflow.ellipsis)),
              ],
            ),
          ),
        ),
        const SizedBox(height: 32),
        SizedBox(
          width: double.infinity,
          height: 60,
          child: ElevatedButton.icon(
            style: ElevatedButton.styleFrom(
              backgroundColor: _isRunning ? Colors.redAccent : Colors.greenAccent,
              foregroundColor: Colors.black,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
            icon: Icon(_isRunning ? Icons.stop : Icons.play_arrow, size: 28),
            label: Text(_isRunning ? 'STOP SERVER' : 'START SERVER', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16, letterSpacing: 1)),
            onPressed: _toggleServer,
          ),
        )
      ],
    );
  }

  Widget _buildTextField(String label, TextEditingController controller, {bool readOnly = false}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: TextField(
        controller: controller,
        readOnly: readOnly,
        style: TextStyle(color: readOnly ? Colors.white54 : Colors.white),
        decoration: InputDecoration(
          labelText: label,
          labelStyle: const TextStyle(color: Colors.white54),
          filled: true,
          fillColor: Colors.white.withOpacity(0.05),
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide.none),
        ),
      ),
    );
  }

  Widget _buildLogConsole() {
    return Container(
      decoration: BoxDecoration(color: Colors.black87, borderRadius: BorderRadius.circular(16), border: Border.all(color: Colors.white12)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: const BoxDecoration(color: Color(0xFF1E293B), borderRadius: BorderRadius.vertical(top: Radius.circular(16))),
            child: Row(
              children: [
                const Icon(Icons.terminal, color: Colors.white54, size: 18),
                const SizedBox(width: 8),
                const Text('SERVER EVENT LOGS', style: TextStyle(color: Colors.white54, fontWeight: FontWeight.bold, fontSize: 12)),
                const Spacer(),
                InkWell(
                  onTap: () => setState(() => _consoleLogs.clear()),
                  child: const Text('CLEAR', style: TextStyle(color: Colors.cyanAccent, fontSize: 12, fontWeight: FontWeight.bold)),
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
                Color textColor = Colors.greenAccent;
                if (logMsg.contains("❌")) textColor = Colors.redAccent;
                if (logMsg.contains("🛑")) textColor = Colors.orangeAccent;
                if (logMsg.contains("📁") || logMsg.contains("🔄")) textColor = Colors.cyanAccent;

                return Padding(
                  padding: const EdgeInsets.only(bottom: 4),
                  child: Text(logMsg, style: TextStyle(color: textColor, fontFamily: 'Courier', fontSize: 13)),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildGlowOrb(Color color, double size) {
    return Container(
      width: size, height: size,
      decoration: BoxDecoration(shape: BoxShape.circle, color: color),
      child: BackdropFilter(filter: ImageFilter.blur(sigmaX: 100, sigmaY: 100), child: Container(color: Colors.transparent)),
    );
  }
}