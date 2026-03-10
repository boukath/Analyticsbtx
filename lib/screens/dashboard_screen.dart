// lib/screens/dashboard_screen.dart

import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:fl_chart/fl_chart.dart';

import '../models/people_count.dart';
import '../services/folder_scanner_service.dart';
import '../core/data_aggregator.dart';

enum ChartFilter { raw, hourly, daily }

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

  // Premium Analytics Variables
  int _totalIn = 0;
  int _totalOut = 0;
  int _occupancy = 0;
  String _peakHour = "--:--";

  final FolderScannerService _scannerService = FolderScannerService();

  Future<void> _pickFolderAndLoadData() async {
    String? folderPath = await FilePicker.platform.getDirectoryPath();

    if (folderPath != null) {
      setState(() {
        _isLoading = true;
        _selectedFolderPath = folderPath;
        _selectedDateRange = null;
      });

      List<PeopleCount> loadedData = await _scannerService.loadScbDataFromFolder(folderPath);

      setState(() {
        _rawData = loadedData;
        if (_rawData.isNotEmpty) {
          var lastDateParts = _rawData.last.date.split('/');
          if (lastDateParts.length == 3) {
            DateTime latestDate = DateTime(
                int.parse(lastDateParts[2]),
                int.parse(lastDateParts[1]),
                int.parse(lastDateParts[0])
            );
            _selectedDateRange = DateTimeRange(start: latestDate, end: latestDate);
          }
        }
        _applyFilter();
        _isLoading = false;
      });
    }
  }

  void _applyFilter() {
    setState(() {
      List<PeopleCount> filteredData = _rawData.where((item) {
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
      } else if (_currentFilter == ChartFilter.hourly) {
        _displayedData = DataAggregator.aggregateByHour(filteredData);
      } else {
        _displayedData = List.from(filteredData);
      }

      // Calculate Advanced Analytics
      _totalIn = 0;
      _totalOut = 0;
      int maxTraffic = 0;
      _peakHour = "--:--";

      for (var item in _displayedData) {
        _totalIn += item.inCount;
        _totalOut += item.outCount;

        int totalTraffic = item.inCount + item.outCount;
        if (totalTraffic > maxTraffic) {
          maxTraffic = totalTraffic;
          _peakHour = item.time;
        }
      }

      _occupancy = _totalIn - _totalOut;
      if (_occupancy < 0) _occupancy = 0; // Prevent negative occupancy
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
          data: ThemeData.dark().copyWith(
            colorScheme: const ColorScheme.dark(
              primary: Colors.cyanAccent,
              onPrimary: Colors.black,
              surface: Color(0xFF1E293B),
              onSurface: Colors.white,
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

  @override
  Widget build(BuildContext context) {
    final isDesktop = MediaQuery.of(context).size.width > 800;

    return Scaffold(
      backgroundColor: const Color(0xFF0B0F19), // Deep Executive Slate
      body: Stack(
        children: [
          // Premium Glow Effects in Background
          Positioned(top: -100, left: -100, child: _buildGlowOrb(Colors.cyanAccent.withOpacity(0.15), 300)),
          Positioned(bottom: -100, right: -100, child: _buildGlowOrb(Colors.pinkAccent.withOpacity(0.15), 400)),

          SafeArea(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator(color: Colors.cyanAccent))
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
                    _buildPremiumSummaryCards(isDesktop),
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
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: color,
      ),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 100, sigmaY: 100),
        child: Container(color: Colors.transparent),
      ),
    );
  }

  Widget _buildCustomHeader() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'RETAIL INTELLIGENCE',
              style: TextStyle(fontSize: 12, color: Colors.cyanAccent, fontWeight: FontWeight.bold, letterSpacing: 2),
            ),
            const SizedBox(height: 4),
            const Text(
              'Traffic Analytics',
              style: TextStyle(fontSize: 36, fontWeight: FontWeight.w800, color: Colors.white, letterSpacing: -1),
            ),
            if (_selectedFolderPath != null)
              Padding(
                padding: const EdgeInsets.only(top: 8.0),
                child: Text('Source: $_selectedFolderPath', style: const TextStyle(color: Colors.white38, fontSize: 12)),
              ),
          ],
        ),
        DarkGlassCard(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
          child: InkWell(
            onTap: _pickFolderAndLoadData,
            child: const Row(
              children: [
                Icon(Icons.drive_folder_upload, color: Colors.cyanAccent),
                SizedBox(width: 12),
                Text('IMPORT DATA', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: Colors.white, letterSpacing: 1)),
              ],
            ),
          ),
        )
      ],
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.only(top: 100),
        child: DarkGlassCard(
          padding: const EdgeInsets.all(60),
          child: Column(
            children: const [
              Icon(Icons.radar, size: 80, color: Colors.white24),
              SizedBox(height: 24),
              Text('System Standby', style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: Colors.white)),
              SizedBox(height: 12),
              Text('Connect to a data source to begin tracking algorithms.', style: TextStyle(color: Colors.white54)),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildPremiumSummaryCards(bool isDesktop) {
    final cards = [
      _buildMetricCard('TOTAL IN', _totalIn.toString(), Icons.login, Colors.cyanAccent),
      _buildMetricCard('TOTAL OUT', _totalOut.toString(), Icons.logout, Colors.pinkAccent),
      _buildMetricCard('LIVE OCCUPANCY', _occupancy.toString(), Icons.people_alt, Colors.amberAccent),
      _buildMetricCard('PEAK HOUR', _peakHour, Icons.trending_up, Colors.purpleAccent),
    ];

    if (isDesktop) {
      return Row(children: cards.map((c) => Expanded(child: Padding(padding: const EdgeInsets.symmetric(horizontal: 8), child: c))).toList());
    } else {
      return Column(children: cards.map((c) => Padding(padding: const EdgeInsets.only(bottom: 16), child: c)).toList());
    }
  }

  Widget _buildMetricCard(String title, String value, IconData icon, Color color) {
    return DarkGlassCard(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(title, style: TextStyle(fontSize: 12, color: Colors.white54, fontWeight: FontWeight.bold, letterSpacing: 1.5)),
              Icon(icon, color: color, size: 20),
            ],
          ),
          const SizedBox(height: 16),
          Text(value, style: const TextStyle(fontSize: 32, fontWeight: FontWeight.w800, color: Colors.white, letterSpacing: -1)),
        ],
      ),
    );
  }

  Widget _buildInteractiveChartSection(bool isDesktop) {
    return DarkGlassCard(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Premium Date Navigation & View Toggles
          Wrap(
            alignment: WrapAlignment.spaceBetween,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              Container(
                decoration: BoxDecoration(color: Colors.white.withOpacity(0.05), borderRadius: BorderRadius.circular(12)),
                padding: const EdgeInsets.all(4),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    IconButton(icon: const Icon(Icons.chevron_left, color: Colors.white70), onPressed: () => _shiftDate(-1)),
                    GestureDetector(
                      onTap: _pickDateRange,
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        child: Text(_getFormattedDateString(), style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.white)),
                      ),
                    ),
                    IconButton(icon: const Icon(Icons.chevron_right, color: Colors.white70), onPressed: () => _shiftDate(1)),
                  ],
                ),
              ),
              DropdownButtonHideUnderline(
                child: DropdownButton<ChartFilter>(
                  value: _currentFilter,
                  dropdownColor: const Color(0xFF1E293B),
                  icon: const Icon(Icons.timeline, color: Colors.white54),
                  style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                  items: const [
                    // REMOVED the 15-min raw view! Now it only shows Hourly and Daily.
                    DropdownMenuItem(value: ChartFilter.hourly, child: Text(' Hourly Timeline')),
                    DropdownMenuItem(value: ChartFilter.daily, child: Text(' Daily Timeline')),
                  ],
                  onChanged: (ChartFilter? newValue) {
                    if (newValue != null) {
                      setState(() {
                        _currentFilter = newValue;
                        _applyFilter();
                      });
                    }
                  },
                ),
              ),
            ],
          ),
          const SizedBox(height: 40),

          // The Interactive Chart
          SizedBox(
            height: 450,
            child: LineChart(
              LineChartData(
                lineTouchData: LineTouchData(
                  touchTooltipData: LineTouchTooltipData(
                    tooltipBgColor: const Color(0xFF1E293B).withOpacity(0.9),
                    tooltipRoundedRadius: 8,
                    getTooltipItems: (touchedSpots) {
                      return touchedSpots.map((LineBarSpot touchedSpot) {
                        final textStyle = TextStyle(
                          color: touchedSpot.bar.color ?? Colors.white,
                          fontWeight: FontWeight.bold,
                          fontSize: 14,
                        );
                        // Also show the exact time in the tooltip!
                        String timeText = _displayedData[touchedSpot.x.toInt()].time;
                        String type = touchedSpot.barIndex == 0 ? "In: " : "Out: ";
                        return LineTooltipItem("$timeText\n$type${touchedSpot.y.toInt()}", textStyle);
                      }).toList();
                    },
                  ),
                ),
                gridData: FlGridData(
                  show: true,
                  drawVerticalLine: false,
                  getDrawingHorizontalLine: (value) => FlLine(color: Colors.white.withOpacity(0.05), strokeWidth: 1),
                ),
                titlesData: FlTitlesData(
                  rightTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)),
                  topTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)),

                  // UPDATED: Clean X-Axis that perfectly maps to your data's Time
                  bottomTitles: AxisTitles(
                    sideTitles: SideTitles(
                      showTitles: true,
                      reservedSize: 32,
                      interval: 1, // We evaluate every single point
                      getTitlesWidget: (value, meta) {
                        int index = value.toInt();
                        if (index >= 0 && index < _displayedData.length) {
                          // If there are a lot of hours, we skip every other label so they don't crash into each other
                          if (_displayedData.length > 12 && index % 2 != 0) {
                            return const SizedBox.shrink();
                          }

                          return Padding(
                            padding: const EdgeInsets.only(top: 10.0),
                            child: Text(
                              _displayedData[index].time, // Displays '09:00', '10:00', etc.
                              style: const TextStyle(color: Colors.white70, fontSize: 11, fontWeight: FontWeight.bold),
                            ),
                          );
                        }
                        return const SizedBox.shrink();
                      },
                    ),
                  ),

                  leftTitles: AxisTitles(
                    sideTitles: SideTitles(
                      showTitles: true,
                      reservedSize: 40,
                      getTitlesWidget: (value, meta) {
                        return Text(value.toInt().toString(), style: const TextStyle(color: Colors.white54, fontSize: 12));
                      },
                    ),
                  ),
                ),
                borderData: FlBorderData(show: false),
                lineBarsData: [
                  LineChartBarData(
                    spots: _displayedData.asMap().entries.map((e) => FlSpot(e.key.toDouble(), e.value.inCount.toDouble())).toList(),
                    isCurved: true,
                    color: Colors.cyanAccent,
                    barWidth: 3,
                    isStrokeCapRound: true,
                    dotData: FlDotData(show: false),
                    belowBarData: BarAreaData(
                      show: true,
                      gradient: LinearGradient(
                        colors: [Colors.cyanAccent.withOpacity(0.3), Colors.cyanAccent.withOpacity(0.0)],
                        begin: Alignment.topCenter, end: Alignment.bottomCenter,
                      ),
                    ),
                  ),
                  LineChartBarData(
                    spots: _displayedData.asMap().entries.map((e) => FlSpot(e.key.toDouble(), e.value.outCount.toDouble())).toList(),
                    isCurved: true,
                    color: Colors.pinkAccent,
                    barWidth: 3,
                    isStrokeCapRound: true,
                    dotData: FlDotData(show: false),
                    belowBarData: BarAreaData(
                      show: true,
                      gradient: LinearGradient(
                        colors: [Colors.pinkAccent.withOpacity(0.3), Colors.pinkAccent.withOpacity(0.0)],
                        begin: Alignment.topCenter, end: Alignment.bottomCenter,
                      ),
                    ),
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
// ============================================================================
// REUSABLE COMPONENT: Executive Dark Glass Card
// ============================================================================
class DarkGlassCard extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry padding;

  const DarkGlassCard({Key? key, required this.child, required this.padding}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(16),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
        child: Container(
          padding: padding,
          decoration: BoxDecoration(
            color: Colors.white.withOpacity(0.03),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: Colors.white.withOpacity(0.08), width: 1),
          ),
          child: child,
        ),
      ),
    );
  }
}