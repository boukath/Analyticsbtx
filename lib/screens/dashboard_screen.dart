// lib/screens/dashboard_screen.dart

import 'dart:ui';
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data'; // 🚀 NEW: Required for manual camera bytes
import 'package:flutter/foundation.dart'; // 🚀 NEW: Required for HTTP streaming
import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:shared_preferences/shared_preferences.dart';
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
enum ChartFilter { hourly, daily }

class DashboardScreen extends StatefulWidget {
  const DashboardScreen({Key? key}) : super(key: key);

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  List<PeopleCount> _rawData = [];
  List<PeopleCount> _displayedData = [];
  Map<String, List<PeopleCount>> _perDoorData = {};
  bool _isLoading = false;
  String? _selectedFolderPath;
  ChartFilter _currentFilter = ChartFilter.hourly;
  DateTimeRange? _selectedDateRange;

  // 🚀 NEW: The Dialog to link an IP directly to the selected Door/Zone
  void _showLinkIpDialog(String cameraName) {
    TextEditingController ipController = TextEditingController(text: _cameraIps[cameraName]);

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: _cardDark,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16), side: BorderSide(color: Colors.white.withOpacity(0.1))),
        title: Row(
          children: [
            Icon(Icons.link, color: _accentCyan),
            const SizedBox(width: 12),
            Text('Link IP to ${cameraName.toUpperCase()}', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Enter the Camera IP Address or Link:', style: TextStyle(color: Colors.white54, fontSize: 14)),
            const SizedBox(height: 16),
            TextField(
              controller: ipController,
              style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
              decoration: InputDecoration(
                hintText: 'e.g. 192.168.1.7',
                hintStyle: const TextStyle(color: Colors.white24),
                filled: true,
                fillColor: _bgDark,
                prefixIcon: Icon(Icons.router, color: _accentCyan),
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
            onPressed: () async {
              String newIp = ipController.text.trim();
              final prefs = await SharedPreferences.getInstance();

              // Saves the IP securely to the exact folder/door name
              await prefs.setString('ip_$cameraName', newIp);

              setState(() {
                _cameraIps[cameraName] = newIp;
              });

              if (context.mounted) Navigator.pop(context);
            },
            child: const Text('SAVE IP', style: TextStyle(fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }

  Timer? _autoRefreshTimer;
  String _localIp = "";
  bool _isFtpRunning = false;

  // --- LIVE FEED STATE ---
  Map<String, String> _cameraIps = {};

  // --- IP Security Variables ---
  Timer? _securityTimer;
  bool _isIpMismatch = false;
  String _expectedIp = "";
  String _actualIp = "";

  bool _isAlertSilenced = false;
  bool _isAlertDialogOpen = false;

  // --- Language State ---
  bool _isFrench = false;

  // --- NEW: OPERATING HOURS STATE (Stored in Total Minutes from Midnight) ---
  int _workingMinuteStart = 0;    // Default: 00:00 (0 mins)
  int _workingMinuteEnd = 1439;   // Default: 23:59 (1439 mins)

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

  // --- PREMIUM THEME COLORS ---
  final Color _bgDark = const Color(0xFF0F172A); // Slate 900
  final Color _cardDark = const Color(0xFF1E293B); // Slate 800
  final Color _accentCyan = const Color(0xFF06B6D4); // Neon Cyan for IN / Active
  final Color _accentMagenta = const Color(0xFFD946EF); // Neon Magenta for OUT
  final Color _accentGrey = const Color(0xFF64748B); // Slate 500 for Comparisons

  @override
  void initState() {
    super.initState();
    _loadLanguagePref();
    _loadWorkingHoursPref();
    _loadStoreProfile();
    _loadPosDatabase();
    _loadSavedFolder();
    _checkFtpStatus();
    _startSecurityMonitor();
    _loadCameraIps();
  }

  @override
  void dispose() {
    _autoRefreshTimer?.cancel();
    _securityTimer?.cancel();
    FtpService.stopServer();
    super.dispose();
  }

  // 🚀 NEW: Load IPs from Storage
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
    setState(() {
      _isFrench = !_isFrench;
    });
    await prefs.setString('app_language', _isFrench ? 'fr' : 'en');

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              _isFrench ? 'Langue changée en Français' : 'Language changed to English',
              style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.white),
            ),
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
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

        if (!_isIpMismatch) {
          _isAlertSilenced = false;
        }

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
      builder: (BuildContext c) {
        return StatefulBuilder(
            builder: (context, setDialogState) {
              return AlertDialog(
                backgroundColor: _cardDark,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16), side: const BorderSide(color: Colors.redAccent, width: 2)),
                title: Row(
                  children: [
                    const Icon(Icons.warning_amber_rounded, color: Colors.redAccent, size: 32),
                    const SizedBox(width: 12),
                    Text(
                        _isFrench ? "ERREUR RÉSEAU CRITIQUE" : "CRITICAL NETWORK ERROR",
                        style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)
                    ),
                  ],
                ),
                content: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _isFrench
                          ? "L'adresse IP du PC a changé et AUCUN TRAFIC (0) n'est enregistré !\n\nIP Attendue: $_expectedIp\nIP Actuelle: ${_actualIp == '127.0.0.1' ? 'DÉCONNECTÉ' : _actualIp}\n\nVeuillez réparer le réseau immédiatement, ou entrez le mot de passe technicien pour désactiver cette alerte."
                          : "The PC's IP Address has changed and NO TRAFFIC (0) is being recorded!\n\nExpected IP: $_expectedIp\nCurrent IP: ${_actualIp == '127.0.0.1' ? 'DISCONNECTED' : _actualIp}\n\nPlease fix the network immediately, or enter the technician password to silence this alert.",
                      style: const TextStyle(color: Colors.white70, fontSize: 16, height: 1.5),
                    ),
                    const SizedBox(height: 20),
                    TextField(
                      controller: passCtrl,
                      obscureText: true,
                      style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                      decoration: InputDecoration(
                        labelText: _isFrench ? 'Mot de passe technicien' : 'Technician Password',
                        labelStyle: const TextStyle(color: Colors.white54),
                        filled: true,
                        fillColor: _bgDark,
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide.none),
                        errorText: errorMessage.isNotEmpty ? errorMessage : null,
                      ),
                    ),
                  ],
                ),
                actions: [
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
                  ElevatedButton(
                    style: ElevatedButton.styleFrom(backgroundColor: Colors.redAccent, foregroundColor: Colors.white),
                    onPressed: () {
                      if (passCtrl.text == "Boitexinfo") {
                        _isAlertSilenced = true;
                        _isAlertDialogOpen = false;
                        Navigator.of(c).pop();
                      } else {
                        setDialogState(() {
                          errorMessage = _isFrench ? "Mot de passe incorrect !" : "Incorrect Password!";
                        });
                      }
                    },
                    child: Text(
                        _isFrench ? "SILENCIEUX" : "SILENCE ALERT",
                        style: const TextStyle(fontWeight: FontWeight.bold)
                    ),
                  ),
                ],
              );
            }
        );
      },
    ).then((_) {
      _isAlertDialogOpen = false;
    });
  }

  Future<void> _loadStoreProfile() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _storeName = prefs.getString('store_name') ?? "My Store";
      _storeLocation = prefs.getString('store_location') ?? "MAIN BRANCH";
      _storeLogoPath = prefs.getString('store_logo_path');
    });
  }

  Future<void> _checkFtpStatus() async {
    String ip = await FtpService.getLocalIpAddress();
    if (mounted) {
      setState(() {
        _isFtpRunning = FtpService.isRunning;
        _localIp = ip;
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
      setState(() {
        _posDatabase = Map<String, Map<String, dynamic>>.from(jsonDecode(posJson)).map((k, v) => MapEntry(k, Map<String, num>.from(v)));
      });
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
            colorScheme: ColorScheme.dark(primary: _accentCyan, onPrimary: Colors.white, surface: _cardDark, onSurface: Colors.white),
            dialogBackgroundColor: _cardDark,
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

    DateTime start = _selectedDateRange!.start, end = _selectedDateRange!.end;
    if (start.isAtSameMomentAs(end) || end.difference(start).inDays == 0) return "${months[start.month - 1]} ${start.day}, ${start.year}";
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
        builder: (context) {
          return StatefulBuilder(
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
                              colorScheme: ColorScheme.dark(primary: _accentCyan, surface: _bgDark, onSurface: Colors.white),
                            ),
                            child: child!,
                          ),
                        );
                        if (picked != null) {
                          setDialogState(() {
                            if (isStart) startTime = picked;
                            else endTime = picked;
                          });
                        }
                      },
                      child: Container(
                        padding: const EdgeInsets.symmetric(vertical: 20),
                        decoration: BoxDecoration(
                          color: _bgDark,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: Colors.white.withOpacity(0.1)),
                        ),
                        child: Column(
                          children: [
                            Text(label, style: const TextStyle(color: Colors.white54, fontSize: 12, fontWeight: FontWeight.bold, letterSpacing: 1)),
                            const SizedBox(height: 8),
                            Text(
                                "${time.hour.toString().padLeft(2, '0')}:${time.minute.toString().padLeft(2, '0')}",
                                style: const TextStyle(color: Colors.white, fontSize: 24, fontWeight: FontWeight.w900)
                            ),
                          ],
                        ),
                      ),
                    ),
                  );
                }

                return AlertDialog(
                  backgroundColor: _cardDark,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16), side: BorderSide(color: Colors.white.withOpacity(0.05))),
                  title: Row(
                    children: [
                      Icon(Icons.access_time, color: _accentCyan),
                      const SizedBox(width: 12),
                      Text(_isFrench ? "Heures d'Ouverture" : "Operating Hours", style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                    ],
                  ),
                  content: SizedBox(
                    width: 400,
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          _isFrench
                              ? "Filtrez les données au niveau de la minute exacte pour exclure le personnel de nettoyage ou les mouvements en dehors des heures de travail."
                              : "Filter data down to the exact minute to exclude cleaning staff or movements outside of business hours.",
                          style: const TextStyle(color: Colors.white54, fontSize: 14),
                        ),
                        const SizedBox(height: 32),
                        Row(
                          children: [
                            _buildTimeButton(_isFrench ? "OUVERTURE" : "OPENING", startTime, true),
                            const Padding(
                              padding: EdgeInsets.symmetric(horizontal: 16),
                              child: Icon(Icons.arrow_forward_rounded, color: Colors.white38),
                            ),
                            _buildTimeButton(_isFrench ? "FERMETURE" : "CLOSING", endTime, false),
                          ],
                        ),
                      ],
                    ),
                  ),
                  actions: [
                    TextButton(
                      onPressed: () => Navigator.pop(context),
                      child: Text(_isFrench ? "ANNULER" : "CANCEL", style: const TextStyle(color: Colors.white54)),
                    ),
                    ElevatedButton(
                      style: ElevatedButton.styleFrom(backgroundColor: _accentCyan, foregroundColor: Colors.black),
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

                        setState(() {
                          _workingMinuteStart = startMins;
                          _workingMinuteEnd = endMins;
                          _applyFilter();
                        });
                        Navigator.pop(context);
                      },
                      child: Text(_isFrench ? "APPLIQUER" : "APPLY FILTER", style: const TextStyle(fontWeight: FontWeight.bold)),
                    )
                  ],
                );
              }
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
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
            color: isPositive ? Colors.greenAccent.withOpacity(0.15) : Colors.redAccent.withOpacity(0.15),
            borderRadius: BorderRadius.circular(20)
        ),
        child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(isPositive ? Icons.trending_up : Icons.trending_down, size: 14, color: isPositive ? Colors.greenAccent : Colors.redAccent),
              const SizedBox(width: 4),
              Text('${change.abs().toStringAsFixed(1)}%', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: isPositive ? Colors.greenAccent : Colors.redAccent)),
            ]
        )
    );
  }

  void _showEditStoreProfileDialog() {
    TextEditingController nameCtrl = TextEditingController(text: _storeName);
    TextEditingController locCtrl = TextEditingController(text: _storeLocation);
    String? tempLogoPath = _storeLogoPath;

    showDialog(
        context: context,
        builder: (context) {
          return StatefulBuilder(
              builder: (context, setDialogState) {
                return AlertDialog(
                  backgroundColor: _cardDark,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16), side: BorderSide(color: Colors.white.withOpacity(0.05))),
                  title: Text(
                      _isFrench ? 'Paramètres du Profil' : 'Store Profile Settings',
                      style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)
                  ),
                  content: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      GestureDetector(
                        onTap: () async {
                          FilePickerResult? result = await FilePicker.platform.pickFiles(type: FileType.image);
                          if (result != null && result.files.single.path != null) {
                            setDialogState(() => tempLogoPath = result.files.single.path);
                          }
                        },
                        child: Container(
                          width: 80, height: 80,
                          decoration: BoxDecoration(
                            color: _bgDark,
                            shape: BoxShape.circle,
                            border: Border.all(color: _accentCyan, width: 2),
                            image: tempLogoPath != null ? DecorationImage(image: FileImage(File(tempLogoPath!)), fit: BoxFit.cover) : null,
                          ),
                          child: tempLogoPath == null ? Icon(Icons.add_a_photo, color: _accentCyan, size: 30) : null,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(_isFrench ? 'Appuyez pour changer le logo' : 'Tap to change logo', style: const TextStyle(color: Colors.white54, fontSize: 12)),
                      const SizedBox(height: 24),

                      TextField(
                        controller: nameCtrl,
                        style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                        decoration: InputDecoration(
                          labelText: _isFrench ? 'Nom du Magasin / Marque' : 'Store / Brand Name',
                          labelStyle: const TextStyle(color: Colors.white54),
                          filled: true, fillColor: _bgDark,
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide.none),
                          prefixIcon: Icon(Icons.storefront, color: _accentCyan),
                        ),
                      ),
                      const SizedBox(height: 12),

                      TextField(
                        controller: locCtrl,
                        style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                        decoration: InputDecoration(
                          labelText: _isFrench ? 'Emplacement (ex: Ville)' : 'Location (e.g. City)',
                          labelStyle: const TextStyle(color: Colors.white54),
                          filled: true, fillColor: _bgDark,
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide.none),
                          prefixIcon: Icon(Icons.location_on, color: _accentMagenta),
                        ),
                      ),
                    ],
                  ),
                  actions: [
                    TextButton(
                        onPressed: () => Navigator.pop(context),
                        child: Text(_isFrench ? 'ANNULER' : 'CANCEL', style: const TextStyle(color: Colors.white54))
                    ),
                    ElevatedButton(
                      style: ElevatedButton.styleFrom(backgroundColor: _accentCyan, foregroundColor: Colors.black),
                      onPressed: () async {
                        final prefs = await SharedPreferences.getInstance();
                        await prefs.setString('store_name', nameCtrl.text);
                        await prefs.setString('store_location', locCtrl.text);
                        if (tempLogoPath != null) await prefs.setString('store_logo_path', tempLogoPath!);

                        setState(() {
                          _storeName = nameCtrl.text;
                          _storeLocation = locCtrl.text;
                          _storeLogoPath = tempLogoPath;
                        });
                        Navigator.pop(context);
                      },
                      child: Text(_isFrench ? 'ENREGISTRER' : 'SAVE SETTINGS', style: const TextStyle(fontWeight: FontWeight.bold)),
                    ),
                  ],
                );
              }
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
        builder: (context) => AlertDialog(
          backgroundColor: _cardDark, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16), side: BorderSide(color: Colors.white.withOpacity(0.05))),
          title: Column(children: [
            const Icon(Icons.point_of_sale, color: Colors.greenAccent, size: 40),
            const SizedBox(height: 8),
            Text(_isFrench ? 'SAISIR LES DONNÉES DE CAISSE' : 'ENTER DAILY POS DATA', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16)),
            Text('${_isFrench ? "Date : " : "Date: "}${_getFormattedDateString()}', style: const TextStyle(color: Colors.white54, fontSize: 12))
          ]),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(controller: caCtrl, style: const TextStyle(color: Colors.white), keyboardType: const TextInputType.numberWithOptions(decimal: true), decoration: InputDecoration(labelText: _isFrench ? 'Chiffre d\'Affaires (DZD)' : 'Revenue (DZD)', labelStyle: const TextStyle(color: Colors.white54), filled: true, fillColor: _bgDark, border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide.none), prefixIcon: const Icon(Icons.payments, color: Colors.greenAccent))),
              const SizedBox(height: 12),
              TextField(controller: clientCtrl, style: const TextStyle(color: Colors.white), keyboardType: TextInputType.number, decoration: InputDecoration(labelText: _isFrench ? 'Total Clients' : 'Total Clients', labelStyle: const TextStyle(color: Colors.white54), filled: true, fillColor: _bgDark, border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide.none), prefixIcon: Icon(Icons.receipt_long, color: _accentCyan))),
              const SizedBox(height: 12),
              TextField(controller: articleCtrl, style: const TextStyle(color: Colors.white), keyboardType: TextInputType.number, decoration: InputDecoration(labelText: _isFrench ? 'Articles Vendus' : 'Articles Sold', labelStyle: const TextStyle(color: Colors.white54), filled: true, fillColor: _bgDark, border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide.none), prefixIcon: Icon(Icons.shopping_bag, color: _accentMagenta))),
            ],
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(context),
                child: Text(_isFrench ? 'ANNULER' : 'CANCEL', style: const TextStyle(color: Colors.white54))
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: Colors.greenAccent, foregroundColor: Colors.black),
              onPressed: () {
                _savePosData(dateStr, double.tryParse(caCtrl.text) ?? 0.0, int.tryParse(clientCtrl.text) ?? 0, int.tryParse(articleCtrl.text) ?? 0);
                Navigator.pop(context);
              },
              child: Text(_isFrench ? 'ENREGISTRER' : 'SAVE DATA', style: const TextStyle(fontWeight: FontWeight.bold)),
            ),
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
          posDatabase: _posDatabase, // 🚀 NEW: Pass the POS data!
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
          color: _cardDark,
          borderRadius: BorderRadius.circular(30),
          border: Border.all(color: Colors.white.withOpacity(0.1), width: 1),
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
                  color: _bgDark,
                  borderRadius: BorderRadius.circular(20),
                  boxShadow: [
                    BoxShadow(color: Colors.black.withOpacity(0.3), blurRadius: 4, offset: const Offset(0, 2)),
                  ],
                ),
              ),
            ),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                Expanded(
                  child: Center(
                    child: AnimatedDefaultTextStyle(
                      duration: const Duration(milliseconds: 200),
                      style: TextStyle(
                        fontWeight: FontWeight.w800, fontSize: 14, letterSpacing: 1,
                        color: !_isFrench ? _accentCyan : Colors.white38,
                      ),
                      child: const Text('EN'),
                    ),
                  ),
                ),
                Expanded(
                  child: Center(
                    child: AnimatedDefaultTextStyle(
                      duration: const Duration(milliseconds: 200),
                      style: TextStyle(
                        fontWeight: FontWeight.w800, fontSize: 14, letterSpacing: 1,
                        color: _isFrench ? _accentCyan : Colors.white38,
                      ),
                      child: const Text('FR'),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  // 🚀 MODIFIED: Embeds the custom CameraStreamWidget instead of failing silently
  Widget _buildLiveFeedSection() {
    if (_selectedCamera == 'All Doors') return const SizedBox.shrink();

    String? ip = _cameraIps[_selectedCamera];
    bool hasIp = ip != null && ip.isNotEmpty;

    return Container(
      margin: const EdgeInsets.only(top: 32),
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: _cardDark,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: _accentCyan.withOpacity(0.3), width: 1.5),
        boxShadow: [
          BoxShadow(color: _accentCyan.withOpacity(0.05), blurRadius: 20)
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  Icon(Icons.fiber_manual_record, color: hasIp ? Colors.redAccent : Colors.grey, size: 16),
                  const SizedBox(width: 8),
                  Text(
                      hasIp ? 'LIVE PREVIEW - ${_selectedCamera.toUpperCase()}' : 'NO IP CONFIGURED FOR ${_selectedCamera.toUpperCase()}',
                      style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold, letterSpacing: 1.5)
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
          const SizedBox(height: 16),

          if (!hasIp)
            Center(
              child: Padding(
                padding: const EdgeInsets.all(32.0),
                child: Column(
                  children: [
                    const Icon(Icons.videocam_off, color: Colors.white24, size: 48),
                    const SizedBox(height: 16),
                    Text('No IP assigned to $_selectedCamera.', style: const TextStyle(color: Colors.white54)),
                    const SizedBox(height: 24),
                    ElevatedButton.icon(
                      style: ElevatedButton.styleFrom(
                          backgroundColor: _accentCyan,
                          foregroundColor: Colors.black,
                          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12)
                      ),
                      onPressed: () => _showLinkIpDialog(_selectedCamera),
                      icon: const Icon(Icons.link),
                      label: const Text('LINK CAMERA IP', style: TextStyle(fontWeight: FontWeight.bold)),
                    )
                  ],
                ),
              ),
            )
          else
            ClipRRect(
              borderRadius: BorderRadius.circular(16),
              child: Container(
                width: double.infinity,
                height: 360,
                color: Colors.black,
                // 🚀 Uses our new bulletproof custom engine
                child: CameraStreamWidget(ipAddress: ip),
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
      backgroundColor: _bgDark,
      body: Row(
        children: [
          if (isDesktop) _buildSidebar(),

          Expanded(
            child: Column(
              children: [
                _buildTopAppBar(),

                if (_isIpMismatch)
                  Container(
                    width: double.infinity,
                    color: Colors.red[700],
                    padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 24),
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
                            style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16),
                          ),
                        ),
                        ElevatedButton(
                          style: ElevatedButton.styleFrom(backgroundColor: Colors.white, foregroundColor: Colors.red[700]),
                          onPressed: () {
                            Navigator.push(context, MaterialPageRoute(builder: (context) => const FtpServerScreen()));
                          },
                          child: Text(_isFrench ? "RÉPARER" : "FIX NETWORK", style: const TextStyle(fontWeight: FontWeight.bold)),
                        )
                      ],
                    ),
                  ),

                Expanded(
                  child: _isLoading
                      ? Center(child: CircularProgressIndicator(color: _accentCyan))
                      : SingleChildScrollView(
                    padding: const EdgeInsets.all(32.0),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _buildPageHeader(),
                        const SizedBox(height: 24),

                        if (_rawData.isEmpty)
                          _buildEmptyState()
                        else ...[
                          _buildSmartInsights(),
                          const SizedBox(height: 24),
                          _buildHeroChart(),
                          const SizedBox(height: 32),
                          _buildZoneSelector(),
                          const SizedBox(height: 32),

                          _buildLiveFeedSection(),

                          const SizedBox(height: 32),
                          _buildBentoGrid(isDesktop),
                          const SizedBox(height: 40),
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
    );
  }

  Widget _buildSidebar() {
    return Container(
      width: 260,
      color: _cardDark,
      child: Column(
        children: [
          const SizedBox(height: 40),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.analytics, color: _accentCyan, size: 32),
              const SizedBox(width: 12),
              Text(_isFrench ? 'Analytique' : 'Analytics', style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w900, color: Colors.white, letterSpacing: -0.5)),
            ],
          ),
          const SizedBox(height: 60),

          _buildSidebarItem(Icons.dashboard, _isFrench ? 'Tableau de bord' : 'Dashboard', isActive: true),
          _buildSidebarItem(Icons.source, _isFrench ? 'Source de données' : 'Data Source', onTap: _pickFolderAndLoadData),
          _buildSidebarItem(Icons.videocam, _isFrench ? 'Config. Caméras' : 'Camera Setup', onTap: () {
            Navigator.push(
                context,
                MaterialPageRoute(builder: (context) => const CameraFtpSetupScreen())
            ).then((_) {
              _loadCameraIps();
              if (mounted) setState(() {});
            });
          }),

          _buildSidebarItem(
              Icons.wifi_tethering,
              _isFrench ? 'Serveur FTP' : 'FTP Server',
              iconColor: _isIpMismatch ? Colors.redAccent : null,
              textColor: _isIpMismatch ? Colors.redAccent : null,
              onTap: () async {
                await Navigator.push(context, MaterialPageRoute(builder: (context) => const FtpServerScreen()));
                _checkFtpStatus();
              }
          ),

          _buildSidebarItem(Icons.cloud_upload, _isFrench ? 'Synchronisation Cloud' : 'Cloud Sync (B2)', onTap: () {
            Navigator.push(context, MaterialPageRoute(builder: (context) => const CloudSyncScreen()));
          }),

          _buildSidebarItem(Icons.point_of_sale, _isFrench ? 'Saisie de Caisse' : 'POS Entry', onTap: _rawData.isNotEmpty ? _showPosEntryDialog : null),
          _buildSidebarItem(Icons.download, _isFrench ? 'Exporter Rapports' : 'Export Reports', onTap: _rawData.isNotEmpty ? _showExportMenu : null),

          const Spacer(),
          if (_isFtpRunning && !_isIpMismatch)
            Container(
              margin: const EdgeInsets.all(24),
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(color: Colors.greenAccent.withOpacity(0.1), borderRadius: BorderRadius.circular(12), border: Border.all(color: Colors.greenAccent.withOpacity(0.3))),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(children: [Icon(Icons.circle, color: Colors.greenAccent, size: 12), const SizedBox(width: 8), Text(_isFrench ? 'FTP Actif' : 'FTP Active', style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.white))]),
                  const SizedBox(height: 8),
                  Text('ftp://$_localIp:21', style: const TextStyle(fontSize: 12, color: Colors.white70)),
                ],
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildSidebarItem(IconData icon, String title, {bool isActive = false, Color? iconColor, Color? textColor, VoidCallback? onTap}) {
    return ListTile(
      leading: Icon(icon, color: iconColor ?? (isActive ? _accentCyan : Colors.white54)),
      title: Text(title, style: TextStyle(color: textColor ?? (isActive ? _accentCyan : Colors.white54), fontWeight: isActive ? FontWeight.bold : FontWeight.normal, fontSize: 16)),
      contentPadding: const EdgeInsets.symmetric(horizontal: 32, vertical: 8),
      onTap: onTap,
    );
  }

  Widget _buildTopAppBar() {
    return Container(
      height: 90,
      padding: const EdgeInsets.symmetric(horizontal: 32),
      decoration: BoxDecoration(
        color: _bgDark,
        border: Border(bottom: BorderSide(color: Colors.white.withOpacity(0.05))),
      ),
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
                  Text("$dayName, ${_isFrench ? "${now.day} $monthName" : "$monthName ${now.day}"}", style: const TextStyle(color: Colors.white54, fontSize: 14, fontWeight: FontWeight.w600, letterSpacing: 0.5)),
                  const SizedBox(height: 2),
                  Text("$hour:$minute", style: const TextStyle(color: Colors.white, fontSize: 24, fontWeight: FontWeight.w900, letterSpacing: 1)),
                ],
              );
            },
          ),

          const Spacer(),

          _buildLanguageToggle(),
          const SizedBox(width: 32),

          InkWell(
            onTap: _showEditStoreProfileDialog,
            borderRadius: BorderRadius.circular(8),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              child: Row(
                children: [
                  Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text(_storeLocation.toUpperCase(), style: const TextStyle(color: Colors.white38, fontSize: 12, fontWeight: FontWeight.bold, letterSpacing: 1.5)),
                      Text(_storeName, style: const TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.bold)),
                    ],
                  ),
                  const SizedBox(width: 20),
                  Container(
                    width: 60, height: 60,
                    decoration: BoxDecoration(
                      color: _cardDark,
                      shape: BoxShape.circle,
                      border: Border.all(color: Colors.white.withOpacity(0.1), width: 1),
                      image: _storeLogoPath != null ? DecorationImage(image: FileImage(File(_storeLogoPath!)), fit: BoxFit.cover) : null,
                    ),
                    child: _storeLogoPath == null ? Icon(Icons.storefront, color: _accentCyan, size: 28) : null,
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPageHeader() {
    bool isFilterActive = _workingMinuteStart > 0 || _workingMinuteEnd < 1439;

    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
                _isFrench ? 'Vue d\'Ensemble' : 'Command Center',
                style: const TextStyle(fontSize: 36, fontWeight: FontWeight.w900, color: Colors.white, letterSpacing: -1)
            ),
            if (_selectedFolderPath != null)
              Padding(
                padding: const EdgeInsets.only(top: 4.0),
                child: Text('Source: $_selectedFolderPath', style: const TextStyle(color: Colors.white38, fontSize: 14)),
              ),
          ],
        ),

        Row(
          children: [
            if (_rawData.isNotEmpty) ...[
              FilterChip(
                selected: _isCompareMode,
                onSelected: (val) {
                  setState(() {
                    _isCompareMode = val;
                    _applyFilter();
                  });
                },
                label: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  child: Text(_isFrench ? 'Comparer au Précédent' : 'Compare vs Previous', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: _isCompareMode ? Colors.black : Colors.white70)),
                ),
                selectedColor: _accentCyan,
                checkmarkColor: Colors.black,
                backgroundColor: _cardDark,
                shape: StadiumBorder(side: BorderSide(color: _isCompareMode ? _accentCyan : Colors.white.withOpacity(0.1), width: 1.5)),
              ),
              const SizedBox(width: 16),
            ],

            Container(
              decoration: BoxDecoration(color: _cardDark, borderRadius: BorderRadius.circular(8), border: Border.all(color: Colors.white.withOpacity(0.1), width: 1.5)),
              padding: const EdgeInsets.all(4),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  IconButton(icon: const Icon(Icons.chevron_left, color: Colors.white54), onPressed: () => _shiftDate(-1)),
                  GestureDetector(
                    onTap: _pickDateRange,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      child: Text(_getFormattedDateString(), style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.white, fontSize: 16)),
                    ),
                  ),
                  IconButton(icon: const Icon(Icons.chevron_right, color: Colors.white54), onPressed: () => _shiftDate(1)),
                ],
              ),
            ),
            const SizedBox(width: 16),

            Container(
              decoration: BoxDecoration(
                  color: isFilterActive ? _accentCyan.withOpacity(0.1) : _cardDark,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: isFilterActive ? _accentCyan : Colors.white.withOpacity(0.1), width: 1.5)
              ),
              child: IconButton(
                icon: Icon(Icons.access_time_filled, color: isFilterActive ? _accentCyan : Colors.white54),
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
        padding: const EdgeInsets.only(top: 100),
        child: Column(
          children: [
            Icon(Icons.folder_open, size: 100, color: Colors.white.withOpacity(0.1)),
            const SizedBox(height: 24),
            Text(_isFrench ? 'Aucune Donnée Sélectionnée' : 'No Data Selected', style: const TextStyle(fontSize: 28, fontWeight: FontWeight.bold, color: Colors.white)),
            const SizedBox(height: 12),
            Text(
                _isFrench
                    ? 'Veuillez sélectionner une source de données ou démarrer le serveur FTP.'
                    : 'Please select a data source or start the FTP server from the menu.',
                style: const TextStyle(color: Colors.white54, fontSize: 16)
            ),
            const SizedBox(height: 32),
            ElevatedButton.icon(
              style: ElevatedButton.styleFrom(backgroundColor: _accentCyan, foregroundColor: Colors.black, padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 20)),
              onPressed: _pickFolderAndLoadData,
              icon: const Icon(Icons.drive_folder_upload, size: 24),
              label: Text(_isFrench ? 'IMPORTER DES DONNÉES' : 'IMPORT DATA', style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
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
        ? "Surveillance en temps réel. Les visiteurs d'aujourd'hui sont à $totalVisitors avec un pic à $_peakHour."
        : "Real-time monitoring. Today's visitor count is $totalVisitors, peaking at $_peakHour.";

    if (isFilterActive) {
      insightText += _isFrench ? " (Filtré: $startStr - $endStr)" : " (Filtered: $startStr - $endStr)";
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
      decoration: BoxDecoration(
        gradient: LinearGradient(colors: [_cardDark, _cardDark.withOpacity(0.5)]),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: _accentCyan.withOpacity(0.3), width: 1),
        boxShadow: [BoxShadow(color: _accentCyan.withOpacity(0.05), blurRadius: 20)],
      ),
      child: Row(
        children: [
          Icon(Icons.auto_awesome, color: _accentCyan, size: 24),
          const SizedBox(width: 16),
          Expanded(child: Text(insightText, style: const TextStyle(color: Colors.white70, fontSize: 15, fontWeight: FontWeight.w500))),
        ],
      ),
    );
  }

  Widget _buildHeroChart() {
    int totalVisitors = (_totalIn + _totalOut) ~/ 2;
    List<LineChartBarData> chartLines = [];

    bool showPerDoor = _selectedCamera == 'All Doors' && _availableCameras.length > 2 && !_isCompareMode;

    List<Color> doorColors = [
      Colors.blueAccent, Colors.redAccent, Colors.greenAccent,
      Colors.orangeAccent, Colors.purpleAccent, Colors.tealAccent,
      Colors.pinkAccent, Colors.yellowAccent
    ];
    List<String> plottedDoors = _perDoorData.keys.toList();

    if (showPerDoor) {
      int colorIndex = 0;
      for (String door in plottedDoors) {
        List<FlSpot> spots = [];
        Color doorColor = doorColors[colorIndex % doorColors.length];

        for (int i = 0; i < _displayedData.length; i++) {
          String expectedTime = _displayedData[i].time;
          String expectedDate = _displayedData[i].date;
          var match = _perDoorData[door]!.where((d) => d.time == expectedTime && d.date == expectedDate).toList();
          double total = 0;
          if (match.isNotEmpty) {
            total = ((match.first.inCount + match.first.outCount) / 2).toDouble();
          }
          spots.add(FlSpot(i.toDouble(), total));
        }

        chartLines.add(LineChartBarData(
          spots: spots,
          isCurved: true, color: doorColor, barWidth: 3, isStrokeCapRound: true, dotData: const FlDotData(show: false),
        ));
        colorIndex++;
      }
    } else if (_isCompareMode) {
      chartLines.add(LineChartBarData(
        spots: _displayedData.asMap().entries.map((e) => FlSpot(e.key.toDouble(), ((e.value.inCount + e.value.outCount) / 2).toDouble())).toList(),
        isCurved: true, color: _accentCyan, barWidth: 4, isStrokeCapRound: true, dotData: const FlDotData(show: false),
        belowBarData: BarAreaData(show: true, gradient: LinearGradient(colors: [_accentCyan.withOpacity(0.3), Colors.transparent], begin: Alignment.topCenter, end: Alignment.bottomCenter)),
      ));
      chartLines.add(LineChartBarData(
        spots: _compareDisplayedData.asMap().entries.map((e) => FlSpot(e.key.toDouble(), ((e.value.inCount + e.value.outCount) / 2).toDouble())).toList(),
        isCurved: true, color: _accentGrey, barWidth: 3, dashArray: [5, 5], isStrokeCapRound: true, dotData: const FlDotData(show: false),
      ));
    } else {
      chartLines.add(LineChartBarData(
        spots: _displayedData.asMap().entries.map((e) => FlSpot(e.key.toDouble(), e.value.inCount.toDouble())).toList(),
        isCurved: true, color: _accentCyan, barWidth: 4, isStrokeCapRound: true, dotData: const FlDotData(show: false),
        belowBarData: BarAreaData(show: true, gradient: LinearGradient(colors: [_accentCyan.withOpacity(0.3), Colors.transparent], begin: Alignment.topCenter, end: Alignment.bottomCenter)),
      ));
      chartLines.add(LineChartBarData(
        spots: _displayedData.asMap().entries.map((e) => FlSpot(e.key.toDouble(), e.value.outCount.toDouble())).toList(),
        isCurved: true, color: _accentMagenta, barWidth: 4, isStrokeCapRound: true, dotData: const FlDotData(show: false),
        belowBarData: BarAreaData(show: true, gradient: LinearGradient(colors: [_accentMagenta.withOpacity(0.3), Colors.transparent], begin: Alignment.topCenter, end: Alignment.bottomCenter)),
      ));
    }

    return Container(
      padding: const EdgeInsets.all(32),
      decoration: BoxDecoration(
        color: _cardDark,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: Colors.white.withOpacity(0.05)),
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.3), blurRadius: 30, offset: const Offset(0, 10))],
      ),
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
                  Text(_isFrench ? 'TOTAL VISITEURS' : 'TOTAL VISITORS', style: const TextStyle(color: Colors.white54, fontSize: 14, fontWeight: FontWeight.bold, letterSpacing: 1.5)),
                  const SizedBox(height: 8),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      Text(totalVisitors.toString(), style: const TextStyle(color: Colors.white, fontSize: 56, fontWeight: FontWeight.w900, letterSpacing: -2)),
                      const SizedBox(width: 16),
                      _buildTrendBadge(totalVisitors, _compareTotalVisitors),
                    ],
                  )
                ],
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                        decoration: BoxDecoration(color: _bgDark, borderRadius: BorderRadius.circular(8)),
                        child: DropdownButtonHideUnderline(
                          child: DropdownButton<ChartFilter>(
                            dropdownColor: _cardDark,
                            value: _currentFilter, icon: const Icon(Icons.keyboard_arrow_down, color: Colors.white54), style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 14),
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
                  const SizedBox(height: 16),

                  if (showPerDoor) ...[
                    ...plottedDoors.asMap().entries.map((entry) {
                      Color dColor = doorColors[entry.key % doorColors.length];
                      return Padding(
                        padding: const EdgeInsets.only(bottom: 4.0),
                        child: Row(children: [Icon(Icons.circle, size: 10, color: dColor), const SizedBox(width: 8), Text("${entry.value.toUpperCase()} Total", style: const TextStyle(color: Colors.white70, fontSize: 14, fontWeight: FontWeight.w600))]),
                      );
                    }).toList(),
                  ] else if (_isCompareMode) ...[
                    Row(children: [Icon(Icons.circle, size: 10, color: _accentCyan), const SizedBox(width: 8), Text(_isFrench ? 'Actuel' : 'Current', style: const TextStyle(color: Colors.white70, fontSize: 14, fontWeight: FontWeight.w600))]),
                    const SizedBox(height: 4),
                    Row(children: [Icon(Icons.circle, size: 10, color: _accentGrey), const SizedBox(width: 8), Text(_isFrench ? 'Précédent' : 'Previous', style: const TextStyle(color: Colors.white70, fontSize: 14, fontWeight: FontWeight.w600))]),
                  ] else ...[
                    Row(children: [Icon(Icons.login, color: _accentCyan, size: 16), const SizedBox(width: 8), Text('${_isFrench ? "Entrées" : "In"}: $_totalIn', style: const TextStyle(color: Colors.white70, fontSize: 16, fontWeight: FontWeight.w600))]),
                    const SizedBox(height: 4),
                    Row(children: [Icon(Icons.logout, color: _accentMagenta, size: 16), const SizedBox(width: 8), Text('${_isFrench ? "Sorties" : "Out"}: $_totalOut', style: const TextStyle(color: Colors.white70, fontSize: 16, fontWeight: FontWeight.w600))]),
                  ]
                ],
              )
            ],
          ),
          const SizedBox(height: 40),

          SizedBox(
            height: 350,
            child: LineChart(
              LineChartData(
                lineTouchData: LineTouchData(
                  touchTooltipData: LineTouchTooltipData(
                    tooltipBgColor: _bgDark,
                    getTooltipItems: (touchedSpots) {
                      return touchedSpots.map((LineBarSpot touchedSpot) {
                        final textStyle = TextStyle(color: touchedSpot.bar.color ?? Colors.white, fontWeight: FontWeight.bold, fontSize: 14);

                        String timeText = "";
                        if (_displayedData.length > touchedSpot.x.toInt()) {
                          if (_currentFilter == ChartFilter.daily) {
                            String dateStr = _displayedData[touchedSpot.x.toInt()].date;
                            List<String> parts = dateStr.split('/');
                            if (parts.length == 3) {
                              DateTime dt = DateTime(int.parse(parts[2]), int.parse(parts[1]), int.parse(parts[0]));
                              List<String> daysEn = ['Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday', 'Sunday'];
                              List<String> daysFr = ['Lundi', 'Mardi', 'Mercredi', 'Jeudi', 'Vendredi', 'Samedi', 'Dimanche'];
                              String dayName = _isFrench ? daysFr[dt.weekday - 1] : daysEn[dt.weekday - 1];
                              timeText = "$dayName, $dateStr";
                            } else {
                              timeText = dateStr;
                            }
                          } else {
                            timeText = _displayedData[touchedSpot.x.toInt()].time;
                          }
                        }

                        String type = "";
                        if (showPerDoor) {
                          if (touchedSpot.barIndex < plottedDoors.length) {
                            type = "${plottedDoors[touchedSpot.barIndex].toUpperCase()} Total: ";
                          }
                        } else if (_isCompareMode) {
                          type = touchedSpot.barIndex == 0 ? (_isFrench ? "Actuel: " : "Current: ") : (_isFrench ? "Précédent: " : "Previous: ");
                        } else {
                          type = touchedSpot.barIndex == 0 ? (_isFrench ? "Entrées: " : "In: ") : (_isFrench ? "Sorties: " : "Out: ");
                        }

                        return LineTooltipItem("$timeText\n$type${touchedSpot.y.toInt()}", textStyle);
                      }).toList();
                    },
                  ),
                ),
                gridData: const FlGridData(show: false),
                titlesData: FlTitlesData(
                  rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                  topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                  leftTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                  bottomTitles: AxisTitles(
                    sideTitles: SideTitles(
                      showTitles: true,
                      reservedSize: 46,
                      interval: 1,
                      getTitlesWidget: (value, meta) {
                        int index = value.toInt();
                        if (index >= 0 && index < _displayedData.length) {

                          String displayText = "";

                          if (_currentFilter == ChartFilter.hourly) {
                            int step = _displayedData.length > 16 ? 3 : (_displayedData.length > 10 ? 2 : 1);
                            if (index % step != 0 && index != _displayedData.length - 1) {
                              return const SizedBox.shrink();
                            }
                            String rawTime = _displayedData[index].time;
                            displayText = "${rawTime.split(':')[0]}h";

                          } else {
                            String dateStr = _displayedData[index].date;
                            List<String> parts = dateStr.split('/');
                            if (parts.length == 3) {
                              DateTime dt = DateTime(int.parse(parts[2]), int.parse(parts[1]), int.parse(parts[0]));
                              List<String> shortDaysEn = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
                              List<String> shortDaysFr = ['Lun', 'Mar', 'Mer', 'Jeu', 'Ven', 'Sam', 'Dim'];
                              String shortDay = _isFrench ? shortDaysFr[dt.weekday - 1] : shortDaysEn[dt.weekday - 1];
                              String shortDate = dateStr.substring(0, 5);
                              displayText = "$shortDay\n$shortDate";
                            } else {
                              displayText = dateStr.substring(0, 5);
                            }
                          }

                          return Padding(
                              padding: const EdgeInsets.only(top: 8.0),
                              child: Text(
                                  displayText,
                                  textAlign: TextAlign.center,
                                  style: const TextStyle(color: Colors.white70, fontSize: 11, fontWeight: FontWeight.bold)
                              )
                          );
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
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(_isFrench ? 'ZONES ET PORTES' : 'ZONES & DOORS', style: const TextStyle(color: Colors.white54, fontSize: 14, fontWeight: FontWeight.bold, letterSpacing: 1.5)),
        const SizedBox(height: 16),
        SizedBox(
          height: 110,
          child: ListView.builder(
            scrollDirection: Axis.horizontal,
            itemCount: _availableCameras.length,
            itemBuilder: (context, index) {
              String cameraName = _availableCameras[index];
              bool isSelected = _selectedCamera == cameraName;
              String displayName = cameraName == 'All Doors' ? (_isFrench ? 'Toutes les Portes' : 'All Doors') : cameraName.toUpperCase();

              return GestureDetector(
                onTap: () => setState(() { _selectedCamera = cameraName; _applyFilter(); }),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 300),
                  margin: const EdgeInsets.only(right: 16),
                  width: 220,
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    color: isSelected ? _accentCyan.withOpacity(0.1) : _cardDark,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: isSelected ? _accentCyan : Colors.white.withOpacity(0.05), width: 2),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(displayName, style: TextStyle(color: isSelected ? Colors.white : Colors.white70, fontWeight: FontWeight.bold, fontSize: 16), maxLines: 1, overflow: TextOverflow.ellipsis),
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          Container(width: 8, height: 8, decoration: BoxDecoration(color: isSelected ? _accentCyan : Colors.white38, shape: BoxShape.circle)),
                          const SizedBox(width: 8),
                          Text(isSelected ? (_isFrench ? 'Sélectionné' : 'Selected') : (_isFrench ? 'Cliquez pour filtrer' : 'Tap to filter'), style: TextStyle(color: isSelected ? _accentCyan : Colors.white38, fontSize: 12, fontWeight: FontWeight.bold)),
                        ],
                      )
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
    int totalVisitors = (_totalIn + _totalOut) ~/ 2;
    double conversionRate = totalVisitors > 0 ? (_currentClients / totalVisitors) * 100 : 0.0;
    double avgBasket = _currentClients > 0 ? (_currentCa / _currentClients) : 0.0;
    double upt = _currentClients > 0 ? (_currentArticles / _currentClients) : 0.0;

    double compareConv = _compareTotalVisitors > 0 ? (_compareClients / _compareTotalVisitors) * 100 : 0.0;
    double compareBasket = _compareClients > 0 ? (_compareCa / _compareClients) : 0.0;
    double compareUpt = _compareClients > 0 ? (_compareArticles / _compareClients) : 0.0;

    List<Widget> gridItems = [
      _buildBentoCard(
          title: _isFrench ? 'Chiffre d\'Affaires (CA)' : 'Revenue (CA)',
          value: '${_currentCa.toStringAsFixed(0)} DZD',
          icon: Icons.payments,
          color: Colors.greenAccent,
          height: 200,
          trendWidget: _buildTrendBadge(_currentCa, _compareCa)
      ),
      _buildBentoCard(
          title: _isFrench ? 'Taux de Conv.' : 'Conv. Rate',
          value: '${conversionRate.toStringAsFixed(1)}%',
          icon: Icons.track_changes,
          color: Colors.orangeAccent,
          height: 200,
          trendWidget: _buildTrendBadge(conversionRate, compareConv)
      ),
      _buildBentoCard(
          title: _isFrench ? 'Panier Moyen' : 'Avg Basket',
          value: '${avgBasket.toStringAsFixed(0)} DZD',
          icon: Icons.shopping_cart,
          color: Colors.indigoAccent,
          height: 200,
          trendWidget: _buildTrendBadge(avgBasket, compareBasket)
      ),
      _buildBentoCard(
          title: _isFrench ? 'I.D.V' : 'U.P.T',
          value: upt.toStringAsFixed(2),
          icon: Icons.layers,
          color: Colors.purpleAccent,
          height: 200,
          trendWidget: _buildTrendBadge(upt, compareUpt)
      ),
    ];

    if (isDesktop) {
      return Row(
        children: [
          Expanded(flex: 2, child: gridItems[0]), const SizedBox(width: 24),
          Expanded(flex: 1, child: gridItems[1]), const SizedBox(width: 24),
          Expanded(flex: 1, child: gridItems[2]), const SizedBox(width: 24),
          Expanded(flex: 1, child: gridItems[3]),
        ],
      );
    } else {
      return Column(
        children: [
          gridItems[0], const SizedBox(height: 16),
          Row(children: [Expanded(child: gridItems[1]), const SizedBox(width: 16), Expanded(child: gridItems[2])]), const SizedBox(height: 16),
          gridItems[3],
        ],
      );
    }
  }

  Widget _buildBentoCard({required String title, required String value, required IconData icon, required Color color, required double height, Widget? trendWidget}) {
    return Container(
      height: height,
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: _cardDark,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: Colors.white.withOpacity(0.05)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(color: color.withOpacity(0.1), shape: BoxShape.circle),
                child: Icon(icon, color: color, size: 28),
              ),
              if (trendWidget != null) trendWidget,
            ],
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: const TextStyle(fontSize: 16, color: Colors.white54, fontWeight: FontWeight.w600)),
              const SizedBox(height: 8),
              Text(value, style: const TextStyle(fontSize: 32, fontWeight: FontWeight.w800, color: Colors.white, letterSpacing: -0.5)),
            ],
          ),
        ],
      ),
    );
  }
}

// =========================================================================
// 🚀 THE NEW CUSTOM IP CAMERA STREAM ENGINE
// =========================================================================
class CameraStreamWidget extends StatefulWidget {
  final String ipAddress;
  const CameraStreamWidget({Key? key, required this.ipAddress}) : super(key: key);

  @override
  State<CameraStreamWidget> createState() => _CameraStreamWidgetState();
}

class _CameraStreamWidgetState extends State<CameraStreamWidget> {
  Timer? _timer;
  Uint8List? _lastFrame;
  String _status = "Initializing...";
  bool _isError = false;
  bool _isDisposed = false;

  @override
  void initState() {
    super.initState();
    _fetchFrame();
    // Safely polls the camera without causing loading overlap
    _timer = Timer.periodic(const Duration(milliseconds: 1500), (_) {
      if (!_isDisposed) _fetchFrame();
    });
  }

  @override
  void didUpdateWidget(covariant CameraStreamWidget oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Restart if user changes the IP via the dialog
    if (oldWidget.ipAddress != widget.ipAddress) {
      _lastFrame = null;
      _isError = false;
      _status = "Reconnecting...";
      _fetchFrame();
    }
  }

  @override
  void dispose() {
    _isDisposed = true;
    _timer?.cancel();
    super.dispose();
  }

  Future<void> _fetchFrame() async {
    if (_isDisposed) return;

    // Remove any trailing slashes the user might have accidentally typed
    String cleanIp = widget.ipAddress.trim().replaceAll(RegExp(r'/$'), '');
    String targetUrl;

    if (cleanIp.contains('/api/getpreview')) {
      // 🚀 Smart Fix: If you pasted the FULL url, we just update the timestamp
      targetUrl = cleanIp.startsWith('http') ? cleanIp : 'http://$cleanIp';
      if (targetUrl.contains(RegExp(r'&\d+$'))) {
        targetUrl = targetUrl.replaceAll(RegExp(r'&\d+$'), '&${DateTime.now().millisecondsSinceEpoch}');
      } else {
        targetUrl = "$targetUrl&${DateTime.now().millisecondsSinceEpoch}";
      }
    } else {
      // 🚀 Just the IP: we build the correct path
      String baseUrl = cleanIp.startsWith('http') ? cleanIp : 'http://$cleanIp';
      targetUrl = "$baseUrl/api/getpreview/?w=320&h=240&${DateTime.now().millisecondsSinceEpoch}";
    }

    try {
      HttpClient client = HttpClient();
      client.connectionTimeout = const Duration(seconds: 2);
      client.badCertificateCallback = (cert, host, port) => true; // Bypass local network SSL issues

      final request = await client.getUrl(Uri.parse(targetUrl));
      // Fake a Windows browser so the camera doesn't reject us
      request.headers.set(HttpHeaders.userAgentHeader, 'Mozilla/5.0 (Windows NT 10.0; Win64; x64)');
      request.headers.set(HttpHeaders.acceptHeader, 'image/jpeg,image/png,*/*');

      final response = await request.close().timeout(const Duration(seconds: 3));

      if (response.statusCode == 200) {
        final bytes = await consolidateHttpClientResponseBytes(response);
        if (!_isDisposed && bytes.isNotEmpty) {
          setState(() {
            _lastFrame = bytes;
            _isError = false;
            _status = "Connected";
          });
        }
      } else {
        if (!_isDisposed) {
          setState(() {
            _isError = true;
            _status = "Camera HTTP Error: ${response.statusCode}";
          });
        }
      }
    } catch (e) {
      if (!_isDisposed) {
        setState(() {
          _isError = true;
          String err = e.toString();
          if (err.contains("Timeout")) {
            _status = "Connection Timed Out";
          } else if (err.contains("SocketException")) {
            _status = "Network unreachable (Check IP)";
          } else {
            _status = "Error: ${err.split('\n').first}";
          }
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_lastFrame != null) {
      return Stack(
        fit: StackFit.expand,
        children: [
          Image.memory(
            _lastFrame!,
            fit: BoxFit.contain,
            width: double.infinity,
            height: double.infinity,
            gaplessPlayback: true, // Prevents screen flickering between frames
          ),
          if (_isError)
            Positioned(
              top: 8,
              right: 8,
              child: Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(color: Colors.black87, borderRadius: BorderRadius.circular(8)),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.warning, color: Colors.redAccent, size: 16),
                    const SizedBox(width: 8),
                    Text(_status, style: const TextStyle(color: Colors.redAccent, fontSize: 12)),
                  ],
                ),
              ),
            ),
        ],
      );
    }

    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          if (_isError) const Icon(Icons.videocam_off, color: Colors.redAccent, size: 48)
          else const CircularProgressIndicator(color: Color(0xFF06B6D4)),
          const SizedBox(height: 16),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24),
            child: Text(
              _status,
              textAlign: TextAlign.center,
              style: TextStyle(color: _isError ? Colors.redAccent : Colors.white54, fontWeight: FontWeight.bold),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            widget.ipAddress,
            style: const TextStyle(color: Colors.white24, fontSize: 11),
          ),
        ],
      ),
    );
  }
}