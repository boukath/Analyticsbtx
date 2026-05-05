// lib/screens/ftp_server_screen.dart

import 'dart:ui';
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../services/ftp_service.dart';
import 'camera_ftp_setup_screen.dart';

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

  List<String> _detectedIps = [];

  final ScrollController _scrollController = ScrollController();

  // --- Live Metrics State ---
  int _filesToday = 0;
  int _bytesToday = 0;
  int _activeCameras = 0;

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

    // Listen to Terminal Logs
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

    // Listen to Live Server Metrics
    FtpService.metricsStream.listen((metrics) {
      if (mounted) {
        setState(() {
          _filesToday = metrics['files'];
          _bytesToday = metrics['bytes'];
          _activeCameras = metrics['activeCameras'];
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
      List<String> currentIps = await FtpService.getAllLocalIpAddresses();
      String expectedIp = _ipController.text.trim();

      if (mounted) {
        setState(() {
          _detectedIps = currentIps;
          _actualPhysicalIp = currentIps.isNotEmpty ? currentIps.first : "127.0.0.1";
          _isIpMismatch = expectedIp.isNotEmpty && !currentIps.contains(expectedIp);
        });

        if (_isIpMismatch && !_isAlertShowing && _isRunning) {
          _showIpAlertDialog(expectedIp, currentIps);
        }
      }
    });
  }

  void _showIpAlertDialog(String expected, List<String> actualIps) {
    _isAlertShowing = true;
    String displayIps = actualIps.join("\n");

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
                  "Available Network IPs:\n$displayIps\n\n"
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
                    _ipController.text = actualIps.first;
                    _isIpMismatch = false;
                  });
                  final prefs = await SharedPreferences.getInstance();
                  await prefs.setString('ftp_ip', actualIps.first);

                  _isAlertShowing = false;
                  if (context.mounted) Navigator.of(c).pop();

                  FtpService.log("⚠️ IP Address updated by user to: ${actualIps.first}");
                },
                child: const Text("UPDATE TO FIRST AVAILABLE", style: TextStyle(fontWeight: FontWeight.bold)),
              ),
            ],
          );
        }
    ).then((_) => _isAlertShowing = false);
  }

  Future<void> _initSettings() async {
    final prefs = await SharedPreferences.getInstance();

    String savedIp = prefs.getString('ftp_ip') ?? '';
    String? savedPath = prefs.getString('saved_data_folder');
    int savedPort = prefs.getInt('ftp_port') ?? 21;
    String savedUser = prefs.getString('ftp_user') ?? "shopline";
    String savedPass = prefs.getString('ftp_pass') ?? "shopline";

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
    final prefs = await SharedPreferences.getInstance();

    if (_isRunning) {
      await FtpService.stopServer();
      await prefs.setBool('ftp_auto_start', false);
      setState(() => _isRunning = false);
    } else {
      if (_selectedDirectory == "No folder selected") {
        FtpService.log("❌ Cannot start server: No directory selected.");
        return;
      }

      int port = int.tryParse(_portController.text) ?? 2121;

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

      await prefs.setBool('ftp_auto_start', true);
      setState(() => _isRunning = true);
    }
  }

  String _formatBytes(int bytes) {
    if (bytes == 0) return "0 MB";
    double mb = bytes / (1024 * 1024);
    return "${mb.toStringAsFixed(2)} MB";
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
        title: const Text(
            'FTP SERVER CONFIGURATION',
            style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16, letterSpacing: 1.5)
        ),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 16.0, top: 8.0, bottom: 8.0),
            child: ElevatedButton.icon(
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.cyanAccent.withOpacity(0.2),
                foregroundColor: Colors.cyanAccent,
                elevation: 0,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                  side: BorderSide(color: Colors.cyanAccent.withOpacity(0.5)),
                ),
              ),
              icon: const Icon(Icons.video_camera_back, size: 20),
              label: const Text('SETUP CAMERAS', style: TextStyle(fontWeight: FontWeight.bold, letterSpacing: 1)),
              onPressed: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (context) => const CameraFtpSetupScreen()),
                );
              },
            ),
          )
        ],
      ),
      body: Stack(
        children: [
          Positioned(top: -100, right: -100, child: _buildGlowOrb(Colors.cyanAccent.withOpacity(0.1), 300)),
          Padding(
            padding: const EdgeInsets.all(32.0),
            child: Column(
              children: [
                _buildMetricsDashboard(),
                const SizedBox(height: 32),
                Expanded(
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
          ),
        ],
      ),
    );
  }

  Widget _buildMetricsDashboard() {
    return Row(
      children: [
        Expanded(
          child: _buildMetricCard(
            title: "FILES RECEIVED TODAY",
            value: _filesToday.toString(),
            icon: Icons.description,
            color: Colors.cyanAccent,
          ),
        ),
        const SizedBox(width: 16),
        Expanded(
          child: _buildMetricCard(
            title: "DATA TRANSFERRED",
            value: _formatBytes(_bytesToday),
            icon: Icons.data_usage,
            color: Colors.purpleAccent,
          ),
        ),
        const SizedBox(width: 16),
        Expanded(
          child: _buildMetricCard(
            title: "ACTIVE CAMERAS",
            value: _activeCameras.toString(),
            icon: Icons.linked_camera,
            color: Colors.greenAccent,
          ),
        ),
      ],
    );
  }

  Widget _buildMetricCard({required String title, required String value, required IconData icon, required Color color}) {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: const Color(0xFF1E293B),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white.withOpacity(0.05)),
        boxShadow: [
          BoxShadow(color: Colors.black.withOpacity(0.2), blurRadius: 15, offset: const Offset(0, 5))
        ],
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: color.withOpacity(0.15),
              shape: BoxShape.circle,
            ),
            child: Icon(icon, color: color, size: 28),
          ),
          const SizedBox(width: 20),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: const TextStyle(color: Colors.white54, fontSize: 12, fontWeight: FontWeight.bold, letterSpacing: 1.0)),
                const SizedBox(height: 8),
                Text(value, style: const TextStyle(color: Colors.white, fontSize: 28, fontWeight: FontWeight.w900)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSettingsPanel() {
    return SingleChildScrollView(
      child: Column(
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
                      "Network changed! Saved IP is not found on this machine.",
                      style: const TextStyle(color: Colors.redAccent, fontSize: 12, fontWeight: FontWeight.bold),
                    ),
                  ),
                ],
              ),
            ),

          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(child: _buildTextField("Expected PC IP Address", _ipController)),
              const SizedBox(width: 12),
              Container(
                height: 56,
                margin: const EdgeInsets.only(bottom: 16),
                child: PopupMenuButton<String>(
                  tooltip: "Select from detected IPs",
                  color: const Color(0xFF1E293B),
                  offset: const Offset(0, 60),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    decoration: BoxDecoration(
                      color: Colors.cyanAccent.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: Colors.cyanAccent, width: 1),
                    ),
                    child: const Row(
                      children: [
                        Icon(Icons.wifi_find, color: Colors.cyanAccent),
                        SizedBox(width: 8),
                        Text("DETECT IPs", style: TextStyle(color: Colors.cyanAccent, fontWeight: FontWeight.bold)),
                        Icon(Icons.arrow_drop_down, color: Colors.cyanAccent),
                      ],
                    ),
                  ),
                  itemBuilder: (context) {
                    return _detectedIps.map((ip) => PopupMenuItem<String>(
                      value: ip,
                      child: Row(
                        children: [
                          const Icon(Icons.network_check, color: Colors.cyanAccent, size: 20),
                          const SizedBox(width: 12),
                          Text(ip, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                        ],
                      ),
                    )).toList();
                  },
                  onSelected: (String selectedIp) {
                    setState(() {
                      _ipController.text = selectedIp;
                      _isIpMismatch = false;
                    });
                    FtpService.log("🔍 IP selected from dropdown: $selectedIp");
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
          ),

          const SizedBox(height: 16),

          SizedBox(
            width: double.infinity,
            height: 50,
            child: OutlinedButton.icon(
              style: OutlinedButton.styleFrom(
                backgroundColor: Colors.orangeAccent.withOpacity(0.1),
                foregroundColor: Colors.orangeAccent,
                side: const BorderSide(color: Colors.orangeAccent, width: 1.5),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
              onPressed: () async {
                await FtpService.requestFirewallException();
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('Requested Firewall Exception. Please click "Yes" on the Windows prompt.'),
                      backgroundColor: Colors.orange,
                      behavior: SnackBarBehavior.floating,
                    ),
                  );
                }
              },
              icon: const Icon(Icons.security),
              label: const Text(
                'FIX FIREWALL ISSUES',
                style: TextStyle(fontWeight: FontWeight.bold, letterSpacing: 1),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTextField(String label, TextEditingController controller, {bool readOnly = false}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: TextField(
        controller: controller,
        readOnly: readOnly,
        onChanged: (val) {
          setState(() {
            _isIpMismatch = val.isNotEmpty && !_detectedIps.contains(val);
          });
        },
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
                if (logMsg.contains("🛑") || logMsg.contains("⚠️")) textColor = Colors.orangeAccent;
                if (logMsg.contains("📁") || logMsg.contains("🔄") || logMsg.contains("🔍")) textColor = Colors.cyanAccent;

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