import 'package:dmm_delivery/models/owner_today.dart';
import 'package:dmm_delivery/models/run_listing.dart';
import 'package:flutter_test/flutter_test.dart';

// Monday 12 October 2026, 6:00 am.
DateTime at(int hour, int minute, {int day = 12}) => DateTime(2026, 10, day, hour, minute);
final now = at(6, 0);

RunListing run(
  String id, {
  String date = '12/10/2026',
  int stops = 60,
  int delivered = 0,
  DateTime? started,
  DateTime? lastDrop,
  DateTime? completed,
}) => RunListing.fromMap(id, {
  'round_key': id,
  'delivery_date': date,
  'stop_count': stops,
  'delivered_count': delivered,
  'estimated_total_s': 7200,
  'started_at': started,
  'last_delivered_at': lastDrop,
  'completed_at': completed,
}, routeName: id);

void main() {
  final crews = <String, RunCrew>{
    'onTime': (driver: 'Ana', startTime: '05:00', endTime: '07:00'),
    'quiet': (driver: 'Ben', startTime: '05:00', endTime: '07:00'),
    'notYet': (driver: 'Cat', startTime: '05:50', endTime: '08:00'),
    'later': (driver: 'Dan', startTime: '09:00', endTime: '11:00'),
    'done': (driver: 'Eve', startTime: '03:00', endTime: '05:00'),
    'tomorrow': (driver: null, startTime: '05:00', endTime: null),
  };
  final runs = [
    run('onTime', delivered: 30, started: at(5, 0), lastDrop: at(5, 59)),
    run('quiet', delivered: 10, started: at(5, 0), lastDrop: at(5, 20)),
    run('notYet'),
    run('later'),
    run('done', stops: 40, delivered: 40, started: at(3, 0), completed: at(4, 50)),
    run('tomorrow', date: '13/10/2026'),
  ];

  final today = OwnerToday.build(runs: runs, crewFor: (r) => crews[r.id]!, now: now);

  test('counts today only', () {
    expect((today.runsToday, today.finishedToday), (5, 1));
    expect((today.stopsToday, today.deliveredToday), (60 * 4 + 40, 30 + 10 + 40));
  });

  test('a quiet app is the worst, then a run nobody drives tomorrow', () {
    expect([for (final r in today.attention) r.run.id], ['quiet', 'tomorrow']);
  });

  test('live is what is on the road, problems first', () {
    expect([for (final r in today.live) r.run.id], ['quiet', 'onTime']);
  });

  test('coming up: today not yet started in start order, then tomorrow', () {
    expect([for (final r in today.comingUp) r.run.id], ['notYet', 'later', 'tomorrow']);
  });

  test('with a heartbeat a quiet run is no longer no-signal - just late, at its pace', () {
    final heard = OwnerToday.build(
      runs: runs,
      crewFor: (r) => crews[r.id]!,
      lastSeen: {'quiet': at(5, 59)},
      now: now,
    );
    final quiet = heard.attention.firstWhere((r) => r.run.id == 'quiet');
    expect(quiet.timing.label, '40 min late');
  });
}
