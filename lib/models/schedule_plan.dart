import 'route_assignment.dart';

/// One route on one day as the schedule has it - before (or without) a run
/// sheet for that day.
class PlannedRun {
  const PlannedRun({
    required this.roundKey,
    required this.routeName,
    required this.day,
    this.driverUid,
    this.driverName,
    this.startTime,
    this.endTime,
    this.covering = false,
  });

  final String roundKey;
  final String routeName;

  /// Local midnight of the day.
  final DateTime day;
  final String? driverUid;
  final String? driverName;
  final String? startTime;
  final String? endTime;

  /// A one-day row: someone covering, or a day booked on its own.
  final bool covering;

  bool get hasDriver => driverUid != null;
}

/// The runs the schedule says are coming, day by day: every route on every
/// day it runs, with its driver and times - what the Upcoming tabs show
/// before the owner uploads that day's run sheet, so "every day" (or "Mon,
/// Tue and weekends") is visible as days, not just a rule.
///
/// Read off `route_assignments` through [RouteAssignment.activeAt] at
/// midday, the same rule as the backend. Left out: days the route doesn't
/// run (`off`), routes nobody has ever scheduled, and days that already
/// have a run sheet ([hasSheet], "roundKey|yyyy-mm-dd" - see [key]) - those
/// show as the real run instead.
///
/// Pure, and tested in test/schedule_plan_test.dart.
class SchedulePlan {
  const SchedulePlan._();

  static const defaultDays = 14;

  static String key(String roundKey, DateTime day) =>
      '$roundKey|${day.year}-${day.month.toString().padLeft(2, '0')}-${day.day.toString().padLeft(2, '0')}';

  static List<PlannedRun> days({
    required Map<String, String> routeNames,
    required Map<String, List<RouteAssignment>> assignmentsByRoute,
    Map<String, String> driverNames = const {},
    Set<String> hasSheet = const {},
    required DateTime from,
    int days = defaultDays,
  }) {
    final start = DateTime(from.year, from.month, from.day);
    final planned = <PlannedRun>[];
    for (var i = 0; i < days; i++) {
      final day = DateTime(start.year, start.month, start.day + i);
      for (final MapEntry(key: roundKey, value: name) in routeNames.entries) {
        if (hasSheet.contains(key(roundKey, day))) continue;
        final active = RouteAssignment.activeAt(
          assignmentsByRoute[roundKey] ?? const [],
          DateTime(day.year, day.month, day.day, 12),
        );
        if (active == null || active.off) continue;
        planned.add(
          PlannedRun(
            roundKey: roundKey,
            routeName: name,
            day: day,
            driverUid: active.driverUid,
            driverName: active.driverUid == null
                ? null
                : (driverNames[active.driverUid] ?? active.driverName ?? 'Driver'),
            startTime: active.startTime,
            endTime: active.endTime,
            covering: active.oneDay,
          ),
        );
      }
    }
    planned.sort((a, b) {
      final byDay = a.day.compareTo(b.day);
      if (byDay != 0) return byDay;
      final byStart = (a.startTime ?? '99:99').compareTo(b.startTime ?? '99:99');
      return byStart != 0 ? byStart : a.routeName.compareTo(b.routeName);
    });
    return planned;
  }
}
