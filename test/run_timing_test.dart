import 'package:dmm_delivery/models/run_listing.dart';
import 'package:dmm_delivery/models/run_timing.dart';
import 'package:flutter_test/flutter_test.dart';

// Today, 10 Oct 2026. A 60-stop run, scheduled 5:00 - 7:00 am, estimated 2 h.
DateTime at(int hour, int minute) => DateTime(2026, 10, 10, hour, minute);

RunListing run({
  int delivered = 0,
  DateTime? started,
  DateTime? lastDrop,
  DateTime? completed,
  String date = '10/10/2026',
}) => RunListing.fromMap('r', {
  'round_key': 'run3',
  'delivery_date': date,
  'stop_count': 60,
  'delivered_count': delivered,
  'estimated_total_s': 7200,
  'started_at': started,
  'last_delivered_at': lastDrop,
  'completed_at': completed,
});

RunTiming timing(RunListing r, DateTime now, {DateTime? lastSeen}) =>
    RunTiming.of(run: r, startTime: '05:00', endTime: '07:00', lastSeen: lastSeen, now: now);

void main() {
  test('before the start, and a few minutes after it, is just not started', () {
    expect(timing(run(), at(4, 30)).kind, TimingKind.notStarted);
    expect(timing(run(), at(5, 8)).kind, TimingKind.notStarted);
  });

  test('ten minutes past the start with nothing done is a late start', () {
    final t = timing(run(), at(5, 25));
    expect((t.kind, t.label), (TimingKind.lateStart, 'Not started - 25 min late'));
  });

  test('half done halfway through is on time', () {
    final t = timing(run(delivered: 30, started: at(5, 0), lastDrop: at(5, 58)), at(6, 0));
    expect(t.kind, TimingKind.onTime);
  });

  test('a third done two thirds of the way through is late, by the projected overrun', () {
    // 40 stops left of 60 = 80 min more from 6:20 -> 7:40, against 7:00.
    final t = timing(run(delivered: 20, started: at(5, 0), lastDrop: at(6, 19)), at(6, 20));
    expect((t.kind, t.label), (TimingKind.late, '40 min late'));
  });

  test('20 minutes without a delivery or a heartbeat is no signal - a heartbeat keeps it alive', () {
    final quiet = run(delivered: 10, started: at(5, 0), lastDrop: at(5, 30));
    expect(timing(quiet, at(5, 55)).label, 'No signal since 5:30 am');
    expect(timing(quiet, at(5, 55), lastSeen: at(5, 54)).kind, isNot(TimingKind.noSignal));
  });

  test('finished, on time or late', () {
    expect(timing(run(delivered: 60, started: at(5, 0), completed: at(6, 58)), at(9, 0)).label, 'Finished');
    expect(
      timing(run(delivered: 60, started: at(5, 0), completed: at(7, 20)), at(9, 0)).label,
      'Finished 20 min late',
    );
  });

  test('a day gone by without finishing is not finished', () {
    expect(
      timing(run(date: '09/10/2026', delivered: 10, started: at(5, 0)), at(9, 0)).kind,
      TimingKind.unfinished,
    );
  });

  test('a driver who tapped Leave shows as left until they come back', () {
    RunListing r({DateTime? back}) => RunListing.fromMap('r', {
      'delivery_date': '10/10/2026',
      'stop_count': 60,
      'delivered_count': 20,
      'estimated_total_s': 7200,
      'driver_started_at': at(5, 0),
      'driver_left_at': at(5, 40),
      'driver_resumed_at': back,
    });
    expect(timing(r(), at(5, 45)).label, 'Left at 5:40 am');
    expect(timing(r(back: at(5, 50)), at(5, 55)).kind, isNot(TimingKind.left));
  });
}
