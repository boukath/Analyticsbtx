// lib/services/folder_scanner_service.dart

import 'dart:io';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:xml/xml.dart'; // Import the XML package to parse modern camera data
import '../models/people_count.dart';

class FolderScannerService {
  // Cache to track file modifications (Path -> "Size_Timestamp")
  // This allows us to know if an .scb file was appended with new data!
  final Map<String, String> _fileHashes = {};

  // Cache to store the historical data perfectly mapped to its file (Path -> Data)
  // This prevents data duplication when we re-read an appended .scb file.
  final Map<String, List<PeopleCount>> _fileDataCache = {};

  /// Clears the scanner cache.
  /// Use this when the user switches to a completely new folder or forces a full refresh.
  void clearCache() {
    _fileHashes.clear();
    _fileDataCache.clear();
  }

  Future<List<PeopleCount>> loadScbDataFromFolder(String folderPath) async {
    final directory = Directory(folderPath);

    // If the directory is missing, just return whatever is already in memory
    if (!directory.existsSync()) return _fileDataCache.values.expand((x) => x).toList();

    final List<FileSystemEntity> filesInFolder = directory.listSync(recursive: true);

    List<String> filesToProcess = [];

    for (var file in filesInFolder) {
      if (file is File) {
        String pathLower = file.path.toLowerCase();
        if (pathLower.endsWith('.scb') || pathLower.endsWith('.dat')) {

          // Generate a unique signature for this exact file state
          String signature = "${file.lengthSync()}_${file.lastModifiedSync().millisecondsSinceEpoch}";

          // If we haven't seen this exact state before (either a brand new .dat file,
          // or an .scb file that grew in size), add it to the processing queue!
          if (_fileHashes[file.path] != signature) {
            filesToProcess.add(file.path);
            _fileHashes[file.path] = signature; // Update the memory with the new signature
          }
        }
      }
    }

    // If no signatures changed, immediately return the cached data (Saves massive CPU time)
    if (filesToProcess.isEmpty) {
      return _fileDataCache.values.expand((x) => x).toList();
    }

    // Pass ONLY the changed/new files to the background worker
    // The worker now returns a Map tying the file path to its extracted data
    Map<String, List<PeopleCount>> newlyParsedData = await compute(_processSpecificFilesInBackground, filesToProcess);

    // Overwrite the cache for these specific files
    // This perfectly handles the .scb append issue without duplicating data!
    _fileDataCache.addAll(newlyParsedData);

    // Flatten the map into a single list for the dashboard to use
    return _fileDataCache.values.expand((x) => x).toList();
  }
}

// Note: Must remain a top-level function to work with Flutter's 'compute' isolate
// Background worker now returns a Map<FilePath, List<PeopleCount>>
Future<Map<String, List<PeopleCount>>> _processSpecificFilesInBackground(List<String> filePaths) async {
  Map<String, List<PeopleCount>> results = {};

  for (String path in filePaths) {
    List<PeopleCount> fileData = [];
    try {
      File file = File(path);
      // EXTRACT THE FOLDER NAME (e.g., gets "sas1" from "C:\comptage\sas1\260114.scb")
      String folderName = file.parent.path.split(Platform.pathSeparator).last;

      List<int> fileBytes = file.readAsBytesSync();
      String fileContent = utf8.decode(fileBytes, allowMalformed: true);

      // =================================================================
      // 🚀 SMART PARSING LOGIC (Handles XML, FTP Text, and DAT)
      // =================================================================

      if (path.toLowerCase().endsWith('.dat')) {
        // --- PIPE DELIMITED PARSING LOGIC (.dat) ---
        List<String> lines = const LineSplitter().convert(fileContent);

        for (String line in lines) {
          if (line.trim().isEmpty) continue;

          List<String> parts = line.split('|');

          if (parts.length >= 9) {
            String dateTimeStr = parts[6];
            var dtParts = dateTimeStr.split(' ');

            if (dtParts.length >= 2) {
              String datePart = dtParts[0];
              String timePart = dtParts[1].substring(0, 5);

              int inCount = int.tryParse(parts[7]) ?? 0;
              int outCount = int.tryParse(parts[8]) ?? 0;

              String fakeLine = "001\t$datePart\t$timePart\t$inCount\t$outCount\t0\t0";

              try {
                fileData.add(PeopleCount.fromScbLine(fakeLine, folderName));
              } catch (e) {
                print("Error parsing fake SCB line from DAT: $e");
              }
            }
          }
        }
      } else if (fileContent.trim().startsWith('<?xml') || fileContent.trim().startsWith('<RealTimePacket>')) {
        // --- XML PARSING LOGIC (HTTP) ---
        try {
          final document = XmlDocument.parse(fileContent);
          final slices = document.findAllElements('RTSlice');

          for (var slice in slices) {
            if (slice.getAttribute('Type') == 'A') {
              String rawTime = slice.getAttribute('Timestamp') ?? '';

              if (rawTime.isNotEmpty && rawTime.contains('T')) {
                var parts = rawTime.split('T');
                var dateParts = parts[0].split('-');
                var timeParts = parts[1].split(':');

                if (dateParts.length == 3 && timeParts.length >= 2) {
                  String formattedDate = "${dateParts[2]}/${dateParts[1]}/${dateParts[0]}";
                  String formattedTime = "${timeParts[0]}:${timeParts[1]}";

                  int inCount = 0;
                  int outCount = 0;

                  final channels = slice.findAllElements('RTChannel');

                  for (var channel in channels) {
                    String direction = channel.getAttribute('Direction') ?? '';
                    int value = int.tryParse(channel.getAttribute('Value') ?? '0') ?? 0;

                    if (direction == 'E') {
                      inCount += value;
                    } else if (direction == 'X') {
                      outCount += value;
                    }
                  }

                  String fakeLine = "001\t$formattedDate\t$formattedTime\t$inCount\t$outCount\t0\t0";

                  try {
                    fileData.add(PeopleCount.fromScbLine(fakeLine, folderName));
                  } catch (e) {}
                }
              }
            }
          }
        } catch (xmlError) {
          print("Error parsing XML SCB file $path: $xmlError");
        }

      } else {
        // --- PLAIN TEXT PARSING LOGIC (FTP) ---
        List<String> lines = const LineSplitter().convert(fileContent);

        for (String line in lines) {
          if (line.trim().isEmpty || line.startsWith('#') || line.startsWith('Magasin') || line.contains('CNL')) {
            continue;
          }
          try {
            fileData.add(PeopleCount.fromScbLine(line, folderName));
          } catch (e) {
            // Silently skip unreadable lines
          }
        }
      }

      // Save the extracted data specifically to this file's path
      results[path] = fileData;

    } catch (fileError) {
      print("Skipping unreadable file $path: $fileError");
    }
  }

  return results;
}