// lib/screens/dashboard_screen.dart

import 'dart:ui';
import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:shared_preferences/shared_preferences.dart';

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

  final FolderScannerService _scannerService = FolderScannerService();

  @override
  void initState() {
    super.initState();
    _loadPosDatabase();
    _loadSavedFolder();
    _checkFtpStatus();
  }

  @override
  void dispose() {
    _autoRefreshTimer?.cancel();
    FtpService.stopServer();
    super.dispose();
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

    if (savedPath != null && savedPath.isNotEmpty) {
      _processDataFromPath(savedPath);
    }
  }

  Future<void> _loadPosDatabase() async {
    final prefs = await SharedPreferences.getInstance();
    final String? posJson = prefs.getString('pos_database');
    if (posJson != null) {
      setState(() {
        _posDatabase = Map<String, Map<String, dynamic>>.from(jsonDecode(posJson)).map(
                (k, v) => MapEntry(k, Map<String, num>.from(v))
        );
      });
    }
  }

  Future<void> _savePosData(String date, double ca, int clients, int articles) async {
    setState(() {
      _posDatabase[date] = {"ca": ca, "clients": clients, "articles": articles};
    });
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('pos_database', jsonEncode(_posDatabase));
    _calculatePosMetrics();
  }

  void _calculatePosMetrics() {
    _currentCa = 0;
    _currentClients = 0;
    _currentArticles = 0;

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
    setState(() {
      _isLoading = true;
      _selectedFolderPath = folderPath;
      _selectedDateRange = null;
    });

    List<PeopleCount> loadedData = await _scannerService.loadScbDataFromFolder(folderPath);

    setState(() {
      _rawData = loadedData;

      if (_rawData.isNotEmpty) {
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
    _autoRefreshTimer = Timer.periodic(const Duration(seconds: 60), (timer) {
      _refreshDataSilently();
    });
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
          if (sortedIds.length != (_availableCameras.length - 1)) {
            _availableCameras = ['All Doors', ...sortedIds];
          }
        }
        _applyFilter();
      });
    }
  }

  void _applyFilter() {
    setState(() {
      List<PeopleCount> filteredData = _rawData.where((item) {
        if (_selectedCamera != 'All Doors' && item.doorName != _selectedCamera) {
          return false;
        }

        if (_selectedDateRange == null) return true;
        var dateParts = item.date.split('/');
        if (dateParts.length != 3) return true;

        int day = int.parse(dateParts[0]);
        int month = int.parse(dateParts[1]);
        int year = int.parse(dateParts[2]);
        DateTime rowDate = DateTime(year, month, day);

        return rowDate.isAfter(_selectedDateRange!.start.subtract(const Duration(days: 1))) &&
            rowDate.isBefore(_selectedDateRange!.end.add(const Duration(days: 1)));
      }).toList();

      if (_currentFilter == ChartFilter.daily) {
        _displayedData = DataAggregator.aggregateByDay(filteredData);
      } else {
        _displayedData = DataAggregator.aggregateByHour(filteredData);
      }

      _totalIn = 0;
      _totalOut = 0;
      int maxTraffic = 0;
      _peakHour = "--:--";

      for (var item in _displayedData) {
        _totalIn += item.inCount;
        _totalOut += item.outCount;

        int totalVisitorsForHour = (item.inCount + item.outCount) ~/ 2;

        if (totalVisitorsForHour > maxTraffic) {
          maxTraffic = totalVisitorsForHour;
          _peakHour = item.time;
        }
      }

      _occupancy = _totalIn - _totalOut;
      if (_occupancy < 0) _occupancy = 0;

      _calculatePosMetrics();
    });
  }

  Future<void> _pickDateRange() async {
    DateTimeRange? pickedRange = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2020),
      lastDate: DateTime.now().add(const Duration(days: 3650)),
      initialDateRange: _selectedDateRange,
      builder: (context, child) {
        return Theme(
          data: ThemeData.light().copyWith(
            colorScheme: ColorScheme.light(
                primary: Colors.blue[700]!,
                onPrimary: Colors.white,
                surface: Colors.white,
                onSurface: Colors.black87
            ),
          ),
          child: child!,
        );
      },
    );

    if (pickedRange != null) {
      setState(() {
        _selectedDateRange = pickedRange;
        _applyFilter();
      });
    }
  }

  void _shiftDate(int days) {
    setState(() {
      if (_selectedDateRange == null) {
        DateTime today = DateTime.now();
        _selectedDateRange = DateTimeRange(start: today, end: today);
      } else {
        _selectedDateRange = DateTimeRange(
          start: _selectedDateRange!.start.add(Duration(days: days)),
          end: _selectedDateRange!.end.add(Duration(days: days)),
        );
      }
      _applyFilter();
    });
  }

  String _getFormattedDateString() {
    if (_selectedDateRange == null) return "All Time";
    const List<String> months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
    DateTime start = _selectedDateRange!.start;
    DateTime end = _selectedDateRange!.end;

    if (start.isAtSameMomentAs(end) || end.difference(start).inDays == 0) {
      return "${months[start.month - 1]} ${start.day}, ${start.year}";
    } else {
      return "${months[start.month - 1]} ${start.day} - ${months[end.month - 1]} ${end.day}";
    }
  }

  String _formatDateOnly(DateTime d) {
    return "${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}";
  }

  void _showPosEntryDialog() {
    if (_selectedDateRange == null) return;

    DateTime targetDate = _selectedDateRange!.end;
    String dateStr = _formatDateOnly(targetDate);

    TextEditingController caCtrl = TextEditingController(text: (_posDatabase[dateStr]?['ca'] ?? '').toString());
    TextEditingController clientCtrl = TextEditingController(text: (_posDatabase[dateStr]?['clients'] ?? '').toString());
    TextEditingController articleCtrl = TextEditingController(text: (_posDatabase[dateStr]?['articles'] ?? '').toString());

    showDialog(
        context: context,
        builder: (context) {
          return AlertDialog(
            backgroundColor: Colors.white,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            title: Column(
              children: [
                Icon(Icons.point_of_sale, color: Colors.orange[600], size: 40),
                const SizedBox(height: 8),
                const Text('ENTER DAILY POS DATA', style: TextStyle(color: Colors.black87, fontWeight: FontWeight.bold, fontSize: 16)),
                Text('Date: ${_getFormattedDateString()}', style: const TextStyle(color: Colors.black54, fontSize: 12)),
              ],
            ),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: caCtrl,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  style: const TextStyle(color: Colors.black87, fontWeight: FontWeight.bold),
                  decoration: InputDecoration(
                    labelText: 'Chiffre d\'Affaires (Revenue)', labelStyle: const TextStyle(color: Colors.black54),
                    filled: true, fillColor: Colors.grey[100],
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide.none),
                    prefixIcon: Icon(Icons.attach_money, color: Colors.orange[600]),
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: clientCtrl,
                  keyboardType: TextInputType.number,
                  style: const TextStyle(color: Colors.black87, fontWeight: FontWeight.bold),
                  decoration: InputDecoration(
                    labelText: 'Total Clients (Receipts)', labelStyle: const TextStyle(color: Colors.black54),
                    filled: true, fillColor: Colors.grey[100],
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide.none),
                    prefixIcon: Icon(Icons.receipt_long, color: Colors.blue[600]),
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: articleCtrl,
                  keyboardType: TextInputType.number,
                  style: const TextStyle(color: Colors.black87, fontWeight: FontWeight.bold),
                  decoration: InputDecoration(
                    labelText: 'Articles Sold', labelStyle: const TextStyle(color: Colors.black54),
                    filled: true, fillColor: Colors.grey[100],
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide.none),
                    prefixIcon: Icon(Icons.shopping_bag, color: Colors.pink[500]),
                  ),
                ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('CANCEL', style: TextStyle(color: Colors.black54)),
              ),
              ElevatedButton(
                style: ElevatedButton.styleFrom(backgroundColor: Colors.orange[600], foregroundColor: Colors.white),
                onPressed: () {
                  double ca = double.tryParse(caCtrl.text) ?? 0.0;
                  int clients = int.tryParse(clientCtrl.text) ?? 0;
                  int articles = int.tryParse(articleCtrl.text) ?? 0;

                  _savePosData(dateStr, ca, clients, articles);
                  Navigator.pop(context);

                  ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('POS Data Saved Successfully!'), backgroundColor: Colors.green));
                },
                child: const Text('SAVE DATA', style: TextStyle(fontWeight: FontWeight.bold)),
              ),
            ],
          );
        }
    );
  }

  Future<void> _generateCustomReport(String cam, DateTimeRange range, ChartFilter filter, {required String format}) async {
    setState(() {
      _selectedCamera = cam;
      _selectedDateRange = range;
      _currentFilter = filter;
      _applyFilter();
    });

    await Future.delayed(const Duration(milliseconds: 200));

    if (_displayedData.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("No data found for the selected settings.")));
      return;
    }

    String reportType = filter == ChartFilter.hourly ? "Hourly Breakdown" : "Daily Summary Breakdown";
    String cameraLabel = cam == 'All Doors' ? 'Global (All Doors)' : 'Camera ${cam.toUpperCase()}';
    String safeCam = cam.replaceAll(' ', '_');
    String safeStart = _formatDateOnly(range.start);
    String safeEnd = _formatDateOnly(range.end);
    String baseFileName = "TrafficReport_${safeCam}_${safeStart}_to_$safeEnd";
    if (safeStart == safeEnd) baseFileName = "TrafficReport_${safeCam}_$safeStart";

    if (format == 'pdf') {
      await PdfExportService.generateAndPreviewReport(
        reportType: reportType, dateRangeText: _getFormattedDateString(), cameraName: cameraLabel,
        data: _displayedData, totalIn: _totalIn, totalOut: _totalOut, peakHour: _peakHour, customFileName: "$baseFileName.pdf",
      );
    } else if (format == 'csv') {
      await CsvExportService.generateAndSaveCsv(
        reportType: reportType, dateRangeText: _getFormattedDateString(), cameraName: cameraLabel,
        data: _displayedData, totalIn: _totalIn, totalOut: _totalOut, peakHour: _peakHour, customFileName: "$baseFileName.csv",
      );
    }
  }

  void _showExportMenu() {
    DateTimeRange exportRange = _selectedDateRange ?? DateTimeRange(start: DateTime.now(), end: DateTime.now());
    String exportCamera = _selectedCamera;
    ChartFilter exportFilter = _currentFilter;

    showModalBottomSheet(
        context: context,
        isScrollControlled: true,
        backgroundColor: Colors.white,
        shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
        builder: (context) {
          return StatefulBuilder(
              builder: (BuildContext context, StateSetter setModalState) {

                void applyPreset(String type) {
                  DateTime refDate = exportRange.end;
                  DateTime start = refDate;
                  if (type == 'Daily') { start = refDate; exportFilter = ChartFilter.hourly; }
                  else if (type == 'Weekly') { start = refDate.subtract(const Duration(days: 6)); exportFilter = ChartFilter.daily; }
                  else if (type == 'Monthly') { start = DateTime(refDate.year, refDate.month - 1, refDate.day); exportFilter = ChartFilter.daily; }
                  else if (type == 'Yearly') { start = DateTime(refDate.year - 1, refDate.month, refDate.day); exportFilter = ChartFilter.daily; }
                  setModalState(() => exportRange = DateTimeRange(start: start, end: refDate));
                }

                return Padding(
                  padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom, left: 24, right: 24, top: 24),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('EXPORT SETTINGS', style: TextStyle(color: Colors.blue[700], fontSize: 18, fontWeight: FontWeight.bold, letterSpacing: 1.5)),
                      const SizedBox(height: 24),
                      const Text('1. Quick Date Presets', style: TextStyle(color: Colors.black54, fontSize: 12)),
                      const SizedBox(height: 8),
                      SingleChildScrollView(
                        scrollDirection: Axis.horizontal,
                        child: Row(
                          children: ['Daily', 'Weekly', 'Monthly', 'Yearly'].map((preset) => Padding(
                            padding: const EdgeInsets.only(right: 8.0),
                            child: OutlinedButton(
                              style: OutlinedButton.styleFrom(foregroundColor: Colors.black87, side: const BorderSide(color: Colors.black26), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8))),
                              onPressed: () => applyPreset(preset),
                              child: Text(preset),
                            ),
                          )).toList(),
                        ),
                      ),
                      const SizedBox(height: 20),
                      const Text('2. Confirm Date Range', style: TextStyle(color: Colors.black54, fontSize: 12)),
                      const SizedBox(height: 8),
                      InkWell(
                        onTap: () async {
                          DateTimeRange? picked = await showDateRangePicker(
                            context: context, firstDate: DateTime(2020), lastDate: DateTime.now().add(const Duration(days: 3650)), initialDateRange: exportRange,
                            builder: (context, child) => Theme(
                                data: ThemeData.light().copyWith(colorScheme: ColorScheme.light(primary: Colors.blue[700]!, onPrimary: Colors.white, surface: Colors.white)),
                                child: child!
                            ),
                          );
                          if (picked != null) setModalState(() => exportRange = picked);
                        },
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                          decoration: BoxDecoration(color: Colors.grey[100], borderRadius: BorderRadius.circular(8)),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text("${_formatDateOnly(exportRange.start)}   →   ${_formatDateOnly(exportRange.end)}", style: const TextStyle(color: Colors.black87, fontWeight: FontWeight.bold)),
                              Icon(Icons.edit_calendar, color: Colors.blue[700], size: 20),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(height: 20),
                      const Text('3. Target Camera', style: TextStyle(color: Colors.black54, fontSize: 12)),
                      const SizedBox(height: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        decoration: BoxDecoration(color: Colors.grey[100], borderRadius: BorderRadius.circular(8)),
                        child: DropdownButtonHideUnderline(
                          child: DropdownButton<String>(
                            isExpanded: true, value: exportCamera, dropdownColor: Colors.white, style: const TextStyle(color: Colors.black87, fontWeight: FontWeight.bold),
                            items: _availableCameras.map((String camera) {
                              return DropdownMenuItem<String>(value: camera, child: Text(camera == 'All Doors' ? '🌍 Global (All Cameras)' : '📹 Camera: ${camera.toUpperCase()}'));
                            }).toList(),
                            onChanged: (val) { if (val != null) setModalState(() => exportCamera = val); },
                          ),
                        ),
                      ),
                      const SizedBox(height: 20),
                      const Text('4. Data Detail Level', style: TextStyle(color: Colors.black54, fontSize: 12)),
                      Row(
                        children: [
                          Expanded(child: RadioListTile<ChartFilter>(title: const Text('Hourly', style: TextStyle(color: Colors.black87, fontSize: 13)), value: ChartFilter.hourly, groupValue: exportFilter, activeColor: Colors.pink[500], contentPadding: EdgeInsets.zero, onChanged: (val) { if (val != null) setModalState(() => exportFilter = val); })),
                          Expanded(child: RadioListTile<ChartFilter>(title: const Text('Daily', style: TextStyle(color: Colors.black87, fontSize: 13)), value: ChartFilter.daily, groupValue: exportFilter, activeColor: Colors.pink[500], contentPadding: EdgeInsets.zero, onChanged: (val) { if (val != null) setModalState(() => exportFilter = val); })),
                        ],
                      ),
                      const SizedBox(height: 32),
                      Row(
                        children: [
                          Expanded(
                            child: SizedBox(
                              height: 50,
                              child: ElevatedButton.icon(
                                style: ElevatedButton.styleFrom(backgroundColor: Colors.blue[600], foregroundColor: Colors.white, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8))),
                                icon: const Icon(Icons.picture_as_pdf), label: const Text('SAVE PDF', style: TextStyle(fontWeight: FontWeight.bold)),
                                onPressed: () { Navigator.pop(context); _generateCustomReport(exportCamera, exportRange, exportFilter, format: 'pdf'); },
                              ),
                            ),
                          ),
                          const SizedBox(width: 16),
                          Expanded(
                            child: SizedBox(
                              height: 50,
                              child: ElevatedButton.icon(
                                style: ElevatedButton.styleFrom(backgroundColor: Colors.green[600], foregroundColor: Colors.white, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8))),
                                icon: const Icon(Icons.table_chart), label: const Text('SAVE CSV', style: TextStyle(fontWeight: FontWeight.bold)),
                                onPressed: () { Navigator.pop(context); _generateCustomReport(exportCamera, exportRange, exportFilter, format: 'csv'); },
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 32),
                    ],
                  ),
                );
              }
          );
        }
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDesktop = MediaQuery.of(context).size.width > 800;

    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC), // Light airy background
      body: Stack(
        children: [
          Positioned(top: -100, left: -100, child: _buildGlowOrb(Colors.blue.withOpacity(0.15), 300)),
          Positioned(bottom: -100, right: -100, child: _buildGlowOrb(Colors.pink.withOpacity(0.15), 400)),

          SafeArea(
            child: _isLoading
                ? Center(child: CircularProgressIndicator(color: Colors.blue[700]))
                : SingleChildScrollView(
              padding: const EdgeInsets.all(32.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _buildCustomHeader(),
                  const SizedBox(height: 40),

                  if (_rawData.isEmpty)
                    _buildEmptyState()
                  else ...[
                    _buildTrafficSummaryCards(isDesktop),
                    const SizedBox(height: 16),
                    _buildBusinessPerformanceCards(isDesktop),

                    const SizedBox(height: 32),
                    _buildInteractiveChartSection(isDesktop),
                  ]
                ],
              ),
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

  Widget _buildCustomHeader() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('RETAIL INTELLIGENCE', style: TextStyle(fontSize: 12, color: Colors.blue[700], fontWeight: FontWeight.bold, letterSpacing: 2)),
            const SizedBox(height: 4),
            const Text('Traffic Analytics', style: TextStyle(fontSize: 36, fontWeight: FontWeight.w800, color: Colors.black87, letterSpacing: -1)),
            if (_selectedFolderPath != null)
              Padding(
                padding: const EdgeInsets.only(top: 8.0),
                child: Text('Source: $_selectedFolderPath', style: const TextStyle(color: Colors.black54, fontSize: 12)),
              ),
            if (_isFtpRunning)
              Padding(
                padding: const EdgeInsets.only(top: 12.0),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(color: Colors.green.withOpacity(0.1), borderRadius: BorderRadius.circular(8), border: Border.all(color: Colors.green.withOpacity(0.3))),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.wifi_tethering, color: Colors.green[700], size: 16),
                      const SizedBox(width: 8),
                      Text('FTP Active: ftp://$_localIp:2121', style: TextStyle(color: Colors.green[700], fontSize: 12, fontWeight: FontWeight.bold)),
                    ],
                  ),
                ),
              ),
          ],
        ),

        Row(
          children: [
            if (_rawData.isNotEmpty) ...[
              GlassCard(
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
                child: InkWell(
                  onTap: _showPosEntryDialog,
                  child: Row(
                    children: [
                      Icon(Icons.point_of_sale, color: Colors.orange[700]),
                      const SizedBox(width: 8),
                      const Text('ENTER POS', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: Colors.black87, letterSpacing: 1)),
                    ],
                  ),
                ),
              ),
              const SizedBox(width: 16),

              GlassCard(
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
                child: InkWell(
                  onTap: _showExportMenu,
                  child: Row(
                    children: [
                      Icon(Icons.download, color: Colors.pink[500]),
                      const SizedBox(width: 8),
                      const Text('EXPORT', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: Colors.black87, letterSpacing: 1)),
                    ],
                  ),
                ),
              ),
              const SizedBox(width: 16),
            ],

            GlassCard(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
              child: InkWell(
                onTap: () async {
                  await Navigator.push(context, MaterialPageRoute(builder: (context) => const FtpServerScreen()));
                  _checkFtpStatus();
                },
                child: const Row(
                  children: [
                    Icon(Icons.wifi_tethering, color: Colors.black54),
                    SizedBox(width: 8),
                    Text('FTP SERVER', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: Colors.black87, letterSpacing: 1)),
                  ],
                ),
              ),
            ),
            const SizedBox(width: 16),

            GlassCard(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
              child: InkWell(
                onTap: _pickFolderAndLoadData,
                child: Row(
                  children: [
                    Icon(Icons.drive_folder_upload, color: Colors.blue[700]),
                    const SizedBox(width: 12),
                    const Text('IMPORT DATA', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: Colors.black87, letterSpacing: 1)),
                  ],
                ),
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
        child: GlassCard(
          padding: const EdgeInsets.all(60),
          child: Column(
            children: const [
              Icon(Icons.radar, size: 80, color: Colors.black12),
              SizedBox(height: 24),
              Text('System Standby', style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: Colors.black87)),
              SizedBox(height: 12),
              Text('Connect to a data source to begin tracking algorithms.', style: TextStyle(color: Colors.black54)),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildTrafficSummaryCards(bool isDesktop) {
    int totalVisitors = (_totalIn + _totalOut) ~/ 2;

    final cards = [
      _buildMetricCard('TOTAL IN', _totalIn.toString(), Icons.login, Colors.blue[600]!),
      _buildMetricCard('TOTAL OUT', _totalOut.toString(), Icons.logout, Colors.pink[500]!),
      _buildMetricCard('TOTAL VISITORS', totalVisitors.toString(), Icons.groups, Colors.green[600]!),
      _buildMetricCard('PEAK HOUR', _peakHour, Icons.trending_up, Colors.deepPurple[400]!),
    ];

    if (isDesktop) {
      return Row(children: cards.map((c) => Expanded(child: Padding(padding: const EdgeInsets.symmetric(horizontal: 6), child: c))).toList());
    } else {
      return Wrap(spacing: 12, runSpacing: 12, children: cards.map((c) => SizedBox(width: MediaQuery.of(context).size.width / 2 - 40, child: c)).toList());
    }
  }

  Widget _buildBusinessPerformanceCards(bool isDesktop) {
    int totalVisitors = (_totalIn + _totalOut) ~/ 2;

    double conversionRate = totalVisitors > 0 ? (_currentClients / totalVisitors) * 100 : 0.0;
    double avgBasket = _currentClients > 0 ? (_currentCa / _currentClients) : 0.0;
    double upt = _currentClients > 0 ? (_currentArticles / _currentClients) : 0.0;

    final cards = [
      _buildMetricCard('CONVERSION RATE', '${conversionRate.toStringAsFixed(1)}%', Icons.track_changes, Colors.orange[600]!),
      _buildMetricCard('REVENUE (CA)', _currentCa.toStringAsFixed(2), Icons.attach_money, Colors.orange[600]!),
      _buildMetricCard('AVG BASKET', avgBasket.toStringAsFixed(2), Icons.shopping_cart, Colors.orange[600]!),
      _buildMetricCard('U.P.T', upt.toStringAsFixed(2), Icons.layers, Colors.orange[600]!),
    ];

    if (isDesktop) {
      return Row(children: cards.map((c) => Expanded(child: Padding(padding: const EdgeInsets.symmetric(horizontal: 6), child: c))).toList());
    } else {
      return Wrap(spacing: 12, runSpacing: 12, children: cards.map((c) => SizedBox(width: MediaQuery.of(context).size.width / 2 - 40, child: c)).toList());
    }
  }

  Widget _buildMetricCard(String title, String value, IconData icon, Color color) {
    return GlassCard(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(title, style: const TextStyle(fontSize: 12, color: Colors.black54, fontWeight: FontWeight.bold, letterSpacing: 1.5)),
              Icon(icon, color: color, size: 20),
            ],
          ),
          const SizedBox(height: 16),
          Text(value, style: const TextStyle(fontSize: 28, fontWeight: FontWeight.w800, color: Colors.black87, letterSpacing: -1)),
        ],
      ),
    );
  }

  Widget _buildInteractiveChartSection(bool isDesktop) {
    return GlassCard(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Wrap(
            alignment: WrapAlignment.spaceBetween,
            crossAxisAlignment: WrapCrossAlignment.center,
            runSpacing: 16,
            children: [
              Container(
                decoration: BoxDecoration(color: Colors.grey[100], borderRadius: BorderRadius.circular(12)),
                padding: const EdgeInsets.all(4),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    IconButton(icon: const Icon(Icons.chevron_left, color: Colors.black54), onPressed: () => _shiftDate(-1)),
                    GestureDetector(
                      onTap: _pickDateRange,
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        child: Text(_getFormattedDateString(), style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.black87)),
                      ),
                    ),
                    IconButton(icon: const Icon(Icons.chevron_right, color: Colors.black54), onPressed: () => _shiftDate(1)),
                  ],
                ),
              ),

              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (_availableCameras.length > 1)
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      margin: const EdgeInsets.only(right: 16),
                      decoration: BoxDecoration(color: Colors.blue.withOpacity(0.1), borderRadius: BorderRadius.circular(8)),
                      child: DropdownButtonHideUnderline(
                        child: DropdownButton<String>(
                          value: _selectedCamera, dropdownColor: Colors.white, icon: Icon(Icons.camera_alt, color: Colors.blue[700], size: 18), style: TextStyle(color: Colors.blue[700], fontWeight: FontWeight.bold),
                          items: _availableCameras.map((String camera) { return DropdownMenuItem<String>(value: camera, child: Padding(padding: const EdgeInsets.only(left: 8.0), child: Text(camera == 'All Doors' ? 'All Doors' : camera.toUpperCase()))); }).toList(),
                          onChanged: (String? newValue) { if (newValue != null) { setState(() { _selectedCamera = newValue; _applyFilter(); }); } },
                        ),
                      ),
                    ),

                  DropdownButtonHideUnderline(
                    child: DropdownButton<ChartFilter>(
                      value: _currentFilter, dropdownColor: Colors.white, icon: const Icon(Icons.timeline, color: Colors.black54), style: const TextStyle(color: Colors.black87, fontWeight: FontWeight.bold),
                      items: const [ DropdownMenuItem(value: ChartFilter.hourly, child: Text(' Hourly Timeline')), DropdownMenuItem(value: ChartFilter.daily, child: Text(' Daily Timeline')) ],
                      onChanged: (ChartFilter? newValue) { if (newValue != null) { setState(() { _currentFilter = newValue; _applyFilter(); }); } },
                    ),
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 40),

          SizedBox(
            height: 450,
            child: LineChart(
              LineChartData(
                lineTouchData: LineTouchData(
                  touchTooltipData: LineTouchTooltipData(
                    tooltipBgColor: Colors.white.withOpacity(0.95),
                    tooltipRoundedRadius: 8,
                    getTooltipItems: (touchedSpots) {
                      return touchedSpots.map((LineBarSpot touchedSpot) {
                        final textStyle = TextStyle(color: touchedSpot.bar.color ?? Colors.black87, fontWeight: FontWeight.bold, fontSize: 14);
                        String timeText = _displayedData[touchedSpot.x.toInt()].time;
                        String type = touchedSpot.barIndex == 0 ? "In: " : "Out: ";
                        return LineTooltipItem("$timeText\n$type${touchedSpot.y.toInt()}", textStyle);
                      }).toList();
                    },
                  ),
                ),
                gridData: FlGridData(show: true, drawVerticalLine: false, getDrawingHorizontalLine: (value) => FlLine(color: Colors.black.withOpacity(0.05), strokeWidth: 1)),
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
                          return Padding(padding: const EdgeInsets.only(top: 10.0), child: Text(_displayedData[index].time, style: const TextStyle(color: Colors.black54, fontSize: 11, fontWeight: FontWeight.bold)));
                        }
                        return const SizedBox.shrink();
                      },
                    ),
                  ),
                  leftTitles: AxisTitles(
                    sideTitles: SideTitles(showTitles: true, reservedSize: 40, getTitlesWidget: (value, meta) { return Text(value.toInt().toString(), style: const TextStyle(color: Colors.black54, fontSize: 12)); }),
                  ),
                ),
                borderData: FlBorderData(show: false),
                lineBarsData: [
                  LineChartBarData(
                    spots: _displayedData.asMap().entries.map((e) => FlSpot(e.key.toDouble(), e.value.inCount.toDouble())).toList(),
                    isCurved: true, color: Colors.blue[600], barWidth: 3, isStrokeCapRound: true, dotData: FlDotData(show: false),
                    belowBarData: BarAreaData(show: true, gradient: LinearGradient(colors: [Colors.blue.withOpacity(0.2), Colors.blue.withOpacity(0.0)], begin: Alignment.topCenter, end: Alignment.bottomCenter)),
                  ),
                  LineChartBarData(
                    spots: _displayedData.asMap().entries.map((e) => FlSpot(e.key.toDouble(), e.value.outCount.toDouble())).toList(),
                    isCurved: true, color: Colors.pink[500], barWidth: 3, isStrokeCapRound: true, dotData: FlDotData(show: false),
                    belowBarData: BarAreaData(show: true, gradient: LinearGradient(colors: [Colors.pink.withOpacity(0.2), Colors.pink.withOpacity(0.0)], begin: Alignment.topCenter, end: Alignment.bottomCenter)),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class GlassCard extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry padding;

  const GlassCard({Key? key, required this.child, required this.padding}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(16),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
        child: Container(
          padding: padding,
          decoration: BoxDecoration(
            color: Colors.white.withOpacity(0.75), // Frosted white for light theme
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: Colors.white.withOpacity(0.5), width: 1.5), // Soft white border
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.02),
                blurRadius: 10,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: child,
        ),
      ),
    );
  }
}