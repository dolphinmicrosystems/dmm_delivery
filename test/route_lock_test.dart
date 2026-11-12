import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:dmm_delivery/models/route_assignment.dart';
import 'package:dmm_delivery/models/route_lock.dart';
import 'package:flutter_test/flutter_test.dart';

final now = DateTime(2026, 11, 12, 16);

RouteAssignment row(String? driver, {int daysAgo = 10}) => RouteAssignment(
  roundKey: 'mosgiel',
  driverUid: driver,
  driverName: driver == null ? null : 'Sonia',
  effectiveFrom: now.subtract(Duration(days: daysAgo)),
);

void main() {
  test('a route nobody has can be deleted', () {
    expect(RouteLock.of({}, [], now), isNull);
    expect(RouteLock.of({}, [row('sonia'), row(null, daysAgo: 1)], now), isNull);
  });

  test('a route with a driver names them and offers to take it off them', () {
    final lock = RouteLock.of({}, [row('sonia')], now)!;
    expect(lock.title, 'Route is assigned');
    expect(lock.message, startsWith('Sonia has this route.'));
    expect(lock.canReassign, isTrue);
  });

  test("the card's assigned_until holds it too - a cover booked for later in the week", () {
    final card = {'assigned_until': Timestamp.fromDate(now.add(const Duration(days: 3)))};
    expect(RouteLock.of(card, [], now)?.title, 'Route is assigned');
    final over = {'assigned_until': Timestamp.fromDate(now.subtract(const Duration(hours: 1)))};
    expect(RouteLock.of(over, [], now), isNull);
  });

  test('a run being driven holds it, until it has gone quiet for a long time', () {
    final driving = {
      'driving_run_id': 'r1',
      'driving_since': Timestamp.fromDate(now.subtract(const Duration(hours: 2))),
    };
    final lock = RouteLock.of(driving, [], now)!;
    expect(lock.title, 'Route is being driven');
    expect(lock.canReassign, isFalse);

    final abandoned = {
      'driving_run_id': 'r1',
      'driving_since': Timestamp.fromDate(now.subtract(const Duration(days: 1))),
    };
    expect(RouteLock.of(abandoned, [], now), isNull);
  });
}
