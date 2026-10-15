import 'package:dmm_delivery/models/route_assignment.dart';
import 'package:dmm_delivery/models/schedule_plan.dart';
import 'package:flutter_test/flutter_test.dart';

// Friday 16 October 2026.
final friday = DateTime(2026, 10, 16, 9);

RouteAssignment row(
  String? driver,
  DateTime from, {
  List<int>? weekdays,
  bool off = false,
  bool oneDay = false,
}) => RouteAssignment(
  roundKey: 'run3',
  effectiveFrom: from,
  driverUid: driver,
  driverName: driver == null ? null : driver[0].toUpperCase() + driver.substring(1),
  startTime: '05:00',
  endTime: '07:49',
  weekdays: weekdays,
  off: off,
  oneDay: oneDay,
);

List<PlannedRun> plan(List<RouteAssignment> rows, {Set<String> hasSheet = const {}}) => SchedulePlan.days(
  routeNames: {'run3': 'Run 3'},
  assignmentsByRoute: RouteAssignment.byRoute(rows),
  hasSheet: hasSheet,
  from: friday,
  days: 7,
);

void main() {
  test('every day: one planned run a day, with its driver and times', () {
    final runs = plan([row('sonia', DateTime(2026, 9, 1))]);
    expect(runs, hasLength(7));
    expect(
      (runs.first.driverName, runs.first.startTime, runs.first.day),
      ('Sonia', '05:00', DateTime(2026, 10, 16)),
    );
  });

  test('Mon, Tue and weekends only: the other days are not running and not shown', () {
    final from = DateTime(2026, 10, 16);
    final runs = plan([
      row('sonia', from, weekdays: [1, 2, 6, 7]),
      row(null, from, weekdays: [3, 4, 5], off: true),
    ]);
    // Fri 16 .. Thu 22: Sat 17, Sun 18, Mon 19, Tue 20.
    expect([for (final r in runs) r.day.day], [17, 18, 19, 20]);
  });

  test('a weekend driver beside an every-day one', () {
    final runs = plan([
      row('sonia', DateTime(2026, 9, 1)),
      row('pawan', DateTime(2026, 10, 16), weekdays: [6, 7]),
    ]);
    expect(
      {for (final r in runs) r.day.day: r.driverUid},
      {16: 'sonia', 17: 'pawan', 18: 'pawan', 19: 'sonia', 20: 'sonia', 21: 'sonia', 22: 'sonia'},
    );
  });

  test(
    "a day with its run sheet uploaded shows as the run, not the plan; a day nobody drives still shows",
    () {
      final runs = plan(
        [row('sonia', DateTime(2026, 9, 1)), row(null, DateTime(2026, 10, 19), oneDay: true)],
        hasSheet: {SchedulePlan.key('run3', DateTime(2026, 10, 16))},
      );
      expect(runs.first.day.day, 17);
      expect(runs.firstWhere((r) => r.day.day == 19).hasDriver, isFalse);
    },
  );

  test('a route nobody ever scheduled plans nothing', () {
    expect(plan([]), isEmpty);
  });
}
