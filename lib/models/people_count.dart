// lib/models/people_count.dart

class PeopleCount {
  final String shopId;
  final String doorName; // NEW: Saves if it came from sas1 or sas2
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

  // We now pass the folderName into the factory
  factory PeopleCount.fromScbLine(String line, String folderName) {
    var parts = line.split('\t');
    return PeopleCount(
      shopId: parts[0].trim(),
      doorName: folderName, // Tag it with 'sas1', 'sas2', etc.
      date: parts[1].trim(),
      time: parts[2].trim(),
      inCount: int.tryParse(parts[3].trim()) ?? 0,
      outCount: int.tryParse(parts[4].trim()) ?? 0,
    );
  }
}