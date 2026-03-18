// lib/services/polaris_parser_service.dart

import 'dart:io';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:archive/archive_io.dart';

/// A simple class to hold the results of our Polaris parsing.
class PolarisData {
  final double chiffreAffaires;
  final int totalTickets;
  final int totalClients;
  final String? date;

  PolarisData({
    required this.chiffreAffaires,
    required this.totalTickets,
    required this.totalClients,
    this.date,
  });

  @override
  String toString() {
    return '📅 Date: ${date ?? "Unknown"}\n💶 CA: ${chiffreAffaires.toStringAsFixed(2)} DZD\n🎫 Tickets: $totalTickets\n👤 Clients: $totalClients';
  }
}

class PolarisParserService {

  // 🚀 NEW: Scans a folder, finds the newest .sav file, and processes it!
  Future<PolarisData?> processPolarisFolder(String folderPath) async {
    print('🔍 Scanning folder for Polaris .sav files: $folderPath');

    try {
      final dir = Directory(folderPath);
      if (!await dir.exists()) {
        print('❌ Error: Directory does not exist.');
        return null;
      }

      // 1. Get all files in the directory
      List<FileSystemEntity> entities = dir.listSync(recursive: false);

      // 2. Filter for .sav files
      List<File> savFiles = entities
          .whereType<File>()
          .where((f) => f.path.toLowerCase().endsWith('.sav'))
          .toList();

      if (savFiles.isEmpty) {
        print('❌ No .sav files found in the selected folder.');
        return null;
      }

      // 3. Sort by last modified date (newest first)
      savFiles.sort((a, b) => b.lastModifiedSync().compareTo(a.lastModifiedSync()));

      File latestSavFile = savFiles.first;
      print('✅ Found latest .sav backup: ${latestSavFile.path}');

      // 4. Process the found file using the existing method
      return await processPolarisFile(latestSavFile.path);

    } catch (e) {
      print('❌ Failed to scan folder: $e');
      return null;
    }
  }

  /// Processes the .sav file and returns the extracted PolarisData.
  Future<PolarisData?> processPolarisFile(String filePath) async {
    print('🔍 Starting to process Polaris file: $filePath');

    try {
      final bytes = await File(filePath).readAsBytes();
      Archive archive;

      try {
        archive = ZipDecoder().decodeBytes(bytes);
      } catch (e) {
        archive = TarDecoder().decodeBytes(bytes);
      }

      ArchiveFile? sqlFile;
      for (final file in archive) {
        if (file.isFile && file.name.contains('0-full.sql')) {
          sqlFile = file;
          break;
        }
      }

      if (sqlFile == null) {
        print('❌ Error: Could not find the SQL file.');
        return null;
      }

      print('✅ SUCCESS! Unpacked ${sqlFile.name} (${(sqlFile.size / 1024 / 1024).toStringAsFixed(2)} MB)');
      print('⏳ Calculating daily totals... (This might take a second)');

      // Decode the SQL file
      final sqlContent = utf8.decode(sqlFile.content as List<int>, allowMalformed: true);

      // Use an Isolate to run the heavy calculation without freezing the UI
      final polarisData = await compute(_extractPolarisData, sqlContent);

      print('\n🎉 --- FINAL EXTRACTION RESULTS ---');
      print(polarisData.toString());
      print('----------------------------------\n');

      return polarisData;

    } catch (e) {
      print('❌ Failed to process Polaris file: $e');
      return null;
    }
  }
}

/// This function runs in a background isolate. It extracts the CA and Tickets accurately per day!
PolarisData _extractPolarisData(String sqlContent) {
  List<String> lines = sqlContent.split('\n');

  bool isReadingEntvte = false;

  // We will map the data by date!
  Map<String, double> caPerDay = {};
  Map<String, int> ticketsPerDay = {};

  for (String line in lines) {
    // --- 1. Detect Sales Table ---
    if (line.startsWith('COPY public.entvte ')) {
      isReadingEntvte = true;
      continue;
    }

    // --- 2. End of Table Block ---
    if (line.trim() == '\\.') {
      isReadingEntvte = false;
      continue;
    }

    // --- 3. Process Sales (entvte table) ---
    if (isReadingEntvte) {
      List<String> columns = line.split('\t');

      // Ensure the row has enough columns (date is index 2, ca_reel is index 6)
      if (columns.length > 6) {
        String date = columns[2].trim(); // e.g., '2026-01-30'
        double? caReel = double.tryParse(columns[6]);

        // If the CA is greater than 0, it's a valid sale ticket!
        if (caReel != null && caReel > 0 && date.isNotEmpty) {
          // Add the money and the ticket to that specific date
          caPerDay[date] = (caPerDay[date] ?? 0.0) + caReel;
          ticketsPerDay[date] = (ticketsPerDay[date] ?? 0) + 1;
        }
      }
    }
  }

  // --- 4. Find the Date of the Cloture ---
  // The cloture date is almost always the most recent date in the backup file.
  String? targetDate;
  if (caPerDay.isNotEmpty) {
    List<String> sortedDates = caPerDay.keys.toList()..sort();
    targetDate = sortedDates.last; // Grab the latest day!
  }

  // --- 5. Return the exact data for that day ---
  double finalCA = targetDate != null ? (caPerDay[targetDate] ?? 0.0) : 0.0;
  int finalTickets = targetDate != null ? (ticketsPerDay[targetDate] ?? 0) : 0;

  return PolarisData(
    chiffreAffaires: finalCA,
    totalTickets: finalTickets,
    // In retail, Walk-in Customers = Number of Tickets
    totalClients: finalTickets,
    date: targetDate,
  );
}