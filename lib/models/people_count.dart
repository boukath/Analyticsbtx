// lib/models/people_count.dart

class PeopleCount {
  final String shopId;
  final String date;
  final String time;
  final int inCount;  // Represents CNL1 (People entering)
  final int outCount; // Represents CNL2 (People exiting)

  PeopleCount({
    required this.shopId,
    required this.date,
    required this.time,
    required this.inCount,
    required this.outCount,
  });

  /// This is a "factory constructor". It is a special function that takes a
  /// raw line of text from your .scb file and automatically builds a
  /// structured PeopleCount object out of it.
  factory PeopleCount.fromScbLine(String line) {
    // Split the row by the tab character (\t)
    var parts = line.split('\t');

    return PeopleCount(
      shopId: parts[0].trim(), // Magasin
      date: parts[1].trim(),   // Date
      time: parts[2].trim(),   // Heure
      inCount: int.tryParse(parts[3].trim()) ?? 0,  // CNL1
      outCount: int.tryParse(parts[4].trim()) ?? 0, // CNL2
    );
  }
}