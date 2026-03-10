// lib/services/folder_scanner_service.dart

import 'dart:io';
import 'dart:convert';
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
    if (!directory.existsSync()) return allData;

    // THE MAGIC FIX: recursive: true allows it to look inside the sas1 and sas2 folders!
    final List<FileSystemEntity> filesInFolder = directory.listSync(recursive: true);

    for (var file in filesInFolder) {
      if (file is File && file.path.toLowerCase().endsWith('.scb')) {
        try {
          // EXTRACT THE FOLDER NAME (e.g., gets "sas1" from "C:\comptage\sas1\260114.scb")
          String folderName = file.parent.path.split(Platform.pathSeparator).last;

          List<int> fileBytes = file.readAsBytesSync();
          String fileContent = utf8.decode(fileBytes, allowMalformed: true);
          List<String> lines = const LineSplitter().convert(fileContent);

          for (String line in lines) {
            if (line.trim().isEmpty || line.startsWith('#') || line.startsWith('Magasin') || line.contains('CNL')) {
              continue;
            }
            try {
              // Pass the folder name into our data model
              allData.add(PeopleCount.fromScbLine(line, folderName));
            } catch (e) { }
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