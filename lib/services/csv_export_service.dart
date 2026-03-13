// lib/services/csv_export_service.dart

import 'dart:io';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import '../models/people_count.dart';

class CsvExportService {
  /// Generates a CSV file and prompts the user to save it.
  static Future<void> generateAndSaveCsv({
    required String reportType,
    required String dateRangeText,
    required String cameraName,
    required List<PeopleCount> data,
    required int totalIn,
    required int totalOut,
    required String peakHour,
    String? customFileName,
    // 🚀 NEW POS PARAMETERS
    required double revenue,
    required int clients,
    required double conversionRate,
    required double avgBasket,
    required double upt,
  }) async {
    try {
      StringBuffer csv = StringBuffer();

      csv.writeln("Retail Intelligence - Traffic Analytics Report");
      csv.writeln("Report Type:,$reportType");
      csv.writeln("Date Range:,$dateRangeText");
      csv.writeln("Camera:,$cameraName");
      csv.writeln("");

      // 🚀 UPDATED: Print POS Data to the CSV Header!
      int totalVisitors = (totalIn + totalOut) ~/ 2;
      csv.writeln("TRAFFIC METRICS:,TOTAL IN,TOTAL OUT,TOTAL VISITORS,PEAK HOUR");
      csv.writeln(",$totalIn,$totalOut,$totalVisitors,$peakHour");
      csv.writeln("");

      csv.writeln("SALES METRICS:,REVENUE,CLIENTS,CONV RATE,AVG BASKET,UPT");
      csv.writeln(",$revenue DZD,$clients,${conversionRate.toStringAsFixed(1)}%,${avgBasket.toStringAsFixed(0)} DZD,${upt.toStringAsFixed(2)}");
      csv.writeln("");

      // Add Table Headers
      csv.writeln("Date,Time,Door/Camera,Entrances (IN),Exits (OUT),Total Visitors");

      // Add Rows
      for (var item in data) {
        int visitors = (item.inCount + item.outCount) ~/ 2;
        csv.writeln("${item.date},${item.time},${item.doorName},${item.inCount},${item.outCount},$visitors");
      }

      // 2. Open the 'Save As' Dialog using FilePicker
      String finalFileName = customFileName ?? 'Traffic_Report_${DateTime.now().millisecondsSinceEpoch}.csv';

      String? outputFile = await FilePicker.platform.saveFile(
        dialogTitle: 'Save CSV Report',
        fileName: finalFileName,
        type: FileType.custom,
        allowedExtensions: ['csv'],
      );

      // 3. Save the file to the chosen location
      if (outputFile != null) {
        // file_picker on some OS doesn't auto-append the extension, let's enforce it:
        if (!outputFile.toLowerCase().endsWith('.csv')) {
          outputFile += '.csv';
        }

        File file = File(outputFile);
        await file.writeAsString(csv.toString());
        debugPrint("✅ CSV saved successfully at: $outputFile");
      } else {
        debugPrint("⚠️ CSV save canceled by user.");
      }
    } catch (e) {
      debugPrint("❌ Error saving CSV: $e");
    }
  }
}