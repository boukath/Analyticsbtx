// lib/core/data_aggregator.dart

import '../models/people_count.dart';

class DataAggregator {

  /// Groups the raw 15-minute data into daily totals.
  static List<PeopleCount> aggregateByDay(List<PeopleCount> rawData) {
    // We use a Map (Dictionary) to group items by their Date string
    Map<String, PeopleCount> dailyMap = {};

    for (var data in rawData) {
      String dateKey = data.date;

      if (dailyMap.containsKey(dateKey)) {
        // If we already have this date, grab the existing total and add the new counts
        var existing = dailyMap[dateKey]!;
        dailyMap[dateKey] = PeopleCount(
          shopId: existing.shopId,
          date: existing.date,
          time: 'All Day', // We replace the specific time with 'All Day'
          inCount: existing.inCount + data.inCount,
          outCount: existing.outCount + data.outCount,
        );
      } else {
        // If this is the first time we see this date, create a new entry
        dailyMap[dateKey] = PeopleCount(
          shopId: data.shopId,
          date: data.date,
          time: 'All Day',
          inCount: data.inCount,
          outCount: data.outCount,
        );
      }
    }

    // Convert the Map back into a flat List for our charts
    return dailyMap.values.toList();
  }

  /// Groups the raw data into hourly totals.
  static List<PeopleCount> aggregateByHour(List<PeopleCount> rawData) {
    Map<String, PeopleCount> hourlyMap = {};

    for (var data in rawData) {
      // Extract just the hour part of the time string (e.g., "09:15" becomes "09:00")
      String hourKey = "${data.time.split(':')[0]}:00";

      // We combine Date and Hour to make a unique key (so 09:00 on Monday doesn't mix with 09:00 on Tuesday)
      String uniqueKey = "${data.date} $hourKey";

      if (hourlyMap.containsKey(uniqueKey)) {
        var existing = hourlyMap[uniqueKey]!;
        hourlyMap[uniqueKey] = PeopleCount(
          shopId: existing.shopId,
          date: existing.date,
          time: hourKey, // Set the time to the rounded hour
          inCount: existing.inCount + data.inCount,
          outCount: existing.outCount + data.outCount,
        );
      } else {
        hourlyMap[uniqueKey] = PeopleCount(
          shopId: data.shopId,
          date: data.date,
          time: hourKey,
          inCount: data.inCount,
          outCount: data.outCount,
        );
      }
    }

    return hourlyMap.values.toList();
  }
}