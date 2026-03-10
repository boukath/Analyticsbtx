// lib/services/folder_scanner_service.dart

import 'dart:io';
import 'dart:convert'; // NEW: We need this to handle the custom text decoding
import 'package:flutter/foundation.dart';
import '../models/people_count.dart';

class FolderScannerService {
  Future<List<PeopleCount>> loadScbDataFromFolder(String folderPath) async {
    return await compute(_processFolderInBackground, folderPath);
  }
}

Future<List<PeopleCount>> _processFolderInBackground(String folderPath) async {
  List<PeopleCount> allData = [];

  try {
    final directory = Directory(folderPath);

    if (!directory.existsSync()) {
      return allData;
    }

    final List<FileSystemEntity> filesInFolder = directory.listSync(recursive: false);

    for (var file in filesInFolder) {
      if (file is File && file.path.toLowerCase().endsWith('.scb')) {

        // NEW: We put the try-catch INSIDE the loop.
        // If one file fails, it just skips to the next one!
        try {
          // 1. Read the file as raw computer bytes first
          List<int> fileBytes = file.readAsBytesSync();

          // 2. Decode it into text, explicitly telling Flutter not to crash
          // if it finds a weird character (allowMalformed: true)
          String fileContent = utf8.decode(fileBytes, allowMalformed: true);

          // 3. Split the text into lines
          List<String> lines = const LineSplitter().convert(fileContent);

          for (String line in lines) {
            // Clean the data
            if (line.trim().isEmpty ||
                line.startsWith('#') ||
                line.startsWith('Magasin') ||
                line.contains('CNL')) {
              continue;
            }

            try {
              allData.add(PeopleCount.fromScbLine(line));
            } catch (e) {
              // Silently ignore a corrupted single line
            }
          }
        } catch (fileError) {
          // If a specific file is totally unreadable, we log it but keep going!
          print("Skipping unreadable file ${file.path}: $fileError");
        }
      }
    }
  } catch (e) {
    print("A major background error occurred: $e");
  }

  return allData;
}