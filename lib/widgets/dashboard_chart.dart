// lib/widgets/dashboard_chart.dart

import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';
import '../models/people_count.dart';
import '../core/app_theme.dart';
import 'glass_container.dart';
import 'trend_badge.dart';

enum ChartFilter { hourly, daily }

class DashboardChart extends StatelessWidget {
  final bool isFrench;
  final int totalIn;
  final int totalOut;
  final int compareTotalVisitors;
  final bool isTableMode;
  final ChartFilter currentFilter;
  final bool isSingleEntrance;
  final String selectedCamera;
  final List<String> availableCameras;
  final bool isCompareMode;
  final Map<String, List<PeopleCount>> perDoorData;
  final List<PeopleCount> displayedData;
  final List<PeopleCount> compareDisplayedData;

  // Callbacks
  final ValueChanged<bool> onTableModeChanged;
  final ValueChanged<ChartFilter> onFilterChanged;
  final Widget tableViewWidget;

  const DashboardChart({
    Key? key,
    required this.isFrench,
    required this.totalIn,
    required this.totalOut,
    required this.compareTotalVisitors,
    required this.isTableMode,
    required this.currentFilter,
    required this.isSingleEntrance,
    required this.selectedCamera,
    required this.availableCameras,
    required this.isCompareMode,
    required this.perDoorData,
    required this.displayedData,
    required this.compareDisplayedData,
    required this.onTableModeChanged,
    required this.onFilterChanged,
    required this.tableViewWidget,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    int totalVisitors = (totalIn + totalOut) ~/ 2;
    List<LineChartBarData> chartLines = [];
    bool showPerDoor = !isSingleEntrance && selectedCamera == 'All Doors' && availableCameras.length > 2 && !isCompareMode;

    List<List<Color>> luxuryGradients = [
      [AppTheme.cyan, const Color(0xFF0072FF)],
      [AppTheme.magenta, const Color(0xFFDD2476)],
      [const Color(0xFF38EF7D), const Color(0xFF11998E)],
      [AppTheme.purple, const Color(0xFF4A00E0)],
      [const Color(0xFFFDC830), const Color(0xFFF37335)],
    ];

    List<String> plottedDoors = perDoorData.keys.toList();
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
        if (perDoorData[door] != null) {
          for (var item in perDoorData[door]!) { processSpotForMetrics((item.inCount + item.outCount) / 2); }
        }
      }
    } else if (isCompareMode) {
      for (var item in displayedData) processSpotForMetrics((item.inCount + item.outCount) / 2);
      for (var item in compareDisplayedData) processSpotForMetrics((item.inCount + item.outCount) / 2);
    } else {
      for (var item in displayedData) {
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
        for (int i = 0; i < displayedData.length; i++) {
          String expectedTime = displayedData[i].time;
          String expectedDate = displayedData[i].date;
          var match = perDoorData[door]!.where((d) => d.time == expectedTime && d.date == expectedDate).toList();
          double total = match.isNotEmpty ? ((match.first.inCount + match.first.outCount) / 2).toDouble() : 0;
          spots.add(FlSpot(i.toDouble(), total));
        }
        chartLines.add(LineChartBarData(
          spots: spots, isCurved: true, curveSmoothness: 0.4, gradient: LinearGradient(colors: doorGradient), barWidth: 4, isStrokeCapRound: true,
          shadow: Shadow(color: doorGradient.first.withOpacity(0.6), blurRadius: 15, offset: const Offset(0, 5)),
          belowBarData: BarAreaData(show: true, gradient: buildVolumetricFade(doorGradient.first)),
          dotData: FlDotData(show: true, checkToShowDot: (spot, barData) => spot.y == maxTrafficY && spot.y > 0, getDotPainter: (spot, percent, barData, index) => FlDotCirclePainter(radius: 6, color: AppTheme.bgDeep(context), strokeWidth: 3, strokeColor: doorGradient.first)),
        ));
        colorIndex++;
      }
    } else if (isCompareMode) {
      chartLines.add(LineChartBarData(
        spots: displayedData.asMap().entries.map((e) => FlSpot(e.key.toDouble(), ((e.value.inCount + e.value.outCount) / 2).toDouble())).toList(),
        isCurved: true, curveSmoothness: 0.4, gradient: LinearGradient(colors: luxuryGradients[0]), barWidth: 5, isStrokeCapRound: true,
        shadow: Shadow(color: luxuryGradients[0].first.withOpacity(0.6), blurRadius: 15, offset: const Offset(0, 5)),
        belowBarData: BarAreaData(show: true, gradient: buildVolumetricFade(luxuryGradients[0].first)),
        dotData: FlDotData(show: true, checkToShowDot: (spot, barData) => spot.y == maxTrafficY && spot.y > 0, getDotPainter: (spot, percent, barData, index) => FlDotCirclePainter(radius: 6, color: AppTheme.bgDeep(context), strokeWidth: 3, strokeColor: luxuryGradients[0].first)),
      ));
      chartLines.add(LineChartBarData(
        spots: compareDisplayedData.asMap().entries.map((e) => FlSpot(e.key.toDouble(), ((e.value.inCount + e.value.outCount) / 2).toDouble())).toList(),
        isCurved: true, curveSmoothness: 0.4, color: const Color(0xFF8E8E93).withOpacity(0.8), barWidth: 3, dashArray: [8, 6], isStrokeCapRound: true, dotData: const FlDotData(show: false),
      ));
    } else {
      chartLines.add(LineChartBarData(
        spots: displayedData.asMap().entries.map((e) => FlSpot(e.key.toDouble(), e.value.inCount.toDouble())).toList(),
        isCurved: true, curveSmoothness: 0.4, gradient: LinearGradient(colors: luxuryGradients[0]), barWidth: 5, isStrokeCapRound: true,
        shadow: Shadow(color: luxuryGradients[0].first.withOpacity(0.6), blurRadius: 15, offset: const Offset(0, 5)),
        belowBarData: BarAreaData(show: true, gradient: buildVolumetricFade(luxuryGradients[0].first)),
        dotData: FlDotData(show: true, checkToShowDot: (spot, barData) => spot.y == maxTrafficY && spot.y > 0, getDotPainter: (spot, percent, barData, index) => FlDotCirclePainter(radius: 6, color: AppTheme.bgDeep(context), strokeWidth: 3, strokeColor: luxuryGradients[0].first)),
      ));
      chartLines.add(LineChartBarData(
        spots: displayedData.asMap().entries.map((e) => FlSpot(e.key.toDouble(), e.value.outCount.toDouble())).toList(),
        isCurved: true, curveSmoothness: 0.4, gradient: LinearGradient(colors: luxuryGradients[1]), barWidth: 5, isStrokeCapRound: true,
        shadow: Shadow(color: luxuryGradients[1].first.withOpacity(0.6), blurRadius: 15, offset: const Offset(0, 5)),
        belowBarData: BarAreaData(show: true, gradient: buildVolumetricFade(luxuryGradients[1].first)),
        dotData: FlDotData(show: true, checkToShowDot: (spot, barData) => spot.y == maxTrafficY && spot.y > 0, getDotPainter: (spot, percent, barData, index) => FlDotCirclePainter(radius: 6, color: AppTheme.bgDeep(context), strokeWidth: 3, strokeColor: luxuryGradients[1].first)),
      ));
    }

    return GlassContainer(
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
                  Text(isFrench ? 'TRAFIC GLOBAL' : 'GLOBAL TRAFFIC', style: TextStyle(color: AppTheme.textSecondary(context), fontSize: 14, fontWeight: FontWeight.w800, letterSpacing: 4.0)),
                  const SizedBox(height: 8),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.baseline, textBaseline: TextBaseline.alphabetic,
                    children: [
                      Text(totalVisitors.toString(), style: TextStyle(color: AppTheme.textPrimary(context), fontSize: 84, fontWeight: FontWeight.w900, letterSpacing: -4.0, height: 1.0)),
                      const SizedBox(width: 20),
                      TrendBadge(current: totalVisitors, previous: compareTotalVisitors, isCompareMode: isCompareMode),
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
                        decoration: BoxDecoration(color: AppTheme.glassTintStart(context).withOpacity(0.05), borderRadius: BorderRadius.circular(24), border: Border.all(color: AppTheme.glassBorder(context))),
                        child: Row(
                          children: [
                            IconButton(icon: Icon(Icons.show_chart_rounded, color: !isTableMode ? AppTheme.cyan : AppTheme.textSecondary(context), size: 22), onPressed: () => onTableModeChanged(false), tooltip: isFrench ? 'Graphique' : 'Chart'),
                            IconButton(icon: Icon(Icons.table_chart_rounded, color: isTableMode ? AppTheme.cyan : AppTheme.textSecondary(context), size: 22), onPressed: () => onTableModeChanged(true), tooltip: isFrench ? 'Tableau' : 'Table'),
                          ],
                        ),
                      ),
                      const SizedBox(width: 16),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
                        decoration: BoxDecoration(color: AppTheme.glassTintStart(context).withOpacity(0.05), borderRadius: BorderRadius.circular(24), border: Border.all(color: AppTheme.glassBorder(context))),
                        child: DropdownButtonHideUnderline(
                          child: DropdownButton<ChartFilter>(
                            dropdownColor: AppTheme.bgDeep(context).withOpacity(0.9), icon: Icon(Icons.expand_more_rounded, color: AppTheme.textSecondary(context)), value: currentFilter,
                            style: TextStyle(color: AppTheme.textPrimary(context), fontWeight: FontWeight.w800, fontSize: 15, letterSpacing: 0.5),
                            items: [
                              DropdownMenuItem(value: ChartFilter.hourly, child: Text(isFrench ? 'Vue Horaire' : 'Hourly View')),
                              DropdownMenuItem(value: ChartFilter.daily, child: Text(isFrench ? 'Vue Journalière' : 'Daily View'))
                            ],
                            onChanged: (ChartFilter? newValue) { if (newValue != null) { onFilterChanged(newValue); } },
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
                          const SizedBox(width: 12), Text("${entry.value.toUpperCase()} Total", style: TextStyle(color: AppTheme.textSecondary(context), fontSize: 15, fontWeight: FontWeight.w700, letterSpacing: 0.5))
                        ]),
                      );
                    }).toList(),
                  ] else if (isCompareMode) ...[
                    Row(children: [Container(width: 14, height: 14, decoration: BoxDecoration(color: luxuryGradients[0].first, shape: BoxShape.circle, boxShadow: [BoxShadow(color: luxuryGradients[0].first.withOpacity(0.6), blurRadius: 10)])), const SizedBox(width: 12), Text(isFrench ? 'Période Actuelle' : 'Current Period', style: TextStyle(color: AppTheme.textSecondary(context), fontSize: 15, fontWeight: FontWeight.w700))]),
                    const SizedBox(height: 12),
                    Row(children: [Container(width: 14, height: 14, decoration: const BoxDecoration(color: Color(0xFF8E8E93), shape: BoxShape.circle)), const SizedBox(width: 12), Text(isFrench ? 'Période Précédente' : 'Previous Period', style: TextStyle(color: AppTheme.textSecondary(context), fontSize: 15, fontWeight: FontWeight.w700))]),
                  ] else ...[
                    Row(children: [Container(width: 14, height: 14, decoration: BoxDecoration(gradient: LinearGradient(colors: luxuryGradients[0]), shape: BoxShape.circle, boxShadow: [BoxShadow(color: luxuryGradients[0].first.withOpacity(0.6), blurRadius: 10)])), const SizedBox(width: 12), Text('${isFrench ? "Total Entrées" : "Total In"}: $totalIn', style: TextStyle(color: AppTheme.textSecondary(context), fontSize: 16, fontWeight: FontWeight.w700))]),
                    const SizedBox(height: 12),
                    Row(children: [Container(width: 14, height: 14, decoration: BoxDecoration(gradient: LinearGradient(colors: luxuryGradients[1]), shape: BoxShape.circle, boxShadow: [BoxShadow(color: luxuryGradients[1].first.withOpacity(0.6), blurRadius: 10)])), const SizedBox(width: 12), Text('${isFrench ? "Total Sorties" : "Total Out"}: $totalOut', style: TextStyle(color: AppTheme.textSecondary(context), fontSize: 16, fontWeight: FontWeight.w700))]),
                  ]
                ],
              )
            ],
          ),
          const SizedBox(height: 60),

          SizedBox(
            height: 400,
            child: isTableMode ? tableViewWidget : LineChart(
              LineChartData(
                minY: 0,
                maxY: maxTrafficY * 1.15,
                extraLinesData: ExtraLinesData(
                  horizontalLines: [
                    if (averageTraffic > 0)
                      HorizontalLine(
                        y: averageTraffic,
                        color: AppTheme.textSecondary(context).withOpacity(0.3),
                        strokeWidth: 2.0,
                        dashArray: [8, 8],
                        label: HorizontalLineLabel(
                          show: true,
                          alignment: Alignment.topRight,
                          padding: const EdgeInsets.only(right: 8, bottom: 8),
                          style: TextStyle(color: AppTheme.textSecondary(context), fontSize: 11, fontWeight: FontWeight.w900, letterSpacing: 2.0),
                          labelResolver: (line) => isFrench ? 'MOYENNE' : 'AVERAGE',
                        ),
                      ),
                  ],
                ),
                lineTouchData: LineTouchData(
                  handleBuiltInTouches: true,
                  getTouchedSpotIndicator: (LineChartBarData barData, List<int> spotIndexes) {
                    return spotIndexes.map((spotIndex) {
                      return TouchedSpotIndicatorData(
                        FlLine(color: AppTheme.textPrimary(context).withOpacity(0.4), strokeWidth: 2, dashArray: [6, 6]),
                        FlDotData(show: true, getDotPainter: (spot, percent, barData, index) => FlDotCirclePainter(radius: 8, color: AppTheme.bgDeep(context), strokeWidth: 4, strokeColor: barData.gradient?.colors.first ?? AppTheme.cyan)),
                      );
                    }).toList();
                  },
                  touchTooltipData: LineTouchTooltipData(
                    tooltipBgColor: AppTheme.textPrimary(context).withOpacity(0.9), tooltipRoundedRadius: 20, tooltipPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16), tooltipBorder: BorderSide(color: AppTheme.glassBorder(context), width: 1.5),
                    getTooltipItems: (touchedSpots) {
                      return touchedSpots.map((LineBarSpot touchedSpot) {
                        final textStyle = TextStyle(color: AppTheme.bgDeep(context), fontWeight: FontWeight.w900, fontSize: 18, letterSpacing: 0.5);
                        String timeText = "";
                        if (displayedData.length > touchedSpot.x.toInt()) { timeText = currentFilter == ChartFilter.daily ? displayedData[touchedSpot.x.toInt()].date : displayedData[touchedSpot.x.toInt()].time; }
                        String type = "";
                        if (showPerDoor) {
                          if (touchedSpot.barIndex < plottedDoors.length) type = "${plottedDoors[touchedSpot.barIndex].toUpperCase()}: ";
                        } else if (isCompareMode) {
                          type = touchedSpot.barIndex == 0 ? (isFrench ? "Actuel: " : "Current: ") : (isFrench ? "Précédent: " : "Previous: ");
                        } else {
                          type = touchedSpot.barIndex == 0 ? (isFrench ? "Entrées: " : "In: ") : (isFrench ? "Sorties: " : "Out: ");
                        }
                        return LineTooltipItem("$timeText\n", TextStyle(color: AppTheme.bgDeep(context).withOpacity(0.7), fontSize: 13, fontWeight: FontWeight.w700), children: [TextSpan(text: "$type${touchedSpot.y.toInt()}", style: textStyle)]);
                      }).toList();
                    },
                  ),
                ),
                gridData: FlGridData(
                    show: true, drawVerticalLine: false, horizontalInterval: yInterval,
                    getDrawingHorizontalLine: (value) => FlLine(color: AppTheme.glassBorder(context).withOpacity(0.08), strokeWidth: 1.5, dashArray: [10, 10])
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
                          child: Text(value.toInt().toString(), textAlign: TextAlign.right, style: TextStyle(color: AppTheme.textSecondary(context), fontSize: 13, fontWeight: FontWeight.w800, fontFeatures: const [FontFeature.tabularFigures()])),
                        );
                      },
                    ),
                  ),
                  bottomTitles: AxisTitles(
                    sideTitles: SideTitles(
                      showTitles: true, reservedSize: 50, interval: 1,
                      getTitlesWidget: (value, meta) {
                        int index = value.toInt();
                        if (index >= 0 && index < displayedData.length) {
                          String displayText = currentFilter == ChartFilter.hourly ? displayedData[index].time.split(':')[0] : displayedData[index].date.substring(0, 5);
                          return Padding(padding: const EdgeInsets.only(top: 16.0), child: Text(displayText, textAlign: TextAlign.center, style: TextStyle(color: AppTheme.textSecondary(context), fontSize: 12, fontWeight: FontWeight.w800, letterSpacing: 0.5)));
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
}