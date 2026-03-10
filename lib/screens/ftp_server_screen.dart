// lib/screens/ftp_server_screen.dart

import 'dart:ui';
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
  final TextEditingController _portController = TextEditingController(text: "2121");
  final TextEditingController _userController = TextEditingController(text: "camera");
  final TextEditingController _passController = TextEditingController(text: "password");

  String _selectedDirectory = "No folder selected";
  bool _isRunning = false;
  List<String> _consoleLogs = [];

  final ScrollController _scrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    _initSettings();
    _isRunning = FtpService.isRunning;

    // Listen to the live log stream!
    FtpService.logStream.listen((logMessage) {
      if (mounted) {
        setState(() {
          _consoleLogs.add(logMessage);
          // Keep logs from getting infinitely huge
          if (_consoleLogs.length > 200) _consoleLogs.removeAt(0);
        });
        // Auto-scroll to bottom of terminal
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

  Future<void> _initSettings() async {
    // Get the PC IP automatically
    String ip = await FtpService.getLocalIpAddress();

    // Load previously saved folder if exists
    final prefs = await SharedPreferences.getInstance();
    String? savedPath = prefs.getString('saved_data_folder');

    setState(() {
      _ipController.text = ip; // Set IP (readonly)
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
      await FtpService.startServer(
        rootDirectory: _selectedDirectory,
        port: port,
        username: _userController.text,
        password: _passController.text,
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
                // LEFT SIDE: Settings
                Expanded(
                  flex: 1,
                  child: _buildSettingsPanel(),
                ),
                const SizedBox(width: 32),
                // RIGHT SIDE: The Live Log Terminal
                Expanded(
                  flex: 2,
                  child: _buildLogConsole(),
                ),
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
        _buildTextField("PC IP Address (Auto)", _ipController, readOnly: true),
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
      decoration: BoxDecoration(
        color: Colors.black87,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white12),
      ),
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
                if (logMsg.contains("📁")) textColor = Colors.cyanAccent;

                return Padding(
                  padding: const EdgeInsets.only(bottom: 4),
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