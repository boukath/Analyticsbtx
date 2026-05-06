// lib/screens/dashboard_windows.dart

import 'dart:ui';
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:shared_preferences/shared_preferences.dart';

// 🚀 Desktop Window and Tray Managers
import 'package:window_manager/window_manager.dart';
import 'package:tray_manager/tray_manager.dart';

import 'cloud_sync_screen.dart';
import '../services/ftp_service.dart';
import '../services/http_server_service.dart';
import 'ftp_server_screen.dart';
import '../models/people_count.dart';
import '../services/folder_scanner_service.dart';
import '../core/data_aggregator.dart';
import 'camera_ftp_setup_screen.dart';
import 'export_screen.dart';
import 'developer_screen.dart';
import '../services/firebase_sync_service.dart';

// 🚀 IMPORTS: Theme Manager & Extracted Widgets
import '../core/app_theme.dart';
import '../widgets/glass_container.dart';
import '../widgets/camera_stream.dart';
import '../widgets/dashboard_sidebar.dart';
import '../widgets/dashboard_bento_grid.dart';
import '../widgets/dashboard_header.dart';
import '../widgets/dashboard_chart.dart'; // ChartFilter is imported from here
import '../widgets/dashboard_data_table.dart';
import '../widgets/dashboard_top_bar.dart'; // 🚀 Added Top Bar import
import 'package:webview_windows/webview_windows.dart';

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

  // 🚀 Flags
  bool _isTableMode = false;
  bool _enablePosFeatures = true;
  bool _isSingleEntrance = false;

  // 🚀 Secret developer menu variables
  int _logoTapCount = 0;
  Timer? _logoTapTimer;

  // 🚀 Function to handle the secret 7-tap logic
  void _handleLogoTap() {
    _logoTapTimer?.cancel();
    _logoTapCount++;

    if (_logoTapCount >= 7) {
      _logoTapCount = 0;
      _openDeveloperScreen();
    } else {
      _logoTapTimer = Timer(const Duration(seconds: 2), () {
        _logoTapCount = 0;
      });
    }
  }

  void _showLinkIpDialog(String cameraName) {
    TextEditingController ipController = TextEditingController(text: _cameraIps[cameraName]);

    showDialog(
      context: context,
      barrierColor: Colors.transparent,
      builder: (context) => Stack(
        children: [
          Positioned.fill(child: BackdropFilter(filter: ImageFilter.blur(sigmaX: 15, sigmaY: 15), child: Container(color: AppTheme.isDark(context) ? Colors.black.withOpacity(0.4) : Colors.white.withOpacity(0.2)))),
          Center(
            child: Material(
              color: Colors.transparent,
              child: GlassContainer(
                width: 400,
                padding: const EdgeInsets.all(32),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        const Icon(Icons.link, color: AppTheme.cyan, size: 28),
                        const SizedBox(width: 12),
                        Text('Link IP to ${cameraName.toUpperCase()}', style: TextStyle(color: AppTheme.textPrimary(context), fontWeight: FontWeight.w800, fontSize: 18)),
                      ],
                    ),
                    const SizedBox(height: 24),
                    Text('Enter the Camera IP Address or Link:', style: TextStyle(color: AppTheme.textSecondary(context), fontSize: 14)),
                    const SizedBox(height: 12),
                    TextField(
                      controller: ipController,
                      style: TextStyle(color: AppTheme.textPrimary(context), fontWeight: FontWeight.bold),
                      decoration: InputDecoration(
                        hintText: 'e.g. 192.168.1.7',
                        hintStyle: TextStyle(color: AppTheme.textSecondary(context).withOpacity(0.3)),
                        filled: true,
                        fillColor: AppTheme.isDark(context) ? Colors.black.withOpacity(0.3) : Colors.white.withOpacity(0.5),
                        prefixIcon: const Icon(Icons.router, color: AppTheme.cyan),
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: BorderSide(color: AppTheme.glassBorder(context))),
                        enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: BorderSide(color: AppTheme.glassBorder(context))),
                        focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: const BorderSide(color: AppTheme.cyan, width: 2)),
                      ),
                    ),
                    const SizedBox(height: 32),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        TextButton(
                          onPressed: () => Navigator.pop(context),
                          child: Text('CANCEL', style: TextStyle(color: AppTheme.textSecondary(context), fontWeight: FontWeight.w600)),
                        ),
                        const SizedBox(width: 16),
                        ElevatedButton(
                          style: ElevatedButton.styleFrom(
                            backgroundColor: AppTheme.cyan,
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

  // 🚀 Server tracking variables
  bool _isFtpRunning = false;
  bool _isHttpRunning = false;
  int _ftpPort = 21;
  int _httpPort = 8080;
  Timer? _serverStatusTimer;

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

  int _estimatedDwellTimeMins = 0;

  Map<String, Map<String, num>> _posDatabase = {};
  double _currentCa = 0;
  int _currentClients = 0;
  int _currentArticles = 0;
  String _storeName = "My Store";
  String _storeLocation = "MAIN BRANCH";
  String? _storeLogoPath;
  String _erpPortalLink = "";
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
    _checkServerStatus();
    _startSecurityMonitor();
    _loadCameraIps();

    _serverStatusTimer = Timer.periodic(const Duration(seconds: 3), (_) => _checkServerStatus());
  }

  Future<void> _initSystemTray() async {
    await trayManager.setIcon('windows/runner/resources/app_icon.ico');
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
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Starting Cloud Sync...'), backgroundColor: Colors.orangeAccent));
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
    _serverStatusTimer?.cancel();
    _logoTapTimer?.cancel();
    FtpService.stopServer();
    HttpServerService.stopServer();
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
            backgroundColor: AppTheme.cyan,
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
            Positioned.fill(child: BackdropFilter(filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20), child: Container(color: AppTheme.isDark(context) ? Colors.black.withOpacity(0.6) : Colors.white.withOpacity(0.3)))),
            Center(
              child: StatefulBuilder(
                  builder: (context, setDialogState) {
                    return Material(
                      color: Colors.transparent,
                      child: GlassContainer(
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
                                    style: TextStyle(color: AppTheme.textPrimary(context), fontWeight: FontWeight.w900, fontSize: 20, letterSpacing: 1.0)
                                ),
                              ],
                            ),
                            const SizedBox(height: 24),
                            Text(
                              _isFrench
                                  ? "L'adresse IP du PC a changé et AUCUN TRAFIC (0) n'est enregistré !\n\nIP Attendue: $_expectedIp\nIP Actuelle: ${_actualIp == '127.0.0.1' ? 'DÉCONNECTÉ' : _actualIp}\n\nVeuillez réparer le réseau immédiatement, ou entrez le mot de passe technicien pour désactiver cette alerte."
                                  : "The PC's IP Address has changed and NO TRAFFIC (0) is being recorded!\n\nExpected IP: $_expectedIp\nCurrent IP: ${_actualIp == '127.0.0.1' ? 'DISCONNECTED' : _actualIp}\n\nPlease fix the network immediately, or enter the technician password to silence this alert.",
                              style: TextStyle(color: AppTheme.textSecondary(context), fontSize: 16, height: 1.6),
                            ),
                            const SizedBox(height: 32),
                            TextField(
                              controller: passCtrl,
                              obscureText: true,
                              style: TextStyle(color: AppTheme.textPrimary(context), fontWeight: FontWeight.bold),
                              decoration: InputDecoration(
                                labelText: _isFrench ? 'Mot de passe technicien' : 'Technician Password',
                                labelStyle: TextStyle(color: AppTheme.textSecondary(context)),
                                filled: true,
                                fillColor: AppTheme.isDark(context) ? Colors.black.withOpacity(0.4) : Colors.white.withOpacity(0.5),
                                border: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: BorderSide(color: AppTheme.glassBorder(context))),
                                enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: BorderSide(color: AppTheme.glassBorder(context))),
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
                                      style: const TextStyle(color: AppTheme.cyan, fontWeight: FontWeight.bold, letterSpacing: 1)
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
                                  child: Text(_isFrench ? "SILENCIEUX" : "SILENCE ALERT", style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w900)),
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
    _checkServerStatus();
    _loadStoreProfile();
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
      _erpPortalLink = prefs.getString('erp_portal_link') ?? '';
    });
  }

  Future<void> _checkServerStatus() async {
    String ip = await FtpService.getLocalIpAddress();
    final prefs = await SharedPreferences.getInstance();
    int ftpPort = prefs.getInt('ftp_port') ?? 21;
    int httpPort = prefs.getInt('http_port') ?? 8080;

    if (mounted) {
      setState(() {
        _isFtpRunning = FtpService.isRunning;
        _isHttpRunning = HttpServerService.isRunning;
        _localIp = ip;
        _ftpPort = ftpPort;
        _httpPort = httpPort;
      });
    }
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

  Future<void> _forceRefreshAndGoToLatest() async {
    if (_selectedFolderPath == null) return;

    setState(() {
      _isLoading = true;
    });

    _scannerService.clearCache();
    List<PeopleCount> latestData = await _scannerService.loadScbDataFromFolder(_selectedFolderPath!);

    setState(() {
      _rawData = latestData;

      if (_rawData.isNotEmpty) {
        Set<String> uniqueIds = _rawData.map((e) => e.doorName).toSet();
        List<String> sortedIds = uniqueIds.toList()..sort();
        _availableCameras = ['All Doors', ...sortedIds];

        DateTime maxDate = DateTime(2000);
        for (var item in _rawData) {
          var dateParts = item.date.split('/');
          if (dateParts.length == 3) {
            DateTime rowDate = DateTime(
                int.parse(dateParts[2]),
                int.parse(dateParts[1]),
                int.parse(dateParts[0])
            );
            if (rowDate.isAfter(maxDate)) {
              maxDate = rowDate;
            }
          }
        }

        if (maxDate.year == 2000) {
          DateTime now = DateTime.now();
          maxDate = DateTime(now.year, now.month, now.day);
        }

        _selectedDateRange = DateTimeRange(start: maxDate, end: maxDate);
      }

      _applyFilter();
      _isLoading = false;
    });

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            _isFrench ? 'Données actualisées !' : 'Data refreshed successfully!',
            style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.white),
          ),
          backgroundColor: AppTheme.cyan,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          duration: const Duration(seconds: 2),
        ),
      );
    }
  }

  Future<void> _processDataFromPath(String folderPath) async {
    setState(() { _isLoading = true; _selectedFolderPath = folderPath; _selectedDateRange = null; });

    _scannerService.clearCache();
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
    _autoRefreshTimer = Timer.periodic(const Duration(minutes: 5), (timer) => _refreshDataSilently());
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

        if (_selectedDateRange != null) {
          var dateParts = item.date.split('/');
          if (dateParts.length == 3) {
            int day = int.parse(dateParts[0]);
            int month = int.parse(dateParts[1]);
            int year = int.parse(dateParts[2]);
            DateTime rowDate = DateTime(year, month, day);

            if (rowDate.isBefore(_selectedDateRange!.start.subtract(const Duration(days: 1))) ||
                rowDate.isAfter(_selectedDateRange!.end.add(const Duration(days: 1)))) {
              return false;
            }
          }
        }

        var timeParts = item.time.split(':');
        int hour = timeParts.isNotEmpty ? (int.tryParse(timeParts[0]) ?? 0) : 0;
        int minute = timeParts.length > 1 ? (int.tryParse(timeParts[1]) ?? 0) : 0;
        int totalMinutes = (hour * 60) + minute;

        if (totalMinutes < _workingMinuteStart || totalMinutes > _workingMinuteEnd) return false;

        return true;
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

      int runningOccupancy = 0;
      double sumOccupancy = 0;
      int activePeriods = 0;

      for (var item in _displayedData) {
        _totalIn += item.inCount;
        _totalOut += item.outCount;

        int totalVisitorsForHour = (item.inCount + item.outCount) ~/ 2;
        if (totalVisitorsForHour > maxTraffic) {
          maxTraffic = totalVisitorsForHour;
          _peakHour = item.time;
        }

        runningOccupancy += (item.inCount - item.outCount);
        if (runningOccupancy < 0) runningOccupancy = 0;
        sumOccupancy += runningOccupancy;
        activePeriods++;
      }

      _occupancy = _totalIn - _totalOut;
      if (_occupancy < 0) _occupancy = 0;

      double avgOccupancy = activePeriods > 0 ? (sumOccupancy / activePeriods) : 0;
      double totalMinutesForDwell = activePeriods > 0
          ? (_currentFilter == ChartFilter.hourly ? activePeriods * 60.0 : activePeriods * 24 * 60.0)
          : 1.0;

      double arrivalRatePerMinute = _totalIn / totalMinutesForDwell;

      if (arrivalRatePerMinute > 0) {
        _estimatedDwellTimeMins = (avgOccupancy / arrivalRatePerMinute).round();
      } else {
        _estimatedDwellTimeMins = 0;
      }

      if (_isCompareMode && _selectedDateRange != null) {
        Duration duration = _selectedDateRange!.end.difference(_selectedDateRange!.start);
        DateTime compareEnd = _selectedDateRange!.start.subtract(const Duration(days: 1));
        DateTime compareStart = compareEnd.subtract(duration);

        List<PeopleCount> compareFilteredData = _rawData.where((item) {
          if (_selectedCamera != 'All Doors' && item.doorName != _selectedCamera) return false;

          var dateParts = item.date.split('/');
          if (dateParts.length == 3) {
            int day = int.parse(dateParts[0]), month = int.parse(dateParts[1]), year = int.parse(dateParts[2]);
            DateTime rowDate = DateTime(year, month, day);
            if (rowDate.isBefore(compareStart.subtract(const Duration(days: 1))) ||
                rowDate.isAfter(compareEnd.add(const Duration(days: 1)))) {
              return false;
            }
          }

          var timeParts = item.time.split(':');
          int hour = timeParts.isNotEmpty ? (int.tryParse(timeParts[0]) ?? 0) : 0;
          int minute = timeParts.length > 1 ? (int.tryParse(timeParts[1]) ?? 0) : 0;
          int totalMinutes = (hour * 60) + minute;
          if (totalMinutes < _workingMinuteStart || totalMinutes > _workingMinuteEnd) return false;

          return true;
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
            colorScheme: ColorScheme.dark(
                primary: AppTheme.cyan,
                onPrimary: Colors.black,
                surface: AppTheme.bgDeep(context),
                onSurface: AppTheme.textPrimary(context)
            ),
            dialogBackgroundColor: AppTheme.bgDeep(context),
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
              Positioned.fill(child: BackdropFilter(filter: ImageFilter.blur(sigmaX: 15, sigmaY: 15), child: Container(color: AppTheme.isDark(context) ? Colors.black.withOpacity(0.4) : Colors.white.withOpacity(0.2)))),
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
                                  builder: (context, child) => Theme(
                                      data: ThemeData.dark().copyWith(
                                          colorScheme: ColorScheme.dark(
                                              primary: AppTheme.cyan,
                                              surface: AppTheme.bgDeep(context),
                                              onSurface: AppTheme.textPrimary(context)
                                          )
                                      ),
                                      child: child!
                                  ),
                                );
                                if (picked != null) { setDialogState(() { if (isStart) startTime = picked; else endTime = picked; }); }
                              },
                              child: GlassContainer(
                                padding: const EdgeInsets.symmetric(vertical: 24),
                                borderRadius: 16,
                                child: Column(
                                  children: [
                                    Text(label, style: TextStyle(color: AppTheme.textSecondary(context), fontSize: 12, fontWeight: FontWeight.w800, letterSpacing: 2)),
                                    const SizedBox(height: 12),
                                    Text(
                                        "${time.hour.toString().padLeft(2, '0')}:${time.minute.toString().padLeft(2, '0')}",
                                        style: TextStyle(color: AppTheme.textPrimary(context), fontSize: 28, fontWeight: FontWeight.w900)
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          );
                        }

                        return GlassContainer(
                          width: 450,
                          padding: const EdgeInsets.all(32),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  const Icon(Icons.access_time, color: AppTheme.cyan, size: 28),
                                  const SizedBox(width: 12),
                                  Text(_isFrench ? "Heures d'Ouverture" : "Operating Hours", style: TextStyle(color: AppTheme.textPrimary(context), fontWeight: FontWeight.w800, fontSize: 18)),
                                ],
                              ),
                              const SizedBox(height: 16),
                              Text(
                                _isFrench
                                    ? "Filtrez les données au niveau de la minute exacte pour exclure le personnel de nettoyage ou les mouvements en dehors des heures de travail."
                                    : "Filter data down to the exact minute to exclude cleaning staff or movements outside of business hours.",
                                style: TextStyle(color: AppTheme.textSecondary(context), fontSize: 14, height: 1.5),
                              ),
                              const SizedBox(height: 32),
                              Row(
                                children: [
                                  _buildTimeButton(_isFrench ? "OUVERTURE" : "OPENING", startTime, true),
                                  Padding(padding: const EdgeInsets.symmetric(horizontal: 16), child: Icon(Icons.arrow_forward_rounded, color: AppTheme.textSecondary(context).withOpacity(0.5))),
                                  _buildTimeButton(_isFrench ? "FERMETURE" : "CLOSING", endTime, false),
                                ],
                              ),
                              const SizedBox(height: 32),
                              Row(
                                mainAxisAlignment: MainAxisAlignment.end,
                                children: [
                                  TextButton(onPressed: () => Navigator.pop(context), child: Text(_isFrench ? "ANNULER" : "CANCEL", style: TextStyle(color: AppTheme.textSecondary(context), fontWeight: FontWeight.w600))),
                                  const SizedBox(width: 16),
                                  ElevatedButton(
                                    style: ElevatedButton.styleFrom(backgroundColor: AppTheme.cyan, foregroundColor: Colors.black, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)), padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12)),
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
            Positioned.fill(child: BackdropFilter(filter: ImageFilter.blur(sigmaX: 15, sigmaY: 15), child: Container(color: AppTheme.isDark(context) ? Colors.black.withOpacity(0.4) : Colors.white.withOpacity(0.2)))),
            Center(
              child: Material(
                color: Colors.transparent,
                child: GlassContainer(
                  width: 450,
                  padding: const EdgeInsets.all(32),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.point_of_sale, color: Colors.greenAccent, size: 48),
                      const SizedBox(height: 16),
                      Text(_isFrench ? 'SAISIR LES DONNÉES DE CAISSE' : 'ENTER DAILY POS DATA', style: TextStyle(color: AppTheme.textPrimary(context), fontWeight: FontWeight.w900, fontSize: 18, letterSpacing: 1.0)),
                      const SizedBox(height: 8),
                      Text('${_isFrench ? "Date : " : "Date: "}${_getFormattedDateString()}', style: TextStyle(color: AppTheme.textSecondary(context), fontSize: 13, fontWeight: FontWeight.w600)),
                      const SizedBox(height: 32),
                      TextField(controller: caCtrl, style: TextStyle(color: AppTheme.textPrimary(context), fontWeight: FontWeight.bold), keyboardType: const TextInputType.numberWithOptions(decimal: true), decoration: InputDecoration(labelText: _isFrench ? 'Chiffre d\'Affaires (DZD)' : 'Revenue (DZD)', labelStyle: TextStyle(color: AppTheme.textSecondary(context)), filled: true, fillColor: AppTheme.isDark(context) ? Colors.black.withOpacity(0.3) : Colors.white.withOpacity(0.5), border: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: BorderSide(color: AppTheme.glassBorder(context))), enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: BorderSide(color: AppTheme.glassBorder(context))), focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: const BorderSide(color: Colors.greenAccent, width: 2)), prefixIcon: const Icon(Icons.payments, color: Colors.greenAccent))),
                      const SizedBox(height: 16),
                      TextField(controller: clientCtrl, style: TextStyle(color: AppTheme.textPrimary(context), fontWeight: FontWeight.bold), keyboardType: TextInputType.number, decoration: InputDecoration(labelText: _isFrench ? 'Total Clients' : 'Total Clients', labelStyle: TextStyle(color: AppTheme.textSecondary(context)), filled: true, fillColor: AppTheme.isDark(context) ? Colors.black.withOpacity(0.3) : Colors.white.withOpacity(0.5), border: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: BorderSide(color: AppTheme.glassBorder(context))), enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: BorderSide(color: AppTheme.glassBorder(context))), focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: const BorderSide(color: AppTheme.cyan, width: 2)), prefixIcon: const Icon(Icons.receipt_long, color: AppTheme.cyan))),
                      const SizedBox(height: 16),
                      TextField(controller: articleCtrl, style: TextStyle(color: AppTheme.textPrimary(context), fontWeight: FontWeight.bold), keyboardType: TextInputType.number, decoration: InputDecoration(labelText: _isFrench ? 'Articles Vendus' : 'Articles Sold', labelStyle: TextStyle(color: AppTheme.textSecondary(context)), filled: true, fillColor: AppTheme.isDark(context) ? Colors.black.withOpacity(0.3) : Colors.white.withOpacity(0.5), border: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: BorderSide(color: AppTheme.glassBorder(context))), enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: BorderSide(color: AppTheme.glassBorder(context))), focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: const BorderSide(color: AppTheme.magenta, width: 2)), prefixIcon: const Icon(Icons.shopping_bag, color: AppTheme.magenta))),
                      const SizedBox(height: 32),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.end,
                        children: [
                          TextButton(onPressed: () => Navigator.pop(context), child: Text(_isFrench ? 'ANNULER' : 'CANCEL', style: TextStyle(color: AppTheme.textSecondary(context), fontWeight: FontWeight.w600))),
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

  @override
  Widget build(BuildContext context) {
    final isDesktop = MediaQuery.of(context).size.width > 800;

    return Scaffold(
      backgroundColor: AppTheme.bgDeep(context), // 🚀 Dynamic Background!
      body: Stack(
        children: [
          // 🌌 HYPER-MODERN AMBIENT MESH ORBS
          Positioned(
              top: -200, left: -200,
              child: AnimatedContainer(
                  duration: const Duration(milliseconds: 700),
                  curve: Curves.easeInOutCubic,
                  width: 600, height: 600,
                  decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: AppTheme.orbPurple(context),
                      boxShadow: [BoxShadow(blurRadius: 200, color: AppTheme.orbPurple(context))]
                  )
              )
          ),
          Positioned(
              bottom: -200, right: -100,
              child: AnimatedContainer(
                  duration: const Duration(milliseconds: 700),
                  curve: Curves.easeInOutCubic,
                  width: 700, height: 700,
                  decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: AppTheme.orbCyan(context),
                      boxShadow: [BoxShadow(blurRadius: 250, color: AppTheme.orbCyan(context))]
                  )
              )
          ),
          Positioned(
              top: 300, right: 300,
              child: AnimatedContainer(
                  duration: const Duration(milliseconds: 700),
                  curve: Curves.easeInOutCubic,
                  width: 400, height: 400,
                  decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: AppTheme.orbMagenta(context),
                      boxShadow: [BoxShadow(blurRadius: 200, color: AppTheme.orbMagenta(context))]
                  )
              )
          ),

          // 💻 MAIN UI
          Row(
            children: [
              if (isDesktop)
                DashboardSidebar(
                  isFrench: _isFrench,
                  enablePosFeatures: _enablePosFeatures,
                  hasData: _rawData.isNotEmpty,
                  erpPortalLink: _erpPortalLink,
                  isIpMismatch: _isIpMismatch,
                  isFtpRunning: _isFtpRunning,
                  isHttpRunning: _isHttpRunning,
                  localIp: _localIp,
                  ftpPort: _ftpPort,
                  httpPort: _httpPort,
                  onLogoTap: _handleLogoTap,
                  onPosEntryTap: _showPosEntryDialog,
                  onExportTap: _showExportMenu,
                  onDeveloperTap: _openDeveloperScreen,
                ),
              Expanded(
                child: Column(
                  children: [
                    // 🚀 NEW: The Top Bar is now beautifully integrated!
                    DashboardTopBar(
                      isFrench: _isFrench,
                      onToggleLanguage: _toggleLanguage,
                      storeName: _storeName,
                      storeLocation: _storeLocation,
                      storeLogoPath: _storeLogoPath,
                    ),

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
                          ? const Center(child: CircularProgressIndicator(color: AppTheme.cyan))
                          : SingleChildScrollView(
                        padding: const EdgeInsets.symmetric(horizontal: 40.0, vertical: 40.0),
                        physics: const BouncingScrollPhysics(),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            DashboardHeader(
                              isFrench: _isFrench,
                              selectedFolderPath: _selectedFolderPath,
                              isFtpRunning: _isFtpRunning,
                              isHttpRunning: _isHttpRunning,
                              isCompareMode: _isCompareMode,
                              isFilterActive: _workingMinuteStart > 0 || _workingMinuteEnd < 1439,
                              formattedDateString: _getFormattedDateString(),
                              hasData: _rawData.isNotEmpty,
                              onCompareModeChanged: (val) {
                                setState(() { _isCompareMode = val; _applyFilter(); });
                              },
                              onRefreshTap: _forceRefreshAndGoToLatest,
                              onPickDateRange: _pickDateRange,
                              onShiftDate: _shiftDate,
                              onShowWorkingHoursDialog: _showWorkingHoursDialog,
                            ),
                            const SizedBox(height: 32),

                            if (_rawData.isEmpty)
                              Center(
                                child: Padding(
                                  padding: const EdgeInsets.only(top: 120),
                                  child: Column(
                                    children: [
                                      Icon(Icons.folder_open_rounded, size: 120, color: AppTheme.textPrimary(context).withOpacity(0.05)),
                                      const SizedBox(height: 32),
                                      Text(_isFrench ? 'Aucune Donnée Sélectionnée' : 'No Data Selected', style: TextStyle(fontSize: 32, fontWeight: FontWeight.w900, color: AppTheme.textPrimary(context), letterSpacing: -1.0)),
                                      const SizedBox(height: 16),
                                      Text(
                                          _isFrench
                                              ? 'Veuillez sélectionner une source de données ou démarrer le serveur FTP.'
                                              : 'Please select a data source or start the FTP server from the menu.',
                                          style: TextStyle(color: AppTheme.textSecondary(context), fontSize: 18, fontWeight: FontWeight.w500)
                                      ),
                                      const SizedBox(height: 40),
                                      ElevatedButton.icon(
                                        style: ElevatedButton.styleFrom(
                                            backgroundColor: AppTheme.cyan,
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
                              )
                            else ...[
                              GlassContainer(
                                padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 24),
                                borderRadius: 24,
                                child: Row(
                                  children: [
                                    Container(
                                      padding: const EdgeInsets.all(12),
                                      decoration: BoxDecoration(
                                        color: AppTheme.purple.withOpacity(0.2),
                                        shape: BoxShape.circle,
                                        boxShadow: [BoxShadow(color: AppTheme.purple.withOpacity(0.5), blurRadius: 20)],
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
                                              style: const TextStyle(color: AppTheme.cyan, fontSize: 12, fontWeight: FontWeight.w900, letterSpacing: 3.0)
                                          ),
                                          const SizedBox(height: 8),
                                          Text(
                                              (_isFrench
                                                  ? "Le trafic d'aujourd'hui atteint ${((_totalIn + _totalOut) ~/ 2)} visiteurs, avec une activité maximale enregistrée à $_peakHour."
                                                  : "Today's traffic has reached ${((_totalIn + _totalOut) ~/ 2)} visitors, with peak activity recorded at $_peakHour.")
                                                  + ((_workingMinuteStart > 0 || _workingMinuteEnd < 1439) ? (_isFrench ? " (Filtré: ${_formatMinutesToTimeString(_workingMinuteStart)} - ${_formatMinutesToTimeString(_workingMinuteEnd)})" : " (Filtered: ${_formatMinutesToTimeString(_workingMinuteStart)} - ${_formatMinutesToTimeString(_workingMinuteEnd)})") : ""),
                                              style: TextStyle(color: AppTheme.textPrimary(context), fontSize: 18, fontWeight: FontWeight.w600, height: 1.4)
                                          ),
                                        ],
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              const SizedBox(height: 32),

                              DashboardChart(
                                isFrench: _isFrench,
                                totalIn: _totalIn,
                                totalOut: _totalOut,
                                compareTotalVisitors: _compareTotalVisitors,
                                isTableMode: _isTableMode,
                                currentFilter: _currentFilter,
                                isSingleEntrance: _isSingleEntrance,
                                selectedCamera: _selectedCamera,
                                availableCameras: _availableCameras,
                                isCompareMode: _isCompareMode,
                                perDoorData: _perDoorData,
                                displayedData: _displayedData,
                                compareDisplayedData: _compareDisplayedData,
                                onTableModeChanged: (val) {
                                  setState(() => _isTableMode = val);
                                },
                                onFilterChanged: (val) {
                                  setState(() { _currentFilter = val; _applyFilter(); });
                                },
                                tableViewWidget: DashboardDataTable(
                                  isFrench: _isFrench,
                                  isSingleEntrance: _isSingleEntrance,
                                  selectedCamera: _selectedCamera,
                                  availableCameras: _availableCameras,
                                  isCompareMode: _isCompareMode,
                                  currentFilter: _currentFilter,
                                  displayedData: _displayedData,
                                  compareDisplayedData: _compareDisplayedData,
                                  perDoorData: _perDoorData,
                                  totalIn: _totalIn,
                                  totalOut: _totalOut,
                                  compareTotalIn: _compareTotalIn,
                                  compareTotalOut: _compareTotalOut,
                                ),
                              ),

                              if (!_isSingleEntrance) ...[
                                const SizedBox(height: 40),
                                Text(_isFrench ? 'ZONES ET CAMÉRAS' : 'ZONES & CAMERAS', style: TextStyle(color: AppTheme.textSecondary(context), fontSize: 13, fontWeight: FontWeight.w900, letterSpacing: 3.0)),
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
                                            color: isSelected ? AppTheme.textPrimary(context) : AppTheme.glassTintStart(context),
                                            borderRadius: BorderRadius.circular(30),
                                            border: Border.all(color: isSelected ? AppTheme.textPrimary(context) : AppTheme.glassBorder(context), width: 1.5),
                                            boxShadow: isSelected ? [BoxShadow(color: AppTheme.textPrimary(context).withOpacity(0.3), blurRadius: 20, spreadRadius: 2)] : [],
                                          ),
                                          child: Row(
                                            mainAxisAlignment: MainAxisAlignment.center,
                                            children: [
                                              if (cameraName != 'All Doors') ...[
                                                Container(width: 10, height: 10, decoration: BoxDecoration(color: isSelected ? AppTheme.bgDeep(context) : AppTheme.cyan, shape: BoxShape.circle, boxShadow: const [BoxShadow(color: AppTheme.cyan, blurRadius: 8)])),
                                                const SizedBox(width: 12),
                                              ],
                                              Text(
                                                  displayName,
                                                  style: TextStyle(color: isSelected ? AppTheme.bgDeep(context) : AppTheme.textSecondary(context), fontWeight: isSelected ? FontWeight.w900 : FontWeight.w700, fontSize: 15, letterSpacing: 0.5)
                                              ),
                                            ],
                                          ),
                                        ),
                                      );
                                    },
                                  ),
                                ),
                              ],

                              if (_selectedCamera != 'All Doors') ...[
                                const SizedBox(height: 40),
                                GlassContainer(
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
                                              Icon(Icons.fiber_manual_record, color: (_cameraIps[_selectedCamera] != null && _cameraIps[_selectedCamera]!.isNotEmpty) ? Colors.redAccent : Colors.grey, size: 16),
                                              const SizedBox(width: 12),
                                              Text(
                                                  (_cameraIps[_selectedCamera] != null && _cameraIps[_selectedCamera]!.isNotEmpty) ? 'LIVE PREVIEW - ${_selectedCamera.toUpperCase()}' : 'NO IP CONFIGURED FOR ${_selectedCamera.toUpperCase()}',
                                                  style: TextStyle(color: AppTheme.textPrimary(context), fontSize: 15, fontWeight: FontWeight.w900, letterSpacing: 2.0)
                                              ),
                                            ],
                                          ),
                                          if (_cameraIps[_selectedCamera] != null && _cameraIps[_selectedCamera]!.isNotEmpty)
                                            IconButton(
                                              icon: Icon(Icons.edit, color: AppTheme.textSecondary(context), size: 20),
                                              tooltip: 'Edit Camera IP',
                                              onPressed: () => _showLinkIpDialog(_selectedCamera),
                                            ),
                                        ],
                                      ),
                                      const SizedBox(height: 24),
                                      if (_cameraIps[_selectedCamera] == null || _cameraIps[_selectedCamera]!.isEmpty)
                                        Center(
                                          child: Padding(
                                            padding: const EdgeInsets.all(40.0),
                                            child: Column(
                                              children: [
                                                Icon(Icons.videocam_off, color: AppTheme.textSecondary(context).withOpacity(0.3), size: 64),
                                                const SizedBox(height: 24),
                                                Text('No IP assigned to $_selectedCamera.', style: TextStyle(color: AppTheme.textSecondary(context), fontSize: 16)),
                                                const SizedBox(height: 32),
                                                ElevatedButton.icon(
                                                  style: ElevatedButton.styleFrom(
                                                      backgroundColor: AppTheme.cyan,
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
                                            color: Colors.black, // Video feed background should stay black
                                            child: CameraStreamWidget(ipAddress: _cameraIps[_selectedCamera]!),
                                          ),
                                        ),
                                    ],
                                  ),
                                ),
                              ],

                              const SizedBox(height: 40),
                              DashboardBentoGrid(
                                isDesktop: isDesktop,
                                enablePosFeatures: _enablePosFeatures,
                                isFrench: _isFrench,
                                totalIn: _totalIn,
                                totalOut: _totalOut,
                                estimatedDwellTimeMins: _estimatedDwellTimeMins,
                                peakHour: _peakHour,
                                occupancy: _occupancy,
                                currentCa: _currentCa,
                                compareCa: _compareCa,
                                conversionRate: _totalIn > 0 ? (_currentClients / ((_totalIn + _totalOut) ~/ 2)) * 100 : 0.0,
                                compareConv: _compareTotalVisitors > 0 ? (_compareClients / _compareTotalVisitors) * 100 : 0.0,
                                avgBasket: _currentClients > 0 ? (_currentCa / _currentClients) : 0.0,
                                compareBasket: _compareClients > 0 ? (_compareCa / _compareClients) : 0.0,
                                upt: _currentClients > 0 ? (_currentArticles / _currentClients) : 0.0,
                                compareUpt: _compareClients > 0 ? (_compareArticles / _compareClients) : 0.0,
                                isCompareMode: _isCompareMode,
                              ),
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
}