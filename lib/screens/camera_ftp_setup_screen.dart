// lib/screens/camera_ftp_setup_screen.dart

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:webview_windows/webview_windows.dart';

// --- PREMIUM COLORS ---
const Color _bgDark = Color(0xFF0F172A);
const Color _cardDark = Color(0xFF1E293B);
const Color _accentCyan = Color(0xFF06B6D4);
const Color _dangerRed = Color(0xFFEF4444);

class CameraFtpSetupScreen extends StatefulWidget {
  const CameraFtpSetupScreen({Key? key}) : super(key: key);

  @override
  State<CameraFtpSetupScreen> createState() => _CameraFtpSetupScreenState();
}

class _CameraFtpSetupScreenState extends State<CameraFtpSetupScreen> {
  List<String> _cameraNames = [];
  final Map<String, String> _cameraIps = {};

  // 🚀 NEW: Keeps track of whether the camera is Model 2 (2D) or Model 1 (3D)
  final Map<String, bool> _cameraIsModel2 = {};

  @override
  void initState() {
    super.initState();
    _loadSavedData();
  }

  Future<void> _loadSavedData() async {
    final prefs = await SharedPreferences.getInstance();
    List<String>? savedList = prefs.getStringList('camera_names_list');

    setState(() {
      _cameraNames.clear();
      _cameraIps.clear();
      _cameraIsModel2.clear();

      if (savedList != null && savedList.isNotEmpty) {
        _cameraNames.addAll(savedList);
      } else {
        _cameraNames.add('Camera 1');
      }

      for (String camName in _cameraNames) {
        _cameraIps[camName] = prefs.getString('ip_$camName') ?? '';
        // 🚀 NEW: Load the saved model preference (Defaults to false / Model 1)
        _cameraIsModel2[camName] = prefs.getBool('isModel2_$camName') ?? false;
      }
    });
  }

  Future<void> _addNewCamera() async {
    final prefs = await SharedPreferences.getInstance();

    int nextNum = _cameraNames.length + 1;
    String newCamName = 'Camera $nextNum';

    while (_cameraNames.contains(newCamName)) {
      nextNum++;
      newCamName = 'Camera $nextNum';
    }

    setState(() {
      _cameraNames.add(newCamName);
      _cameraIps[newCamName] = '';
      _cameraIsModel2[newCamName] = false; // Default to Model 1
    });

    await prefs.setStringList('camera_names_list', _cameraNames);
  }

  Future<void> _deleteCamera(int indexToDelete) async {
    final prefs = await SharedPreferences.getInstance();
    String camName = _cameraNames[indexToDelete];

    setState(() {
      _cameraNames.removeAt(indexToDelete);
      _cameraIps.remove(camName);
      _cameraIsModel2.remove(camName);

      if (_cameraNames.isEmpty) {
        _cameraNames.add('Camera 1');
        _cameraIps['Camera 1'] = '';
        _cameraIsModel2['Camera 1'] = false;
      }
    });

    await prefs.remove('ip_$camName');
    await prefs.remove('isModel2_$camName'); // 🚀 NEW: Clean up the saved model type
    await prefs.setStringList('camera_names_list', _cameraNames);
  }

  void _showDeleteConfirmation(String cameraName, int index) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: _cardDark,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16), side: BorderSide(color: Colors.white.withOpacity(0.1))),
        title: Row(
          children: [
            const Icon(Icons.warning_amber_rounded, color: _dangerRed),
            const SizedBox(width: 12),
            Text('Delete $cameraName?', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
          ],
        ),
        content: const Text('Are you sure you want to remove this camera? This action cannot be undone.', style: TextStyle(color: Colors.white54, fontSize: 14)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('CANCEL', style: TextStyle(color: Colors.white54)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: _dangerRed, foregroundColor: Colors.white),
            onPressed: () {
              Navigator.pop(context);
              _deleteCamera(index);
            },
            child: const Text('DELETE', style: TextStyle(fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }

  void _showSetupDialog(String currentName, int index) {
    TextEditingController nameController = TextEditingController(text: currentName);
    TextEditingController ipController = TextEditingController(text: _cameraIps[currentName]);

    // 🚀 NEW: Local state for the dialog's dropdown
    bool localIsModel2 = _cameraIsModel2[currentName] ?? false;
    String errorMessage = "";

    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              backgroundColor: _cardDark,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16), side: BorderSide(color: Colors.white.withOpacity(0.1))),
              title: const Row(
                children: [
                  Icon(Icons.router, color: _accentCyan),
                  SizedBox(width: 12),
                  Text('Camera Setup', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                ],
              ),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Camera Name (Must match Folder Name exactly):', style: TextStyle(color: Colors.white54, fontSize: 14)),
                  const SizedBox(height: 8),
                  TextField(
                    controller: nameController,
                    style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                    decoration: InputDecoration(
                      hintText: 'e.g. Main Door',
                      filled: true,
                      fillColor: _bgDark,
                      prefixIcon: const Icon(Icons.folder, color: _accentCyan),
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide.none),
                      errorText: errorMessage.isNotEmpty ? errorMessage : null,
                    ),
                  ),
                  const SizedBox(height: 24),

                  const Text('Camera IP Address / Link:', style: TextStyle(color: Colors.white54, fontSize: 14)),
                  const SizedBox(height: 8),
                  TextField(
                    controller: ipController,
                    style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                    decoration: InputDecoration(
                      hintText: 'e.g. 192.168.1.7',
                      filled: true,
                      fillColor: _bgDark,
                      prefixIcon: const Icon(Icons.link, color: Colors.greenAccent),
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide.none),
                    ),
                  ),
                  const SizedBox(height: 24),

                  // 🚀 NEW: Camera Model Dropdown
                  const Text('Camera Model:', style: TextStyle(color: Colors.white54, fontSize: 14)),
                  const SizedBox(height: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    decoration: BoxDecoration(
                      color: _bgDark,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: DropdownButtonHideUnderline(
                      child: DropdownButton<bool>(
                        value: localIsModel2,
                        dropdownColor: _cardDark,
                        isExpanded: true,
                        icon: const Icon(Icons.expand_more, color: _accentCyan),
                        items: const [
                          DropdownMenuItem(
                              value: false,
                              child: Text('Model 1 - 3D (/ftp)', style: TextStyle(color: Colors.white))
                          ),
                          DropdownMenuItem(
                              value: true,
                              child: Text('Model 2 - 2D (/ftpserver/table/)', style: TextStyle(color: Colors.white))
                          ),
                        ],
                        onChanged: (val) {
                          if (val != null) setDialogState(() => localIsModel2 = val);
                        },
                      ),
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
                  onPressed: () async {
                    String newName = nameController.text.trim();
                    String newIp = ipController.text.trim();

                    if (newName.isEmpty) {
                      setDialogState(() => errorMessage = "Name cannot be empty");
                      return;
                    }
                    if (newName != currentName && _cameraNames.contains(newName)) {
                      setDialogState(() => errorMessage = "This name already exists");
                      return;
                    }

                    final prefs = await SharedPreferences.getInstance();

                    setState(() {
                      if (newName != currentName) {
                        _cameraNames[index] = newName;
                        _cameraIps.remove(currentName);
                        _cameraIsModel2.remove(currentName);
                        prefs.remove('ip_$currentName');
                        prefs.remove('isModel2_$currentName');
                      }
                      _cameraIps[newName] = newIp;
                      _cameraIsModel2[newName] = localIsModel2; // Save locally
                    });

                    await prefs.setString('ip_$newName', newIp);
                    await prefs.setBool('isModel2_$newName', localIsModel2); // Save to disk
                    await prefs.setStringList('camera_names_list', _cameraNames);

                    if (context.mounted) Navigator.pop(context);
                  },
                  child: const Text('SAVE SETTINGS', style: TextStyle(fontWeight: FontWeight.bold)),
                ),
              ],
            );
          }
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _bgDark,
      appBar: AppBar(
        backgroundColor: _bgDark,
        title: const Text('Camera Configuration', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
        iconTheme: const IconThemeData(color: Colors.white),
        elevation: 0,
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _addNewCamera,
        backgroundColor: _accentCyan,
        foregroundColor: Colors.black,
        icon: const Icon(Icons.add_a_photo),
        label: const Text("Add Camera", style: TextStyle(fontWeight: FontWeight.bold)),
      ),
      body: ListView.builder(
        padding: const EdgeInsets.all(24),
        itemCount: _cameraNames.length,
        itemBuilder: (context, index) {
          String camName = _cameraNames[index];
          String currentIp = _cameraIps[camName] ?? '';
          bool isModel2 = _cameraIsModel2[camName] ?? false; // 🚀 Check model
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
                  // Icon changes based on model type!
                  child: Icon(isModel2 ? Icons.folder_shared : Icons.camera_alt, color: hasIp ? _accentCyan : Colors.white38),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(camName, style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold)),
                      const SizedBox(height: 4),
                      Text(
                        // 🚀 NEW: Shows the selected model in the list!
                          hasIp ? 'IP: $currentIp  •  ${isModel2 ? "2D Model" : "3D Model"}' : 'No IP configured',
                          style: TextStyle(color: hasIp ? Colors.greenAccent : Colors.redAccent, fontSize: 14)
                      ),
                    ],
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.edit, color: Colors.white54),
                  onPressed: () => _showSetupDialog(camName, index),
                  tooltip: 'Edit Camera & IP',
                ),
                IconButton(
                  icon: const Icon(Icons.delete_outline, color: _dangerRed),
                  onPressed: () => _showDeleteConfirmation(camName, index),
                  tooltip: 'Delete Camera',
                ),
                const SizedBox(width: 8),
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
                                ipAddress: currentIp,
                                initialIsModel2: isModel2 // 🚀 Pass the saved preference
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
  final bool initialIsModel2; // 🚀 NEW: Accept the saved preference

  const WindowsCameraWebScreen({
    Key? key,
    required this.cameraName,
    required this.ipAddress,
    required this.initialIsModel2,
  }) : super(key: key);

  @override
  State<WindowsCameraWebScreen> createState() => _WindowsCameraWebScreenState();
}

class _WindowsCameraWebScreenState extends State<WindowsCameraWebScreen> {
  final _webviewController = WebviewController();
  bool _isWebviewInitialized = false;
  late bool _isModel2; // 🚀 Initialize this from the widget parameter

  @override
  void initState() {
    super.initState();
    _isModel2 = widget.initialIsModel2; // Set default based on user's saved choice
    initPlatformState();
  }

  Future<void> initPlatformState() async {
    String baseUrl = widget.ipAddress.startsWith('http')
        ? widget.ipAddress
        : 'http://${widget.ipAddress}';

    // Safety check: Remove trailing slash if user accidentally typed "192.168.1.7/"
    if (baseUrl.endsWith('/')) {
      baseUrl = baseUrl.substring(0, baseUrl.length - 1);
    }

    String targetUrl = _isModel2
        ? '$baseUrl/ftpserver/table/'
        : '$baseUrl/ftp';

    try {
      await _webviewController.initialize();
      await _webviewController.loadUrl(targetUrl);

      if (!mounted) return;

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

  void _switchCameraModel(bool isModel2) {
    setState(() {
      _isModel2 = isModel2;
    });

    if (_isWebviewInitialized) {
      String baseUrl = widget.ipAddress.startsWith('http')
          ? widget.ipAddress
          : 'http://${widget.ipAddress}';

      if (baseUrl.endsWith('/')) {
        baseUrl = baseUrl.substring(0, baseUrl.length - 1);
      }

      String targetUrl = isModel2
          ? '$baseUrl/ftpserver/table/'
          : '$baseUrl/ftp';

      _webviewController.loadUrl(targetUrl);
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
          PopupMenuButton<bool>(
            icon: const Icon(Icons.swap_horiz, color: _accentCyan),
            tooltip: 'Temporary Switch Model',
            color: _cardDark,
            onSelected: (bool isModel2) {
              _switchCameraModel(isModel2);
            },
            itemBuilder: (context) => [
              PopupMenuItem(
                value: false,
                child: Row(
                  children: [
                    Icon(Icons.camera_alt, color: !_isModel2 ? _accentCyan : Colors.white54, size: 20),
                    const SizedBox(width: 12),
                    Text("Model 1 (3D)", style: TextStyle(color: !_isModel2 ? _accentCyan : Colors.white)),
                  ],
                ),
              ),
              PopupMenuItem(
                value: true,
                child: Row(
                  children: [
                    Icon(Icons.folder_shared, color: _isModel2 ? _accentCyan : Colors.white54, size: 20),
                    const SizedBox(width: 12),
                    Text("Model 2 (2D)", style: TextStyle(color: _isModel2 ? _accentCyan : Colors.white)),
                  ],
                ),
              ),
            ],
          ),

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
          ? Webview(_webviewController)
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