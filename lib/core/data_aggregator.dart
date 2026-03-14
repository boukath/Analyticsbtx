// lib/core/data_aggregator.dart

import '../models/people_count.dart';

class DataAggregator {
  // --- ADDED: Helper method to safely parse dates for sorting ---
  // This ensures we always process the carry-over chronologically.
  static DateTime _parseDate(String dateStr, [String timeStr = "00:00"]) {
    try {
      var parts = dateStr.split('/');
      if (parts.length == 3) {
        int day = int.parse(parts[0]);
        int month = int.parse(parts[1]);
        int year = int.parse(parts[2]);
        if (year < 100) year += 2000; // Handle YY to YYYY

        int hour = 0;
        if (timeStr != "All Day") {
          var tParts = timeStr.split(':');
          if (tParts.isNotEmpty) hour = int.parse(tParts[0]);
        }
        return DateTime(year, month, day, hour);
      }
      return DateTime.parse(dateStr);
    } catch (e) {
      return DateTime(1970); // Fallback if parsing fails
    }
  }

  static List<PeopleCount> aggregateByDay(List<PeopleCount> rawData) {
    Map<String, PeopleCount> dailyMap = {};

    // 1. Group the raw data by day
    for (var data in rawData) {
      String dateKey = data.date;
      if (dailyMap.containsKey(dateKey)) {
        var existing = dailyMap[dateKey]!;
        dailyMap[dateKey] = PeopleCount(
          shopId: existing.shopId,
          doorName: existing.doorName,
          date: existing.date,
          time: 'All Day',
          inCount: existing.inCount + data.inCount,
          outCount: existing.outCount + data.outCount,
        );
      } else {
        dailyMap[dateKey] = PeopleCount(
          shopId: data.shopId,
          doorName: data.doorName,
          date: data.date,
          time: 'All Day',
          inCount: data.inCount,
          outCount: data.outCount,
        );
      }
    }

    // 2. Sort chronologically so the carry-over flows forward correctly
    var sortedKeys = dailyMap.keys.toList()
      ..sort((a, b) => _parseDate(a).compareTo(_parseDate(b)));

    // 3. Apply the Carry-Over Logic
    List<PeopleCount> finalData = [];
    int carriedIn = 0;
    int carriedOut = 0;

    for (var key in sortedKeys) {
      var dayData = dailyMap[key]!;

      // Add any remainders carried over from the previous day
      int currentIn = dayData.inCount + carriedIn;
      int currentOut = dayData.outCount + carriedOut;

      // Is there 1 person left over?
      int remaining = (currentIn + currentOut) % 2;

      int nextCarriedIn = 0;
      int nextCarriedOut = 0;

      // If there's a remainder, it belongs to whichever side was larger
      if (remaining > 0) {
        if (currentIn > currentOut) {
          nextCarriedIn = 1;
        } else {
          nextCarriedOut = 1;
        }
      }

      // Output the count MINUS the remainder (so it isn't double-counted)
      finalData.add(PeopleCount(
        shopId: dayData.shopId,
        doorName: dayData.doorName,
        date: dayData.date,
        time: dayData.time,
        inCount: currentIn - nextCarriedIn,
        outCount: currentOut - nextCarriedOut,
      ));

      // Save the remainder for the next loop
      carriedIn = nextCarriedIn;
      carriedOut = nextCarriedOut;
    }

    return finalData;
  }

  static List<PeopleCount> aggregateByHour(List<PeopleCount> rawData) {
    Map<String, PeopleCount> hourlyMap = {};

    // 1. Group the raw data by hour
    for (var data in rawData) {
      String hourKey = "${data.time.split(':')[0]}:00";
      String uniqueKey = "${data.date} $hourKey";

      if (hourlyMap.containsKey(uniqueKey)) {
        var existing = hourlyMap[uniqueKey]!;
        hourlyMap[uniqueKey] = PeopleCount(
          shopId: existing.shopId,
          doorName: existing.doorName,
          date: existing.date,
          time: hourKey,
          inCount: existing.inCount + data.inCount,
          outCount: existing.outCount + data.outCount,
        );
      } else {
        hourlyMap[uniqueKey] = PeopleCount(
          shopId: data.shopId,
          doorName: data.doorName,
          date: data.date,
          time: hourKey,
          inCount: data.inCount,
          outCount: data.outCount,
        );
      }
    }

    // 2. Sort chronologically
    var sortedKeys = hourlyMap.keys.toList()
      ..sort((a, b) {
        var dataA = hourlyMap[a]!;
        var dataB = hourlyMap[b]!;
        return _parseDate(dataA.date, dataA.time).compareTo(_parseDate(dataB.date, dataB.time));
      });

    // 3. Apply the Carry-Over Logic
    List<PeopleCount> finalData = [];
    int carriedIn = 0;
    int carriedOut = 0;

    for (var key in sortedKeys) {
      var hourData = hourlyMap[key]!;

      // Add any remainders carried over from the previous hour
      int currentIn = hourData.inCount + carriedIn;
      int currentOut = hourData.outCount + carriedOut;

      // Check for an odd person out
      int remaining = (currentIn + currentOut) % 2;

      int nextCarriedIn = 0;
      int nextCarriedOut = 0;

      // Identify if the remainder was an "In" or an "Out"
      if (remaining > 0) {
        if (currentIn > currentOut) {
          nextCarriedIn = 1;
        } else {
          nextCarriedOut = 1;
        }
      }

      // Important: We subtract nextCarried from this hour's final result so that
      // the charts display the exact right pairs, and double counting is avoided!
      finalData.add(PeopleCount(
        shopId: hourData.shopId,
        doorName: hourData.doorName,
        date: hourData.date,
        time: hourData.time,
        inCount: currentIn - nextCarriedIn,
        outCount: currentOut - nextCarriedOut,
      ));

      // Save for the next hour!
      carriedIn = nextCarriedIn;
      carriedOut = nextCarriedOut;
    }

    return finalData;
  }
}