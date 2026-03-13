// lib/screens/camera_ftp_setup_screen.dart

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:webview_windows/webview_windows.dart'; // 🚀 THE WINDOWS WEBVIEW ENGINE

// --- PREMIUM COLORS ---
const Color _bgDark = Color(0xFF0F172A);
const Color _cardDark = Color(0xFF1E293B);
const Color _accentCyan = Color(0xFF06B6D4);

class CameraFtpSetupScreen extends StatefulWidget {
  const CameraFtpSetupScreen({Key? key}) : super(key: key);

  @override
  State<CameraFtpSetupScreen> createState() => _CameraFtpSetupScreenState();
}

class _CameraFtpSetupScreenState extends State<CameraFtpSetupScreen> {
  final List<String> _cameraNames = ['Camera 1', 'Camera 2', 'Camera 3', 'Camera 4'];
  final Map<String, String> _cameraIps = {};

  @override
  void initState() {
    super.initState();
    _loadSavedIps();
  }

  Future<void> _loadSavedIps() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      for (String cam in _cameraNames) {
        _cameraIps[cam] = prefs.getString('ip_$cam') ?? '';
      }
    });
  }

  Future<void> _saveIp(String cameraName, String ip) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('ip_$cameraName', ip);
    setState(() {
      _cameraIps[cameraName] = ip;
    });
  }

  void _showSetupDialog(String cameraName) {
    TextEditingController ipController = TextEditingController(text: _cameraIps[cameraName]);

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: _cardDark,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16), side: BorderSide(color: Colors.white.withOpacity(0.1))),
        title: Row(
          children: [
            const Icon(Icons.router, color: _accentCyan),
            const SizedBox(width: 12),
            Text('Setup $cameraName', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Enter the Camera IP Address:', style: TextStyle(color: Colors.white54, fontSize: 14)),
            const SizedBox(height: 16),
            TextField(
              controller: ipController,
              style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
              decoration: InputDecoration(
                hintText: 'e.g. 192.168.1.7',
                hintStyle: const TextStyle(color: Colors.white24),
                filled: true,
                fillColor: _bgDark,
                prefixIcon: const Icon(Icons.link, color: _accentCyan),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide.none),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('CANCEL', style: TextStyle(color: Colors.white54)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: _accentCyan, foregroundColor: Colors.black),
            onPressed: () {
              _saveIp(cameraName, ipController.text.trim());
              Navigator.pop(context);
            },
            child: const Text('SAVE IP', style: TextStyle(fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _bgDark,
      appBar: AppBar(
        backgroundColor: _bgDark,
        title: const Text('Camera FTP Setup', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
        iconTheme: const IconThemeData(color: Colors.white),
        elevation: 0,
      ),
      body: ListView.builder(
        padding: const EdgeInsets.all(24),
        itemCount: _cameraNames.length,
        itemBuilder: (context, index) {
          String camName = _cameraNames[index];
          String currentIp = _cameraIps[camName] ?? '';
          bool hasIp = currentIp.isNotEmpty;

          return Container(
            margin: const EdgeInsets.only(bottom: 16),
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: _cardDark,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: hasIp ? _accentCyan.withOpacity(0.3) : Colors.white.withOpacity(0.05)),
            ),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: const BoxDecoration(color: _bgDark, shape: BoxShape.circle),
                  child: Icon(Icons.camera_alt, color: hasIp ? _accentCyan : Colors.white38),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(camName, style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold)),
                      const SizedBox(height: 4),
                      Text(
                          hasIp ? 'IP: $currentIp' : 'No IP configured',
                          style: TextStyle(color: hasIp ? Colors.greenAccent : Colors.redAccent, fontSize: 14)
                      ),
                    ],
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.edit, color: Colors.white54),
                  onPressed: () => _showSetupDialog(camName),
                  tooltip: 'Edit IP',
                ),
                const SizedBox(width: 8),
                // --- 🚀 NEW: OPEN EMBEDDED WINDOWS WEBVIEW ---
                ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: hasIp ? _accentCyan : Colors.white12,
                    foregroundColor: hasIp ? Colors.black : Colors.white54,
                  ),
                  icon: const Icon(Icons.settings),
                  label: const Text('CONFIGURE'),
                  onPressed: hasIp ? () {
                    Navigator.push(
                        context,
                        MaterialPageRoute(
                            builder: (context) => WindowsCameraWebScreen(
                                cameraName: camName,
                                ipAddress: currentIp
                            )
                        )
                    );
                  } : null,
                )
              ],
            ),
          );
        },
      ),
    );
  }
}

// =========================================================================
// 🚀 THE WINDOWS-NATIVE EMBEDDED WEB BROWSER
// =========================================================================
class WindowsCameraWebScreen extends StatefulWidget {
  final String cameraName;
  final String ipAddress;

  const WindowsCameraWebScreen({Key? key, required this.cameraName, required this.ipAddress}) : super(key: key);

  @override
  State<WindowsCameraWebScreen> createState() => _WindowsCameraWebScreenState();
}

class _WindowsCameraWebScreenState extends State<WindowsCameraWebScreen> {
  final _webviewController = WebviewController();
  bool _isWebviewInitialized = false;

  @override
  void initState() {
    super.initState();
    initPlatformState();
  }

  Future<void> initPlatformState() async {
    // 1. Format the URL correctly
    String targetUrl = widget.ipAddress.startsWith('http')
        ? widget.ipAddress
        : 'http://${widget.ipAddress}/ftp';

    try {
      // 2. Initialize the Windows Web Engine
      await _webviewController.initialize();

      // 3. Load the Camera's Configuration Page
      await _webviewController.loadUrl(targetUrl);

      if (!mounted) return;

      // 4. Update the UI to show the browser
      setState(() {
        _isWebviewInitialized = true;
      });
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Failed to load Webview: $e'), backgroundColor: Colors.redAccent)
        );
      }
    }
  }

  @override
  void dispose() {
    _webviewController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _bgDark,
      appBar: AppBar(
        backgroundColor: _cardDark,
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('${widget.cameraName} Settings', style: const TextStyle(color: Colors.white, fontSize: 16)),
            Text(widget.ipAddress, style: const TextStyle(color: _accentCyan, fontSize: 12)),
          ],
        ),
        iconTheme: const IconThemeData(color: Colors.white),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: () {
              if (_isWebviewInitialized) {
                _webviewController.reload();
              }
            },
          )
        ],
      ),
      body: _isWebviewInitialized
          ? Webview(_webviewController) // 🚀 This draws the embedded browser!
          : const Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            CircularProgressIndicator(color: _accentCyan),
            SizedBox(height: 16),
            Text("Initializing Camera Connection...", style: TextStyle(color: Colors.white54))
          ],
        ),
      ),
    );
  }
}