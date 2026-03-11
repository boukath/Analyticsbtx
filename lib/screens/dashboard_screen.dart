// lib/screens/dashboard_screen.dart

import 'dart:ui';
import 'dart:async';
import 'dart:convert';
import 'dart:io';
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

enum ChartFilter { hourly, daily }

class DashboardScreen extends StatefulWidget {
  const DashboardScreen({Key? key}) : super(key: key);

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  List<PeopleCount> _rawData = [];
  List<PeopleCount> _displayedData = [];

  bool _isLoading = false;
  String? _selectedFolderPath;
  ChartFilter _currentFilter = ChartFilter.hourly;
  DateTimeRange? _selectedDateRange;

  Timer? _autoRefreshTimer;
  String _localIp = "";
  bool _isFtpRunning = false;

  // --- IP Security Variables ---
  Timer? _securityTimer;
  bool _isIpMismatch = false;
  String _expectedIp = "";
  String _actualIp = "";

  // --- NEW: Aggressive Alert Variables ---
  bool _isAlertSilenced = false;
  bool _isAlertDialogOpen = false;

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
    _loadStoreProfile();
    _loadPosDatabase();
    _loadSavedFolder();
    _checkFtpStatus();
    _startSecurityMonitor();
  }

  @override
  void dispose() {
    _autoRefreshTimer?.cancel();
    _securityTimer?.cancel();
    FtpService.stopServer();
    super.dispose();
  }

  // --- UPDATED: Security Monitor with Aggressive Alert ---
  void _startSecurityMonitor() {
    _securityTimer = Timer.periodic(const Duration(seconds: 10), (timer) async {
      final prefs = await SharedPreferences.getInstance();
      String savedIp = prefs.getString('ftp_ip') ?? '';

      if (savedIp.isEmpty) return; // Ignore if no IP is configured yet

      String currentIp = await FtpService.getLocalIpAddress();

      if (mounted) {
        setState(() {
          _expectedIp = savedIp;
          _actualIp = currentIp;
          _isIpMismatch = (currentIp != savedIp);
        });

        // If the IP is correct, reset the silence flag so it can alert again if it breaks later
        if (!_isIpMismatch) {
          _isAlertSilenced = false;
        }

        int totalVisitors = _totalIn + _totalOut; // Check if "comptage is still 0"

        // TRIGGER CONDITION: IP is wrong AND Comptage is 0 AND Not silenced AND Dialog isn't already open
        if (_isIpMismatch && totalVisitors == 0 && !_isAlertSilenced && !_isAlertDialogOpen) {
          _showPasswordAlertDialog();
        }
      }
    });
  }

  // --- NEW: Aggressive Password Alert Dialog ---
  void _showPasswordAlertDialog() {
    _isAlertDialogOpen = true;
    TextEditingController passCtrl = TextEditingController();
    String errorMessage = "";

    showDialog(
      context: context,
      barrierDismissible: false, // Forces interaction! They cannot click outside to close it.
      builder: (BuildContext c) {
        return StatefulBuilder(
            builder: (context, setDialogState) {
              return AlertDialog(
                backgroundColor: const Color(0xFF1E293B),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16), side: const BorderSide(color: Colors.redAccent, width: 2)),
                title: const Row(
                  children: [
                    Icon(Icons.warning_amber_rounded, color: Colors.redAccent, size: 32),
                    SizedBox(width: 12),
                    Text("CRITICAL NETWORK ERROR", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                  ],
                ),
                content: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      "The PC's IP Address has changed and NO TRAFFIC (0) is being recorded!\n\n"
                          "Expected IP: $_expectedIp\n"
                          "Current IP: ${_actualIp == '127.0.0.1' ? 'DISCONNECTED' : _actualIp}\n\n"
                          "Please fix the network immediately, or enter the technician password to silence this alert.",
                      style: const TextStyle(color: Colors.white70, fontSize: 16, height: 1.5),
                    ),
                    const SizedBox(height: 20),
                    TextField(
                      controller: passCtrl,
                      obscureText: true,
                      style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                      decoration: InputDecoration(
                        labelText: 'Technician Password',
                        labelStyle: const TextStyle(color: Colors.white54),
                        filled: true,
                        fillColor: Colors.black45,
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                        errorText: errorMessage.isNotEmpty ? errorMessage : null,
                      ),
                    ),
                  ],
                ),
                actions: [
                  TextButton(
                    onPressed: () {
                      // Close dialog and go to FTP settings to fix the network
                      _isAlertDialogOpen = false;
                      Navigator.of(c).pop();
                      Navigator.push(context, MaterialPageRoute(builder: (context) => const FtpServerScreen()));
                    },
                    child: const Text("FIX NETWORK", style: TextStyle(color: Colors.cyanAccent, fontWeight: FontWeight.bold, letterSpacing: 1)),
                  ),
                  ElevatedButton(
                    style: ElevatedButton.styleFrom(backgroundColor: Colors.redAccent, foregroundColor: Colors.white),
                    onPressed: () {
                      if (passCtrl.text == "Boitexinfo") {
                        // Password is correct! Silence the popups.
                        _isAlertSilenced = true;
                        _isAlertDialogOpen = false;
                        Navigator.of(c).pop();
                      } else {
                        // Wrong password
                        setDialogState(() {
                          errorMessage = "Incorrect Password!";
                        });
                      }
                    },
                    child: const Text("SILENCE ALERT", style: TextStyle(fontWeight: FontWeight.bold)),
                  ),
                ],
              );
            }
        );
      },
    ).then((_) {
      _isAlertDialogOpen = false; // Reset if it somehow closes
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
        if (_selectedDateRange == null) return true;
        var dateParts = item.date.split('/');
        if (dateParts.length != 3) return true;
        int day = int.parse(dateParts[0]), month = int.parse(dateParts[1]), year = int.parse(dateParts[2]);
        DateTime rowDate = DateTime(year, month, day);
        return rowDate.isAfter(_selectedDateRange!.start.subtract(const Duration(days: 1))) && rowDate.isBefore(_selectedDateRange!.end.add(const Duration(days: 1)));
      }).toList();

      if (_currentFilter == ChartFilter.daily) _displayedData = DataAggregator.aggregateByDay(filteredData);
      else _displayedData = DataAggregator.aggregateByHour(filteredData);

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
      builder: (context, child) => Theme(data: ThemeData.light().copyWith(colorScheme: ColorScheme.light(primary: Colors.blue[700]!, onPrimary: Colors.white, surface: Colors.white)), child: child!),
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
    if (_selectedDateRange == null) return "All Time";
    const List<String> months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
    DateTime start = _selectedDateRange!.start, end = _selectedDateRange!.end;
    if (start.isAtSameMomentAs(end) || end.difference(start).inDays == 0) return "${months[start.month - 1]} ${start.day}, ${start.year}";
    return "${months[start.month - 1]} ${start.day} - ${months[end.month - 1]} ${end.day}";
  }

  String _formatDateOnly(DateTime d) => "${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}";

  Widget _buildTrendBadge(num current, num previous) {
    if (!_isCompareMode) return const SizedBox.shrink();
    if (previous == 0) return const SizedBox.shrink();

    double change = ((current - previous) / previous) * 100;
    bool isPositive = change >= 0;

    return Container(
        margin: const EdgeInsets.only(top: 8),
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
            color: isPositive ? Colors.green.withOpacity(0.1) : Colors.red.withOpacity(0.1),
            borderRadius: BorderRadius.circular(20)
        ),
        child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(isPositive ? Icons.trending_up : Icons.trending_down, size: 14, color: isPositive ? Colors.green[700] : Colors.red[700]),
              const SizedBox(width: 4),
              Text('${change.abs().toStringAsFixed(1)}%', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: isPositive ? Colors.green[700] : Colors.red[700])),
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
                  backgroundColor: Colors.white,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                  title: const Text('Store Profile Settings', style: TextStyle(color: Colors.black87, fontWeight: FontWeight.bold)),
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
                            color: Colors.grey[200],
                            shape: BoxShape.circle,
                            border: Border.all(color: Colors.grey[300]!, width: 2),
                            image: tempLogoPath != null ? DecorationImage(image: FileImage(File(tempLogoPath!)), fit: BoxFit.cover) : null,
                          ),
                          child: tempLogoPath == null ? Icon(Icons.add_a_photo, color: Colors.blue[700], size: 30) : null,
                        ),
                      ),
                      const SizedBox(height: 8),
                      const Text('Tap to change logo', style: TextStyle(color: Colors.black54, fontSize: 12)),
                      const SizedBox(height: 24),

                      TextField(
                        controller: nameCtrl,
                        style: const TextStyle(color: Colors.black87, fontWeight: FontWeight.bold),
                        decoration: InputDecoration(
                          labelText: 'Store / Brand Name',
                          filled: true, fillColor: Colors.grey[100],
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide.none),
                          prefixIcon: Icon(Icons.storefront, color: Colors.blue[600]),
                        ),
                      ),
                      const SizedBox(height: 12),

                      TextField(
                        controller: locCtrl,
                        style: const TextStyle(color: Colors.black87, fontWeight: FontWeight.bold),
                        decoration: InputDecoration(
                          labelText: 'Location (e.g. Branch, City)',
                          filled: true, fillColor: Colors.grey[100],
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide.none),
                          prefixIcon: Icon(Icons.location_on, color: Colors.pink[500]),
                        ),
                      ),
                    ],
                  ),
                  actions: [
                    TextButton(onPressed: () => Navigator.pop(context), child: const Text('CANCEL', style: TextStyle(color: Colors.black54))),
                    ElevatedButton(
                      style: ElevatedButton.styleFrom(backgroundColor: Colors.blue[700], foregroundColor: Colors.white),
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
                      child: const Text('SAVE SETTINGS', style: TextStyle(fontWeight: FontWeight.bold)),
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
          backgroundColor: Colors.white, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: Column(children: [ Icon(Icons.point_of_sale, color: Colors.orange[600], size: 40), const SizedBox(height: 8), const Text('ENTER DAILY POS DATA', style: TextStyle(color: Colors.black87, fontWeight: FontWeight.bold, fontSize: 16)), Text('Date: ${_getFormattedDateString()}', style: const TextStyle(color: Colors.black54, fontSize: 12)) ]),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(controller: caCtrl, keyboardType: const TextInputType.numberWithOptions(decimal: true), decoration: InputDecoration(labelText: 'Revenue (DZD)', filled: true, fillColor: Colors.grey[100], border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide.none), prefixIcon: Icon(Icons.payments, color: Colors.orange[600]))),
              const SizedBox(height: 12),
              TextField(controller: clientCtrl, keyboardType: TextInputType.number, decoration: InputDecoration(labelText: 'Total Clients', filled: true, fillColor: Colors.grey[100], border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide.none), prefixIcon: Icon(Icons.receipt_long, color: Colors.blue[600]))),
              const SizedBox(height: 12),
              TextField(controller: articleCtrl, keyboardType: TextInputType.number, decoration: InputDecoration(labelText: 'Articles Sold', filled: true, fillColor: Colors.grey[100], border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide.none), prefixIcon: Icon(Icons.shopping_bag, color: Colors.pink[500]))),
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context), child: const Text('CANCEL', style: TextStyle(color: Colors.black54))),
            ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: Colors.orange[600], foregroundColor: Colors.white),
              onPressed: () {
                _savePosData(dateStr, double.tryParse(caCtrl.text) ?? 0.0, int.tryParse(clientCtrl.text) ?? 0, int.tryParse(articleCtrl.text) ?? 0);
                Navigator.pop(context);
              },
              child: const Text('SAVE DATA', style: TextStyle(fontWeight: FontWeight.bold)),
            ),
          ],
        )
    );
  }

  Future<void> _generateCustomReport(String cam, DateTimeRange range, ChartFilter filter, {required String format}) async {
    setState(() { _selectedCamera = cam; _selectedDateRange = range; _currentFilter = filter; _applyFilter(); });
    await Future.delayed(const Duration(milliseconds: 200));
    if (_displayedData.isEmpty) return;
    String rType = filter == ChartFilter.hourly ? "Hourly Breakdown" : "Daily Summary Breakdown";
    String cLabel = cam == 'All Doors' ? 'Global (All Doors)' : 'Camera ${cam.toUpperCase()}';
    String sCam = cam.replaceAll(' ', '_'), sStart = _formatDateOnly(range.start), sEnd = _formatDateOnly(range.end);
    String fName = sStart == sEnd ? "TrafficReport_${sCam}_$sStart" : "TrafficReport_${sCam}_${sStart}_to_$sEnd";

    if (format == 'pdf') {
      await PdfExportService.generateAndPreviewReport(reportType: rType, dateRangeText: _getFormattedDateString(), cameraName: cLabel, data: _displayedData, totalIn: _totalIn, totalOut: _totalOut, peakHour: _peakHour, customFileName: "$fName.pdf");
    } else {
      await CsvExportService.generateAndSaveCsv(reportType: rType, dateRangeText: _getFormattedDateString(), cameraName: cLabel, data: _displayedData, totalIn: _totalIn, totalOut: _totalOut, peakHour: _peakHour, customFileName: "$fName.csv");
    }
  }

  void _showExportMenu() {
    DateTimeRange eRange = _selectedDateRange ?? DateTimeRange(start: DateTime.now(), end: DateTime.now());
    String eCam = _selectedCamera; ChartFilter eFilt = _currentFilter;

    showModalBottomSheet(
        context: context, isScrollControlled: true, backgroundColor: Colors.white, shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
        builder: (context) => StatefulBuilder(
            builder: (context, setModalState) {
              void applyPreset(String type) {
                DateTime ref = eRange.end, start = ref;
                if (type == 'Daily') { start = ref; eFilt = ChartFilter.hourly; }
                else if (type == 'Weekly') { start = ref.subtract(const Duration(days: 6)); eFilt = ChartFilter.daily; }
                else if (type == 'Monthly') { start = DateTime(ref.year, ref.month - 1, ref.day); eFilt = ChartFilter.daily; }
                setModalState(() => eRange = DateTimeRange(start: start, end: ref));
              }
              return Padding(
                padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom, left: 24, right: 24, top: 24),
                child: Column(
                  mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('EXPORT SETTINGS', style: TextStyle(color: Colors.blue[700], fontSize: 18, fontWeight: FontWeight.bold)), const SizedBox(height: 24),
                    SingleChildScrollView(scrollDirection: Axis.horizontal, child: Row(children: ['Daily', 'Weekly', 'Monthly'].map((p) => Padding(padding: const EdgeInsets.only(right: 8.0), child: OutlinedButton(onPressed: () => applyPreset(p), child: Text(p)))).toList())), const SizedBox(height: 20),
                    InkWell(onTap: () async { DateTimeRange? picked = await showDateRangePicker(context: context, firstDate: DateTime(2020), lastDate: DateTime.now().add(const Duration(days: 3650)), initialDateRange: eRange); if (picked != null) setModalState(() => eRange = picked); }, child: Container(padding: const EdgeInsets.all(14), decoration: BoxDecoration(color: Colors.grey[100], borderRadius: BorderRadius.circular(8)), child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [Text("${_formatDateOnly(eRange.start)}   →   ${_formatDateOnly(eRange.end)}", style: const TextStyle(fontWeight: FontWeight.bold)), Icon(Icons.edit_calendar, color: Colors.blue[700])]))), const SizedBox(height: 20),
                    Row(children: [ Expanded(child: ElevatedButton.icon(style: ElevatedButton.styleFrom(backgroundColor: Colors.blue[600], foregroundColor: Colors.white), icon: const Icon(Icons.picture_as_pdf), label: const Text('SAVE PDF'), onPressed: () { Navigator.pop(context); _generateCustomReport(eCam, eRange, eFilt, format: 'pdf'); })), const SizedBox(width: 16), Expanded(child: ElevatedButton.icon(style: ElevatedButton.styleFrom(backgroundColor: Colors.green[600], foregroundColor: Colors.white), icon: const Icon(Icons.table_chart), label: const Text('SAVE CSV'), onPressed: () { Navigator.pop(context); _generateCustomReport(eCam, eRange, eFilt, format: 'csv'); }))]), const SizedBox(height: 32),
                  ],
                ),
              );
            }
        )
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDesktop = MediaQuery.of(context).size.width > 800;

    return Scaffold(
      backgroundColor: const Color(0xFFF3F4F6),
      body: Row(
        children: [
          if (isDesktop) _buildSidebar(),

          Expanded(
            child: Column(
              children: [
                _buildTopAppBar(),

                // The Passive Security Banner (Always shows if IP is wrong, even if popups are silenced)
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
                            "CRITICAL: Network IP Changed! Expected: $_expectedIp | Current: ${_actualIp == '127.0.0.1' ? 'DISCONNECTED' : _actualIp}. Cameras are currently blind.",
                            style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16),
                          ),
                        ),
                        ElevatedButton(
                          style: ElevatedButton.styleFrom(backgroundColor: Colors.white, foregroundColor: Colors.red[700]),
                          onPressed: () {
                            Navigator.push(context, MaterialPageRoute(builder: (context) => const FtpServerScreen()));
                          },
                          child: const Text("FIX NETWORK", style: TextStyle(fontWeight: FontWeight.bold)),
                        )
                      ],
                    ),
                  ),

                Expanded(
                  child: _isLoading
                      ? Center(child: CircularProgressIndicator(color: Colors.blue[700]))
                      : SingleChildScrollView(
                    padding: const EdgeInsets.all(32.0),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _buildPageHeader(),
                        const SizedBox(height: 32),

                        if (_rawData.isEmpty)
                          _buildEmptyState()
                        else ...[
                          _buildTrafficSummaryCards(isDesktop),
                          const SizedBox(height: 24),
                          _buildBusinessPerformanceCards(isDesktop),
                          const SizedBox(height: 32),
                          _buildInteractiveChartSection(),
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
      color: const Color(0xFF1E293B),
      child: Column(
        children: [
          const SizedBox(height: 40),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.analytics, color: Colors.blue[400], size: 32),
              const SizedBox(width: 12),
              const Text('Analytics', style: TextStyle(fontSize: 24, fontWeight: FontWeight.w900, color: Colors.white)),
            ],
          ),
          const SizedBox(height: 60),

          _buildSidebarItem(Icons.dashboard, 'Dashboard', isActive: true),
          _buildSidebarItem(Icons.source, 'Data Source', onTap: _pickFolderAndLoadData),

          _buildSidebarItem(
              Icons.wifi_tethering,
              'FTP Server',
              iconColor: _isIpMismatch ? Colors.redAccent : null,
              textColor: _isIpMismatch ? Colors.redAccent : null,
              onTap: () async {
                await Navigator.push(context, MaterialPageRoute(builder: (context) => const FtpServerScreen()));
                _checkFtpStatus();
              }
          ),

          _buildSidebarItem(Icons.cloud_upload, 'Cloud Sync (B2)', onTap: () {
            Navigator.push(context, MaterialPageRoute(builder: (context) => const CloudSyncScreen()));
          }),

          _buildSidebarItem(Icons.point_of_sale, 'POS Entry', onTap: _rawData.isNotEmpty ? _showPosEntryDialog : null),
          _buildSidebarItem(Icons.download, 'Export Reports', onTap: _rawData.isNotEmpty ? _showExportMenu : null),

          const Spacer(),
          if (_isFtpRunning && !_isIpMismatch)
            Container(
              margin: const EdgeInsets.all(24),
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(color: Colors.green.withOpacity(0.1), borderRadius: BorderRadius.circular(12), border: Border.all(color: Colors.green.withOpacity(0.3))),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(children: [Icon(Icons.circle, color: Colors.green[400], size: 12), const SizedBox(width: 8), const Text('FTP Active', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.white))]),
                  const SizedBox(height: 8),
                  Text('ftp://$_localIp:2121', style: const TextStyle(fontSize: 12, color: Colors.white70)),
                ],
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildSidebarItem(IconData icon, String title, {bool isActive = false, Color? iconColor, Color? textColor, VoidCallback? onTap}) {
    return ListTile(
      leading: Icon(icon, color: iconColor ?? (isActive ? Colors.blue[400] : Colors.white54)),
      title: Text(title, style: TextStyle(color: textColor ?? (isActive ? Colors.blue[400] : Colors.white54), fontWeight: isActive ? FontWeight.bold : FontWeight.normal, fontSize: 16)),
      contentPadding: const EdgeInsets.symmetric(horizontal: 32, vertical: 8),
      onTap: onTap,
    );
  }

  Widget _buildTopAppBar() {
    return Container(
      height: 90,
      padding: const EdgeInsets.symmetric(horizontal: 32),
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border(bottom: BorderSide(color: Colors.grey[200]!)),
      ),
      child: Row(
        children: [
          StreamBuilder(
            stream: Stream.periodic(const Duration(seconds: 1)),
            builder: (context, snapshot) {
              final now = DateTime.now();
              const List<String> weekdays = ['Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday', 'Sunday'];
              const List<String> months = ['January', 'February', 'March', 'April', 'May', 'June', 'July', 'August', 'September', 'October', 'November', 'December'];

              String dayName = weekdays[now.weekday - 1];
              String monthName = months[now.month - 1];
              String hour = now.hour.toString().padLeft(2, '0');
              String minute = now.minute.toString().padLeft(2, '0');
              String second = now.second.toString().padLeft(2, '0');

              return Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text("$dayName, $monthName ${now.day}, ${now.year}", style: const TextStyle(color: Colors.black54, fontSize: 14, fontWeight: FontWeight.w600, letterSpacing: 0.5)),
                  const SizedBox(height: 2),
                  Text("$hour:$minute:$second", style: const TextStyle(color: Colors.black87, fontSize: 24, fontWeight: FontWeight.w900, letterSpacing: 1)),
                ],
              );
            },
          ),

          const Spacer(),

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
                      Text(_storeLocation.toUpperCase(), style: const TextStyle(color: Colors.black45, fontSize: 12, fontWeight: FontWeight.bold, letterSpacing: 1.5)),
                      Text(_storeName, style: const TextStyle(color: Colors.black87, fontSize: 20, fontWeight: FontWeight.bold)),
                    ],
                  ),
                  const SizedBox(width: 20),
                  Container(
                    width: 70, height: 70,
                    decoration: BoxDecoration(
                      color: Colors.grey[100],
                      shape: BoxShape.circle,
                      border: Border.all(color: Colors.grey[300]!, width: 2),
                      image: _storeLogoPath != null ? DecorationImage(image: FileImage(File(_storeLogoPath!)), fit: BoxFit.cover) : null,
                    ),
                    child: _storeLogoPath == null ? Icon(Icons.storefront, color: Colors.blue[700], size: 36) : null,
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
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Dashboard Overview', style: TextStyle(fontSize: 32, fontWeight: FontWeight.w800, color: Colors.black87, letterSpacing: -0.5)),
            if (_selectedFolderPath != null)
              Padding(
                padding: const EdgeInsets.only(top: 4.0),
                child: Text('Source: $_selectedFolderPath', style: const TextStyle(color: Colors.black45, fontSize: 14)),
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
                label: const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  child: Text('Compare vs Previous', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                ),
                selectedColor: Colors.blue.withOpacity(0.15),
                checkmarkColor: Colors.blue[700],
                backgroundColor: Colors.white,
                shape: StadiumBorder(side: BorderSide(color: _isCompareMode ? Colors.blue[700]! : Colors.grey[300]!, width: 1.5)),
              ),
              const SizedBox(width: 16),
            ],

            Container(
              decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(8), border: Border.all(color: Colors.grey[300]!, width: 1.5)),
              padding: const EdgeInsets.all(4),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  IconButton(icon: const Icon(Icons.chevron_left, color: Colors.black54), onPressed: () => _shiftDate(-1)),
                  GestureDetector(
                    onTap: _pickDateRange,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      child: Text(_getFormattedDateString(), style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.black87, fontSize: 16)),
                    ),
                  ),
                  IconButton(icon: const Icon(Icons.chevron_right, color: Colors.black54), onPressed: () => _shiftDate(1)),
                ],
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
            Icon(Icons.folder_open, size: 100, color: Colors.grey[300]),
            const SizedBox(height: 24),
            const Text('No Data Selected', style: TextStyle(fontSize: 28, fontWeight: FontWeight.bold, color: Colors.black87)),
            const SizedBox(height: 12),
            const Text('Please select a data source or start the FTP server from the menu.', style: TextStyle(color: Colors.black54, fontSize: 16)),
            const SizedBox(height: 32),
            ElevatedButton.icon(
              style: ElevatedButton.styleFrom(backgroundColor: Colors.blue[700], foregroundColor: Colors.white, padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 20)),
              onPressed: _pickFolderAndLoadData,
              icon: const Icon(Icons.drive_folder_upload, size: 24),
              label: const Text('IMPORT DATA', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
            )
          ],
        ),
      ),
    );
  }

  Widget _buildTrafficSummaryCards(bool isDesktop) {
    int totalVisitors = (_totalIn + _totalOut) ~/ 2;

    final cards = [
      _buildWhiteMetricCard('Total In', _totalIn.toString(), Icons.login, Colors.blue, trendWidget: _buildTrendBadge(_totalIn, _compareTotalIn)),
      _buildWhiteMetricCard('Total Out', _totalOut.toString(), Icons.logout, Colors.orange, trendWidget: _buildTrendBadge(_totalOut, _compareTotalOut)),
      _buildWhiteMetricCard('Total Visitors', totalVisitors.toString(), Icons.groups, Colors.green, trendWidget: _buildTrendBadge(totalVisitors, _compareTotalVisitors)),
      _buildWhiteMetricCard('Peak Hour', _peakHour, Icons.access_time, Colors.purple),
    ];

    if (isDesktop) { return Row(children: cards.map((c) => Expanded(child: Padding(padding: const EdgeInsets.symmetric(horizontal: 8), child: c))).toList()); }
    else { return Wrap(spacing: 16, runSpacing: 16, children: cards.map((c) => SizedBox(width: MediaQuery.of(context).size.width / 2 - 40, child: c)).toList()); }
  }

  Widget _buildBusinessPerformanceCards(bool isDesktop) {
    int totalVisitors = (_totalIn + _totalOut) ~/ 2;
    double conversionRate = totalVisitors > 0 ? (_currentClients / totalVisitors) * 100 : 0.0;
    double avgBasket = _currentClients > 0 ? (_currentCa / _currentClients) : 0.0;
    double upt = _currentClients > 0 ? (_currentArticles / _currentClients) : 0.0;

    double compareConv = _compareTotalVisitors > 0 ? (_compareClients / _compareTotalVisitors) * 100 : 0.0;
    double compareBasket = _compareClients > 0 ? (_compareCa / _compareClients) : 0.0;
    double compareUpt = _compareClients > 0 ? (_compareArticles / _compareClients) : 0.0;

    final cards = [
      _buildWhiteMetricCard('Conversion Rate', '${conversionRate.toStringAsFixed(1)}%', Icons.track_changes, Colors.red, trendWidget: _buildTrendBadge(conversionRate, compareConv)),
      _buildWhiteMetricCard('Revenue (CA)', '${_currentCa.toStringAsFixed(0)} DZD', Icons.payments, Colors.teal, trendWidget: _buildTrendBadge(_currentCa, _compareCa)),
      _buildWhiteMetricCard('Avg Basket', '${avgBasket.toStringAsFixed(2)} DZD', Icons.shopping_cart, Colors.indigo, trendWidget: _buildTrendBadge(avgBasket, compareBasket)),
      _buildWhiteMetricCard('U.P.T', upt.toStringAsFixed(2), Icons.layers, Colors.pink, trendWidget: _buildTrendBadge(upt, compareUpt)),
    ];

    if (isDesktop) { return Row(children: cards.map((c) => Expanded(child: Padding(padding: const EdgeInsets.symmetric(horizontal: 8), child: c))).toList()); }
    else { return Wrap(spacing: 16, runSpacing: 16, children: cards.map((c) => SizedBox(width: MediaQuery.of(context).size.width / 2 - 40, child: c)).toList()); }
  }

  Widget _buildWhiteMetricCard(String title, String value, IconData icon, MaterialColor colorTheme, {Widget? trendWidget}) {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.04), blurRadius: 15, offset: const Offset(0, 5))],
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: const TextStyle(fontSize: 15, color: Colors.black54, fontWeight: FontWeight.w600)),
              const SizedBox(height: 8),
              Text(value, style: const TextStyle(fontSize: 28, fontWeight: FontWeight.w800, color: Colors.black87, letterSpacing: -0.5)),
              if (trendWidget != null) trendWidget,
            ],
          ),
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(color: colorTheme[50], shape: BoxShape.circle),
            child: Icon(icon, color: colorTheme[600], size: 28),
          ),
        ],
      ),
    );
  }

  Widget _buildInteractiveChartSection() {
    List<LineChartBarData> chartLines = [];

    if (_isCompareMode) {
      chartLines.add(LineChartBarData(
        spots: _displayedData.asMap().entries.map((e) => FlSpot(e.key.toDouble(), ((e.value.inCount + e.value.outCount) / 2).toDouble())).toList(),
        isCurved: true, color: Colors.blue[600], barWidth: 4, isStrokeCapRound: true, dotData: FlDotData(show: false),
        belowBarData: BarAreaData(show: true, gradient: LinearGradient(colors: [Colors.blue.withOpacity(0.2), Colors.blue.withOpacity(0.0)], begin: Alignment.topCenter, end: Alignment.bottomCenter)),
      ));
      chartLines.add(LineChartBarData(
        spots: _compareDisplayedData.asMap().entries.map((e) => FlSpot(e.key.toDouble(), ((e.value.inCount + e.value.outCount) / 2).toDouble())).toList(),
        isCurved: true, color: Colors.grey[400], barWidth: 3, dashArray: [5, 5], isStrokeCapRound: true, dotData: FlDotData(show: false),
      ));
    } else {
      chartLines.add(LineChartBarData(
        spots: _displayedData.asMap().entries.map((e) => FlSpot(e.key.toDouble(), e.value.inCount.toDouble())).toList(),
        isCurved: true, color: Colors.blue[600], barWidth: 4, isStrokeCapRound: true, dotData: FlDotData(show: false),
        belowBarData: BarAreaData(show: true, gradient: LinearGradient(colors: [Colors.blue.withOpacity(0.2), Colors.blue.withOpacity(0.0)], begin: Alignment.topCenter, end: Alignment.bottomCenter)),
      ));
      chartLines.add(LineChartBarData(
        spots: _displayedData.asMap().entries.map((e) => FlSpot(e.key.toDouble(), e.value.outCount.toDouble())).toList(),
        isCurved: true, color: Colors.pink[400], barWidth: 4, isStrokeCapRound: true, dotData: FlDotData(show: false),
        belowBarData: BarAreaData(show: true, gradient: LinearGradient(colors: [Colors.pink.withOpacity(0.2), Colors.pink.withOpacity(0.0)], begin: Alignment.topCenter, end: Alignment.bottomCenter)),
      ));
    }

    return Container(
      padding: const EdgeInsets.all(32),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.04), blurRadius: 15, offset: const Offset(0, 5))],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  const Text('Traffic Overview', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: Colors.black87)),
                  const SizedBox(width: 16),
                  if (_isCompareMode) ...[
                    Row(children: [Icon(Icons.circle, size: 12, color: Colors.blue[600]), const SizedBox(width: 6), const Text('Current', style: TextStyle(fontSize: 14, color: Colors.black54))]),
                    const SizedBox(width: 16),
                    Row(children: [Icon(Icons.circle, size: 12, color: Colors.grey[400]), const SizedBox(width: 6), const Text('Previous', style: TextStyle(fontSize: 14, color: Colors.black54))]),
                  ] else ...[
                    Row(children: [Icon(Icons.circle, size: 12, color: Colors.blue[600]), const SizedBox(width: 6), const Text('In', style: TextStyle(fontSize: 14, color: Colors.black54))]),
                    const SizedBox(width: 16),
                    Row(children: [Icon(Icons.circle, size: 12, color: Colors.pink[400]), const SizedBox(width: 6), const Text('Out', style: TextStyle(fontSize: 14, color: Colors.black54))]),
                  ]
                ],
              ),

              Row(
                children: [
                  if (_availableCameras.length > 1)
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                      decoration: BoxDecoration(color: Colors.blue.withOpacity(0.05), borderRadius: BorderRadius.circular(8)),
                      child: DropdownButtonHideUnderline(
                        child: DropdownButton<String>(
                          value: _selectedCamera, icon: Icon(Icons.keyboard_arrow_down, color: Colors.blue[700]), style: TextStyle(color: Colors.blue[700], fontWeight: FontWeight.bold, fontSize: 16),
                          items: _availableCameras.map((String camera) { return DropdownMenuItem<String>(value: camera, child: Text(camera == 'All Doors' ? 'All Doors' : camera.toUpperCase())); }).toList(),
                          onChanged: (String? newValue) { if (newValue != null) { setState(() { _selectedCamera = newValue; _applyFilter(); }); } },
                        ),
                      ),
                    ),
                  const SizedBox(width: 16),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                    decoration: BoxDecoration(color: Colors.grey[100], borderRadius: BorderRadius.circular(8)),
                    child: DropdownButtonHideUnderline(
                      child: DropdownButton<ChartFilter>(
                        value: _currentFilter, icon: const Icon(Icons.keyboard_arrow_down, color: Colors.black54), style: const TextStyle(color: Colors.black87, fontWeight: FontWeight.bold, fontSize: 16),
                        items: const [ DropdownMenuItem(value: ChartFilter.hourly, child: Text('Hourly View')), DropdownMenuItem(value: ChartFilter.daily, child: Text('Daily View')) ],
                        onChanged: (ChartFilter? newValue) { if (newValue != null) { setState(() { _currentFilter = newValue; _applyFilter(); }); } },
                      ),
                    ),
                  ),
                ],
              )
            ],
          ),
          const SizedBox(height: 40),

          SizedBox(
            height: 450,
            child: LineChart(
              LineChartData(
                lineTouchData: LineTouchData(
                  touchTooltipData: LineTouchTooltipData(
                    tooltipBgColor: Colors.black87,
                    getTooltipItems: (touchedSpots) {
                      return touchedSpots.map((LineBarSpot touchedSpot) {
                        final textStyle = TextStyle(color: touchedSpot.bar.color ?? Colors.white, fontWeight: FontWeight.bold, fontSize: 14);
                        String timeText = _displayedData.length > touchedSpot.x.toInt() ? _displayedData[touchedSpot.x.toInt()].time : "";
                        String type = "";

                        if (_isCompareMode) {
                          type = touchedSpot.barIndex == 0 ? "Current: " : "Previous: ";
                        } else {
                          type = touchedSpot.barIndex == 0 ? "In: " : "Out: ";
                        }

                        return LineTooltipItem("$timeText\n$type${touchedSpot.y.toInt()}", textStyle);
                      }).toList();
                    },
                  ),
                ),
                gridData: FlGridData(show: true, drawVerticalLine: false, getDrawingHorizontalLine: (value) => FlLine(color: Colors.grey[200]!, strokeWidth: 1)),
                titlesData: FlTitlesData(
                  rightTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)),
                  topTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)),
                  bottomTitles: AxisTitles(
                    sideTitles: SideTitles(
                      showTitles: true, reservedSize: 32, interval: 1,
                      getTitlesWidget: (value, meta) {
                        int index = value.toInt();
                        if (index >= 0 && index < _displayedData.length) {
                          if (_displayedData.length > 12 && index % 2 != 0) return const SizedBox.shrink();
                          return Padding(padding: const EdgeInsets.only(top: 10.0), child: Text(_displayedData[index].time, style: const TextStyle(color: Colors.black54, fontSize: 12)));
                        }
                        return const SizedBox.shrink();
                      },
                    ),
                  ),
                  leftTitles: AxisTitles(
                    sideTitles: SideTitles(showTitles: true, reservedSize: 40, getTitlesWidget: (value, meta) { return Text(value.toInt().toString(), style: const TextStyle(color: Colors.black54, fontSize: 13)); }),
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
}