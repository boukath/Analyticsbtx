// lib/screens/export_screen.dart

import 'dart:io';
import 'package:flutter/foundation.dart'; // 🚀 Required for kIsWeb
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/people_count.dart';
import '../core/data_aggregator.dart';
import '../services/pdf_export_service.dart';
import '../services/csv_export_service.dart';
import 'dashboard_windows.dart'; // To access the ChartFilter enum

class ExportScreen extends StatefulWidget {
  final List<PeopleCount> rawData;
  final List<String> availableCameras;
  final bool isFrench;
  final int workingMinuteStart;
  final int workingMinuteEnd;
  final Map<String, Map<String, num>> posDatabase;
  final String? storeName;
  final String? storeLocation;

  // The callback to fetch more data from Firebase when dates change!
  final Future<Map<String, dynamic>> Function(DateTimeRange)? onFetchWebData;

  const ExportScreen({
    Key? key,
    required this.rawData,
    required this.availableCameras,
    required this.isFrench,
    required this.workingMinuteStart,
    required this.workingMinuteEnd,
    required this.posDatabase,
    this.storeName,
    this.storeLocation,
    this.onFetchWebData,
  }) : super(key: key);

  @override
  State<ExportScreen> createState() => _ExportScreenState();
}

class _ExportScreenState extends State<ExportScreen> {
  late List<PeopleCount> _localRawData;
  late Map<String, Map<String, num>> _localPosDatabase;
  bool _isFetching = false;

  // --- Export State ---
  late String _selectedCamera;
  late DateTimeRange _selectedDateRange;
  ChartFilter _currentFilter = ChartFilter.hourly;

  // 🚀 NEW: State to hold the toggles
  bool _enablePosFeatures = true;
  bool _isSingleEntrance = false; // 🚀 NEW: Track single entrance mode

  // --- Theme Colors ---
  final Color _bgDark = const Color(0xFF0F172A);
  final Color _cardDark = const Color(0xFF1E293B);
  final Color _accentCyan = const Color(0xFF06B6D4);

  @override
  void initState() {
    super.initState();
    // Load the initial data passed from the dashboard
    _localRawData = List.from(widget.rawData);
    _localPosDatabase = Map.from(widget.posDatabase);

    // Default to the first available camera (usually 'All Doors')
    _selectedCamera = widget.availableCameras.isNotEmpty ? widget.availableCameras.first : 'All Doors';

    // Default to today
    DateTime now = DateTime.now();
    _selectedDateRange = DateTimeRange(
        start: DateTime(now.year, now.month, now.day),
        end: DateTime(now.year, now.month, now.day)
    );

    // 🚀 Fetch settings immediately
    _loadSettings();
  }

  // 🚀 NEW: Load the global settings to see if POS and Single Entrance should be active
  Future<void> _loadSettings() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      // Check the key depending on if we are on Web or Windows
      _enablePosFeatures = kIsWeb
          ? (prefs.getBool('web_enable_pos_features') ?? true)
          : (prefs.getBool('enable_pos_features') ?? true);

      // 🚀 NEW: Load Single Entrance Mode
      _isSingleEntrance = prefs.getBool('is_single_entrance') ?? false;

      // If single entrance is forced, lock the camera selection to global!
      if (_isSingleEntrance) {
        _selectedCamera = 'All Doors';
      }
    });
  }

  Future<void> _handleDateRangeChange(DateTimeRange newRange) async {
    setState(() {
      _selectedDateRange = newRange;
      _isFetching = true; // Start loading spinner
    });

    if (widget.onFetchWebData != null) {
      // ☁️ WEB: Ask the dashboard to fetch the new dates from Firebase
      var fetched = await widget.onFetchWebData!(newRange);
      if (mounted) {
        setState(() {
          _localRawData = fetched['rawData'] ?? [];
          _localPosDatabase = fetched['posDatabase'] ?? {};
          _isFetching = false; // Stop loading spinner
        });
      }
    } else {
      // 💻 WINDOWS: Data is already in memory, just stop the loader
      setState(() {
        _isFetching = false;
      });
    }
  }

  // --- Core Logic: Filter and Export ---
  Future<void> _processAndExport(String format) async {
    if (_localRawData.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text(widget.isFrench ? "Aucune donnée disponible pour cette période." : "No data available for this period."),
              backgroundColor: Colors.redAccent
          )
      );
      return;
    }

    // 1. Filter Data
    List<PeopleCount> filteredData = _localRawData.where((item) {
      if (_selectedCamera != 'All Doors' && item.doorName != _selectedCamera) return false;

      var timeParts = item.time.split(':');
      int hour = timeParts.isNotEmpty ? (int.tryParse(timeParts[0]) ?? 0) : 0;
      int minute = timeParts.length > 1 ? (int.tryParse(timeParts[1]) ?? 0) : 0;
      if ((hour * 60) + minute < widget.workingMinuteStart || (hour * 60) + minute > widget.workingMinuteEnd) return false;

      var dateParts = item.date.split('/');
      if (dateParts.length != 3) return true;
      DateTime rowDate = DateTime(int.parse(dateParts[2]), int.parse(dateParts[1]), int.parse(dateParts[0]));
      return rowDate.isAfter(_selectedDateRange.start.subtract(const Duration(days: 1))) &&
          rowDate.isBefore(_selectedDateRange.end.add(const Duration(days: 1)));
    }).toList();

    List<PeopleCount> finalData = _currentFilter == ChartFilter.daily ? DataAggregator.aggregateByDay(filteredData) : DataAggregator.aggregateByHour(filteredData);
    if (finalData.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text(widget.isFrench ? "Aucune donnée dans cette plage." : "No data found for this range."),
              backgroundColor: Colors.orangeAccent
          )
      );
      return;
    }

    // 2. Compute Totals
    int totalIn = 0, totalOut = 0, maxTraffic = 0;
    String peakHour = "--:--";
    for (var item in finalData) {
      totalIn += item.inCount; totalOut += item.outCount;
      int visitors = (item.inCount + item.outCount) ~/ 2;
      if (visitors > maxTraffic) { maxTraffic = visitors; peakHour = item.time; }
    }
    int totalVisitors = (totalIn + totalOut) ~/ 2;

    double totalRevenue = 0, upt = 0, avgBasket = 0, conversionRate = 0;
    int totalClients = 0, totalArticles = 0;

    // Only compute POS numbers if the feature is enabled!
    if (_enablePosFeatures) {
      for (DateTime d = _selectedDateRange.start; d.isBefore(_selectedDateRange.end.add(const Duration(days: 1))); d = d.add(const Duration(days: 1))) {
        String dateStr = "${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}";
        if (_localPosDatabase.containsKey(dateStr)) {
          totalRevenue += _localPosDatabase[dateStr]!['ca'] ?? 0;
          totalClients += (_localPosDatabase[dateStr]!['clients'] ?? 0).toInt();
          totalArticles += (_localPosDatabase[dateStr]!['articles'] ?? 0).toInt();
        }
      }

      conversionRate = totalVisitors > 0 ? (totalClients / totalVisitors) * 100 : 0.0;
      avgBasket = totalClients > 0 ? (totalRevenue / totalClients) : 0.0;
      upt = totalClients > 0 ? (totalArticles / totalClients) : 0.0;
    }

    // 3. DIRECTORY & PREFERENCES MANAGEMENT
    final prefs = await SharedPreferences.getInstance();

    // Get the Store Profile Data for the PDF
    String storeName = widget.storeName ?? prefs.getString('store_name') ?? "My Store";
    String storeLocation = widget.storeLocation ?? prefs.getString('store_location') ?? "MAIN BRANCH";
    String? storeLogoPath = prefs.getString('store_logo_path');

    // 4. SMART FILE NAMING
    String sStart = "${_selectedDateRange.start.year}-${_selectedDateRange.start.month.toString().padLeft(2, '0')}-${_selectedDateRange.start.day.toString().padLeft(2, '0')}";
    String sEnd = "${_selectedDateRange.end.year}-${_selectedDateRange.end.month.toString().padLeft(2, '0')}-${_selectedDateRange.end.day.toString().padLeft(2, '0')}";
    String sCam = _selectedCamera.replaceAll(' ', '_');

    String niceFileName;
    if (sStart == sEnd) {
      niceFileName = "Report_Daily_${sCam}_$sStart";
    } else {
      niceFileName = "Report_Period_${sCam}_${sStart}_to_$sEnd";
    }

    String rType = _currentFilter == ChartFilter.hourly ? "Hourly Breakdown" : "Daily Summary Breakdown";

    String cLabel = _selectedCamera == 'All Doors'
        ? (widget.isFrench ? 'Global (Toutes les Portes)' : 'Global (All Doors)')
        : _selectedCamera;

    String dateRangeStr = sStart == sEnd ? sStart : "$sStart to $sEnd";

    // 5. CROSS-PLATFORM PATH RESOLUTION
    String finalOutputPath = "";
    String folderPathToOpen = "";

    if (kIsWeb) {
      finalOutputPath = "$niceFileName.$format";
    } else {
      String baseDir = prefs.getString('saved_data_folder') ?? 'C:\\comptage';
      String reportsDirPath = '$baseDir${Platform.pathSeparator}Reports';
      Directory reportsDir = Directory(reportsDirPath);

      if (!await reportsDir.exists()) {
        await reportsDir.create(recursive: true);
      }

      finalOutputPath = "${reportsDir.path}${Platform.pathSeparator}$niceFileName.$format";
      folderPathToOpen = reportsDir.path;
    }

    // 6. Trigger the Export Services
    try {
      if (format == 'pdf') {
        await PdfExportService.generateAndSaveReport(
          reportType: rType,
          dateRangeText: dateRangeStr,
          cameraName: cLabel,
          data: finalData,
          totalIn: totalIn,
          totalOut: totalOut,
          peakHour: peakHour,
          outputPath: finalOutputPath,
          storeName: storeName,
          storeLocation: storeLocation,
          storeLogoPath: storeLogoPath,
          revenue: totalRevenue,
          clients: totalClients,
          conversionRate: conversionRate,
          avgBasket: avgBasket,
          upt: upt,
          enablePosFeatures: _enablePosFeatures,
          isSingleEntrance: _isSingleEntrance, // 🚀 NEW: Passed flag to PDF
        );
      } else {
        await CsvExportService.generateAndSaveCsv(
          reportType: rType,
          dateRangeText: dateRangeStr,
          cameraName: cLabel,
          data: finalData,
          totalIn: totalIn,
          totalOut: totalOut,
          peakHour: peakHour,
          outputPath: finalOutputPath,
          revenue: totalRevenue,
          clients: totalClients,
          conversionRate: conversionRate,
          avgBasket: avgBasket,
          upt: upt,
          enablePosFeatures: _enablePosFeatures,
          isSingleEntrance: _isSingleEntrance, // 🚀 NEW: Passed flag to CSV
        );
      }

      _showSuccessDialog(finalOutputPath, folderPathToOpen, format.toUpperCase());

    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(widget.isFrench ? "Erreur d'exportation." : "Export error: $e"),
            backgroundColor: Colors.redAccent,
          )
      );
    }
  }

  // 7. WEB-SAFE SUCCESS UI
  void _showSuccessDialog(String filePath, String folderPath, String fileType) {
    showDialog(
        context: context,
        builder: (context) => AlertDialog(
          backgroundColor: _cardDark,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16), side: const BorderSide(color: Colors.greenAccent)),
          title: Row(
            children: [
              const Icon(Icons.check_circle, color: Colors.greenAccent, size: 30),
              const SizedBox(width: 12),
              Text(widget.isFrench ? "Rapport Sauvegardé!" : "Report Saved!", style: const TextStyle(color: Colors.white)),
            ],
          ),
          content: Text(
            kIsWeb
                ? (widget.isFrench
                ? "Le fichier $fileType a été généré et le téléchargement a commencé."
                : "The $fileType was successfully generated and the download has started.")
                : (widget.isFrench
                ? "Le fichier $fileType a été généré et enregistré dans :\n\n$filePath"
                : "The $fileType was successfully generated and saved to:\n\n$filePath"),
            style: const TextStyle(color: Colors.white70),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text("CLOSE", style: TextStyle(color: Colors.white54)),
            ),
            if (!kIsWeb)
              ElevatedButton.icon(
                style: ElevatedButton.styleFrom(backgroundColor: Colors.greenAccent, foregroundColor: Colors.black),
                onPressed: () {
                  Navigator.pop(context);
                  if (Platform.isWindows) {
                    Process.run('explorer.exe', [folderPath]);
                  }
                },
                icon: const Icon(Icons.folder_open),
                label: Text(widget.isFrench ? "OUVRIR LE DOSSIER" : "OPEN FOLDER", style: const TextStyle(fontWeight: FontWeight.bold)),
              ),
          ],
        )
    );
  }

  void _applyPreset(String presetType) {
    DateTime end = DateTime.now();
    DateTime start = end;

    if (presetType == 'Daily') {
      start = end;
      _currentFilter = ChartFilter.hourly;
    }
    else if (presetType == 'Weekly') {
      start = end.subtract(const Duration(days: 6));
      _currentFilter = ChartFilter.daily;
    }
    else if (presetType == 'Monthly') {
      start = end.subtract(const Duration(days: 30));
      _currentFilter = ChartFilter.daily;
    }
    else if (presetType == 'Yearly') {
      start = DateTime(end.year, 1, 1);
      _currentFilter = ChartFilter.daily;
    }
    else if (presetType == 'AllTime') {
      start = DateTime(2020, 1, 1);
      _currentFilter = ChartFilter.daily;
    }

    _handleDateRangeChange(DateTimeRange(start: start, end: end));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _bgDark,
      appBar: AppBar(
        backgroundColor: Colors.transparent, elevation: 0,
        leading: IconButton(icon: Icon(Icons.arrow_back, color: _accentCyan), onPressed: () => Navigator.pop(context)),
        title: Text(widget.isFrench ? 'CENTRE D\'EXPORTATION' : 'DATA EXPORT CENTER', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, letterSpacing: 1.5)),
      ),
      body: Center(
        child: SingleChildScrollView(
          child: Container(
            constraints: const BoxConstraints(maxWidth: 600), padding: const EdgeInsets.all(32.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Icon(Icons.analytics, size: 80, color: _accentCyan.withOpacity(0.5)),
                const SizedBox(height: 24),
                Text(
                  // 🚀 Smart subtitle updates based on mode!
                    _enablePosFeatures
                        ? (widget.isFrench ? 'Générez des rapports précis avec les données de trafic et de caisse.' : 'Generate precise reports with injected traffic and POS data.')
                        : (widget.isFrench ? 'Générez des rapports détaillés sur le flux des visiteurs.' : 'Generate detailed footfall traffic reports.'),
                    textAlign: TextAlign.center,
                    style: const TextStyle(color: Colors.white54, fontSize: 16)
                ),
                const SizedBox(height: 48),

                // 🚀 Conditionally show the Camera Selector
                if (!_isSingleEntrance) ...[
                  Text(widget.isFrench ? '1. CHOISIR LA CAMÉRA' : '1. SELECT CAMERA', style: TextStyle(color: _accentCyan, fontWeight: FontWeight.bold, letterSpacing: 1)),
                  const SizedBox(height: 12),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                    decoration: BoxDecoration(color: _cardDark, borderRadius: BorderRadius.circular(12), border: Border.all(color: Colors.white.withOpacity(0.1))),
                    child: DropdownButtonHideUnderline(
                      child: DropdownButton<String>(
                        isExpanded: true, dropdownColor: _cardDark, value: _selectedCamera, icon: const Icon(Icons.videocam, color: Colors.white54), style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16),
                        items: widget.availableCameras.map((String cam) => DropdownMenuItem<String>(value: cam, child: Text(cam == 'All Doors' ? (widget.isFrench ? 'Toutes les Portes' : 'All Doors') : cam.toUpperCase()))).toList(),
                        onChanged: (String? val) { if (val != null) setState(() => _selectedCamera = val); },
                      ),
                    ),
                  ),
                  const SizedBox(height: 32),
                ],

                // 🚀 Dynamic numbering: If Single Entrance is ON, this becomes step 1!
                Text(widget.isFrench ? (_isSingleEntrance ? '1. PLAGE DE DATES' : '2. PLAGE DE DATES') : (_isSingleEntrance ? '1. DATE RANGE' : '2. DATE RANGE'), style: TextStyle(color: _accentCyan, fontWeight: FontWeight.bold, letterSpacing: 1)),
                const SizedBox(height: 12),

                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    _buildPresetButton('Daily', widget.isFrench ? 'Aujourd\'hui' : 'Today'),
                    _buildPresetButton('Weekly', widget.isFrench ? '7 Jours' : '7 Days'),
                    _buildPresetButton('Monthly', widget.isFrench ? '30 Jours' : '30 Days'),
                    _buildPresetButton('Yearly', widget.isFrench ? 'Cette Année' : 'This Year'),
                    _buildPresetButton('AllTime', widget.isFrench ? 'Tout le temps' : 'All Time'),
                  ],
                ),
                const SizedBox(height: 16),

                InkWell(
                    onTap: () async {
                      DateTimeRange? picked = await showDateRangePicker(
                          context: context,
                          initialEntryMode: DatePickerEntryMode.input,
                          firstDate: DateTime(2020),
                          lastDate: DateTime.now().add(const Duration(days: 3650)),
                          initialDateRange: _selectedDateRange,
                          builder: (context, child) => Theme(
                              data: ThemeData.dark().copyWith(
                                  colorScheme: ColorScheme.dark(
                                      primary: _accentCyan,
                                      onPrimary: Colors.black,
                                      surface: _cardDark,
                                      onSurface: Colors.white
                                  )
                              ),
                              child: child!
                          )
                      );
                      if (picked != null) _handleDateRangeChange(picked);
                    },
                    child: Container(
                        padding: const EdgeInsets.all(20), decoration: BoxDecoration(color: _cardDark, borderRadius: BorderRadius.circular(12), border: Border.all(color: Colors.white.withOpacity(0.1))),
                        child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                          Text("${_selectedDateRange.start.year}-${_selectedDateRange.start.month.toString().padLeft(2, '0')}-${_selectedDateRange.start.day.toString().padLeft(2, '0')}   →   ${_selectedDateRange.end.year}-${_selectedDateRange.end.month.toString().padLeft(2, '0')}-${_selectedDateRange.end.day.toString().padLeft(2, '0')}", style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.white, fontSize: 16)),
                          Icon(Icons.edit_calendar, color: _accentCyan)
                        ])
                    )
                ),
                const SizedBox(height: 32),

                // 🚀 Dynamic numbering: If Single Entrance is ON, this becomes step 2!
                Text(widget.isFrench ? (_isSingleEntrance ? '2. INTERVALLE DE DONNÉES' : '3. INTERVALLE DE DONNÉES') : (_isSingleEntrance ? '2. DATA INTERVAL' : '3. DATA INTERVAL'), style: TextStyle(color: _accentCyan, fontWeight: FontWeight.bold, letterSpacing: 1)),
                const SizedBox(height: 12),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                  decoration: BoxDecoration(color: _cardDark, borderRadius: BorderRadius.circular(12), border: Border.all(color: Colors.white.withOpacity(0.1))),
                  child: DropdownButtonHideUnderline(
                    child: DropdownButton<ChartFilter>(
                      isExpanded: true, dropdownColor: _cardDark, value: _currentFilter, icon: const Icon(Icons.access_time, color: Colors.white54), style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16),
                      items: [DropdownMenuItem(value: ChartFilter.hourly, child: Text(widget.isFrench ? 'Répartition Horaire (Chaque Heure)' : 'Hourly Breakdown (Every Hour)')), DropdownMenuItem(value: ChartFilter.daily, child: Text(widget.isFrench ? 'Résumé Journalier (Chaque Jour)' : 'Daily Summary (Every Day)'))],
                      onChanged: (ChartFilter? val) { if (val != null) setState(() => _currentFilter = val); },
                    ),
                  ),
                ),
                const SizedBox(height: 48),

                _isFetching
                    ? Center(child: CircularProgressIndicator(color: _accentCyan))
                    : Row(children: [
                  Expanded(child: ElevatedButton.icon(style: ElevatedButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 20), backgroundColor: _accentCyan, foregroundColor: Colors.black, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))), icon: const Icon(Icons.picture_as_pdf), label: Text(widget.isFrench ? 'GÉNÉRER PDF' : 'GENERATE PDF', style: const TextStyle(fontWeight: FontWeight.w900, letterSpacing: 1)), onPressed: () => _processAndExport('pdf'))),
                  const SizedBox(width: 16),
                  Expanded(child: ElevatedButton.icon(style: ElevatedButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 20), backgroundColor: Colors.greenAccent, foregroundColor: Colors.black, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))), icon: const Icon(Icons.table_chart), label: Text(widget.isFrench ? 'GÉNÉRER CSV' : 'GENERATE CSV', style: const TextStyle(fontWeight: FontWeight.w900, letterSpacing: 1)), onPressed: () => _processAndExport('csv')))
                ]),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildPresetButton(String presetId, String label) {
    return OutlinedButton(
        style: OutlinedButton.styleFrom(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            foregroundColor: Colors.white,
            side: BorderSide(color: Colors.white.withOpacity(0.2)),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8))
        ),
        onPressed: () => _applyPreset(presetId),
        child: Text(label, style: const TextStyle(fontWeight: FontWeight.bold))
    );
  }
}