// lib/models/people_count.dart

class PeopleCount {
  final String shopId;
  final String doorName; // Saves if it came from sas1, sas2, etc.
  final String date;
  final String time;
  final int inCount;
  final int outCount;

  PeopleCount({
    required this.shopId,
    required this.doorName,
    required this.date,
    required this.time,
    required this.inCount,
    required this.outCount,
  });

  /// Factory constructor to generate a PeopleCount object from a raw SCB text line.
  /// We pass the folderName in to properly tag the camera source.
  factory PeopleCount.fromScbLine(String line, String folderName) {
    var parts = line.split('\t');

    // 🛡️ DEFENSIVE PROGRAMMING: Prevent "Index Out of Bounds" crashes.
    // If the line is corrupted or incomplete, we throw a FormatException
    // which is safely caught and ignored by the try/catch in FolderScannerService.
    if (parts.length < 5) {
      throw const FormatException("Invalid SCB line format: insufficient columns");
    }

    return PeopleCount(
      shopId: parts[0].trim(),
      doorName: folderName, // Tag it with 'sas1', 'sas2', etc.
      date: parts[1].trim(),
      time: parts[2].trim(),
      inCount: int.tryParse(parts[3].trim()) ?? 0,
      outCount: int.tryParse(parts[4].trim()) ?? 0,
    );
  }

  // 🐛 DEBUGGING HELPER: Overriding toString makes terminal prints highly readable.
  @override
  String toString() {
    return 'PeopleCount(door: $doorName, date: $date, time: $time, IN: $inCount, OUT: $outCount)';
  }
}