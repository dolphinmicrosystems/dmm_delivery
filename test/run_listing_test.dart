import 'package:dmm_delivery/models/run_listing.dart';
import 'package:flutter_test/flutter_test.dart';

final now = DateTime(2026, 9, 25, 6, 30); // 6:30am on the 25th

RunListing run({
  String date = '25/09/2026',
  int stops = 60,
  int delivered = 0,
  DateTime? started,
  DateTime? completed,
  DateTime? driverStarted,
  DateTime? driverEnded,
}) => RunListing.fromMap('r', {
  'round_key': 'south',
  'round': 'Run 2',
  'delivery_date': date,
  'stop_count': stops,
  'delivered_count': delivered,
  'started_at': started,
  'completed_at': completed,
  'driver_started_at': driverStarted,
  'driver_ended_at': driverEnded,
});

void main() {
  test('reads the run sheet\'s day-first date', () {
    expect(parseSheetDate('15/07/2026'), DateTime(2026, 7, 15));
    expect(parseSheetDate('2026-07-15'), isNull);
    expect(parseSheetDate('31/13/2026'), isNull);
  });

  group('which tab', () {
    test('a later day is upcoming, today is today, an earlier day is past', () {
      expect(run(date: '26/09/2026').phase(now), RunPhase.upcoming);
      expect(run(date: '25/09/2026').phase(now), RunPhase.today);
      expect(run(date: '24/09/2026').phase(now), RunPhase.past);
    });

    test('a finished run is past even on its own day', () {
      expect(run(completed: now).phase(now), RunPhase.past);
    });
  });

  group('status', () {
    test('today: not started, then on the road, then done', () {
      expect(run().status(now), RunStatus.notStarted);
      expect(run(delivered: 12, started: now).status(now), RunStatus.onTheRoad);
      expect(run(delivered: 60, started: now, completed: now).status(now), RunStatus.done);
    });

    test('a past day tells a part-run from one that never ran', () {
      expect(run(date: '24/09/2026', delivered: 40, started: now).status(now), RunStatus.unfinished);
      expect(run(date: '24/09/2026').status(now), RunStatus.notRun);
    });
  });

  test('progress and actual time come from the live fields', () {
    final done = run(
      delivered: 30,
      stops: 60,
      started: DateTime(2026, 9, 25, 5),
      completed: DateTime(2026, 9, 25, 7, 16),
    );
    expect(done.progress, 0.5);
    expect(done.actualDuration, const Duration(hours: 2, minutes: 16));
  });

  test('upcoming lists soonest first, past lists most recent first', () {
    final runs = [run(date: '28/09/2026'), run(date: '26/09/2026'), run(date: '27/09/2026')];
    expect([for (final r in RunListing.sorted(runs, RunPhase.upcoming)) r.date!.day], [26, 27, 28]);
    expect([for (final r in RunListing.sorted(runs, RunPhase.past)) r.date!.day], [28, 27, 26]);
  });

  group("the driver's Start and End", () {
    test('tapping Start puts the run on the road before any delivery', () {
      expect(run(driverStarted: now).status(now), RunStatus.onTheRoad);
    });

    test('tapping End finishes it: past, and not finished if stops were left', () {
      final ended = run(delivered: 52, started: now, driverStarted: now, driverEnded: now);
      expect(ended.phase(now), RunPhase.past);
      expect(ended.status(now), RunStatus.unfinished);
    });

    test('history runs from the earlier of Start and first delivery, to the finish', () {
      final done = run(
        delivered: 60,
        driverStarted: DateTime(2026, 9, 25, 4, 55),
        started: DateTime(2026, 9, 25, 5, 4),
        completed: DateTime(2026, 9, 25, 7, 10),
        driverEnded: DateTime(2026, 9, 25, 7, 20),
      );
      expect(done.started, DateTime(2026, 9, 25, 4, 55));
      expect(done.finished, DateTime(2026, 9, 25, 7, 10));
      expect(done.totalTime, const Duration(hours: 2, minutes: 15));
    });

    test('no total time until it has both ends', () {
      expect(run(driverStarted: now).totalTime, isNull);
      expect(run().totalTime, isNull);
    });
  });
}
