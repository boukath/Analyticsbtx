// lib/screens/export_screen.dart

import 'package:flutter/material.dart';
import '../models/people_count.dart';
import '../core/data_aggregator.dart';
import '../services/pdf_export_service.dart';
import '../services/csv_export_service.dart';
import 'dashboard_screen.dart'; // To access the ChartFilter enum

class ExportScreen extends StatefulWidget {
  final List<PeopleCount> rawData;
  final List<String> availableCameras;
  final bool isFrench;
  final int workingMinuteStart;
  final int workingMinuteEnd;
  final Map<String, Map<String, num>> posDatabase; // 🚀 NEW: Added POS Database

  const ExportScreen({
    Key? key,
    required this.rawData,
    required this.availableCameras,
    required this.isFrench,
    required this.workingMinuteStart,
    required this.workingMinuteEnd,
    required this.posDatabase, // 🚀 NEW
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
  final Color _accentMagenta = const Color(0xFFD946EF);

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
            content: Text(widget.isFrench ? "Aucune donnée disponible pour l'exportation." : "No data available to export."),
            backgroundColor: Colors.redAccent,
          )
      );
      return;
    }

    // 1. Filter the raw data based on screen selections
    List<PeopleCount> filteredData = widget.rawData.where((item) {
      // Filter by Camera
      if (_selectedCamera != 'All Doors' && item.doorName != _selectedCamera) return false;

      // Filter by Working Hours
      var timeParts = item.time.split(':');
      int hour = timeParts.isNotEmpty ? (int.tryParse(timeParts[0]) ?? 0) : 0;
      int minute = timeParts.length > 1 ? (int.tryParse(timeParts[1]) ?? 0) : 0;
      int totalMinutes = (hour * 60) + minute;
      if (totalMinutes < widget.workingMinuteStart || totalMinutes > widget.workingMinuteEnd) return false;

      // Filter by Date Range
      var dateParts = item.date.split('/');
      if (dateParts.length != 3) return true;
      int day = int.parse(dateParts[0]), month = int.parse(dateParts[1]), year = int.parse(dateParts[2]);
      DateTime rowDate = DateTime(year, month, day);
      return rowDate.isAfter(_selectedDateRange.start.subtract(const Duration(days: 1))) &&
          rowDate.isBefore(_selectedDateRange.end.add(const Duration(days: 1)));
    }).toList();

    // 2. Aggregate Data
    List<PeopleCount> finalData;
    if (_currentFilter == ChartFilter.daily) {
      finalData = DataAggregator.aggregateByDay(filteredData);
    } else {
      finalData = DataAggregator.aggregateByHour(filteredData);
    }

    if (finalData.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(widget.isFrench ? "Aucune donnée dans cette plage de dates." : "No data found for this date range."),
            backgroundColor: Colors.orangeAccent,
          )
      );
      return;
    }

    // 3. Calculate Traffic Totals and Peak Hour
    int totalIn = 0;
    int totalOut = 0;
    int maxTraffic = 0;
    String peakHour = "--:--";

    for (var item in finalData) {
      totalIn += item.inCount;
      totalOut += item.outCount;
      int totalVisitorsForHour = (item.inCount + item.outCount) ~/ 2;
      if (totalVisitorsForHour > maxTraffic) {
        maxTraffic = totalVisitorsForHour;
        peakHour = item.time;
      }
    }

    int totalVisitors = (totalIn + totalOut) ~/ 2;

    // 🚀 4. NEW: POS & Conversion Rate Calculations
    double totalRevenue = 0;
    int totalClients = 0;
    int totalArticles = 0;

    for (DateTime d = _selectedDateRange.start; d.isBefore(_selectedDateRange.end.add(const Duration(days: 1))); d = d.add(const Duration(days: 1))) {
      String dateStr = "${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}";
      if (widget.posDatabase.containsKey(dateStr)) {
        totalRevenue += widget.posDatabase[dateStr]!['ca'] ?? 0;
        totalClients += (widget.posDatabase[dateStr]!['clients'] ?? 0).toInt();
        totalArticles += (widget.posDatabase[dateStr]!['articles'] ?? 0).toInt();
      }
    }

    double conversionRate = totalVisitors > 0 ? (totalClients / totalVisitors) * 100 : 0.0;
    double avgBasket = totalClients > 0 ? (totalRevenue / totalClients) : 0.0;
    double upt = totalClients > 0 ? (totalArticles / totalClients) : 0.0;

    // 5. Formatting properties
    String rType = _currentFilter == ChartFilter.hourly ? "Hourly Breakdown" : "Daily Summary Breakdown";
    String cLabel = _selectedCamera == 'All Doors' ? 'Global (All Doors)' : 'Camera ${_selectedCamera.toUpperCase()}';
    String sCam = _selectedCamera.replaceAll(' ', '_');
    String sStart = "${_selectedDateRange.start.year}-${_selectedDateRange.start.month.toString().padLeft(2, '0')}-${_selectedDateRange.start.day.toString().padLeft(2, '0')}";
    String sEnd = "${_selectedDateRange.end.year}-${_selectedDateRange.end.month.toString().padLeft(2, '0')}-${_selectedDateRange.end.day.toString().padLeft(2, '0')}";
    String fName = sStart == sEnd ? "TrafficReport_${sCam}_$sStart" : "TrafficReport_${sCam}_${sStart}_to_$sEnd";

    String dateRangeStr = sStart == sEnd ? sStart : "$sStart to $sEnd";

    // 6. Trigger the Export Services with POS Data
    if (format == 'pdf') {
      await PdfExportService.generateAndPreviewReport(
        reportType: rType,
        dateRangeText: dateRangeStr,
        cameraName: cLabel,
        data: finalData,
        totalIn: totalIn,
        totalOut: totalOut,
        peakHour: peakHour,
        customFileName: "$fName.pdf",
        // 🚀 Pass the new variables to the PDF engine
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
        customFileName: "$fName.csv",
        // 🚀 Pass the new variables to the CSV engine
        revenue: totalRevenue,
        clients: totalClients,
        conversionRate: conversionRate,
        avgBasket: avgBasket,
        upt: upt,
      );
    }
  }

  void _applyPreset(String presetType) {
    DateTime end = DateTime.now();
    DateTime start = end;

    if (presetType == 'Daily') {
      start = end;
      _currentFilter = ChartFilter.hourly;
    } else if (presetType == 'Weekly') {
      start = end.subtract(const Duration(days: 6));
      _currentFilter = ChartFilter.daily;
    } else if (presetType == 'Monthly') {
      start = DateTime(end.year, end.month - 1, end.day);
      _currentFilter = ChartFilter.daily;
    }
    setState(() => _selectedDateRange = DateTimeRange(start: start, end: end));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _bgDark,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: Icon(Icons.arrow_back, color: _accentCyan),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text(
            widget.isFrench ? 'CENTRE D\'EXPORTATION' : 'DATA EXPORT CENTER',
            style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, letterSpacing: 1.5)
        ),
      ),
      body: Center(
        child: SingleChildScrollView(
          child: Container(
            constraints: const BoxConstraints(maxWidth: 600),
            padding: const EdgeInsets.all(32.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Icon(Icons.analytics, size: 80, color: _accentCyan.withOpacity(0.5)),
                const SizedBox(height: 24),
                // 🚀 Updated UI text to reflect POS data injection
                Text(
                  widget.isFrench
                      ? 'Générez des rapports précis avec les données de trafic et de caisse.'
                      : 'Generate precise reports with injected traffic and POS data.',
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: Colors.white54, fontSize: 16),
                ),
                const SizedBox(height: 48),

                // 1. SELECT CAMERA
                Text(widget.isFrench ? '1. CHOISIR LA CAMÉRA' : '1. SELECT CAMERA', style: TextStyle(color: _accentCyan, fontWeight: FontWeight.bold, letterSpacing: 1)),
                const SizedBox(height: 12),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                  decoration: BoxDecoration(color: _cardDark, borderRadius: BorderRadius.circular(12), border: Border.all(color: Colors.white.withOpacity(0.1))),
                  child: DropdownButtonHideUnderline(
                    child: DropdownButton<String>(
                      isExpanded: true,
                      dropdownColor: _cardDark,
                      value: _selectedCamera,
                      icon: const Icon(Icons.videocam, color: Colors.white54),
                      style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16),
                      items: widget.availableCameras.map((String cam) {
                        return DropdownMenuItem<String>(
                          value: cam,
                          child: Text(cam == 'All Doors' ? (widget.isFrench ? 'Toutes les Portes' : 'All Doors') : cam.toUpperCase()),
                        );
                      }).toList(),
                      onChanged: (String? val) { if (val != null) setState(() => _selectedCamera = val); },
                    ),
                  ),
                ),
                const SizedBox(height: 32),

                // 2. SELECT DATE RANGE
                Text(widget.isFrench ? '2. PLAGE DE DATES' : '2. DATE RANGE', style: TextStyle(color: _accentCyan, fontWeight: FontWeight.bold, letterSpacing: 1)),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(child: _buildPresetButton('Daily', widget.isFrench ? 'Aujourd\'hui' : 'Today')),
                    const SizedBox(width: 8),
                    Expanded(child: _buildPresetButton('Weekly', widget.isFrench ? '7 Jours' : '7 Days')),
                    const SizedBox(width: 8),
                    Expanded(child: _buildPresetButton('Monthly', widget.isFrench ? '30 Jours' : '30 Days')),
                  ],
                ),
                const SizedBox(height: 16),
                InkWell(
                    onTap: () async {
                      DateTimeRange? picked = await showDateRangePicker(
                          context: context,
                          firstDate: DateTime(2020),
                          lastDate: DateTime.now(),
                          initialDateRange: _selectedDateRange,
                          builder: (context, child) => Theme(
                              data: ThemeData.dark().copyWith(
                                colorScheme: ColorScheme.dark(primary: _accentCyan, surface: _cardDark),
                              ),
                              child: child!
                          )
                      );
                      if (picked != null) setState(() => _selectedDateRange = picked);
                    },
                    child: Container(
                        padding: const EdgeInsets.all(20),
                        decoration: BoxDecoration(color: _cardDark, borderRadius: BorderRadius.circular(12), border: Border.all(color: Colors.white.withOpacity(0.1))),
                        child: Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text(
                                  "${_selectedDateRange.start.year}-${_selectedDateRange.start.month.toString().padLeft(2, '0')}-${_selectedDateRange.start.day.toString().padLeft(2, '0')}   →   ${_selectedDateRange.end.year}-${_selectedDateRange.end.month.toString().padLeft(2, '0')}-${_selectedDateRange.end.day.toString().padLeft(2, '0')}",
                                  style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.white, fontSize: 16)
                              ),
                              Icon(Icons.edit_calendar, color: _accentCyan)
                            ]
                        )
                    )
                ),
                const SizedBox(height: 32),

                // 3. SELECT INTERVAL
                Text(widget.isFrench ? '3. INTERVALLE DE DONNÉES' : '3. DATA INTERVAL', style: TextStyle(color: _accentCyan, fontWeight: FontWeight.bold, letterSpacing: 1)),
                const SizedBox(height: 12),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                  decoration: BoxDecoration(color: _cardDark, borderRadius: BorderRadius.circular(12), border: Border.all(color: Colors.white.withOpacity(0.1))),
                  child: DropdownButtonHideUnderline(
                    child: DropdownButton<ChartFilter>(
                      isExpanded: true,
                      dropdownColor: _cardDark,
                      value: _currentFilter,
                      icon: const Icon(Icons.access_time, color: Colors.white54),
                      style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16),
                      items: [
                        DropdownMenuItem(value: ChartFilter.hourly, child: Text(widget.isFrench ? 'Répartition Horaire (Chaque Heure)' : 'Hourly Breakdown (Every Hour)')),
                        DropdownMenuItem(value: ChartFilter.daily, child: Text(widget.isFrench ? 'Résumé Journalier (Chaque Jour)' : 'Daily Summary (Every Day)'))
                      ],
                      onChanged: (ChartFilter? val) { if (val != null) setState(() => _currentFilter = val); },
                    ),
                  ),
                ),
                const SizedBox(height: 48),

                // 4. ACTION BUTTONS
                Row(
                    children: [
                      Expanded(
                          child: ElevatedButton.icon(
                              style: ElevatedButton.styleFrom(
                                  padding: const EdgeInsets.symmetric(vertical: 20),
                                  backgroundColor: _accentCyan,
                                  foregroundColor: Colors.black,
                                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))
                              ),
                              icon: const Icon(Icons.picture_as_pdf),
                              label: Text(widget.isFrench ? 'GÉNÉRER PDF' : 'GENERATE PDF', style: const TextStyle(fontWeight: FontWeight.w900, letterSpacing: 1)),
                              onPressed: () => _processAndExport('pdf')
                          )
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                          child: ElevatedButton.icon(
                              style: ElevatedButton.styleFrom(
                                  padding: const EdgeInsets.symmetric(vertical: 20),
                                  backgroundColor: Colors.greenAccent,
                                  foregroundColor: Colors.black,
                                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))
                              ),
                              icon: const Icon(Icons.table_chart),
                              label: Text(widget.isFrench ? 'GÉNÉRER CSV' : 'GENERATE CSV', style: const TextStyle(fontWeight: FontWeight.w900, letterSpacing: 1)),
                              onPressed: () => _processAndExport('csv')
                          )
                      )
                    ]
                ),
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
            padding: const EdgeInsets.symmetric(vertical: 16),
            foregroundColor: Colors.white,
            side: BorderSide(color: Colors.white.withOpacity(0.2)),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8))
        ),
        onPressed: () => _applyPreset(presetId),
        child: Text(label, style: const TextStyle(fontWeight: FontWeight.bold))
    );
  }
}