// lib/services/csv_export_service.dart

import 'dart:io';
import 'dart:convert'; // Required for UTF-8 encoding
import 'dart:typed_data'; // 🚀 NEW: Required for converting strings to bytes
import 'package:flutter/foundation.dart'; // 🚀 NEW: Required for kIsWeb
import 'package:flutter/material.dart';
import 'package:file_saver/file_saver.dart'; // 🚀 NEW: Required for web downloads
import '../models/people_count.dart';

class CsvExportService {
  /// Generates a premium, highly-structured CSV file and saves it silently to the local disk or downloads on Web.
  static Future<void> generateAndSaveCsv({
    required String reportType,
    required String dateRangeText,
    required String cameraName,
    required List<PeopleCount> data,
    required int totalIn,
    required int totalOut,
    required String peakHour,
    required String outputPath,
    // 🚀 POS PARAMETERS
    required double revenue,
    required int clients,
    required double conversionRate,
    required double avgBasket,
    required double upt,
    // 🚀 NEW: MALL VS RETAIL MODE FLAG
    required bool enablePosFeatures,
  }) async {
    try {
      StringBuffer csv = StringBuffer();

      // 🚀 1. ADD UTF-8 BOM (Byte Order Mark)
      // This forces Microsoft Excel to read the file in UTF-8 mode immediately,
      // ensuring accents (é, à) and special characters look perfect globally!
      csv.write('\uFEFF');

      // 🚀 2. PREMIUM HEADER SECTION
      String generatedTime = DateTime.now().toString().split('.')[0];

      csv.writeln("=====================================================================");
      csv.writeln("📊 RETAIL INTELLIGENCE - TRAFFIC & SALES ANALYTICS REPORT");
      csv.writeln("=====================================================================");
      csv.writeln("Report Type:, \"$reportType\"");
      csv.writeln("Date Range:, \"$dateRangeText\"");
      csv.writeln("Camera Location:, \"$cameraName\"");
      csv.writeln("Generated On:, \"$generatedTime\"");
      csv.writeln("");

      // 🚀 3. EXECUTIVE SUMMARY (KPIs)
      int totalVisitors = (totalIn + totalOut) ~/ 2;

      csv.writeln("--- 🎯 EXECUTIVE SUMMARY ---");
      csv.writeln("CATEGORY, METRIC, VALUE");
      csv.writeln("Traffic, Total Entrances (IN), $totalIn");
      csv.writeln("Traffic, Total Exits (OUT), $totalOut");
      csv.writeln("Traffic, Net Visitors, $totalVisitors");
      csv.writeln("Traffic, Peak Hour, \"$peakHour\"");

      // 🚀 Conditionally add POS rows only if Retail Mode is enabled
      if (enablePosFeatures) {
        csv.writeln("Sales, Total Revenue, \"${revenue.toStringAsFixed(2)} DZD\"");
        csv.writeln("Sales, Total Clients, $clients");
        csv.writeln("Sales, Conversion Rate, \"${conversionRate.toStringAsFixed(2)} %\"");
        csv.writeln("Sales, Average Basket, \"${avgBasket.toStringAsFixed(2)} DZD\"");
        csv.writeln("Sales, Units Per Transaction (UPT), ${upt.toStringAsFixed(2)}");
      }

      csv.writeln("");

      // 🚀 4. DETAILED DATA LOG
      csv.writeln("--- 📈 DETAILED DATA LOG ---");
      // Clean, well-spaced headers
      csv.writeln("Date, Time, Door/Camera, Entrances (IN), Exits (OUT), Net Visitors");

      // Add Rows safely wrapped in quotes to prevent layout breakage
      for (var item in data) {
        int visitors = (item.inCount + item.outCount) ~/ 2;
        csv.writeln("\"${item.date}\", \"${item.time}\", \"${item.doorName}\", ${item.inCount}, ${item.outCount}, $visitors");
      }

      csv.writeln("");
      csv.writeln("=====================================================================");
      csv.writeln("End of Report");

      // 🚀 5. SAVE OR DOWNLOAD THE FILE
      // Convert the string buffer to bytes using UTF-8
      final Uint8List bytes = Uint8List.fromList(utf8.encode(csv.toString()));

      if (kIsWeb) {
        // 🌐 WEB BEHAVIOR: Trigger browser download
        // We clean up the file name to avoid spaces or special characters
        String safeFileName = 'Traffic_Analytics_${reportType.replaceAll(' ', '_')}_${dateRangeText.replaceAll(' ', '_').replaceAll('/', '-')}';

        await FileSaver.instance.saveFile(
          name: safeFileName,
          bytes: bytes,
          ext: 'csv',
          mimeType: MimeType.csv,
        );
        debugPrint("✅ Premium CSV triggered for download on Web");
      } else {
        // 💻 WINDOWS BEHAVIOR: Silently save to disk
        File file = File(outputPath);
        await file.writeAsBytes(bytes);
        debugPrint("✅ Premium CSV saved successfully at: $outputPath");
      }
    } catch (e) {
      debugPrint("❌ Error saving CSV: $e");
    }
  }
}