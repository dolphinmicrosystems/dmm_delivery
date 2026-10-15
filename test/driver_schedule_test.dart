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

    // Tomorrow's sheet is the run; every scheduled day after it, a booking.
    final upcoming = cards[RunPhase.upcoming]!;
    expect((upcoming.first.day, upcoming.first.run != null), (DateTime(2026, 10, 6), true));
    expect([for (final c in upcoming.skip(1)) c.day!.day], [for (var d = 7; d <= 18; d++) d]);
    expect(upcoming.skip(1).every((c) => c.booking != null && c.start == '05:00'), isTrue);
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

    final upcoming = build([], rows)[RunPhase.upcoming]!;
    expect(upcoming.first.day, DateTime(2026, 10, 12));
    expect(upcoming.first.start, '05:15');
    // ...and every day after it, theirs.
    expect([for (final c in upcoming) c.day!.day], [12, 13, 14, 15, 16, 17, 18]);
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

  group('the Home tab', () {
    final rows = [row('south', 'ana', longAgo, start: '05:00'), row('run3', 'ana', longAgo, start: '13:00')];

    test('a run under way is live, and the next is what is still to start', () {
      final driving = RunListing.fromMap('a', {
        'round_key': 'south',
        'delivery_date': '05/10/2026',
        'stop_count': 60,
        'delivered_count': 12,
        'started_at': DateTime(2026, 10, 5, 5, 5),
      });
      final home = DriverSchedule.home(
        build([driving, run('run3', '05/10/2026'), run('south', '06/10/2026')], rows),
        now,
      );

      expect(home.live?.run?.id, 'a');
      expect(home.next?.routeName, 'Run 3');
      expect(home.later.first.day, DateTime(2026, 10, 6));
    });

    test('with nothing under way, the next run up leads', () {
      final home = DriverSchedule.home(build([run('south', '06/10/2026')], rows), now);

      // Today is scheduled (both routes) though no sheet is uploaded yet:
      // today's earliest leads, ahead of tomorrow's run.
      expect(home.live, isNull);
      expect((home.next?.day, home.next?.routeName), (DateTime(2026, 10, 5), 'South Runsheet'));
    });

    test('a finished run is neither live nor next', () {
      final done = run('south', '05/10/2026', completed: DateTime(2026, 10, 5, 7));
      final home = DriverSchedule.home(build([done], rows), now);

      // Done; what is next is today's other scheduled route.
      expect((home.live, home.next?.routeName), (null, 'Run 3'));
    });
  });

  test('only the driver the schedule names today may start the route', () {
    final rows = [
      row('south', 'ana', longAgo),
      row('run3', 'ben', longAgo),
      row('run3', 'ana', DateTime(2026, 10, 5), oneDay: true), // Ana covers Run 3 today
    ];

    expect(DriverSchedule.scheduledToday('ana', rows, 'south', now), isTrue);
    expect(DriverSchedule.scheduledToday('ana', rows, 'run3', now), isTrue);
    expect(DriverSchedule.scheduledToday('ben', rows, 'run3', now), isFalse);
  });

  test('a route on some days of the week shows on those days only', () {
    final rows = [
      RouteAssignment(
        roundKey: 'run3',
        effectiveFrom: longAgo,
        driverUid: 'ana',
        weekdays: const [1, 2, 6, 7],
      ),
      RouteAssignment(roundKey: 'run3', effectiveFrom: longAgo, weekdays: const [3, 4, 5], off: true),
    ];
    final cards = build([], rows);
    // Mon 5 Oct is today; then Tue 6, Sat 10, Sun 11, Mon 12, Tue 13, Sat 17, Sun 18.
    expect(cards[RunPhase.today]!.single.day, DateTime(2026, 10, 5));
    expect([for (final c in cards[RunPhase.upcoming]!) c.day!.day], [6, 10, 11, 12, 13, 17, 18]);
  });

  group('the Home greeting', () {
    final rows = [row('south', 'ana', longAgo, start: '05:00', end: '10:00')];

    test('a run under way, on time or late', () {
      RunListing driving(int delivered) => RunListing.fromMap('a', {
        'round_key': 'south',
        'delivery_date': '05/10/2026',
        'stop_count': 60,
        'delivered_count': delivered,
        'estimated_total_s': 7200,
        'started_at': DateTime(2026, 10, 5, 5),
      });
      final onTime = DriverSchedule.greeting(DriverSchedule.home(build([driving(50)], rows), now), now);
      expect((onTime.text, onTime.tone), ('South Runsheet is live · 50 of 60 delivered', GreetingTone.good));
      // 50 of 60 at 9 am: back ~9:20, on time. 10 of 60: back ~10:40 against 10:00.
      final late = DriverSchedule.greeting(DriverSchedule.home(build([driving(10)], rows), now), now);
      expect(late.tone, GreetingTone.warn);
      expect(late.text, startsWith('South Runsheet · '));
    });

    test('due and not started, coming up later today, tomorrow, or nothing at all', () {
      final due = DriverSchedule.greeting(DriverSchedule.home(build([run('south', '05/10/2026')], rows), now), now);
      expect((due.text, due.tone), ('South Runsheet was due at 5:00 am', GreetingTone.warn));

      final evening = [row('south', 'ana', longAgo, start: '17:00')];
      final later = DriverSchedule.greeting(DriverSchedule.home(build([], evening), now), now);
      expect((later.text, later.tone), ('South Runsheet today at 5:00 pm', GreetingTone.good));

      final tomorrowOnly = [row('south', 'ana', DateTime(2026, 10, 6), start: '05:00')];
      final next = DriverSchedule.greeting(DriverSchedule.home(build([], tomorrowOnly), now), now);
      expect((next.text, next.tone), ('Next: South Runsheet · Tomorrow 5:00 am', GreetingTone.quiet));

      final none = DriverSchedule.greeting(DriverSchedule.home(build([], const []), now), now);
      expect(none.text, 'Nothing scheduled - enjoy the day');
    });
  });
}
