import 'route_assignment.dart';

/// Who drives each route on one day, from the schedule.
class RosterSlot {
  const RosterSlot({
    required this.roundKey,
    required this.routeName,
    this.driverUid,
    this.driverName,
    this.startTime,
    this.endTime,
    this.cover = false,
    this.off = false,
  });

  final String roundKey;
  final String routeName;
  final String? driverUid;
  final String? driverName;
  final String? startTime;
  final String? endTime;

  /// A one-day row: someone covering, or a day booked on its own.
  final bool cover;

  /// The route doesn't run that day (a "not running" weekday row).
  final bool off;

  bool get hasDriver => driverUid != null;

  /// Nobody is driving a day the route does run.
  bool get needsDriver => !hasDriver && !off;
}

class RosterDay {
  const RosterDay(this.date, this.slots);

  final DateTime date;

  /// Every route, by start time then name.
  final List<RosterSlot> slots;

  int get unassigned => slots.where((s) => s.needsDriver).length;
}

/// The delivery roster: every route on each of the next [days] days, with
/// the driver the schedule names and their times. Read straight off
/// `route_assignments` through [RouteAssignment.activeAt] at midday - the
/// same rule the backend and the Runs tab use - so a one-day cover shows on
/// its day and the regular driver either side of it.
///
/// Pure, and tested in test/week_roster_test.dart.
class WeekRoster {
  const WeekRoster(this.days);

  final List<RosterDay> days;

  /// Route-days in the window with nobody driving.
  int get unassigned => days.fold(0, (sum, day) => sum + day.unassigned);

  static WeekRoster build({
    required Map<String, String> routeNames,
    required Map<String, List<RouteAssignment>> assignmentsByRoute,
    Map<String, String> driverNames = const {},
    required DateTime from,
    int days = 7,
  }) {
    final start = DateTime(from.year, from.month, from.day);
    return WeekRoster([
      for (var i = 0; i < days; i++)
        if (DateTime(start.year, start.month, start.day + i) case final day)
          RosterDay(
            day,
            [
              for (final MapEntry(key: roundKey, value: name) in routeNames.entries)
                if (RouteAssignment.activeAt(
                      assignmentsByRoute[roundKey] ?? const [],
                      DateTime(day.year, day.month, day.day, 12),
                    )
                    case final active)
                  RosterSlot(
                    roundKey: roundKey,
                    routeName: name,
                    driverUid: active?.driverUid,
                    driverName: active?.driverUid == null
                        ? null
                        : (driverNames[active!.driverUid] ?? active.driverName ?? 'Driver'),
                    startTime: active?.startTime,
                    endTime: active?.endTime,
                    cover: active?.oneDay ?? false,
                    off: active?.off ?? false,
                  ),
            ]..sort(_byStart),
          ),
    ]);
  }

  static int _byStart(RosterSlot a, RosterSlot b) {
    final byStart = (a.startTime ?? '99:99').compareTo(b.startTime ?? '99:99');
    return byStart != 0 ? byStart : a.routeName.compareTo(b.routeName);
  }
}
