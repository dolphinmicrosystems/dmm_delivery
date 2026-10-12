import 'package:dmm_delivery/models/route_assignment.dart';
import 'package:dmm_delivery/models/week_roster.dart';
import 'package:flutter_test/flutter_test.dart';

// Monday 12 October 2026.
final monday = DateTime(2026, 10, 12);

void main() {
  final routes = {'south': 'South Runsheet', 'run3': 'Run 3'};

  test('the regular driver every day, a cover on its own day only, an unassigned route counted', () {
    final roster = WeekRoster.build(
      routeNames: routes,
      assignmentsByRoute: RouteAssignment.byRoute([
        RouteAssignment(
          roundKey: 'south',
          effectiveFrom: DateTime(2026, 9, 1),
          driverUid: 'ana',
          driverName: 'Ana',
          startTime: '05:00',
          endTime: '07:00',
        ),
        RouteAssignment(
          roundKey: 'south',
          effectiveFrom: DateTime(2026, 10, 14),
          driverUid: 'ben',
          driverName: 'Ben',
          oneDay: true,
        ),
      ]),
      driverNames: {'ana': 'Ana Smith'},
      from: monday.add(const Duration(hours: 9)),
    );

    expect(roster.days, hasLength(7));
    final south = [for (final day in roster.days) day.slots.firstWhere((s) => s.roundKey == 'south')];
    expect(
      [for (final s in south) s.driverName],
      [
        'Ana Smith',
        'Ana Smith',
        'Ben', // Wednesday's cover
        'Ana Smith',
        'Ana Smith',
        'Ana Smith',
        'Ana Smith',
      ],
    );
    expect(south[2].cover, isTrue);
    expect(south[2].startTime, '05:00', reason: 'a cover without times keeps the regular ones');
    // Run 3 has nobody, every day; and sorts after the timed route.
    expect(roster.days.first.slots.last.routeName, 'Run 3');
    expect(roster.unassigned, 7);
  });

  test('a hand-over later in the week shows from its day', () {
    final roster = WeekRoster.build(
      routeNames: {'south': 'South Runsheet'},
      assignmentsByRoute: RouteAssignment.byRoute([
        RouteAssignment(
          roundKey: 'south',
          effectiveFrom: DateTime(2026, 9, 1),
          driverUid: 'ana',
          driverName: 'Ana',
        ),
        RouteAssignment(
          roundKey: 'south',
          effectiveFrom: DateTime(2026, 10, 15),
          driverUid: 'ben',
          driverName: 'Ben',
        ),
      ]),
      from: monday,
    );
    expect(
      [for (final day in roster.days) day.slots.single.driverName],
      ['Ana', 'Ana', 'Ana', 'Ben', 'Ben', 'Ben', 'Ben'],
    );
  });
}
