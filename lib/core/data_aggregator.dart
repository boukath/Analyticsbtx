// lib/core/data_aggregator.dart

import '../models/people_count.dart';

class DataAggregator {
  static List<PeopleCount> aggregateByDay(List<PeopleCount> rawData) {
    Map<String, PeopleCount> dailyMap = {};

    for (var data in rawData) {
      String dateKey = data.date;
      if (dailyMap.containsKey(dateKey)) {
        var existing = dailyMap[dateKey]!;
        dailyMap[dateKey] = PeopleCount(
          shopId: existing.shopId,
          doorName: existing.doorName, // Keep the door name
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
    return dailyMap.values.toList();
  }

  static List<PeopleCount> aggregateByHour(List<PeopleCount> rawData) {
    Map<String, PeopleCount> hourlyMap = {};

    for (var data in rawData) {
      String hourKey = "${data.time.split(':')[0]}:00";
      String uniqueKey = "${data.date} $hourKey";

      if (hourlyMap.containsKey(uniqueKey)) {
        var existing = hourlyMap[uniqueKey]!;
        hourlyMap[uniqueKey] = PeopleCount(
          shopId: existing.shopId,
          doorName: existing.doorName, // Keep the door name
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
    return hourlyMap.values.toList();
  }
}