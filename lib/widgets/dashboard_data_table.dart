// lib/widgets/dashboard_data_table.dart

import 'package:flutter/material.dart';
import '../models/people_count.dart';
import 'glass_container.dart';
import 'dashboard_chart.dart'; // Import ChartFilter from here

class DashboardDataTable extends StatelessWidget {
  final bool isFrench;
  final bool isSingleEntrance;
  final String selectedCamera;
  final List<String> availableCameras;
  final bool isCompareMode;
  final ChartFilter currentFilter;
  final List<PeopleCount> displayedData;
  final List<PeopleCount> compareDisplayedData;
  final Map<String, List<PeopleCount>> perDoorData;
  final int totalIn;
  final int totalOut;
  final int compareTotalIn;
  final int compareTotalOut;

  const DashboardDataTable({
    Key? key,
    required this.isFrench,
    required this.isSingleEntrance,
    required this.selectedCamera,
    required this.availableCameras,
    required this.isCompareMode,
    required this.currentFilter,
    required this.displayedData,
    required this.compareDisplayedData,
    required this.perDoorData,
    required this.totalIn,
    required this.totalOut,
    required this.compareTotalIn,
    required this.compareTotalOut,
  }) : super(key: key);

  final Color _accentCyan = const Color(0xFF00F0FF);

  Widget _buildMatrixTable() {
    List<String> individualDoors = availableCameras.where((c) => c != 'All Doors').toList();
    const double timeColWidth = 100;
    const double dataColWidth = 70;

    Map<String, int> doorInTotals = {};
    Map<String, int> doorOutTotals = {};
    for (String door in individualDoors) { doorInTotals[door] = 0; doorOutTotals[door] = 0; }

    List<Map<String, dynamic>> rowData = [];
    for (int i = 0; i < displayedData.length; i++) {
      var globalItem = displayedData[i];
      String timeLabel = currentFilter == ChartFilter.hourly ? globalItem.time : globalItem.date;
      Map<String, dynamic> row = { 'time': timeLabel, 'globalIn': globalItem.inCount, 'globalOut': globalItem.outCount, 'doors': <String, Map<String, int>>{} };
      for (String door in individualDoors) {
        int dIn = 0; int dOut = 0;
        if (perDoorData[door] != null) {
          var match = perDoorData[door]!.where((d) => (currentFilter == ChartFilter.hourly ? d.time == globalItem.time : d.date == globalItem.date)).toList();
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

    return GlassContainer(
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
                    buildCell(isFrench ? 'GLOBAL' : 'GLOBAL', dataColWidth * 2, isTitle: true, color: Colors.white, rightBorder: true),
                    ...individualDoors.map((door) => buildCell(door.toUpperCase(), dataColWidth * 2, isTitle: true, color: _accentCyan, rightBorder: true)).toList(),
                  ],
                ),
              ),
              Container(
                decoration: BoxDecoration(color: Colors.white.withOpacity(0.03), border: Border(bottom: BorderSide(color: Colors.white.withOpacity(0.1)))),
                child: Row(
                  children: [
                    buildCell(isFrench ? 'Période' : 'Time', timeColWidth, isTitle: true, rightBorder: true),
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
                    buildCell(totalIn.toString(), dataColWidth, color: Colors.greenAccent, isTitle: true),
                    buildCell(totalOut.toString(), dataColWidth, color: Colors.redAccent, isTitle: true, rightBorder: true),
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
    bool isCompare = isCompareMode && compareDisplayedData.isNotEmpty;

    return GlassContainer(
      borderRadius: 24,
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
            decoration: BoxDecoration(color: Colors.white.withOpacity(0.05), border: Border(bottom: BorderSide(color: Colors.white.withOpacity(0.1)))),
            child: Row(
              children: [
                Expanded(flex: 2, child: Text(isFrench ? 'Période' : 'Time', style: const TextStyle(color: Colors.white54, fontWeight: FontWeight.w800, letterSpacing: 1.0))),
                Expanded(child: Text(isFrench ? 'Entrées' : 'In', textAlign: TextAlign.center, style: const TextStyle(color: Colors.white54, fontWeight: FontWeight.w800, letterSpacing: 1.0))),
                Expanded(child: Text(isFrench ? 'Sorties' : 'Out', textAlign: TextAlign.center, style: const TextStyle(color: Colors.white54, fontWeight: FontWeight.w800, letterSpacing: 1.0))),
                if (isCompare) ...[
                  Expanded(child: Text(isFrench ? 'Préc. In' : 'Prev In', textAlign: TextAlign.center, style: const TextStyle(color: Colors.white54, fontWeight: FontWeight.w800, letterSpacing: 1.0))),
                  Expanded(child: Text(isFrench ? 'Préc. Out' : 'Prev Out', textAlign: TextAlign.center, style: const TextStyle(color: Colors.white54, fontWeight: FontWeight.w800, letterSpacing: 1.0))),
                ],
                Expanded(child: Text(isFrench ? 'Total' : 'Total', textAlign: TextAlign.right, style: const TextStyle(color: Colors.white54, fontWeight: FontWeight.w800, letterSpacing: 1.0))),
              ],
            ),
          ),
          Expanded(
            child: ListView.builder(
              itemCount: displayedData.length,
              itemBuilder: (context, index) {
                var item = displayedData[index];
                String timeLabel = currentFilter == ChartFilter.hourly ? item.time : item.date;
                int total = (item.inCount + item.outCount) ~/ 2;
                PeopleCount? compareItem;
                if (isCompare && index < compareDisplayedData.length) compareItem = compareDisplayedData[index];

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
                Expanded(flex: 2, child: const Text('TOTAL', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w900, fontSize: 15, letterSpacing: 1.0))), // FIXED: 'const child' to 'child: const'
                Expanded(child: Text(totalIn.toString(), textAlign: TextAlign.center, style: const TextStyle(color: Colors.greenAccent, fontWeight: FontWeight.w900, fontSize: 15))),
                Expanded(child: Text(totalOut.toString(), textAlign: TextAlign.center, style: const TextStyle(color: Colors.redAccent, fontWeight: FontWeight.w900, fontSize: 15))),
                if (isCompare) ...[
                  Expanded(child: Text(compareTotalIn.toString(), textAlign: TextAlign.center, style: const TextStyle(color: Colors.white70, fontWeight: FontWeight.w900, fontSize: 15))),
                  Expanded(child: Text(compareTotalOut.toString(), textAlign: TextAlign.center, style: const TextStyle(color: Colors.white70, fontWeight: FontWeight.w900, fontSize: 15))),
                ],
                Expanded(child: Text(((totalIn + totalOut) ~/ 2).toString(), textAlign: TextAlign.right, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w900, fontSize: 15))),
              ],
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    bool showMatrix = !isSingleEntrance && selectedCamera == 'All Doors' && availableCameras.length > 2 && !isCompareMode;
    if (showMatrix) return _buildMatrixTable();
    else return _buildStandardTable();
  }
}