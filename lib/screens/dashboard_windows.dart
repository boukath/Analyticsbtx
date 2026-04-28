// lib/screens/dashboard_windows.dart

import 'dart:ui';
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:shared_preferences/shared_preferences.dart';

// 🚀 Desktop Window and Tray Managers
import 'package:window_manager/window_manager.dart';
import 'package:tray_manager/tray_manager.dart';

import 'cloud_sync_screen.dart';
import '../services/ftp_service.dart';
import 'ftp_server_screen.dart';
import '../models/people_count.dart';
import '../services/folder_scanner_service.dart';
import '../core/data_aggregator.dart';
import '../services/pdf_export_service.dart';
import '../services/csv_export_service.dart';
import 'camera_ftp_setup_screen.dart';
import 'export_screen.dart';
import 'developer_screen.dart';
import 'store_profile_screen.dart';
import 'package:webview_windows/webview_windows.dart';
import '../services/firebase_sync_service.dart';

enum ChartFilter { hourly, daily }

class DashboardScreen extends StatefulWidget {
  const DashboardScreen({Key? key}) : super(key: key);

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> with WindowListener, TrayListener {
  List<PeopleCount> _rawData = [];
  List<PeopleCount> _displayedData = [];
  Map<String, List<PeopleCount>> _perDoorData = {};
  bool _isLoading = false;
  String? _selectedFolderPath;
  ChartFilter _currentFilter = ChartFilter.hourly;
  DateTimeRange? _selectedDateRange;

  // 🚀 Flag to toggle between Chart Mode and Table Mode
  bool _isTableMode = false;

  // 🚀 Flag to toggle POS (Retail) vs Footfall (Mall) mode
  bool _enablePosFeatures = true;

  // 🚀 Flag for Single Entrance (Merge) mode
  bool _isSingleEntrance = false;

  // =========================================================================
  // 🎨 iOS 26 THEME CONSTANTS & GLASSMORPHISM UTILITIES
  // =========================================================================
  final Color _bgDeep = const Color(0xFF05050A); // Ultra deep black
  final Color _accentCyan = const Color(0xFF00F0FF); // Neon vibrant cyan
  final Color _accentMagenta = const Color(0xFFFF003C); // Neon magenta
  final Color _accentPurple = const Color(0xFF7000FF); // Deep spatial purple
  final Color _accentGrey = const Color(0xFF8E8E93);
  final Color _glassWhiteTint = Colors.white.withOpacity(0.06);
  final Color _glassBorder = Colors.white.withOpacity(0.12);
  final double _glassBlur = 30.0; // High blur for rich frosted effect

  /// Reusable Glassmorphism Container Engine
  Widget _buildGlassContainer({
    required Widget child,
    double? width,
    double? height,
    EdgeInsetsGeometry? padding,
    EdgeInsetsGeometry? margin,
    double borderRadius = 24,
    bool isInteractive = false,
  }) {
    return Container(
      width: width,
      height: height,
      margin: margin,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(borderRadius),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: _glassBlur, sigmaY: _glassBlur),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 300),
            padding: padding,
            decoration: BoxDecoration(
              color: isInteractive ? Colors.white.withOpacity(0.1) : _glassWhiteTint,
              borderRadius: BorderRadius.circular(borderRadius),
              border: Border.all(color: _glassBorder, width: 1.0),
              boxShadow: [
                BoxShadow(color: Colors.black.withOpacity(0.2), blurRadius: 30, spreadRadius: -5),
              ],
            ),
            child: child,
          ),
        ),
      ),
    );
  }

  void _showLinkIpDialog(String cameraName) {
    TextEditingController ipController = TextEditingController(text: _cameraIps[cameraName]);

    showDialog(
      context: context,
      barrierColor: Colors.transparent, // Required for custom blur background
      builder: (context) => Stack(
        children: [
          // Background blur for dialog
          Positioned.fill(child: BackdropFilter(filter: ImageFilter.blur(sigmaX: 15, sigmaY: 15), child: Container(color: Colors.black.withOpacity(0.4)))),
          Center(
            child: Material(
              color: Colors.transparent,
              child: _buildGlassContainer(
                width: 400,
                padding: const EdgeInsets.all(32),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(Icons.link, color: _accentCyan, size: 28),
                        const SizedBox(width: 12),
                        Text('Link IP to ${cameraName.toUpperCase()}', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 18)),
                      ],
                    ),
                    const SizedBox(height: 24),
                    const Text('Enter the Camera IP Address or Link:', style: TextStyle(color: Colors.white70, fontSize: 14)),
                    const SizedBox(height: 12),
                    TextField(
                      controller: ipController,
                      style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                      decoration: InputDecoration(
                        hintText: 'e.g. 192.168.1.7',
                        hintStyle: const TextStyle(color: Colors.white24),
                        filled: true,
                        fillColor: Colors.black.withOpacity(0.3),
                        prefixIcon: Icon(Icons.router, color: _accentCyan),
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: BorderSide(color: _glassBorder)),
                        enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: BorderSide(color: _glassBorder)),
                        focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: BorderSide(color: _accentCyan, width: 2)),
                      ),
                    ),
                    const SizedBox(height: 32),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        TextButton(
                          onPressed: () => Navigator.pop(context),
                          child: const Text('CANCEL', style: TextStyle(color: Colors.white54, fontWeight: FontWeight.w600)),
                        ),
                        const SizedBox(width: 16),
                        ElevatedButton(
                          style: ElevatedButton.styleFrom(
                            backgroundColor: _accentCyan,
                            foregroundColor: Colors.black,
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                          ),
                          onPressed: () async {
                            String newIp = ipController.text.trim();
                            final prefs = await SharedPreferences.getInstance();
                            await prefs.setString('ip_$cameraName', newIp);
                            setState(() { _cameraIps[cameraName] = newIp; });
                            if (context.mounted) Navigator.pop(context);
                          },
                          child: const Text('SAVE IP', style: TextStyle(fontWeight: FontWeight.w900, letterSpacing: 0.5)),
                        ),
                      ],
                    )
                  ],
                ),
              ),
            ),
          )
        ],
      ),
    );
  }

  Timer? _autoRefreshTimer;
  String _localIp = "";
  bool _isFtpRunning = false;
  Map<String, String> _cameraIps = {};
  Timer? _securityTimer;
  bool _isIpMismatch = false;
  String _expectedIp = "";
  String _actualIp = "";
  bool _isAlertSilenced = false;
  bool _isAlertDialogOpen = false;
  bool _isFrench = false;
  int _workingMinuteStart = 0;
  int _workingMinuteEnd = 1439;
  List<String> _availableCameras = ['All Doors'];
  String _selectedCamera = 'All Doors';
  int _totalIn = 0;
  int _totalOut = 0;
  int _occupancy = 0;
  String _peakHour = "--:--";
  Map<String, Map<String, num>> _posDatabase = {};
  double _currentCa = 0;
  int _currentClients = 0;
  int _currentArticles = 0;
  String _storeName = "My Store";
  String _storeLocation = "MAIN BRANCH";
  String? _storeLogoPath;
  bool _isCompareMode = false;
  List<PeopleCount> _compareDisplayedData = [];
  int _compareTotalIn = 0;
  int _compareTotalOut = 0;
  int _compareTotalVisitors = 0;
  double _compareCa = 0;
  int _compareClients = 0;
  int _compareArticles = 0;

  final FolderScannerService _scannerService = FolderScannerService();

  @override
  void initState() {
    super.initState();
    if (!kIsWeb) {
      windowManager.addListener(this);
      trayManager.addListener(this);
      _initSystemTray();
    }
    _loadLanguagePref();
    _loadWorkingHoursPref();
    _loadStoreProfile();
    _loadPosDatabase();
    _loadSavedFolder();
    _checkFtpStatus();
    _startSecurityMonitor();
    _loadCameraIps();
  }

  Future<void> _initSystemTray() async {
    await trayManager.setIcon('assets/app_icon.ico');
    Menu menu = Menu(
      items: [
        MenuItem(key: 'show_app', label: 'Show Dashboard'),
        MenuItem.separator(),
        MenuItem(key: 'exit_app', label: 'Exit Analytics completely'),
      ],
    );
    await trayManager.setContextMenu(menu);
  }

  @override
  void onWindowClose() async {
    bool isPreventClose = await windowManager.isPreventClose();
    if (isPreventClose) await windowManager.hide();
  }

  @override
  void onTrayIconMouseDown() {
    windowManager.show();
    windowManager.focus();
  }

  @override
  void onTrayMenuItemClick(MenuItem menuItem) {
    if (menuItem.key == 'show_app') {
      windowManager.show();
      windowManager.focus();
    } else if (menuItem.key == 'exit_app') {
      windowManager.destroy();
    }
  }

  Future<void> _performFirebaseSync() async {
    if (_displayedData.isEmpty) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Starting Cloud Sync...'), backgroundColor: Colors.orangeAccent));
    final now = DateTime.now();
    String dateStr = "${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}";
    Map<String, dynamic>? posDataForToday = _posDatabase[dateStr];
    await FirebaseSyncService.uploadDailySummary(perDoorData: _perDoorData, totalIn: _totalIn, totalOut: _totalOut, posDataForToday: _enablePosFeatures ? posDataForToday : null);
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(_isFrench ? 'Synchronisation réussie !' : 'Cloud Sync Successful!'), backgroundColor: Colors.greenAccent, behavior: SnackBarBehavior.floating));
    }
  }

  @override
  void dispose() {
    if (!kIsWeb) {
      windowManager.removeListener(this);
      trayManager.removeListener(this);
    }
    _autoRefreshTimer?.cancel();
    _securityTimer?.cancel();
    FtpService.stopServer();
    super.dispose();
  }

  Future<void> _loadCameraIps() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      final keys = prefs.getKeys();
      for(String key in keys) {
        if (key.startsWith('ip_')) {
          String camName = key.substring(3);
          _cameraIps[camName] = prefs.getString(key) ?? '';
        }
      }
    });
  }

  Future<void> _loadWorkingHoursPref() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _workingMinuteStart = prefs.getInt('working_minute_start') ?? 0;
      _workingMinuteEnd = prefs.getInt('working_minute_end') ?? 1439;
    });
  }

  Future<void> _loadLanguagePref() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _isFrench = prefs.getString('app_language') == 'fr';
    });
  }

  Future<void> _toggleLanguage() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() { _isFrench = !_isFrench; });
    await prefs.setString('app_language', _isFrench ? 'fr' : 'en');
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(_isFrench ? 'Langue changée en Français' : 'Language changed to English', style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.white)),
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            backgroundColor: _accentCyan,
            duration: const Duration(seconds: 2),
          )
      );
    }
  }

  void _startSecurityMonitor() {
    _securityTimer = Timer.periodic(const Duration(seconds: 10), (timer) async {
      final prefs = await SharedPreferences.getInstance();
      String savedIp = prefs.getString('ftp_ip') ?? '';
      if (savedIp.isEmpty) return;
      String currentIp = await FtpService.getLocalIpAddress();

      if (mounted) {
        setState(() {
          _expectedIp = savedIp;
          _actualIp = currentIp;
          _isIpMismatch = (currentIp != savedIp);
        });
        if (!_isIpMismatch) _isAlertSilenced = false;
        int totalVisitors = _totalIn + _totalOut;
        if (_isIpMismatch && totalVisitors == 0 && !_isAlertSilenced && !_isAlertDialogOpen) {
          _showPasswordAlertDialog();
        }
      }
    });
  }

  void _showPasswordAlertDialog() {
    _isAlertDialogOpen = true;
    TextEditingController passCtrl = TextEditingController();
    String errorMessage = "";

    showDialog(
      context: context,
      barrierDismissible: false,
      barrierColor: Colors.transparent,
      builder: (BuildContext c) {
        return Stack(
          children: [
            Positioned.fill(child: BackdropFilter(filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20), child: Container(color: Colors.black.withOpacity(0.6)))),
            Center(
              child: StatefulBuilder(
                  builder: (context, setDialogState) {
                    return Material(
                      color: Colors.transparent,
                      child: _buildGlassContainer(
                        width: 500,
                        padding: const EdgeInsets.all(40),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                const Icon(Icons.warning_amber_rounded, color: Colors.redAccent, size: 40),
                                const SizedBox(width: 16),
                                Text(
                                    _isFrench ? "ERREUR RÉSEAU CRITIQUE" : "CRITICAL NETWORK ERROR",
                                    style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w900, fontSize: 20, letterSpacing: 1.0)
                                ),
                              ],
                            ),
                            const SizedBox(height: 24),
                            Text(
                              _isFrench
                                  ? "L'adresse IP du PC a changé et AUCUN TRAFIC (0) n'est enregistré !\n\nIP Attendue: $_expectedIp\nIP Actuelle: ${_actualIp == '127.0.0.1' ? 'DÉCONNECTÉ' : _actualIp}\n\nVeuillez réparer le réseau immédiatement, ou entrez le mot de passe technicien pour désactiver cette alerte."
                                  : "The PC's IP Address has changed and NO TRAFFIC (0) is being recorded!\n\nExpected IP: $_expectedIp\nCurrent IP: ${_actualIp == '127.0.0.1' ? 'DISCONNECTED' : _actualIp}\n\nPlease fix the network immediately, or enter the technician password to silence this alert.",
                              style: const TextStyle(color: Colors.white70, fontSize: 16, height: 1.6),
                            ),
                            const SizedBox(height: 32),
                            TextField(
                              controller: passCtrl,
                              obscureText: true,
                              style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                              decoration: InputDecoration(
                                labelText: _isFrench ? 'Mot de passe technicien' : 'Technician Password',
                                labelStyle: const TextStyle(color: Colors.white54),
                                filled: true,
                                fillColor: Colors.black.withOpacity(0.4),
                                border: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: BorderSide(color: _glassBorder)),
                                enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: BorderSide(color: _glassBorder)),
                                focusedBorder: const OutlineInputBorder(borderRadius: BorderRadius.all(Radius.circular(16)), borderSide: BorderSide(color: Colors.redAccent, width: 2)),
                                errorText: errorMessage.isNotEmpty ? errorMessage : null,
                              ),
                            ),
                            const SizedBox(height: 40),
                            Row(
                              mainAxisAlignment: MainAxisAlignment.end,
                              children: [
                                TextButton(
                                  onPressed: () {
                                    _isAlertDialogOpen = false;
                                    Navigator.of(c).pop();
                                    Navigator.push(context, MaterialPageRoute(builder: (context) => const FtpServerScreen()));
                                  },
                                  child: Text(
                                      _isFrench ? "RÉPARER LE RÉSEAU" : "FIX NETWORK",
                                      style: const TextStyle(color: Colors.cyanAccent, fontWeight: FontWeight.bold, letterSpacing: 1)
                                  ),
                                ),
                                const SizedBox(width: 16),
                                ElevatedButton(
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: Colors.redAccent,
                                    foregroundColor: Colors.white,
                                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                                    padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
                                  ),
                                  onPressed: () {
                                    if (passCtrl.text == "Boitexinfo" || passCtrl.text == "bi2026" || passCtrl.text == "boitexinfodev") {
                                      _isAlertSilenced = true;
                                      _isAlertDialogOpen = false;
                                      Navigator.of(c).pop();
                                    } else {
                                      setDialogState(() { errorMessage = _isFrench ? "Mot de passe incorrect !" : "Incorrect Password!"; });
                                    }
                                  },
                                  child: Text(_isFrench ? "SILENCIEUX" : "SILENCE ALERT", style: const TextStyle(fontWeight: FontWeight.w900)),
                                ),
                              ],
                            )
                          ],
                        ),
                      ),
                    );
                  }
              ),
            )
          ],
        );
      },
    ).then((_) { _isAlertDialogOpen = false; });
  }

  Future<void> _openDeveloperScreen() async {
    await Navigator.push(
        context,
        MaterialPageRoute(
            builder: (context) => DeveloperScreen(
              isFrench: _isFrench,
              onSelectDataSource: () {
                Navigator.pop(context);
                _pickFolderAndLoadData();
              },
              onForceSync: () { if (_rawData.isNotEmpty) _performFirebaseSync(); },
              currentFolderPath: _selectedFolderPath,
            )
        )
    );
    _loadCameraIps();
    _checkFtpStatus();
    if (mounted) setState(() {});
  }

  Future<void> _loadStoreProfile() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _storeName = prefs.getString('store_name') ?? "My Store";
      _storeLocation = prefs.getString('store_location') ?? "MAIN BRANCH";
      _storeLogoPath = prefs.getString('store_logo_path');
      _enablePosFeatures = prefs.getBool('enable_pos_features') ?? true;
      _isSingleEntrance = prefs.getBool('is_single_entrance') ?? false;
    });
  }

  Future<void> _checkFtpStatus() async {
    String ip = await FtpService.getLocalIpAddress();
    if (mounted) setState(() { _isFtpRunning = FtpService.isRunning; _localIp = ip; });
  }

  Future<void> _loadSavedFolder() async {
    final prefs = await SharedPreferences.getInstance();
    final savedPath = prefs.getString('saved_data_folder');
    if (savedPath != null && savedPath.isNotEmpty) _processDataFromPath(savedPath);
  }

  Future<void> _loadPosDatabase() async {
    final prefs = await SharedPreferences.getInstance();
    final String? posJson = prefs.getString('pos_database');
    if (posJson != null) {
      setState(() { _posDatabase = Map<String, Map<String, dynamic>>.from(jsonDecode(posJson)).map((k, v) => MapEntry(k, Map<String, num>.from(v))); });
    }
  }

  Future<void> _savePosData(String date, double ca, int clients, int articles) async {
    setState(() => _posDatabase[date] = {"ca": ca, "clients": clients, "articles": articles});
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('pos_database', jsonEncode(_posDatabase));
    _calculatePosMetrics();
  }

  void _calculatePosMetrics() {
    _currentCa = 0; _currentClients = 0; _currentArticles = 0;
    _compareCa = 0; _compareClients = 0; _compareArticles = 0;
    if (_selectedDateRange != null) {
      DateTime start = _selectedDateRange!.start;
      DateTime end = _selectedDateRange!.end;
      for (DateTime d = start; d.isBefore(end.add(const Duration(days: 1))); d = d.add(const Duration(days: 1))) {
        String dateStr = _formatDateOnly(d);
        if (_posDatabase.containsKey(dateStr)) {
          _currentCa += _posDatabase[dateStr]!['ca'] ?? 0;
          _currentClients += (_posDatabase[dateStr]!['clients'] ?? 0).toInt();
          _currentArticles += (_posDatabase[dateStr]!['articles'] ?? 0).toInt();
        }
      }
      if (_isCompareMode) {
        Duration duration = end.difference(start);
        DateTime compareEnd = start.subtract(const Duration(days: 1));
        DateTime compareStart = compareEnd.subtract(duration);
        for (DateTime d = compareStart; d.isBefore(compareEnd.add(const Duration(days: 1))); d = d.add(const Duration(days: 1))) {
          String dateStr = _formatDateOnly(d);
          if (_posDatabase.containsKey(dateStr)) {
            _compareCa += _posDatabase[dateStr]!['ca'] ?? 0;
            _compareClients += (_posDatabase[dateStr]!['clients'] ?? 0).toInt();
            _compareArticles += (_posDatabase[dateStr]!['articles'] ?? 0).toInt();
          }
        }
      }
    }
  }

  Future<void> _pickFolderAndLoadData() async {
    String? folderPath = await FilePicker.platform.getDirectoryPath();
    if (folderPath != null) {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('saved_data_folder', folderPath);
      _processDataFromPath(folderPath);
    }
  }

  Future<void> _processDataFromPath(String folderPath) async {
    setState(() { _isLoading = true; _selectedFolderPath = folderPath; _selectedDateRange = null; });
    List<PeopleCount> loadedData = await _scannerService.loadScbDataFromFolder(folderPath);
    setState(() {
      _rawData = loadedData;
      if (_rawData.isNotEmpty) {
        DateTime maxDate = DateTime(2000);
        for (var item in _rawData) {
          var dateParts = item.date.split('/');
          if (dateParts.length == 3) {
            DateTime rowDate = DateTime(int.parse(dateParts[2]), int.parse(dateParts[1]), int.parse(dateParts[0]));
            if (rowDate.isAfter(maxDate)) maxDate = rowDate;
          }
        }
        if (maxDate.year == 2000) { DateTime now = DateTime.now(); maxDate = DateTime(now.year, now.month, now.day); }
        _selectedDateRange = DateTimeRange(start: maxDate, end: maxDate);
        Set<String> uniqueIds = _rawData.map((e) => e.doorName).toSet();
        List<String> sortedIds = uniqueIds.toList()..sort();
        _availableCameras = ['All Doors', ...sortedIds];
        _selectedCamera = 'All Doors';
      }
      _applyFilter();
      _isLoading = false;
    });
    _startAutoRefresh();
  }

  void _startAutoRefresh() {
    _autoRefreshTimer?.cancel();
    _autoRefreshTimer = Timer.periodic(const Duration(seconds: 60), (timer) => _refreshDataSilently());
  }

  Future<void> _refreshDataSilently() async {
    if (_selectedFolderPath == null) return;
    List<PeopleCount> latestData = await _scannerService.loadScbDataFromFolder(_selectedFolderPath!);
    if (mounted) {
      setState(() {
        _rawData = latestData;
        if (_rawData.isNotEmpty) {
          Set<String> uniqueIds = _rawData.map((e) => e.doorName).toSet();
          List<String> sortedIds = uniqueIds.toList()..sort();
          if (sortedIds.length != (_availableCameras.length - 1)) _availableCameras = ['All Doors', ...sortedIds];
        }
        _applyFilter();
      });
    }
  }

  void _applyFilter() {
    setState(() {
      List<PeopleCount> filteredData = _rawData.where((item) {
        if (_selectedCamera != 'All Doors' && item.doorName != _selectedCamera) return false;
        var timeParts = item.time.split(':');
        int hour = timeParts.isNotEmpty ? (int.tryParse(timeParts[0]) ?? 0) : 0;
        int minute = timeParts.length > 1 ? (int.tryParse(timeParts[1]) ?? 0) : 0;
        int totalMinutes = (hour * 60) + minute;
        if (totalMinutes < _workingMinuteStart || totalMinutes > _workingMinuteEnd) return false;
        if (_selectedDateRange == null) return true;
        var dateParts = item.date.split('/');
        if (dateParts.length != 3) return true;
        int day = int.parse(dateParts[0]), month = int.parse(dateParts[1]), year = int.parse(dateParts[2]);
        DateTime rowDate = DateTime(year, month, day);
        return rowDate.isAfter(_selectedDateRange!.start.subtract(const Duration(days: 1))) && rowDate.isBefore(_selectedDateRange!.end.add(const Duration(days: 1)));
      }).toList();

      if (_currentFilter == ChartFilter.daily) _displayedData = DataAggregator.aggregateByDay(filteredData);
      else _displayedData = DataAggregator.aggregateByHour(filteredData);

      _perDoorData.clear();
      if (_selectedCamera == 'All Doors' && _availableCameras.length > 2 && !_isCompareMode) {
        for (String door in _availableCameras) {
          if (door == 'All Doors') continue;
          var doorSpecificData = filteredData.where((item) => item.doorName == door).toList();
          if (_currentFilter == ChartFilter.daily) {
            _perDoorData[door] = DataAggregator.aggregateByDay(doorSpecificData);
          } else {
            _perDoorData[door] = DataAggregator.aggregateByHour(doorSpecificData);
          }
        }
      }

      _totalIn = 0; _totalOut = 0; int maxTraffic = 0; _peakHour = "--:--";
      for (var item in _displayedData) {
        _totalIn += item.inCount; _totalOut += item.outCount;
        int totalVisitorsForHour = (item.inCount + item.outCount) ~/ 2;
        if (totalVisitorsForHour > maxTraffic) { maxTraffic = totalVisitorsForHour; _peakHour = item.time; }
      }
      _occupancy = _totalIn - _totalOut;
      if (_occupancy < 0) _occupancy = 0;

      if (_isCompareMode && _selectedDateRange != null) {
        Duration duration = _selectedDateRange!.end.difference(_selectedDateRange!.start);
        DateTime compareEnd = _selectedDateRange!.start.subtract(const Duration(days: 1));
        DateTime compareStart = compareEnd.subtract(duration);

        List<PeopleCount> compareFilteredData = _rawData.where((item) {
          if (_selectedCamera != 'All Doors' && item.doorName != _selectedCamera) return false;
          var timeParts = item.time.split(':');
          int hour = timeParts.isNotEmpty ? (int.tryParse(timeParts[0]) ?? 0) : 0;
          int minute = timeParts.length > 1 ? (int.tryParse(timeParts[1]) ?? 0) : 0;
          int totalMinutes = (hour * 60) + minute;
          if (totalMinutes < _workingMinuteStart || totalMinutes > _workingMinuteEnd) return false;
          var dateParts = item.date.split('/');
          if (dateParts.length != 3) return true;
          int day = int.parse(dateParts[0]), month = int.parse(dateParts[1]), year = int.parse(dateParts[2]);
          DateTime rowDate = DateTime(year, month, day);
          return rowDate.isAfter(compareStart.subtract(const Duration(days: 1))) && rowDate.isBefore(compareEnd.add(const Duration(days: 1)));
        }).toList();

        if (_currentFilter == ChartFilter.daily) _compareDisplayedData = DataAggregator.aggregateByDay(compareFilteredData);
        else _compareDisplayedData = DataAggregator.aggregateByHour(compareFilteredData);

        _compareTotalIn = 0; _compareTotalOut = 0;
        for (var item in _compareDisplayedData) {
          _compareTotalIn += item.inCount; _compareTotalOut += item.outCount;
        }
        _compareTotalVisitors = (_compareTotalIn + _compareTotalOut) ~/ 2;
      }
      _calculatePosMetrics();
    });
  }

  Future<void> _pickDateRange() async {
    DateTimeRange? pickedRange = await showDateRangePicker(
      context: context, firstDate: DateTime(2020), lastDate: DateTime.now().add(const Duration(days: 3650)), initialDateRange: _selectedDateRange,
      builder: (context, child) => Theme(
          data: ThemeData.dark().copyWith(
            colorScheme: ColorScheme.dark(primary: _accentCyan, onPrimary: Colors.black, surface: _bgDeep, onSurface: Colors.white),
            dialogBackgroundColor: _bgDeep,
          ),
          child: child!
      ),
    );
    if (pickedRange != null) { setState(() { _selectedDateRange = pickedRange; _applyFilter(); }); }
  }

  void _shiftDate(int days) {
    setState(() {
      if (_selectedDateRange == null) { DateTime today = DateTime.now(); _selectedDateRange = DateTimeRange(start: today, end: today); }
      else { _selectedDateRange = DateTimeRange(start: _selectedDateRange!.start.add(Duration(days: days)), end: _selectedDateRange!.end.add(Duration(days: days))); }
      _applyFilter();
    });
  }

  String _getFormattedDateString() {
    if (_selectedDateRange == null) return _isFrench ? "De tout temps" : "All Time";
    List<String> monthsEn = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
    List<String> monthsFr = ['Jan', 'Fév', 'Mar', 'Avr', 'Mai', 'Juin', 'Juil', 'Aoû', 'Sep', 'Oct', 'Nov', 'Déc'];
    List<String> months = _isFrench ? monthsFr : monthsEn;
    List<String> weekdaysEn = ['Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday', 'Sunday'];
    List<String> weekdaysFr = ['Lundi', 'Mardi', 'Mercredi', 'Jeudi', 'Vendredi', 'Samedi', 'Dimanche'];
    List<String> weekdays = _isFrench ? weekdaysFr : weekdaysEn;
    DateTime start = _selectedDateRange!.start, end = _selectedDateRange!.end;

    if (start.isAtSameMomentAs(end) || end.difference(start).inDays == 0) {
      String dayName = weekdays[start.weekday - 1];
      if (_isFrench) return "$dayName ${start.day} ${months[start.month - 1]} ${start.year}";
      else return "$dayName, ${months[start.month - 1]} ${start.day}, ${start.year}";
    }
    return "${months[start.month - 1]} ${start.day} - ${months[end.month - 1]} ${end.day}";
  }

  String _formatDateOnly(DateTime d) => "${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}";

  String _formatMinutesToTimeString(int totalMinutes) {
    int h = totalMinutes ~/ 60;
    int m = totalMinutes % 60;
    return "${h.toString().padLeft(2, '0')}:${m.toString().padLeft(2, '0')}";
  }

  void _showWorkingHoursDialog() {
    TimeOfDay startTime = TimeOfDay(hour: _workingMinuteStart ~/ 60, minute: _workingMinuteStart % 60);
    TimeOfDay endTime = TimeOfDay(hour: _workingMinuteEnd ~/ 60, minute: _workingMinuteEnd % 60);

    showDialog(
        context: context,
        barrierColor: Colors.transparent,
        builder: (context) {
          return Stack(
            children: [
              Positioned.fill(child: BackdropFilter(filter: ImageFilter.blur(sigmaX: 15, sigmaY: 15), child: Container(color: Colors.black.withOpacity(0.4)))),
              Center(
                child: Material(
                  color: Colors.transparent,
                  child: StatefulBuilder(
                      builder: (context, setDialogState) {
                        Widget _buildTimeButton(String label, TimeOfDay time, bool isStart) {
                          return Expanded(
                            child: InkWell(
                              onTap: () async {
                                TimeOfDay? picked = await showTimePicker(
                                  context: context,
                                  initialTime: time,
                                  builder: (context, child) => Theme(data: ThemeData.dark().copyWith(colorScheme: ColorScheme.dark(primary: _accentCyan, surface: _bgDeep, onSurface: Colors.white)), child: child!),
                                );
                                if (picked != null) { setDialogState(() { if (isStart) startTime = picked; else endTime = picked; }); }
                              },
                              child: _buildGlassContainer(
                                padding: const EdgeInsets.symmetric(vertical: 24),
                                borderRadius: 16,
                                child: Column(
                                  children: [
                                    Text(label, style: const TextStyle(color: Colors.white54, fontSize: 12, fontWeight: FontWeight.w800, letterSpacing: 2)),
                                    const SizedBox(height: 12),
                                    Text(
                                        "${time.hour.toString().padLeft(2, '0')}:${time.minute.toString().padLeft(2, '0')}",
                                        style: const TextStyle(color: Colors.white, fontSize: 28, fontWeight: FontWeight.w900)
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          );
                        }

                        return _buildGlassContainer(
                          width: 450,
                          padding: const EdgeInsets.all(32),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Icon(Icons.access_time, color: _accentCyan, size: 28),
                                  const SizedBox(width: 12),
                                  Text(_isFrench ? "Heures d'Ouverture" : "Operating Hours", style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 18)),
                                ],
                              ),
                              const SizedBox(height: 16),
                              Text(
                                _isFrench
                                    ? "Filtrez les données au niveau de la minute exacte pour exclure le personnel de nettoyage ou les mouvements en dehors des heures de travail."
                                    : "Filter data down to the exact minute to exclude cleaning staff or movements outside of business hours.",
                                style: const TextStyle(color: Colors.white70, fontSize: 14, height: 1.5),
                              ),
                              const SizedBox(height: 32),
                              Row(
                                children: [
                                  _buildTimeButton(_isFrench ? "OUVERTURE" : "OPENING", startTime, true),
                                  const Padding(padding: EdgeInsets.symmetric(horizontal: 16), child: Icon(Icons.arrow_forward_rounded, color: Colors.white38)),
                                  _buildTimeButton(_isFrench ? "FERMETURE" : "CLOSING", endTime, false),
                                ],
                              ),
                              const SizedBox(height: 32),
                              Row(
                                mainAxisAlignment: MainAxisAlignment.end,
                                children: [
                                  TextButton(onPressed: () => Navigator.pop(context), child: Text(_isFrench ? "ANNULER" : "CANCEL", style: const TextStyle(color: Colors.white54, fontWeight: FontWeight.w600))),
                                  const SizedBox(width: 16),
                                  ElevatedButton(
                                    style: ElevatedButton.styleFrom(backgroundColor: _accentCyan, foregroundColor: Colors.black, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)), padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12)),
                                    onPressed: () async {
                                      int startMins = startTime.hour * 60 + startTime.minute;
                                      int endMins = endTime.hour * 60 + endTime.minute;
                                      if (startMins >= endMins) {
                                        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(_isFrench ? "L'heure de fin doit être après l'heure de début." : "Closing time must be after opening time."), backgroundColor: Colors.redAccent));
                                        return;
                                      }
                                      final prefs = await SharedPreferences.getInstance();
                                      await prefs.setInt('working_minute_start', startMins);
                                      await prefs.setInt('working_minute_end', endMins);
                                      setState(() { _workingMinuteStart = startMins; _workingMinuteEnd = endMins; _applyFilter(); });
                                      Navigator.pop(context);
                                    },
                                    child: Text(_isFrench ? "APPLIQUER" : "APPLY FILTER", style: const TextStyle(fontWeight: FontWeight.w900, letterSpacing: 0.5)),
                                  )
                                ],
                              )
                            ],
                          ),
                        );
                      }
                  ),
                ),
              )
            ],
          );
        }
    );
  }

  Widget _buildTrendBadge(num current, num previous) {
    if (!_isCompareMode) return const SizedBox.shrink();
    if (previous == 0) return const SizedBox.shrink();

    double change = ((current - previous) / previous) * 100;
    bool isPositive = change >= 0;

    return Container(
        margin: const EdgeInsets.only(top: 8),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
            color: isPositive ? Colors.greenAccent.withOpacity(0.15) : Colors.redAccent.withOpacity(0.15),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: isPositive ? Colors.greenAccent.withOpacity(0.3) : Colors.redAccent.withOpacity(0.3))
        ),
        child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(isPositive ? Icons.trending_up : Icons.trending_down, size: 14, color: isPositive ? Colors.greenAccent : Colors.redAccent),
              const SizedBox(width: 6),
              Text('${change.abs().toStringAsFixed(1)}%', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w800, color: isPositive ? Colors.greenAccent : Colors.redAccent)),
            ]
        )
    );
  }

  void _showPosEntryDialog() {
    if (_selectedDateRange == null) return;
    String dateStr = _formatDateOnly(_selectedDateRange!.end);
    TextEditingController caCtrl = TextEditingController(text: (_posDatabase[dateStr]?['ca'] ?? '').toString());
    TextEditingController clientCtrl = TextEditingController(text: (_posDatabase[dateStr]?['clients'] ?? '').toString());
    TextEditingController articleCtrl = TextEditingController(text: (_posDatabase[dateStr]?['articles'] ?? '').toString());

    showDialog(
        context: context,
        barrierColor: Colors.transparent,
        builder: (context) => Stack(
          children: [
            Positioned.fill(child: BackdropFilter(filter: ImageFilter.blur(sigmaX: 15, sigmaY: 15), child: Container(color: Colors.black.withOpacity(0.4)))),
            Center(
              child: Material(
                color: Colors.transparent,
                child: _buildGlassContainer(
                  width: 450,
                  padding: const EdgeInsets.all(32),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.point_of_sale, color: Colors.greenAccent, size: 48),
                      const SizedBox(height: 16),
                      Text(_isFrench ? 'SAISIR LES DONNÉES DE CAISSE' : 'ENTER DAILY POS DATA', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w900, fontSize: 18, letterSpacing: 1.0)),
                      const SizedBox(height: 8),
                      Text('${_isFrench ? "Date : " : "Date: "}${_getFormattedDateString()}', style: const TextStyle(color: Colors.white54, fontSize: 13, fontWeight: FontWeight.w600)),
                      const SizedBox(height: 32),
                      TextField(controller: caCtrl, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold), keyboardType: const TextInputType.numberWithOptions(decimal: true), decoration: InputDecoration(labelText: _isFrench ? 'Chiffre d\'Affaires (DZD)' : 'Revenue (DZD)', labelStyle: const TextStyle(color: Colors.white54), filled: true, fillColor: Colors.black.withOpacity(0.3), border: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: BorderSide(color: _glassBorder)), enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: BorderSide(color: _glassBorder)), focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: const BorderSide(color: Colors.greenAccent, width: 2)), prefixIcon: const Icon(Icons.payments, color: Colors.greenAccent))),
                      const SizedBox(height: 16),
                      TextField(controller: clientCtrl, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold), keyboardType: TextInputType.number, decoration: InputDecoration(labelText: _isFrench ? 'Total Clients' : 'Total Clients', labelStyle: const TextStyle(color: Colors.white54), filled: true, fillColor: Colors.black.withOpacity(0.3), border: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: BorderSide(color: _glassBorder)), enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: BorderSide(color: _glassBorder)), focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: BorderSide(color: _accentCyan, width: 2)), prefixIcon: Icon(Icons.receipt_long, color: _accentCyan))),
                      const SizedBox(height: 16),
                      TextField(controller: articleCtrl, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold), keyboardType: TextInputType.number, decoration: InputDecoration(labelText: _isFrench ? 'Articles Vendus' : 'Articles Sold', labelStyle: const TextStyle(color: Colors.white54), filled: true, fillColor: Colors.black.withOpacity(0.3), border: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: BorderSide(color: _glassBorder)), enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: BorderSide(color: _glassBorder)), focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: BorderSide(color: _accentMagenta, width: 2)), prefixIcon: Icon(Icons.shopping_bag, color: _accentMagenta))),
                      const SizedBox(height: 32),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.end,
                        children: [
                          TextButton(onPressed: () => Navigator.pop(context), child: Text(_isFrench ? 'ANNULER' : 'CANCEL', style: const TextStyle(color: Colors.white54, fontWeight: FontWeight.w600))),
                          const SizedBox(width: 16),
                          ElevatedButton(
                            style: ElevatedButton.styleFrom(backgroundColor: Colors.greenAccent, foregroundColor: Colors.black, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)), padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12)),
                            onPressed: () {
                              _savePosData(dateStr, double.tryParse(caCtrl.text) ?? 0.0, int.tryParse(clientCtrl.text) ?? 0, int.tryParse(articleCtrl.text) ?? 0);
                              Navigator.pop(context);
                            },
                            child: Text(_isFrench ? 'ENREGISTRER' : 'SAVE DATA', style: const TextStyle(fontWeight: FontWeight.w900, letterSpacing: 0.5)),
                          ),
                        ],
                      )
                    ],
                  ),
                ),
              ),
            )
          ],
        )
    );
  }

  void _showExportMenu() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => ExportScreen(
          rawData: _rawData,
          availableCameras: _availableCameras,
          isFrench: _isFrench,
          workingMinuteStart: _workingMinuteStart,
          workingMinuteEnd: _workingMinuteEnd,
          posDatabase: _posDatabase,
        ),
      ),
    );
  }

  Widget _buildLanguageToggle() {
    return GestureDetector(
      onTap: _toggleLanguage,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 300),
        width: 100,
        height: 44,
        padding: const EdgeInsets.all(4),
        decoration: BoxDecoration(
          color: _glassWhiteTint,
          borderRadius: BorderRadius.circular(30),
          border: Border.all(color: _glassBorder, width: 1),
        ),
        child: Stack(
          children: [
            AnimatedAlign(
              duration: const Duration(milliseconds: 400),
              curve: Curves.easeOutBack,
              alignment: _isFrench ? Alignment.centerRight : Alignment.centerLeft,
              child: Container(
                width: 46,
                height: 36,
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.15),
                  borderRadius: BorderRadius.circular(20),
                  boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.2), blurRadius: 8, offset: const Offset(0, 2))],
                ),
              ),
            ),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                Expanded(child: Center(child: AnimatedDefaultTextStyle(duration: const Duration(milliseconds: 200), style: TextStyle(fontWeight: FontWeight.w800, fontSize: 14, letterSpacing: 1, color: !_isFrench ? _accentCyan : Colors.white38), child: const Text('EN')))),
                Expanded(child: Center(child: AnimatedDefaultTextStyle(duration: const Duration(milliseconds: 200), style: TextStyle(fontWeight: FontWeight.w800, fontSize: 14, letterSpacing: 1, color: _isFrench ? _accentCyan : Colors.white38), child: const Text('FR')))),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildLiveFeedSection() {
    if (_selectedCamera == 'All Doors') return const SizedBox.shrink();

    String? ip = _cameraIps[_selectedCamera];
    bool hasIp = ip != null && ip.isNotEmpty;

    return _buildGlassContainer(
      margin: const EdgeInsets.only(top: 32),
      padding: const EdgeInsets.all(24),
      borderRadius: 32,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  Icon(Icons.fiber_manual_record, color: hasIp ? Colors.redAccent : Colors.grey, size: 16),
                  const SizedBox(width: 12),
                  Text(
                      hasIp ? 'LIVE PREVIEW - ${_selectedCamera.toUpperCase()}' : 'NO IP CONFIGURED FOR ${_selectedCamera.toUpperCase()}',
                      style: const TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.w900, letterSpacing: 2.0)
                  ),
                ],
              ),
              if (hasIp)
                IconButton(
                  icon: const Icon(Icons.edit, color: Colors.white54, size: 20),
                  tooltip: 'Edit Camera IP',
                  onPressed: () => _showLinkIpDialog(_selectedCamera),
                ),
            ],
          ),
          const SizedBox(height: 24),

          if (!hasIp)
            Center(
              child: Padding(
                padding: const EdgeInsets.all(40.0),
                child: Column(
                  children: [
                    const Icon(Icons.videocam_off, color: Colors.white24, size: 64),
                    const SizedBox(height: 24),
                    Text('No IP assigned to $_selectedCamera.', style: const TextStyle(color: Colors.white54, fontSize: 16)),
                    const SizedBox(height: 32),
                    ElevatedButton.icon(
                      style: ElevatedButton.styleFrom(
                          backgroundColor: _accentCyan,
                          foregroundColor: Colors.black,
                          padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 16),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16))
                      ),
                      onPressed: () => _showLinkIpDialog(_selectedCamera),
                      icon: const Icon(Icons.link),
                      label: const Text('LINK CAMERA IP', style: TextStyle(fontWeight: FontWeight.w900, letterSpacing: 1.0)),
                    )
                  ],
                ),
              ),
            )
          else
            ClipRRect(
              borderRadius: BorderRadius.circular(24),
              child: Container(
                width: double.infinity,
                height: 360,
                color: Colors.black,
                child: CameraStreamWidget(ipAddress: ip),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildTableView() {
    bool showMatrix = !_isSingleEntrance && _selectedCamera == 'All Doors' && _availableCameras.length > 2 && !_isCompareMode;
    if (showMatrix) return _buildMatrixTable();
    else return _buildStandardTable();
  }

  Widget _buildMatrixTable() {
    List<String> individualDoors = _availableCameras.where((c) => c != 'All Doors').toList();
    const double timeColWidth = 100;
    const double dataColWidth = 70;

    Map<String, int> doorInTotals = {};
    Map<String, int> doorOutTotals = {};
    for (String door in individualDoors) { doorInTotals[door] = 0; doorOutTotals[door] = 0; }

    List<Map<String, dynamic>> rowData = [];
    for (int i = 0; i < _displayedData.length; i++) {
      var globalItem = _displayedData[i];
      String timeLabel = _currentFilter == ChartFilter.hourly ? globalItem.time : globalItem.date;
      Map<String, dynamic> row = { 'time': timeLabel, 'globalIn': globalItem.inCount, 'globalOut': globalItem.outCount, 'doors': <String, Map<String, int>>{} };
      for (String door in individualDoors) {
        int dIn = 0; int dOut = 0;
        if (_perDoorData[door] != null) {
          var match = _perDoorData[door]!.where((d) => (_currentFilter == ChartFilter.hourly ? d.time == globalItem.time : d.date == globalItem.date)).toList();
          if (match.isNotEmpty) { dIn = match.first.inCount; dOut = match.first.outCount; }
        }
        row['doors'][door] = {'in': dIn, 'out': dOut};
        doorInTotals[door] = doorInTotals[door]! + dIn;
        doorOutTotals[door] = doorOutTotals[door]! + dOut;
      }
      rowData.add(row);
    }

    Widget buildCell(String text, double width, {Color? color, bool isTitle = false, bool rightBorder = false}) {
      return Container(
        width: width,
        padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 8),
        decoration: rightBorder ? BoxDecoration(border: Border(right: BorderSide(color: Colors.white.withOpacity(0.05)))) : null,
        child: Text(
          text,
          textAlign: TextAlign.center,
          style: TextStyle(
            color: color ?? (isTitle ? Colors.white : Colors.white54),
            fontWeight: isTitle ? FontWeight.w900 : FontWeight.w600,
            fontSize: isTitle ? 13 : 12,
            letterSpacing: isTitle ? 1.0 : 0.5,
          ),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
      );
    }

    return _buildGlassContainer(
      borderRadius: 24,
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        physics: const BouncingScrollPhysics(),
        child: IntrinsicWidth(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                decoration: BoxDecoration(color: Colors.white.withOpacity(0.05), border: Border(bottom: BorderSide(color: Colors.white.withOpacity(0.05)))),
                child: Row(
                  children: [
                    buildCell('', timeColWidth, rightBorder: true),
                    buildCell(_isFrench ? 'GLOBAL' : 'GLOBAL', dataColWidth * 2, isTitle: true, color: Colors.white, rightBorder: true),
                    ...individualDoors.map((door) => buildCell(door.toUpperCase(), dataColWidth * 2, isTitle: true, color: _accentCyan, rightBorder: true)).toList(),
                  ],
                ),
              ),
              Container(
                decoration: BoxDecoration(color: Colors.white.withOpacity(0.03), border: Border(bottom: BorderSide(color: Colors.white.withOpacity(0.1)))),
                child: Row(
                  children: [
                    buildCell(_isFrench ? 'Période' : 'Time', timeColWidth, isTitle: true, rightBorder: true),
                    buildCell('IN', dataColWidth, color: Colors.greenAccent, isTitle: true),
                    buildCell('OUT', dataColWidth, color: Colors.redAccent, isTitle: true, rightBorder: true),
                    ...individualDoors.expand((door) => [
                      buildCell('IN', dataColWidth, color: Colors.greenAccent, isTitle: true),
                      buildCell('OUT', dataColWidth, color: Colors.redAccent, isTitle: true, rightBorder: true),
                    ]).toList(),
                  ],
                ),
              ),
              Expanded(
                child: ListView.builder(
                  itemCount: rowData.length,
                  itemBuilder: (context, index) {
                    var row = rowData[index];
                    return Container(
                      decoration: BoxDecoration(border: Border(bottom: BorderSide(color: Colors.white.withOpacity(0.02)))),
                      child: Row(
                        children: [
                          buildCell(row['time'], timeColWidth, color: Colors.white, isTitle: true, rightBorder: true),
                          buildCell(row['globalIn'].toString(), dataColWidth, color: Colors.greenAccent),
                          buildCell(row['globalOut'].toString(), dataColWidth, color: Colors.redAccent, rightBorder: true),
                          ...individualDoors.expand((door) => [
                            buildCell(row['doors'][door]['in'].toString(), dataColWidth, color: Colors.greenAccent.withOpacity(0.7)),
                            buildCell(row['doors'][door]['out'].toString(), dataColWidth, color: Colors.redAccent.withOpacity(0.7), rightBorder: true),
                          ]).toList(),
                        ],
                      ),
                    );
                  },
                ),
              ),
              Container(
                decoration: BoxDecoration(color: Colors.white.withOpacity(0.05), border: Border(top: BorderSide(color: Colors.white.withOpacity(0.1)))),
                child: Row(
                  children: [
                    buildCell('TOTAL', timeColWidth, isTitle: true, color: Colors.white, rightBorder: true),
                    buildCell(_totalIn.toString(), dataColWidth, color: Colors.greenAccent, isTitle: true),
                    buildCell(_totalOut.toString(), dataColWidth, color: Colors.redAccent, isTitle: true, rightBorder: true),
                    ...individualDoors.expand((door) => [
                      buildCell(doorInTotals[door].toString(), dataColWidth, color: Colors.greenAccent, isTitle: true),
                      buildCell(doorOutTotals[door].toString(), dataColWidth, color: Colors.redAccent, isTitle: true, rightBorder: true),
                    ]).toList(),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildStandardTable() {
    bool isCompare = _isCompareMode && _compareDisplayedData.isNotEmpty;

    return _buildGlassContainer(
      borderRadius: 24,
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
            decoration: BoxDecoration(color: Colors.white.withOpacity(0.05), border: Border(bottom: BorderSide(color: Colors.white.withOpacity(0.1)))),
            child: Row(
              children: [
                Expanded(flex: 2, child: Text(_isFrench ? 'Période' : 'Time', style: const TextStyle(color: Colors.white54, fontWeight: FontWeight.w800, letterSpacing: 1.0))),
                Expanded(child: Text(_isFrench ? 'Entrées' : 'In', textAlign: TextAlign.center, style: const TextStyle(color: Colors.white54, fontWeight: FontWeight.w800, letterSpacing: 1.0))),
                Expanded(child: Text(_isFrench ? 'Sorties' : 'Out', textAlign: TextAlign.center, style: const TextStyle(color: Colors.white54, fontWeight: FontWeight.w800, letterSpacing: 1.0))),
                if (isCompare) ...[
                  Expanded(child: Text(_isFrench ? 'Préc. In' : 'Prev In', textAlign: TextAlign.center, style: const TextStyle(color: Colors.white54, fontWeight: FontWeight.w800, letterSpacing: 1.0))),
                  Expanded(child: Text(_isFrench ? 'Préc. Out' : 'Prev Out', textAlign: TextAlign.center, style: const TextStyle(color: Colors.white54, fontWeight: FontWeight.w800, letterSpacing: 1.0))),
                ],
                Expanded(child: Text(_isFrench ? 'Total' : 'Total', textAlign: TextAlign.right, style: const TextStyle(color: Colors.white54, fontWeight: FontWeight.w800, letterSpacing: 1.0))),
              ],
            ),
          ),
          Expanded(
            child: ListView.builder(
              itemCount: _displayedData.length,
              itemBuilder: (context, index) {
                var item = _displayedData[index];
                String timeLabel = _currentFilter == ChartFilter.hourly ? item.time : item.date;
                int total = (item.inCount + item.outCount) ~/ 2;
                PeopleCount? compareItem;
                if (isCompare && index < _compareDisplayedData.length) compareItem = _compareDisplayedData[index];

                return Container(
                  padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
                  decoration: BoxDecoration(border: Border(bottom: BorderSide(color: Colors.white.withOpacity(0.02)))),
                  child: Row(
                    children: [
                      Expanded(flex: 2, child: Text(timeLabel, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700))),
                      Expanded(child: Text(item.inCount.toString(), textAlign: TextAlign.center, style: const TextStyle(color: Colors.greenAccent, fontWeight: FontWeight.w600))),
                      Expanded(child: Text(item.outCount.toString(), textAlign: TextAlign.center, style: const TextStyle(color: Colors.redAccent, fontWeight: FontWeight.w600))),
                      if (isCompare) ...[
                        Expanded(child: Text(compareItem?.inCount.toString() ?? '-', textAlign: TextAlign.center, style: const TextStyle(color: Colors.white54))),
                        Expanded(child: Text(compareItem?.outCount.toString() ?? '-', textAlign: TextAlign.center, style: const TextStyle(color: Colors.white54))),
                      ],
                      Expanded(child: Text(total.toString(), textAlign: TextAlign.right, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w900))),
                    ],
                  ),
                );
              },
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
            decoration: BoxDecoration(color: Colors.white.withOpacity(0.05), border: Border(top: BorderSide(color: Colors.white.withOpacity(0.1)))),
            child: Row(
              children: [
                Expanded(flex: 2, child: const Text('TOTAL', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w900, fontSize: 15, letterSpacing: 1.0))),
                Expanded(child: Text(_totalIn.toString(), textAlign: TextAlign.center, style: const TextStyle(color: Colors.greenAccent, fontWeight: FontWeight.w900, fontSize: 15))),
                Expanded(child: Text(_totalOut.toString(), textAlign: TextAlign.center, style: const TextStyle(color: Colors.redAccent, fontWeight: FontWeight.w900, fontSize: 15))),
                if (isCompare) ...[
                  Expanded(child: Text(_compareTotalIn.toString(), textAlign: TextAlign.center, style: const TextStyle(color: Colors.white70, fontWeight: FontWeight.w900, fontSize: 15))),
                  Expanded(child: Text(_compareTotalOut.toString(), textAlign: TextAlign.center, style: const TextStyle(color: Colors.white70, fontWeight: FontWeight.w900, fontSize: 15))),
                ],
                Expanded(child: Text(((_totalIn + _totalOut) ~/ 2).toString(), textAlign: TextAlign.right, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w900, fontSize: 15))),
              ],
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDesktop = MediaQuery.of(context).size.width > 800;

    return Scaffold(
      backgroundColor: _bgDeep,
      body: Stack(
        children: [
          // 🌌 iOS 26 SPATIAL BACKGROUND MESH (Ambient Orbs)
          Positioned(top: -200, left: -200, child: Container(width: 600, height: 600, decoration: BoxDecoration(shape: BoxShape.circle, color: _accentPurple.withOpacity(0.25), boxShadow: [BoxShadow(blurRadius: 200, color: _accentPurple.withOpacity(0.25))]))),
          Positioned(bottom: -200, right: -100, child: Container(width: 700, height: 700, decoration: BoxDecoration(shape: BoxShape.circle, color: _accentCyan.withOpacity(0.20), boxShadow: [BoxShadow(blurRadius: 250, color: _accentCyan.withOpacity(0.20))]))),
          Positioned(top: 300, right: 300, child: Container(width: 400, height: 400, decoration: BoxDecoration(shape: BoxShape.circle, color: _accentMagenta.withOpacity(0.15), boxShadow: [BoxShadow(blurRadius: 200, color: _accentMagenta.withOpacity(0.15))]))),

          // 💻 MAIN UI
          Row(
            children: [
              if (isDesktop) _buildSidebar(),
              Expanded(
                child: Column(
                  children: [
                    _buildTopAppBar(),

                    if (_isIpMismatch)
                      Container(
                        width: double.infinity,
                        color: Colors.redAccent.withOpacity(0.9),
                        padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 24),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            const Icon(Icons.warning_amber_rounded, color: Colors.white, size: 28),
                            const SizedBox(width: 16),
                            Expanded(
                              child: Text(
                                _isFrench
                                    ? "CRITIQUE : L'IP du réseau a changé ! Attendu : $_expectedIp | Actuel : ${_actualIp == '127.0.0.1' ? 'DÉCONNECTÉ' : _actualIp}. Les caméras sont aveugles."
                                    : "CRITICAL: Network IP Changed! Expected: $_expectedIp | Current: ${_actualIp == '127.0.0.1' ? 'DISCONNECTED' : _actualIp}. Cameras are currently blind.",
                                style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 16),
                              ),
                            ),
                            ElevatedButton(
                              style: ElevatedButton.styleFrom(backgroundColor: Colors.white, foregroundColor: Colors.red[900], shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
                              onPressed: () { Navigator.push(context, MaterialPageRoute(builder: (context) => const FtpServerScreen())); },
                              child: Text(_isFrench ? "RÉPARER" : "FIX NETWORK", style: const TextStyle(fontWeight: FontWeight.w900)),
                            )
                          ],
                        ),
                      ),

                    Expanded(
                      child: _isLoading
                          ? Center(child: CircularProgressIndicator(color: _accentCyan))
                          : SingleChildScrollView(
                        padding: const EdgeInsets.symmetric(horizontal: 40.0, vertical: 40.0),
                        physics: const BouncingScrollPhysics(),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            _buildPageHeader(),
                            const SizedBox(height: 32),

                            if (_rawData.isEmpty)
                              _buildEmptyState()
                            else ...[
                              _buildSmartInsights(),
                              const SizedBox(height: 32),

                              _buildHeroChart(),

                              if (!_isSingleEntrance) const SizedBox(height: 40),
                              _buildZoneSelector(),
                              if (!_isSingleEntrance) const SizedBox(height: 40),

                              _buildLiveFeedSection(),

                              const SizedBox(height: 40),
                              _buildBentoGrid(isDesktop),
                              const SizedBox(height: 60),
                            ]
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildSidebar() {
    return _buildGlassContainer(
      width: 280,
      margin: const EdgeInsets.only(right: 2), // Slight separation line
      borderRadius: 0, // Flush against the edge
      child: Column(
        children: [
          const SizedBox(height: 50),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24.0),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Image.asset(
                  'assets/boitex_logo.png',
                  width: 140,
                  height: 140,
                  fit: BoxFit.contain,
                  errorBuilder: (context, error, stackTrace) {
                    return Icon(Icons.business, color: _accentCyan, size: 80);
                  },
                ),
                const SizedBox(height: 24),
                const Text(
                  'BoitexInfo',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 28, fontWeight: FontWeight.w900, color: Colors.white, letterSpacing: -1.0, height: 1.1),
                ),
                Text(
                  'Analytics',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 14, fontWeight: FontWeight.w800, color: _accentCyan, letterSpacing: 4.0),
                ),
              ],
            ),
          ),
          const SizedBox(height: 40),
          Expanded(
            child: SingleChildScrollView(
              physics: const BouncingScrollPhysics(),
              child: Column(
                children: [
                  _buildSidebarItem(Icons.dashboard_rounded, _isFrench ? 'Tableau de bord' : 'Dashboard', isActive: true),
                  if (_enablePosFeatures)
                    _buildSidebarItem(Icons.point_of_sale_rounded, _isFrench ? 'Saisie de Caisse' : 'POS Entry', onTap: _rawData.isNotEmpty ? _showPosEntryDialog : null),
                  _buildSidebarItem(Icons.download_rounded, _isFrench ? 'Exporter Rapports' : 'Export Reports', onTap: _rawData.isNotEmpty ? _showExportMenu : null),
                  _buildSidebarItem(
                    Icons.developer_mode_rounded,
                    _isFrench ? 'Développeur' : 'Developer',
                    iconColor: _isIpMismatch ? Colors.redAccent : null,
                    textColor: _isIpMismatch ? Colors.redAccent : null,
                    onTap: _openDeveloperScreen,
                  ),
                  const SizedBox(height: 20),
                ],
              ),
            ),
          ),
          if (_isFtpRunning && !_isIpMismatch)
            Container(
              margin: const EdgeInsets.all(24),
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                  color: Colors.greenAccent.withOpacity(0.08),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: Colors.greenAccent.withOpacity(0.2))
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(children: [
                    Container(width: 10, height: 10, decoration: const BoxDecoration(color: Colors.greenAccent, shape: BoxShape.circle, boxShadow: [BoxShadow(color: Colors.greenAccent, blurRadius: 8)])),
                    const SizedBox(width: 12),
                    Text(_isFrench ? 'FTP Actif' : 'FTP Active', style: const TextStyle(fontWeight: FontWeight.w800, color: Colors.white, letterSpacing: 0.5))
                  ]),
                  const SizedBox(height: 8),
                  Text('ftp://$_localIp:21', style: const TextStyle(fontSize: 13, color: Colors.white70, fontWeight: FontWeight.w500)),
                ],
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildSidebarItem(IconData icon, String title, {bool isActive = false, Color? iconColor, Color? textColor, VoidCallback? onTap}) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 4.0),
      child: ListTile(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        tileColor: isActive ? Colors.white.withOpacity(0.08) : Colors.transparent,
        leading: Icon(icon, color: iconColor ?? (isActive ? _accentCyan : Colors.white54)),
        title: Text(title, style: TextStyle(color: textColor ?? (isActive ? Colors.white : Colors.white54), fontWeight: isActive ? FontWeight.w800 : FontWeight.w600, fontSize: 15)),
        contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 4),
        onTap: onTap,
      ),
    );
  }

  Widget _buildTopAppBar() {
    return _buildGlassContainer(
      height: 100,
      borderRadius: 0,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 40),
        child: Row(
          children: [
            StreamBuilder(
              stream: Stream.periodic(const Duration(seconds: 1)),
              builder: (context, snapshot) {
                final now = DateTime.now();
                const List<String> weekdaysEn = ['Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday', 'Sunday'];
                const List<String> monthsEn = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
                const List<String> weekdaysFr = ['Lundi', 'Mardi', 'Mercredi', 'Jeudi', 'Vendredi', 'Samedi', 'Dimanche'];
                const List<String> monthsFr = ['Janvier', 'Février', 'Mars', 'Avril', 'Mai', 'Juin', 'Juillet', 'Août', 'Septembre', 'Octobre', 'Novembre', 'Décembre'];
                String dayName = _isFrench ? weekdaysFr[now.weekday - 1] : weekdaysEn[now.weekday - 1];
                String monthName = _isFrench ? monthsFr[now.month - 1] : monthsEn[now.month - 1];
                String hour = now.hour.toString().padLeft(2, '0');
                String minute = now.minute.toString().padLeft(2, '0');

                return Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text("$dayName, ${_isFrench ? "${now.day} $monthName" : "$monthName ${now.day}"}", style: const TextStyle(color: Colors.white54, fontSize: 14, fontWeight: FontWeight.w700, letterSpacing: 1.0)),
                    const SizedBox(height: 4),
                    Text("$hour:$minute", style: const TextStyle(color: Colors.white, fontSize: 28, fontWeight: FontWeight.w900, letterSpacing: 1.5)),
                  ],
                );
              },
            ),
            const Spacer(),
            _buildLanguageToggle(),
            const SizedBox(width: 40),
            Row(
              children: [
                Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(_storeLocation.toUpperCase(), style: const TextStyle(color: Colors.white38, fontSize: 12, fontWeight: FontWeight.w800, letterSpacing: 2.0)),
                    const SizedBox(height: 2),
                    Text(_storeName, style: const TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.w900, letterSpacing: -0.5)),
                  ],
                ),
                const SizedBox(width: 20),
                Container(
                  width: 64, height: 64,
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.05),
                    shape: BoxShape.circle,
                    border: Border.all(color: _glassBorder, width: 1.5),
                    image: _storeLogoPath != null ? DecorationImage(image: FileImage(File(_storeLogoPath!)), fit: BoxFit.cover) : null,
                  ),
                  child: _storeLogoPath == null ? Icon(Icons.storefront_rounded, color: _accentCyan, size: 30) : null,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPageHeader() {
    bool isFilterActive = _workingMinuteStart > 0 || _workingMinuteEnd < 1439;

    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
                _isFrench ? 'Vue d\'Ensemble' : 'Command Center',
                style: const TextStyle(fontSize: 48, fontWeight: FontWeight.w900, color: Colors.white, letterSpacing: -2.0)
            ),
            if (_selectedFolderPath != null)
              Padding(
                padding: const EdgeInsets.only(top: 8.0),
                child: Text('Source: $_selectedFolderPath', style: const TextStyle(color: Colors.white38, fontSize: 15, fontWeight: FontWeight.w600)),
              ),
          ],
        ),

        Row(
          children: [
            if (_rawData.isNotEmpty) ...[
              FilterChip(
                selected: _isCompareMode,
                onSelected: (val) { setState(() { _isCompareMode = val; _applyFilter(); }); },
                label: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  child: Text(_isFrench ? 'Comparer au Préc.' : 'Compare vs Prev', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 14, color: _isCompareMode ? Colors.black : Colors.white)),
                ),
                selectedColor: _accentCyan,
                checkmarkColor: Colors.black,
                backgroundColor: _glassWhiteTint,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20), side: BorderSide(color: _isCompareMode ? _accentCyan : _glassBorder, width: 1.5)),
              ),
              const SizedBox(width: 20),
            ],

            _buildGlassContainer(
              padding: const EdgeInsets.all(6),
              borderRadius: 20,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  IconButton(icon: const Icon(Icons.chevron_left_rounded, color: Colors.white54), onPressed: () => _shiftDate(-1)),
                  GestureDetector(
                    onTap: _pickDateRange,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      child: Text(_getFormattedDateString(), style: const TextStyle(fontWeight: FontWeight.w800, color: Colors.white, fontSize: 16, letterSpacing: 0.5)),
                    ),
                  ),
                  IconButton(icon: const Icon(Icons.chevron_right_rounded, color: Colors.white54), onPressed: () => _shiftDate(1)),
                ],
              ),
            ),
            const SizedBox(width: 20),

            _buildGlassContainer(
              borderRadius: 20,
              isInteractive: isFilterActive,
              child: IconButton(
                padding: const EdgeInsets.all(12),
                icon: Icon(Icons.tune_rounded, color: isFilterActive ? _accentCyan : Colors.white54),
                onPressed: _showWorkingHoursDialog,
                tooltip: _isFrench ? "Heures d'Ouverture" : "Operating Hours",
              ),
            ),
          ],
        )
      ],
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.only(top: 120),
        child: Column(
          children: [
            Icon(Icons.folder_open_rounded, size: 120, color: Colors.white.withOpacity(0.05)),
            const SizedBox(height: 32),
            Text(_isFrench ? 'Aucune Donnée Sélectionnée' : 'No Data Selected', style: const TextStyle(fontSize: 32, fontWeight: FontWeight.w900, color: Colors.white, letterSpacing: -1.0)),
            const SizedBox(height: 16),
            Text(
                _isFrench
                    ? 'Veuillez sélectionner une source de données ou démarrer le serveur FTP.'
                    : 'Please select a data source or start the FTP server from the menu.',
                style: const TextStyle(color: Colors.white54, fontSize: 18, fontWeight: FontWeight.w500)
            ),
            const SizedBox(height: 40),
            ElevatedButton.icon(
              style: ElevatedButton.styleFrom(
                  backgroundColor: _accentCyan,
                  foregroundColor: Colors.black,
                  padding: const EdgeInsets.symmetric(horizontal: 40, vertical: 24),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20))
              ),
              onPressed: _pickFolderAndLoadData,
              icon: const Icon(Icons.drive_folder_upload_rounded, size: 28),
              label: Text(_isFrench ? 'IMPORTER DES DONNÉES' : 'IMPORT DATA', style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w900, letterSpacing: 1.0)),
            )
          ],
        ),
      ),
    );
  }

  Widget _buildSmartInsights() {
    int totalVisitors = (_totalIn + _totalOut) ~/ 2;
    String startStr = _formatMinutesToTimeString(_workingMinuteStart);
    String endStr = _formatMinutesToTimeString(_workingMinuteEnd);
    bool isFilterActive = _workingMinuteStart > 0 || _workingMinuteEnd < 1439;

    String insightText = _isFrench
        ? "Le trafic d'aujourd'hui atteint $totalVisitors visiteurs, avec une activité maximale enregistrée à $_peakHour."
        : "Today's traffic has reached $totalVisitors visitors, with peak activity recorded at $_peakHour.";

    if (isFilterActive) insightText += _isFrench ? " (Filtré: $startStr - $endStr)" : " (Filtered: $startStr - $endStr)";

    return _buildGlassContainer(
      padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 24),
      borderRadius: 24,
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: _accentPurple.withOpacity(0.2),
              shape: BoxShape.circle,
              boxShadow: [BoxShadow(color: _accentPurple.withOpacity(0.5), blurRadius: 20)],
            ),
            child: const Icon(Icons.auto_awesome_rounded, color: Colors.white, size: 28),
          ),
          const SizedBox(width: 24),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                    _isFrench ? "ANALYSE INTELLIGENTE" : "SMART INSIGHT",
                    style: TextStyle(color: _accentCyan, fontSize: 12, fontWeight: FontWeight.w900, letterSpacing: 3.0)
                ),
                const SizedBox(height: 8),
                Text(
                    insightText,
                    style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w600, height: 1.4)
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHeroChart() {
    int totalVisitors = (_totalIn + _totalOut) ~/ 2;
    List<LineChartBarData> chartLines = [];
    bool showPerDoor = !_isSingleEntrance && _selectedCamera == 'All Doors' && _availableCameras.length > 2 && !_isCompareMode;

    List<List<Color>> luxuryGradients = [
      [_accentCyan, const Color(0xFF0072FF)],
      [_accentMagenta, const Color(0xFFDD2476)],
      [const Color(0xFF38EF7D), const Color(0xFF11998E)],
      [_accentPurple, const Color(0xFF4A00E0)],
      [const Color(0xFFFDC830), const Color(0xFFF37335)],
    ];

    List<String> plottedDoors = _perDoorData.keys.toList();
    double maxTrafficY = 1.0;
    double sumTraffic = 0;
    int dataPointCount = 0;

    void processSpotForMetrics(double value) {
      if (value > maxTrafficY) maxTrafficY = value;
      sumTraffic += value;
      dataPointCount++;
    }

    if (showPerDoor) {
      for (String door in plottedDoors) {
        if (_perDoorData[door] != null) {
          for (var item in _perDoorData[door]!) { processSpotForMetrics((item.inCount + item.outCount) / 2); }
        }
      }
    } else if (_isCompareMode) {
      for (var item in _displayedData) processSpotForMetrics((item.inCount + item.outCount) / 2);
      for (var item in _compareDisplayedData) processSpotForMetrics((item.inCount + item.outCount) / 2);
    } else {
      for (var item in _displayedData) {
        processSpotForMetrics(item.inCount.toDouble());
        processSpotForMetrics(item.outCount.toDouble());
      }
    }

    double averageTraffic = dataPointCount > 0 ? (sumTraffic / dataPointCount) : 0;
    double yInterval = 1;
    if (maxTrafficY > 1000) yInterval = 200;
    else if (maxTrafficY > 500) yInterval = 100;
    else if (maxTrafficY > 100) yInterval = 50;
    else if (maxTrafficY > 50) yInterval = 10;
    else if (maxTrafficY > 20) yInterval = 5;
    else if (maxTrafficY > 10) yInterval = 2;

    LinearGradient buildVolumetricFade(Color baseColor) {
      return LinearGradient(
        colors: [baseColor.withOpacity(0.4), baseColor.withOpacity(0.0)],
        begin: Alignment.topCenter, end: Alignment.bottomCenter,
      );
    }

    if (showPerDoor) {
      int colorIndex = 0;
      for (String door in plottedDoors) {
        List<FlSpot> spots = [];
        List<Color> doorGradient = luxuryGradients[colorIndex % luxuryGradients.length];
        for (int i = 0; i < _displayedData.length; i++) {
          String expectedTime = _displayedData[i].time;
          String expectedDate = _displayedData[i].date;
          var match = _perDoorData[door]!.where((d) => d.time == expectedTime && d.date == expectedDate).toList();
          double total = match.isNotEmpty ? ((match.first.inCount + match.first.outCount) / 2).toDouble() : 0;
          spots.add(FlSpot(i.toDouble(), total));
        }
        chartLines.add(LineChartBarData(
          spots: spots, isCurved: true, curveSmoothness: 0.4, gradient: LinearGradient(colors: doorGradient), barWidth: 4, isStrokeCapRound: true,
          shadow: Shadow(color: doorGradient.first.withOpacity(0.6), blurRadius: 15, offset: const Offset(0, 5)),
          belowBarData: BarAreaData(show: true, gradient: buildVolumetricFade(doorGradient.first)),
          dotData: FlDotData(show: true, checkToShowDot: (spot, barData) => spot.y == maxTrafficY && spot.y > 0, getDotPainter: (spot, percent, barData, index) => FlDotCirclePainter(radius: 6, color: _bgDeep, strokeWidth: 3, strokeColor: doorGradient.first)),
        ));
        colorIndex++;
      }
    } else if (_isCompareMode) {
      chartLines.add(LineChartBarData(
        spots: _displayedData.asMap().entries.map((e) => FlSpot(e.key.toDouble(), ((e.value.inCount + e.value.outCount) / 2).toDouble())).toList(),
        isCurved: true, curveSmoothness: 0.4, gradient: LinearGradient(colors: luxuryGradients[0]), barWidth: 5, isStrokeCapRound: true,
        shadow: Shadow(color: luxuryGradients[0].first.withOpacity(0.6), blurRadius: 15, offset: const Offset(0, 5)),
        belowBarData: BarAreaData(show: true, gradient: buildVolumetricFade(luxuryGradients[0].first)),
        dotData: FlDotData(show: true, checkToShowDot: (spot, barData) => spot.y == maxTrafficY && spot.y > 0, getDotPainter: (spot, percent, barData, index) => FlDotCirclePainter(radius: 6, color: _bgDeep, strokeWidth: 3, strokeColor: luxuryGradients[0].first)),
      ));
      chartLines.add(LineChartBarData(
        spots: _compareDisplayedData.asMap().entries.map((e) => FlSpot(e.key.toDouble(), ((e.value.inCount + e.value.outCount) / 2).toDouble())).toList(),
        isCurved: true, curveSmoothness: 0.4, color: _accentGrey.withOpacity(0.8), barWidth: 3, dashArray: [8, 6], isStrokeCapRound: true, dotData: const FlDotData(show: false),
      ));
    } else {
      chartLines.add(LineChartBarData(
        spots: _displayedData.asMap().entries.map((e) => FlSpot(e.key.toDouble(), e.value.inCount.toDouble())).toList(),
        isCurved: true, curveSmoothness: 0.4, gradient: LinearGradient(colors: luxuryGradients[0]), barWidth: 5, isStrokeCapRound: true,
        shadow: Shadow(color: luxuryGradients[0].first.withOpacity(0.6), blurRadius: 15, offset: const Offset(0, 5)),
        belowBarData: BarAreaData(show: true, gradient: buildVolumetricFade(luxuryGradients[0].first)),
        dotData: FlDotData(show: true, checkToShowDot: (spot, barData) => spot.y == maxTrafficY && spot.y > 0, getDotPainter: (spot, percent, barData, index) => FlDotCirclePainter(radius: 6, color: _bgDeep, strokeWidth: 3, strokeColor: luxuryGradients[0].first)),
      ));
      chartLines.add(LineChartBarData(
        spots: _displayedData.asMap().entries.map((e) => FlSpot(e.key.toDouble(), e.value.outCount.toDouble())).toList(),
        isCurved: true, curveSmoothness: 0.4, gradient: LinearGradient(colors: luxuryGradients[1]), barWidth: 5, isStrokeCapRound: true,
        shadow: Shadow(color: luxuryGradients[1].first.withOpacity(0.6), blurRadius: 15, offset: const Offset(0, 5)),
        belowBarData: BarAreaData(show: true, gradient: buildVolumetricFade(luxuryGradients[1].first)),
        dotData: FlDotData(show: true, checkToShowDot: (spot, barData) => spot.y == maxTrafficY && spot.y > 0, getDotPainter: (spot, percent, barData, index) => FlDotCirclePainter(radius: 6, color: _bgDeep, strokeWidth: 3, strokeColor: luxuryGradients[1].first)),
      ));
    }

    return _buildGlassContainer(
      padding: const EdgeInsets.all(40),
      borderRadius: 40,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(_isFrench ? 'TRAFIC GLOBAL' : 'GLOBAL TRAFFIC', style: const TextStyle(color: Colors.white54, fontSize: 14, fontWeight: FontWeight.w800, letterSpacing: 4.0)),
                  const SizedBox(height: 8),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.baseline, textBaseline: TextBaseline.alphabetic,
                    children: [
                      Text(totalVisitors.toString(), style: const TextStyle(color: Colors.white, fontSize: 84, fontWeight: FontWeight.w900, letterSpacing: -4.0, height: 1.0)),
                      const SizedBox(width: 20),
                      _buildTrendBadge(totalVisitors, _compareTotalVisitors),
                    ],
                  )
                ],
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        decoration: BoxDecoration(color: Colors.white.withOpacity(0.08), borderRadius: BorderRadius.circular(24), border: Border.all(color: _glassBorder)),
                        child: Row(
                          children: [
                            IconButton(icon: Icon(Icons.show_chart_rounded, color: !_isTableMode ? _accentCyan : Colors.white54, size: 22), onPressed: () => setState(() => _isTableMode = false), tooltip: _isFrench ? 'Graphique' : 'Chart'),
                            IconButton(icon: Icon(Icons.table_chart_rounded, color: _isTableMode ? _accentCyan : Colors.white54, size: 22), onPressed: () => setState(() => _isTableMode = true), tooltip: _isFrench ? 'Tableau' : 'Table'),
                          ],
                        ),
                      ),
                      const SizedBox(width: 16),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
                        decoration: BoxDecoration(color: Colors.white.withOpacity(0.08), borderRadius: BorderRadius.circular(24), border: Border.all(color: _glassBorder)),
                        child: DropdownButtonHideUnderline(
                          child: DropdownButton<ChartFilter>(
                            dropdownColor: _bgDeep.withOpacity(0.9), icon: const Icon(Icons.expand_more_rounded, color: Colors.white70), value: _currentFilter,
                            style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 15, letterSpacing: 0.5),
                            items: [
                              DropdownMenuItem(value: ChartFilter.hourly, child: Text(_isFrench ? 'Vue Horaire' : 'Hourly View')),
                              DropdownMenuItem(value: ChartFilter.daily, child: Text(_isFrench ? 'Vue Journalière' : 'Daily View'))
                            ],
                            onChanged: (ChartFilter? newValue) { if (newValue != null) { setState(() { _currentFilter = newValue; _applyFilter(); }); } },
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 32),

                  if (showPerDoor) ...[
                    ...plottedDoors.asMap().entries.map((entry) {
                      Color dColor = luxuryGradients[entry.key % luxuryGradients.length].first;
                      return Padding(
                        padding: const EdgeInsets.only(bottom: 12.0),
                        child: Row(children: [
                          Container(width: 14, height: 14, decoration: BoxDecoration(color: dColor, shape: BoxShape.circle, boxShadow: [BoxShadow(color: dColor.withOpacity(0.6), blurRadius: 10)])),
                          const SizedBox(width: 12), Text("${entry.value.toUpperCase()} Total", style: const TextStyle(color: Colors.white70, fontSize: 15, fontWeight: FontWeight.w700, letterSpacing: 0.5))
                        ]),
                      );
                    }).toList(),
                  ] else if (_isCompareMode) ...[
                    Row(children: [Container(width: 14, height: 14, decoration: BoxDecoration(color: luxuryGradients[0].first, shape: BoxShape.circle, boxShadow: [BoxShadow(color: luxuryGradients[0].first.withOpacity(0.6), blurRadius: 10)])), const SizedBox(width: 12), Text(_isFrench ? 'Période Actuelle' : 'Current Period', style: const TextStyle(color: Colors.white70, fontSize: 15, fontWeight: FontWeight.w700))]),
                    const SizedBox(height: 12),
                    Row(children: [Container(width: 14, height: 14, decoration: BoxDecoration(color: _accentGrey, shape: BoxShape.circle)), const SizedBox(width: 12), Text(_isFrench ? 'Période Précédente' : 'Previous Period', style: const TextStyle(color: Colors.white70, fontSize: 15, fontWeight: FontWeight.w700))]),
                  ] else ...[
                    Row(children: [Container(width: 14, height: 14, decoration: BoxDecoration(gradient: LinearGradient(colors: luxuryGradients[0]), shape: BoxShape.circle, boxShadow: [BoxShadow(color: luxuryGradients[0].first.withOpacity(0.6), blurRadius: 10)])), const SizedBox(width: 12), Text('${_isFrench ? "Total Entrées" : "Total In"}: $_totalIn', style: const TextStyle(color: Colors.white70, fontSize: 16, fontWeight: FontWeight.w700))]),
                    const SizedBox(height: 12),
                    Row(children: [Container(width: 14, height: 14, decoration: BoxDecoration(gradient: LinearGradient(colors: luxuryGradients[1]), shape: BoxShape.circle, boxShadow: [BoxShadow(color: luxuryGradients[1].first.withOpacity(0.6), blurRadius: 10)])), const SizedBox(width: 12), Text('${_isFrench ? "Total Sorties" : "Total Out"}: $_totalOut', style: const TextStyle(color: Colors.white70, fontSize: 16, fontWeight: FontWeight.w700))]),
                  ]
                ],
              )
            ],
          ),
          const SizedBox(height: 60),

          SizedBox(
            height: 400,
            child: _isTableMode ? _buildTableView() : LineChart(
              LineChartData(
                minY: 0,
                maxY: maxTrafficY * 1.15,
                extraLinesData: ExtraLinesData(
                  horizontalLines: [
                    if (averageTraffic > 0)
                      HorizontalLine(
                        y: averageTraffic,
                        color: Colors.white.withOpacity(0.3),
                        strokeWidth: 2.0,
                        dashArray: [8, 8],
                        label: HorizontalLineLabel(
                          show: true,
                          alignment: Alignment.topRight,
                          padding: const EdgeInsets.only(right: 8, bottom: 8),
                          style: const TextStyle(color: Colors.white70, fontSize: 11, fontWeight: FontWeight.w900, letterSpacing: 2.0),
                          labelResolver: (line) => _isFrench ? 'MOYENNE' : 'AVERAGE',
                        ),
                      ),
                  ],
                ),
                lineTouchData: LineTouchData(
                  handleBuiltInTouches: true,
                  getTouchedSpotIndicator: (LineChartBarData barData, List<int> spotIndexes) {
                    return spotIndexes.map((spotIndex) {
                      return TouchedSpotIndicatorData(
                        FlLine(color: Colors.white.withOpacity(0.4), strokeWidth: 2, dashArray: [6, 6]),
                        FlDotData(show: true, getDotPainter: (spot, percent, barData, index) => FlDotCirclePainter(radius: 8, color: Colors.white, strokeWidth: 4, strokeColor: barData.gradient?.colors.first ?? _accentCyan)),
                      );
                    }).toList();
                  },
                  touchTooltipData: LineTouchTooltipData(
                    tooltipBgColor: Colors.black.withOpacity(0.8), tooltipRoundedRadius: 20, tooltipPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16), tooltipBorder: const BorderSide(color: Colors.white24, width: 1.5),
                    getTooltipItems: (touchedSpots) {
                      return touchedSpots.map((LineBarSpot touchedSpot) {
                        final textStyle = const TextStyle(color: Colors.white, fontWeight: FontWeight.w900, fontSize: 18, letterSpacing: 0.5);
                        String timeText = "";
                        if (_displayedData.length > touchedSpot.x.toInt()) { timeText = _currentFilter == ChartFilter.daily ? _displayedData[touchedSpot.x.toInt()].date : _displayedData[touchedSpot.x.toInt()].time; }
                        String type = "";
                        if (showPerDoor) {
                          if (touchedSpot.barIndex < plottedDoors.length) type = "${plottedDoors[touchedSpot.barIndex].toUpperCase()}: ";
                        } else if (_isCompareMode) {
                          type = touchedSpot.barIndex == 0 ? (_isFrench ? "Actuel: " : "Current: ") : (_isFrench ? "Précédent: " : "Previous: ");
                        } else {
                          type = touchedSpot.barIndex == 0 ? (_isFrench ? "Entrées: " : "In: ") : (_isFrench ? "Sorties: " : "Out: ");
                        }
                        return LineTooltipItem("$timeText\n", const TextStyle(color: Colors.white70, fontSize: 13, fontWeight: FontWeight.w700), children: [TextSpan(text: "$type${touchedSpot.y.toInt()}", style: textStyle)]);
                      }).toList();
                    },
                  ),
                ),
                gridData: FlGridData(
                    show: true, drawVerticalLine: false, horizontalInterval: yInterval,
                    getDrawingHorizontalLine: (value) => FlLine(color: Colors.white.withOpacity(0.08), strokeWidth: 1.5, dashArray: [10, 10])
                ),
                titlesData: FlTitlesData(
                  rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                  topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                  leftTitles: AxisTitles(
                    sideTitles: SideTitles(
                      showTitles: true, reservedSize: 60, interval: yInterval,
                      getTitlesWidget: (value, meta) {
                        if (value == meta.max) return const SizedBox.shrink();
                        return Padding(
                          padding: const EdgeInsets.only(right: 20.0),
                          child: Text(value.toInt().toString(), textAlign: TextAlign.right, style: const TextStyle(color: Colors.white54, fontSize: 13, fontWeight: FontWeight.w800, fontFeatures: [FontFeature.tabularFigures()])),
                        );
                      },
                    ),
                  ),
                  bottomTitles: AxisTitles(
                    sideTitles: SideTitles(
                      showTitles: true, reservedSize: 50, interval: 1,
                      getTitlesWidget: (value, meta) {
                        int index = value.toInt();
                        if (index >= 0 && index < _displayedData.length) {
                          String displayText = _currentFilter == ChartFilter.hourly ? _displayedData[index].time.split(':')[0] : _displayedData[index].date.substring(0, 5);
                          return Padding(padding: const EdgeInsets.only(top: 16.0), child: Text(displayText, textAlign: TextAlign.center, style: const TextStyle(color: Colors.white54, fontSize: 12, fontWeight: FontWeight.w800, letterSpacing: 0.5)));
                        }
                        return const SizedBox.shrink();
                      },
                    ),
                  ),
                ),
                borderData: FlBorderData(show: false),
                lineBarsData: chartLines,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildZoneSelector() {
    if (_isSingleEntrance) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(_isFrench ? 'ZONES ET CAMÉRAS' : 'ZONES & CAMERAS', style: const TextStyle(color: Colors.white54, fontSize: 13, fontWeight: FontWeight.w900, letterSpacing: 3.0)),
        const SizedBox(height: 20),
        SizedBox(
          height: 60,
          child: ListView.builder(
            scrollDirection: Axis.horizontal,
            itemCount: _availableCameras.length,
            physics: const BouncingScrollPhysics(),
            itemBuilder: (context, index) {
              String cameraName = _availableCameras[index];
              bool isSelected = _selectedCamera == cameraName;
              String displayName = cameraName == 'All Doors' ? (_isFrench ? 'Vue Globale' : 'Global View') : cameraName.toUpperCase();

              return GestureDetector(
                onTap: () => setState(() { _selectedCamera = cameraName; _applyFilter(); }),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 300),
                  curve: Curves.easeOutCubic,
                  margin: const EdgeInsets.only(right: 16),
                  padding: const EdgeInsets.symmetric(horizontal: 32),
                  decoration: BoxDecoration(
                    color: isSelected ? Colors.white : _glassWhiteTint,
                    borderRadius: BorderRadius.circular(30),
                    border: Border.all(color: isSelected ? Colors.white : _glassBorder, width: 1.5),
                    boxShadow: isSelected ? [BoxShadow(color: Colors.white.withOpacity(0.3), blurRadius: 20, spreadRadius: 2)] : [],
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      if (cameraName != 'All Doors') ...[
                        Container(width: 10, height: 10, decoration: BoxDecoration(color: isSelected ? Colors.black : _accentCyan, shape: BoxShape.circle, boxShadow: [BoxShadow(color: _accentCyan, blurRadius: 8)])),
                        const SizedBox(width: 12),
                      ],
                      Text(
                          displayName,
                          style: TextStyle(color: isSelected ? Colors.black : Colors.white70, fontWeight: isSelected ? FontWeight.w900 : FontWeight.w700, fontSize: 15, letterSpacing: 0.5)
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _buildBentoGrid(bool isDesktop) {
    List<Widget> gridItems = [];

    if (!_enablePosFeatures) {
      gridItems = [
        _buildBentoCard(title: _isFrench ? 'TOTAL ENTRÉES' : 'TOTAL IN', value: '$_totalIn', unit: _isFrench ? 'PERS' : 'PAX', icon: Icons.login_rounded, color: const Color(0xFF38EF7D)),
        _buildBentoCard(title: _isFrench ? 'TOTAL SORTIES' : 'TOTAL OUT', value: '$_totalOut', unit: _isFrench ? 'PERS' : 'PAX', icon: Icons.logout_rounded, color: const Color(0xFFFF512F)),
        _buildBentoCard(title: _isFrench ? 'HEURE DE POINTE' : 'PEAK HOUR', value: _peakHour, unit: 'TIME', icon: Icons.access_time_filled_rounded, color: _accentCyan),
        _buildBentoCard(title: _isFrench ? 'OCCUPATION' : 'OCCUPANCY', value: '$_occupancy', unit: _isFrench ? 'ACTUEL' : 'NOW', icon: Icons.people_alt_rounded, color: _accentPurple),
      ];
    } else {
      int totalVisitors = (_totalIn + _totalOut) ~/ 2;
      double conversionRate = totalVisitors > 0 ? (_currentClients / totalVisitors) * 100 : 0.0;
      double avgBasket = _currentClients > 0 ? (_currentCa / _currentClients) : 0.0;
      double upt = _currentClients > 0 ? (_currentArticles / _currentClients) : 0.0;

      double compareConv = _compareTotalVisitors > 0 ? (_compareClients / _compareTotalVisitors) * 100 : 0.0;
      double compareBasket = _compareClients > 0 ? (_compareCa / _compareClients) : 0.0;
      double compareUpt = _compareClients > 0 ? (_compareArticles / _compareClients) : 0.0;

      gridItems = [
        _buildBentoCard(title: _isFrench ? 'CHIFFRE D\'AFFAIRES' : 'REVENUE', value: '${_currentCa.toStringAsFixed(0)}', unit: 'DZD', icon: Icons.account_balance_wallet_rounded, color: const Color(0xFF38EF7D), trendWidget: _buildTrendBadge(_currentCa, _compareCa)),
        _buildBentoCard(title: _isFrench ? 'TAUX DE CONV.' : 'CONV. RATE', value: conversionRate.toStringAsFixed(1), unit: '%', icon: Icons.track_changes_rounded, color: const Color(0xFFFF512F), trendWidget: _buildTrendBadge(conversionRate, compareConv)),
        _buildBentoCard(title: _isFrench ? 'PANIER MOYEN' : 'AVG BASKET', value: avgBasket.toStringAsFixed(0), unit: 'DZD', icon: Icons.shopping_bag_rounded, color: _accentCyan, trendWidget: _buildTrendBadge(avgBasket, compareBasket)),
        _buildBentoCard(title: _isFrench ? 'INDICE DE VENTE' : 'U.P.T', value: upt.toStringAsFixed(2), unit: 'ART', icon: Icons.layers_rounded, color: _accentPurple, trendWidget: _buildTrendBadge(upt, compareUpt)),
      ];
    }

    if (isDesktop) {
      return Row(
        children: [
          Expanded(flex: 2, child: gridItems[0]), const SizedBox(width: 32),
          Expanded(flex: 1, child: gridItems[1]), const SizedBox(width: 32),
          Expanded(flex: 1, child: gridItems[2]), const SizedBox(width: 32),
          Expanded(flex: 1, child: gridItems[3]),
        ],
      );
    } else {
      return Column(
        children: [
          gridItems[0], const SizedBox(height: 24),
          Row(children: [Expanded(child: gridItems[1]), const SizedBox(width: 24), Expanded(child: gridItems[2])]), const SizedBox(height: 24),
          gridItems[3],
        ],
      );
    }
  }

  Widget _buildBentoCard({required String title, required String value, required String unit, required IconData icon, required Color color, Widget? trendWidget}) {
    return _buildGlassContainer(
      height: 240,
      padding: const EdgeInsets.all(32),
      borderRadius: 40,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: color.withOpacity(0.15),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: color.withOpacity(0.4), width: 1.5),
                  boxShadow: [BoxShadow(color: color.withOpacity(0.3), blurRadius: 20)],
                ),
                child: Icon(icon, color: color, size: 32),
              ),
              if (trendWidget != null) trendWidget,
            ],
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: const TextStyle(fontSize: 13, color: Colors.white70, fontWeight: FontWeight.w900, letterSpacing: 2.5)),
              const SizedBox(height: 8),
              Row(
                crossAxisAlignment: CrossAxisAlignment.baseline,
                textBaseline: TextBaseline.alphabetic,
                children: [
                  Text(value, style: const TextStyle(fontSize: 52, fontWeight: FontWeight.w900, color: Colors.white, letterSpacing: -2.0)),
                  const SizedBox(width: 8),
                  Text(unit, style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: color.withOpacity(0.9))),
                ],
              ),
            ],
          ),
        ],
      ),
    );
  }
}

// =========================================================================
// THE SMART IP CAMERA STREAM ENGINE (AUTO-DETECT 2D/3D)
// =========================================================================
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