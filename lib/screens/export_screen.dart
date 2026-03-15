// lib/screens/export_screen.dart

import 'dart:io';
import 'package:flutter/foundation.dart'; // 🚀 NEW: Required for kIsWeb
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

  const ExportScreen({
    Key? key,
    required this.rawData,
    required this.availableCameras,
    required this.isFrench,
    required this.workingMinuteStart,
    required this.workingMinuteEnd,
    required this.posDatabase,
  }) : super(key: key);

  @override
  State<ExportScreen> createState() => _ExportScreenState();
}

class _ExportScreenState extends State<ExportScreen> {
  // --- Export State ---
  late String _selectedCamera;
  late DateTimeRange _selectedDateRange;
  ChartFilter _currentFilter = ChartFilter.hourly;

  // --- Theme Colors (matching your dashboard) ---
  final Color _bgDark = const Color(0xFF0F172A);
  final Color _cardDark = const Color(0xFF1E293B);
  final Color _accentCyan = const Color(0xFF06B6D4);

  @override
  void initState() {
    super.initState();
    // Default to the first available camera (usually 'All Doors')
    _selectedCamera = widget.availableCameras.isNotEmpty ? widget.availableCameras.first : 'All Doors';

    // Default to today
    DateTime now = DateTime.now();
    _selectedDateRange = DateTimeRange(
        start: DateTime(now.year, now.month, now.day),
        end: DateTime(now.year, now.month, now.day)
    );
  }

  // --- Core Logic: Filter and Export ---
  Future<void> _processAndExport(String format) async {
    if (widget.rawData.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text(widget.isFrench ? "Aucune donnée disponible." : "No data available."),
              backgroundColor: Colors.redAccent
          )
      );
      return;
    }

    // 1. Filter Data
    List<PeopleCount> filteredData = widget.rawData.where((item) {
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

    for (DateTime d = _selectedDateRange.start; d.isBefore(_selectedDateRange.end.add(const Duration(days: 1))); d = d.add(const Duration(days: 1))) {
      String dateStr = "${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}";
      if (widget.posDatabase.containsKey(dateStr)) {
        totalRevenue += widget.posDatabase[dateStr]!['ca'] ?? 0;
        totalClients += (widget.posDatabase[dateStr]!['clients'] ?? 0).toInt();
        totalArticles += (widget.posDatabase[dateStr]!['articles'] ?? 0).toInt();
      }
    }

    conversionRate = totalVisitors > 0 ? (totalClients / totalVisitors) * 100 : 0.0;
    avgBasket = totalClients > 0 ? (totalRevenue / totalClients) : 0.0;
    upt = totalClients > 0 ? (totalArticles / totalClients) : 0.0;

    // 3. DIRECTORY & PREFERENCES MANAGEMENT
    final prefs = await SharedPreferences.getInstance();

    // Get the Store Profile Data for the PDF
    String storeName = prefs.getString('store_name') ?? "My Store";
    String storeLocation = prefs.getString('store_location') ?? "MAIN BRANCH";
    String? storeLogoPath = prefs.getString('store_logo_path');

    // 🚀 4. SMART FILE NAMING
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

    // 🚀 5. CROSS-PLATFORM PATH RESOLUTION
    String finalOutputPath = "";
    String folderPathToOpen = "";

    if (kIsWeb) {
      // 🌐 WEB: We just pass a dummy name, the browser will download it automatically
      finalOutputPath = "$niceFileName.$format";
    } else {
      // 💻 WINDOWS: Resolve the physical directory
      String baseDir = prefs.getString('saved_data_folder') ?? 'C:\\comptage';
      String reportsDirPath = '$baseDir${Platform.pathSeparator}Reports';
      Directory reportsDir = Directory(reportsDirPath);

      // Create the "Reports" folder if it doesn't exist
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
        );
      }

      // Show dynamic success dialog
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

  // 🚀 7. WEB-SAFE SUCCESS UI
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
            // Show a different message based on whether it's downloading via Web or saving locally
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
            // 🌐 WEB SAFETY: Hide the "Open Folder" button on the web completely
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
    if (presetType == 'Daily') { start = end; _currentFilter = ChartFilter.hourly; }
    else if (presetType == 'Weekly') { start = end.subtract(const Duration(days: 6)); _currentFilter = ChartFilter.daily; }
    else if (presetType == 'Monthly') { start = DateTime(end.year, end.month - 1, end.day); _currentFilter = ChartFilter.daily; }
    setState(() => _selectedDateRange = DateTimeRange(start: start, end: end));
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
                Text(widget.isFrench ? 'Générez des rapports précis avec les données de trafic et de caisse.' : 'Generate precise reports with injected traffic and POS data.', textAlign: TextAlign.center, style: const TextStyle(color: Colors.white54, fontSize: 16)),
                const SizedBox(height: 48),

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

                Text(widget.isFrench ? '2. PLAGE DE DATES' : '2. DATE RANGE', style: TextStyle(color: _accentCyan, fontWeight: FontWeight.bold, letterSpacing: 1)),
                const SizedBox(height: 12),
                Row(children: [
                  Expanded(child: _buildPresetButton('Daily', widget.isFrench ? 'Aujourd\'hui' : 'Today')), const SizedBox(width: 8),
                  Expanded(child: _buildPresetButton('Weekly', widget.isFrench ? '7 Jours' : '7 Days')), const SizedBox(width: 8),
                  Expanded(child: _buildPresetButton('Monthly', widget.isFrench ? '30 Jours' : '30 Days')),
                ]),
                const SizedBox(height: 16),
                InkWell(
                    onTap: () async {
                      DateTimeRange? picked = await showDateRangePicker(context: context, firstDate: DateTime(2020), lastDate: DateTime.now(), initialDateRange: _selectedDateRange, builder: (context, child) => Theme(data: ThemeData.dark().copyWith(colorScheme: ColorScheme.dark(primary: _accentCyan, surface: _cardDark)), child: child!));
                      if (picked != null) setState(() => _selectedDateRange = picked);
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

                Text(widget.isFrench ? '3. INTERVALLE DE DONNÉES' : '3. DATA INTERVAL', style: TextStyle(color: _accentCyan, fontWeight: FontWeight.bold, letterSpacing: 1)),
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

                Row(children: [
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
    return OutlinedButton(style: OutlinedButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 16), foregroundColor: Colors.white, side: BorderSide(color: Colors.white.withOpacity(0.2)), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8))), onPressed: () => _applyPreset(presetId), child: Text(label, style: const TextStyle(fontWeight: FontWeight.bold)));
  }
}