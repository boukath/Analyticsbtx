// lib/services/folder_scanner_service.dart

import 'dart:io';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:xml/xml.dart'; // Import the XML package to parse modern camera data
import '../models/people_count.dart';

class FolderScannerService {
  Future<List<PeopleCount>> loadScbDataFromFolder(String folderPath) async {
    return await compute(_processFolderInBackground, folderPath);
  }
}

// Note: Must remain a top-level function to work with Flutter's 'compute' isolate
Future<List<PeopleCount>> _processFolderInBackground(String folderPath) async {
  List<PeopleCount> allData = [];

  try {
    final directory = Directory(folderPath);
    if (!directory.existsSync()) return allData;

    // recursive: true allows it to look inside the sas1 and sas2 folders!
    final List<FileSystemEntity> filesInFolder = directory.listSync(recursive: true);

    for (var file in filesInFolder) {
      if (file is File && file.path.toLowerCase().endsWith('.scb')) {
        try {
          // EXTRACT THE FOLDER NAME (e.g., gets "sas1" from "C:\comptage\sas1\260114.scb")
          String folderName = file.parent.path.split(Platform.pathSeparator).last;

          List<int> fileBytes = file.readAsBytesSync();
          String fileContent = utf8.decode(fileBytes, allowMalformed: true);

          // =================================================================
          // 🚀 SMART PARSING LOGIC (Handles both HTTP XML and FTP Text)
          // =================================================================
          if (fileContent.trim().startsWith('<?xml') || fileContent.trim().startsWith('<RealTimePacket>')) {

            // --- XML PARSING LOGIC (HTTP) ---
            try {
              final document = XmlDocument.parse(fileContent);

              // 🚀 THE FIX: Look at the actual Data Slices, not the whole file!
              final slices = document.findAllElements('RTSlice');

              for (var slice in slices) {
                // 🛡️ CRITICAL: Only process Type="A" (Archive/Aggregated chunks)
                // Type="I" (Instantaneous) are cumulative running totals. If we add them up,
                // your traffic numbers will explode into the thousands!
                if (slice.getAttribute('Type') == 'A') {

                  // Extract the specific time for this chunk, NOT the file's SendTime!
                  String rawTime = slice.getAttribute('Timestamp') ?? ''; // e.g., "2026-05-03T13:45:00"

                  if (rawTime.isNotEmpty && rawTime.contains('T')) {
                    var parts = rawTime.split('T');
                    var dateParts = parts[0].split('-'); // [2026, 05, 03]
                    var timeParts = parts[1].split(':'); // [13, 45, 00]

                    if (dateParts.length == 3 && timeParts.length >= 2) {
                      // Reformat to match the legacy DD/MM/YYYY and HH:MM format
                      String formattedDate = "${dateParts[2]}/${dateParts[1]}/${dateParts[0]}";
                      String formattedTime = "${timeParts[0]}:${timeParts[1]}";

                      int inCount = 0;
                      int outCount = 0;

                      // Only get the channels FOR THIS SPECIFIC 15-MINUTE SLICE
                      final channels = slice.findAllElements('RTChannel');

                      for (var channel in channels) {
                        String direction = channel.getAttribute('Direction') ?? '';
                        int value = int.tryParse(channel.getAttribute('Value') ?? '0') ?? 0;

                        if (direction == 'E') {
                          inCount += value; // Entrées
                        } else if (direction == 'X') {
                          outCount += value; // Exits
                        }
                      }

                      // Create a fake plain-text line and feed it to the existing parser
                      String fakeLine = "001\t$formattedDate\t$formattedTime\t$inCount\t$outCount\t0\t0";

                      try {
                        allData.add(PeopleCount.fromScbLine(fakeLine, folderName));
                      } catch (e) {
                        print("Error parsing fake SCB line: $e");
                      }
                    }
                  }
                }
              }
            } catch (xmlError) {
              print("Error parsing XML SCB file ${file.path}: $xmlError");
            }

          } else {

            // --- PLAIN TEXT PARSING LOGIC (FTP) ---
            List<String> lines = const LineSplitter().convert(fileContent);

            for (String line in lines) {
              if (line.trim().isEmpty || line.startsWith('#') || line.startsWith('Magasin') || line.contains('CNL')) {
                continue;
              }
              try {
                // Pass the folder name into our data model
                allData.add(PeopleCount.fromScbLine(line, folderName));
              } catch (e) {
                // Silently skip unreadable lines
              }
            }
          }
        } catch (fileError) {
          print("Skipping unreadable file ${file.path}: $fileError");
        }
      }
    }
  } catch (e) {
    print("A major background error occurred: $e");
  }

  return allData;
}
