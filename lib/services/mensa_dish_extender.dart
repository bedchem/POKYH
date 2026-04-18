import 'package:flutter/foundation.dart';
import '../models/dish.dart';
import 'webuntis_service.dart';

/// Extends the Mensa dish list beyond the dates provided in the JSON by
/// cycling through the original weeks as a template. Holiday weeks (detected
/// via WebUntis — a week with zero timetable entries) are skipped so the
/// menu doesn't advance during breaks.
///
/// Example: JSON provides 6 template weeks (week 1..6). After the last
/// Monday in the JSON, we start generating future weeks by cycling:
/// week 1 → week 2 → ... → week 6 → week 1 → ...
/// A week with no lessons in WebUntis is treated as Ferien and consumed
/// without advancing the cycle counter.
class MensaDishExtender {
  /// Number of weeks to extend into the future when a school calendar
  /// source is available.
  static const int defaultWeeksAhead = 10;

  /// Extends the dishes with a WebUntis-backed holiday check.
  /// If [untisService] is null or not logged in, returns the original list
  /// unchanged.
  static Future<List<Dish>> extendWithUntis({
    required List<Dish> dishes,
    required WebUntisService? untisService,
    int weeksAhead = defaultWeeksAhead,
  }) async {
    if (untisService == null || !untisService.isLoggedIn) return dishes;
    return extend(
      dishes: dishes,
      isHolidayWeek: (monday) async {
        try {
          final entries =
              await untisService.getWeekTimetable(weekStart: monday);
          return entries.isEmpty;
        } catch (e) {
          debugPrint('[MensaDishExtender] Ferien-Check Fehler für $monday: $e');
          return null;
        }
      },
      weeksAhead: weeksAhead,
    );
  }

  /// Pure extender. [isHolidayWeek] returns:
  /// - `true`  → holiday week, skip (no dishes, cycle doesn't advance)
  /// - `false` → school week, assign next template week
  /// - `null`  → unknown → stop extending entirely
  static Future<List<Dish>> extend({
    required List<Dish> dishes,
    required Future<bool?> Function(DateTime monday) isHolidayWeek,
    int weeksAhead = defaultWeeksAhead,
  }) async {
    if (dishes.isEmpty || weeksAhead <= 0) return dishes;

    // Group source dishes by the Monday of their week.
    final Map<DateTime, List<Dish>> byWeek = {};
    for (final d in dishes) {
      final monday = _mondayOf(d.date);
      (byWeek[monday] ??= []).add(d);
    }

    final sortedMondays = byWeek.keys.toList()..sort();
    final templateCycle =
        sortedMondays.map((m) => byWeek[m]!).toList(growable: false);
    final cycleLength = templateCycle.length;
    if (cycleLength == 0) return dishes;

    final lastMonday = sortedMondays.last;
    final futureMondays = List<DateTime>.generate(
      weeksAhead,
      (i) => lastMonday.add(Duration(days: (i + 1) * 7)),
    );

    // Check all future weeks for holidays in parallel.
    final holidayChecks = await Future.wait(
      futureMondays.map((m) => isHolidayWeek(m)),
    );

    final extended = List<Dish>.from(dishes);
    int cycleIndex = 0;

    for (int i = 0; i < futureMondays.length; i++) {
      final result = holidayChecks[i];
      if (result == null) break; // unknown → stop extending
      if (result == true) continue; // Ferien → skip, don't advance cycle

      final monday = futureMondays[i];
      final template = templateCycle[cycleIndex % cycleLength];
      for (final t in template) {
        final offset = (t.date.weekday - 1).clamp(0, 6);
        final newDate = DateTime(monday.year, monday.month, monday.day)
            .add(Duration(days: offset));
        extended.add(t.copyWith(
          id: '${t.id}_${_dateKey(newDate)}',
          date: newDate,
        ));
      }
      cycleIndex++;
    }

    extended.sort((a, b) => a.date.compareTo(b.date));
    return extended;
  }

  static DateTime _mondayOf(DateTime d) {
    final day = DateTime(d.year, d.month, d.day);
    return day.subtract(Duration(days: day.weekday - 1));
  }

  static String _dateKey(DateTime d) =>
      '${d.year}${d.month.toString().padLeft(2, '0')}${d.day.toString().padLeft(2, '0')}';
}
