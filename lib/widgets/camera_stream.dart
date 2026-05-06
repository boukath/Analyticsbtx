// lib/widgets/camera_stream.dart
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:webview_windows/webview_windows.dart';

enum CameraType { unknown, model1_3d, model2_2d, error }

class CameraStreamWidget extends StatefulWidget {
  final String ipAddress;
  const CameraStreamWidget({Key? key, required this.ipAddress}) : super(key: key);

  @override
  State<CameraStreamWidget> createState() => _CameraStreamWidgetState();
}

class _CameraStreamWidgetState extends State<CameraStreamWidget> {
  Timer? _pollingTimer;
  Uint8List? _lastFrame;
  WebviewController? _webviewController;
  bool _isWebviewInitialized = false;

  CameraType _cameraType = CameraType.unknown;
  String _status = "Detecting Camera Model...";
  bool _isError = false;
  bool _isDisposed = false;

  @override
  void initState() {
    super.initState();
    _detectAndStart();
  }

  @override
  void didUpdateWidget(covariant CameraStreamWidget oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.ipAddress != widget.ipAddress) {
      _cleanup();
      _cameraType = CameraType.unknown;
      _isError = false;
      _status = "Reconnecting...";
      _detectAndStart();
    }
  }

  void _cleanup() {
    _pollingTimer?.cancel();
    _webviewController?.dispose();
    _webviewController = null;
    _isWebviewInitialized = false;
    _lastFrame = null;
  }

  @override
  void dispose() {
    _isDisposed = true;
    _cleanup();
    super.dispose();
  }

  Future<void> _detectAndStart() async {
    if (_isDisposed) return;
    String baseIp = widget.ipAddress.trim().replaceAll('http://', '').replaceAll('https://', '').split('/').first;

    setState(() => _status = "Checking 3D Model API...");
    if (await _testModel1(baseIp)) {
      if (_isDisposed) return;
      setState(() { _cameraType = CameraType.model1_3d; _status = "Connected (3D Model)"; });
      _startModel1Polling(baseIp);
      return;
    }

    setState(() => _status = "Checking 2D Model API...");
    if (await _testModel2(baseIp)) {
      if (_isDisposed) return;
      setState(() { _cameraType = CameraType.model2_2d; _status = "Connected (2D Model)"; });
      await _startModel2Webview(baseIp);
      return;
    }

    if (!_isDisposed) {
      setState(() { _isError = true; _cameraType = CameraType.error; _status = "Unrecognized Camera Model or Offline"; });
    }
  }

  Future<bool> _testModel1(String baseIp) async {
    try {
      HttpClient client = HttpClient()..connectionTimeout = const Duration(seconds: 2);
      final request = await client.getUrl(Uri.parse('http://$baseIp/api/getpreview/?w=320&h=240'));
      final response = await request.close().timeout(const Duration(seconds: 2));
      return response.statusCode == 200 && response.headers.contentType?.primaryType == 'image';
    } catch (e) { return false; }
  }

  Future<bool> _testModel2(String baseIp) async {
    try {
      HttpClient client = HttpClient()..connectionTimeout = const Duration(seconds: 2);
      final request = await client.getUrl(Uri.parse('http://$baseIp/control/countingsource/'));
      final response = await request.close().timeout(const Duration(seconds: 2));
      if (response.statusCode == 200) {
        final body = await consolidateHttpClientResponseBytes(response);
        final content = utf8.decode(body, allowMalformed: true);
        return content.contains('id_ImagePreview');
      }
      return false;
    } catch (e) { return false; }
  }

  void _startModel1Polling(String baseIp) {
    _fetchModel1Frame(baseIp);
    _pollingTimer = Timer.periodic(const Duration(milliseconds: 1500), (_) { if (!_isDisposed) _fetchModel1Frame(baseIp); });
  }

  Future<void> _fetchModel1Frame(String baseIp) async {
    try {
      HttpClient client = HttpClient()..connectionTimeout = const Duration(seconds: 2);
      final url = "http://$baseIp/api/getpreview/?w=320&h=240&${DateTime.now().millisecondsSinceEpoch}";
      final request = await client.getUrl(Uri.parse(url));
      final response = await request.close().timeout(const Duration(seconds: 3));

      if (response.statusCode == 200) {
        final bytes = await consolidateHttpClientResponseBytes(response);
        if (!_isDisposed && bytes.isNotEmpty) {
          setState(() { _lastFrame = bytes; _isError = false; });
        }
      }
    } catch (e) {
      if (!_isDisposed) setState(() { _isError = true; _status = "Connection Lost"; });
    }
  }

  Future<void> _startModel2Webview(String baseIp) async {
    _webviewController = WebviewController();
    try {
      await _webviewController!.initialize();
      if (_isDisposed) return;
      await _webviewController!.loadUrl('http://$baseIp/control/countingsource/');
      setState(() => _isWebviewInitialized = true);

      Timer.periodic(const Duration(seconds: 1), (timer) {
        if (_isDisposed || _webviewController == null) { timer.cancel(); return; }
        try {
          _webviewController!.executeScript("""
            var cvs = document.getElementById('id_ImagePreview');
            if(cvs && !document.getElementById('boitex_custom_container')) {
               var container = document.createElement('div');
               container.id = 'boitex_custom_container';
               container.style.position = 'fixed';
               container.style.top = '0';
               container.style.left = '0';
               container.style.width = '100vw';
               container.style.height = '100vh';
               container.style.backgroundColor = 'black';
               container.style.zIndex = '999999';
               container.style.display = 'flex';
               container.style.justifyContent = 'center';
               container.style.alignItems = 'center';
               document.body.style.overflow = 'hidden';
               cvs.style.display = 'block';
               cvs.style.width = '100%';
               cvs.style.height = '100%';
               cvs.style.objectFit = 'contain';
               container.appendChild(cvs);
               document.body.appendChild(container);
            }
          """);
        } catch(e) {}
      });
    } catch (e) {
      if (!_isDisposed) setState(() { _isError = true; _status = "Webview Error: $e"; });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_cameraType == CameraType.model1_3d && _lastFrame != null) {
      return Stack(
        fit: StackFit.expand,
        children: [
          Image.memory(_lastFrame!, fit: BoxFit.contain, gaplessPlayback: true),
          if (_isError) _buildErrorOverlay(),
        ],
      );
    }

    if (_cameraType == CameraType.model2_2d && _isWebviewInitialized) {
      return Stack(
        fit: StackFit.expand,
        children: [
          Webview(_webviewController!),
          if (_isError) _buildErrorOverlay(),
        ],
      );
    }

    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          if (_isError) const Icon(Icons.videocam_off, color: Colors.redAccent, size: 56)
          else const CircularProgressIndicator(color: Color(0xFF00F0FF)),
          const SizedBox(height: 24),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24),
            child: Text(
              _status,
              textAlign: TextAlign.center,
              style: TextStyle(color: _isError ? Colors.redAccent : Colors.white54, fontWeight: FontWeight.w800, fontSize: 16),
            ),
          ),
          const SizedBox(height: 8),
          Text(widget.ipAddress, style: const TextStyle(color: Colors.white24, fontSize: 12, fontWeight: FontWeight.bold)),
        ],
      ),
    );
  }

  Widget _buildErrorOverlay() {
    return Positioned(
      top: 16, right: 16,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          color: Colors.black.withOpacity(0.8),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: Colors.redAccent.withOpacity(0.5)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.warning_rounded, color: Colors.redAccent, size: 20),
            const SizedBox(width: 8),
            Text(_status, style: const TextStyle(color: Colors.redAccent, fontSize: 13, fontWeight: FontWeight.bold)),
          ],
        ),
      ),
    );
  }
}