import 'package:flutter_test/flutter_test.dart';

import 'package:dmm_delivery/models/route_assignment.dart';

/// Mirrors `tests/domain/test_route_assignment.py` in the backend repo. The
/// two resolve the same rows the same way - the backend when it stamps
/// `delivery_run.rider_id` at confirm time, this when it labels a route card.
/// A card that disagreed with the run the driver actually gets would be worse
/// than showing nothing.
final monday = DateTime(2026, 8, 3, 6);

RouteAssignment assignment(
  String? driverUid, {
  DateTime? from,
  DateTime? createdAt,
  String roundKey = 'route-1',
}) {
  return RouteAssignment(
    roundKey: roundKey,
    driverUid: driverUid,
    driverName: driverUid == null ? null : 'Pawan',
    effectiveFrom: from ?? monday,
    createdAt: createdAt ?? from ?? monday,
  );
}

void main() {
  group('activeAt', () {
    test('nobody assigned yet is nobody', () {
      expect(RouteAssignment.activeAt([], monday), isNull);
      expect(RouteAssignment.driverLabel([], monday), 'No driver assigned');
    });

    test('the only assignment applies from its date', () {
      expect(RouteAssignment.activeAt([assignment('pawan')], monday)?.driverUid, 'pawan');
    });

    test('an assignment dated in the future does not apply yet', () {
      // How "Ana takes over on the 15th" is entered on the 1st.
      final future = [assignment('ana', from: monday.add(const Duration(days: 14)))];

      expect(RouteAssignment.activeAt(future, monday), isNull);
    });

    test('forgetting to reassign keeps the same driver indefinitely', () {
      // The headline requirement. Nothing rolls this forward; a row that has
      // taken effect simply stays the most recent one.
      final rows = [assignment('pawan')];

      for (final weeks in [1, 4, 52]) {
        final at = monday.add(Duration(days: 7 * weeks));
        expect(
          RouteAssignment.activeAt(rows, at)?.driverUid,
          'pawan',
          reason: 'lost the driver after ${weeks}w',
        );
      }
    });

    test('a later assignment takes over from its own date and not before', () {
      final rows = [assignment('pawan'), assignment('ana', from: monday.add(const Duration(days: 14)))];

      expect(RouteAssignment.activeAt(rows, monday.add(const Duration(days: 13)))?.driverUid, 'pawan');
      expect(RouteAssignment.activeAt(rows, monday.add(const Duration(days: 14)))?.driverUid, 'ana');
    });

    test('rows are not assumed to arrive in order', () {
      // Firestore returns documents in whatever order the query gives.
      final rows = [assignment('ana', from: monday.add(const Duration(days: 14))), assignment('pawan')];

      expect(RouteAssignment.activeAt(rows, monday.add(const Duration(days: 20)))?.driverUid, 'ana');
    });

    test('taking a route off everybody is an assignment, not a deletion', () {
      // Deleting the row would bring the previous driver back.
      final rows = [assignment('pawan'), assignment(null, from: monday.add(const Duration(days: 7)))];

      expect(RouteAssignment.driverLabel(rows, monday.add(const Duration(days: 8))), 'No driver assigned');
      // ... and the history stands for the week it covered.
      expect(RouteAssignment.activeAt(rows, monday.add(const Duration(days: 1)))?.driverUid, 'pawan');
    });

    test('two assignments for the same day resolve to the one entered second', () {
      final rows = [
        assignment('pawan', createdAt: monday),
        assignment('ana', createdAt: monday.add(const Duration(minutes: 5))),
      ];

      expect(RouteAssignment.activeAt(rows, monday)?.driverUid, 'ana');
    });
  });

  group('driverLabel', () {
    test('names the driver when there is one', () {
      expect(RouteAssignment.driverLabel([assignment('pawan')], monday), 'Pawan');
    });

    test('says something when a row has a driver but no name', () {
      final unnamed = RouteAssignment(roundKey: 'r', driverUid: 'uid', effectiveFrom: monday);

      expect(RouteAssignment.driverLabel([unnamed], monday), 'Assigned');
    });
  });

  group('byRoute', () {
    test('groups so one query can feed a whole list of cards', () {
      final rows = [
        assignment('pawan', roundKey: 'route-1'),
        assignment('ana', roundKey: 'route-2'),
        assignment('ben', roundKey: 'route-1', from: monday.add(const Duration(days: 1))),
      ];

      final grouped = RouteAssignment.byRoute(rows);

      expect(grouped['route-1'], hasLength(2));
      expect(grouped['route-2'], hasLength(1));
      expect(grouped['route-3'], isNull);
    });

    test('a route with no assignments is simply absent', () {
      expect(RouteAssignment.byRoute([]), isEmpty);
    });
  });

  group('routesFor', () {
    test('lists the routes a driver drives now and the ones they start later, not anyone else\'s', () {
      final rows = [
        assignment('ana', roundKey: 'south'),
        assignment('ben', roundKey: 'north'),
        assignment('ben', roundKey: 'city'),
        // Ana takes over City next week.
        assignment('ana', roundKey: 'city', from: monday.add(const Duration(days: 7))),
      ];

      final ana = RouteAssignment.routesFor('ana', rows, monday.add(const Duration(days: 1)));
      final ben = RouteAssignment.routesFor('ben', rows, monday.add(const Duration(days: 1)));

      expect(ana.current, ['south']);
      expect(ana.upcoming.map((a) => a.roundKey), ['city']);
      expect(ben.current..sort(), ['city', 'north']);
      expect(ben.upcoming, isEmpty);
    });

    test('a route taken off the driver is not theirs', () {
      final rows = [
        assignment('ana', roundKey: 'south'),
        assignment(null, roundKey: 'south', from: monday.add(const Duration(days: 2))),
      ];

      expect(RouteAssignment.routesFor('ana', rows, monday.add(const Duration(days: 3))).current, isEmpty);
    });
  });

  group('one-day runs and start times', () {
    // Same cases as the backend's tests/domain/test_route_assignment.py -
    // the two resolve the same rows, and must agree.
    RouteAssignment row(String? driver, int day, {bool oneDay = false, String? start, int? created}) =>
        RouteAssignment(
          roundKey: 'south',
          driverUid: driver,
          driverName: driver,
          effectiveFrom: DateTime(2026, 9, day),
          createdAt: DateTime(2026, 9, created ?? day),
          startTime: start,
          oneDay: oneDay,
        );

    test('applies on its day, and the regular driver is back the next', () {
      final rows = [row('pawan', 1, start: '05:00'), row('ben', 25, oneDay: true, created: 20)];

      expect(RouteAssignment.activeAt(rows, DateTime(2026, 9, 24, 5))!.driverUid, 'pawan');
      expect(RouteAssignment.activeAt(rows, DateTime(2026, 9, 25, 5))!.driverUid, 'ben');
      expect(RouteAssignment.activeAt(rows, DateTime(2026, 9, 26, 5))!.driverUid, 'pawan');
    });

    test('keeps the regular start time unless it sets its own', () {
      final keeps = [row('pawan', 1, start: '05:00'), row('ben', 25, oneDay: true)];
      final sets = [row('pawan', 1, start: '05:00'), row('ben', 25, oneDay: true, start: '04:30')];

      expect(RouteAssignment.activeAt(keeps, DateTime(2026, 9, 25, 3))!.startTime, '05:00');
      expect(RouteAssignment.activeAt(sets, DateTime(2026, 9, 25, 3))!.startTime, '04:30');
    });

    test('the later of two one-day runs for the same day wins', () {
      final rows = [
        row('pawan', 1),
        row('ben', 25, oneDay: true, created: 20),
        row('ana', 25, oneDay: true, created: 21),
      ];
      expect(RouteAssignment.activeAt(rows, DateTime(2026, 9, 25, 5))!.driverUid, 'ana');
    });

    test('a colleague covering one day does not take the route off the regular driver', () {
      final rows = [row('pawan', 1), row('ben', 25, oneDay: true)];

      final pawan = RouteAssignment.routesFor('pawan', rows, DateTime(2026, 9, 25, 5));
      final ben = RouteAssignment.routesFor('ben', rows, DateTime(2026, 9, 20));

      expect(pawan.current, ['south']);
      expect(ben.current, isEmpty);
      expect(ben.upcoming.single.oneDay, isTrue);
    });

    test('the route card says who drives today, and when', () {
      final rows = [row('pawan', 1, start: '05:00'), row('ben', 25, oneDay: true)];
      expect(RouteAssignment.driverLabel(rows, DateTime(2026, 9, 25, 3)), 'ben · 5:00 am');
      expect(RouteAssignment.driverLabel(rows, DateTime(2026, 9, 26, 3)), 'pawan · 5:00 am');
    });
  });
}
