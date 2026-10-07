import 'package:dmm_delivery/driver/driver_schedule.dart';
import 'package:dmm_delivery/models/route_assignment.dart';
import 'package:dmm_delivery/models/run_listing.dart';
import 'package:flutter_test/flutter_test.dart';

final now = DateTime(2026, 10, 5, 9); // Monday 5 Oct, 9 am
final longAgo = DateTime(2026, 9, 1);
const names = {'south': 'South Runsheet', 'run3': 'Run 3'};

RouteAssignment row(
  String route,
  String? driver,
  DateTime from, {
  String? start,
  String? end,
  bool oneDay = false,
}) => RouteAssignment(
  roundKey: route,
  effectiveFrom: from,
  driverUid: driver,
  createdAt: from,
  startTime: start,
  endTime: end,
  oneDay: oneDay,
);

RunListing run(String route, String date, {DateTime? completed}) => RunListing.fromMap('$route-$date', {
  'round_key': route,
  'delivery_date': date,
  'stop_count': 60,
  'completed_at': completed,
});

Map<RunPhase, List<DriverRunCard>> build(List<RunListing> runs, List<RouteAssignment> rows) =>
    DriverSchedule.build(driverUid: 'ana', runs: runs, assignments: rows, routeNames: names, now: now);

void main() {
  test("the driver's runs land in Upcoming, Today and Past, with the day's start time", () {
    final rows = [row('south', 'ana', longAgo, start: '05:00')];
    final cards = build([
      run('south', '06/10/2026'),
      run('south', '05/10/2026'),
      run('south', '02/10/2026', completed: DateTime(2026, 10, 2, 7)),
    ], rows);

    expect(cards[RunPhase.upcoming]!.single.day, DateTime(2026, 10, 6));
    expect(cards[RunPhase.today]!.single.start, '05:00');
    expect(cards[RunPhase.past]!.single.run!.finished, DateTime(2026, 10, 2, 7));
  });

  test('a day they cover shows as a booking until its run sheet is uploaded', () {
    final rows = [
      row('run3', 'ben', longAgo, start: '04:30'),
      row('run3', 'ana', DateTime(2026, 10, 8), oneDay: true),
    ];

    final booking = build([], rows)[RunPhase.upcoming]!.single;
    expect(booking.booking!.oneDay, isTrue);
    expect(booking.routeName, 'Run 3');

    // Once the sheet for that day is confirmed and given to Ana, the run
    // replaces the booking.
    final withRun = build([run('run3', '08/10/2026')], rows)[RunPhase.upcoming]!;
    expect(withRun.single.run, isNotNull);
  });

  test('a route they take over from a later date is upcoming', () {
    final rows = [row('south', 'ben', longAgo), row('south', 'ana', DateTime(2026, 10, 12), start: '05:15')];

    final card = build([], rows)[RunPhase.upcoming]!.single;
    expect(card.day, DateTime(2026, 10, 12));
    expect(card.start, '05:15');
  });

  test('runs of deleted routes are left out', () {
    expect(build([run('gone', '05/10/2026')], const [])[RunPhase.today], isEmpty);
  });

  test("the Routes tab: routes they have now, then ones they take over later", () {
    final rows = [
      row('south', 'ana', longAgo, start: '05:00'),
      row('run3', 'ben', longAgo),
      row('run3', 'ana', DateTime(2026, 10, 12), start: '04:30'),
      // A one-day cover is a day, not a route of theirs.
      row('run3', 'ana', DateTime(2026, 10, 7), oneDay: true),
    ];

    final routes = DriverSchedule.routes(driverUid: 'ana', assignments: rows, routeNames: names, now: now);
    expect(
      [for (final r in routes) (r.name, r.startTime, r.from)],
      [('South Runsheet', '05:00', null), ('Run 3', '04:30', DateTime(2026, 10, 12))],
    );
  });

  test("the owner's finish time reaches the driver's runs and routes", () {
    final rows = [row('south', 'ana', longAgo, start: '20:00', end: '22:44')];

    final today = build([run('south', '05/10/2026')], rows)[RunPhase.today]!.single;
    expect((today.start, today.end), ('20:00', '22:44'));

    final route = DriverSchedule.routes(
      driverUid: 'ana',
      assignments: rows,
      routeNames: names,
      now: now,
    ).single;
    expect((route.startTime, route.endTime), ('20:00', '22:44'));
  });
}
