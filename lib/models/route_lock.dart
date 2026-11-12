import 'package:cloud_firestore/cloud_firestore.dart';

import 'route_assignment.dart';

/// Why a route can't be deleted right now, or null when it can.
///
/// The same two facts firestore.rules checks (the backend's route_locks.py
/// keeps them on the route card): a driver still has the route
/// (`assigned_until`), or a run of it is being driven (`driving_since`). The
/// assignments are checked too, so a route assigned a moment ago is refused
/// before the backend has stamped the card.
///
/// Pure, so it is tested directly (test/route_lock_test.dart).
class RouteLock {
  const RouteLock._(this.title, this.message, {this.canReassign = false});

  final String title;
  final String message;

  /// Taking the route off its driver would lift the lock - offered as a
  /// button. Not for a run being driven: that ends when the driver finishes.
  final bool canReassign;

  /// How long a started run keeps its route; mirrors DRIVING_LOCK_HOURS.
  static const drivingHours = 18;

  static RouteLock? of(Map<String, dynamic> card, List<RouteAssignment> assignments, DateTime now) {
    final since = _time(card['driving_since']);
    if (card['driving_run_id'] != null &&
        since != null &&
        now.difference(since) < const Duration(hours: drivingHours)) {
      return const RouteLock._(
        'Route is being driven',
        "A driver is on this route's run right now. It can be deleted once they complete the run.",
      );
    }

    final active = RouteAssignment.activeAt(assignments, now);
    final until = _time(card['assigned_until']);
    if ((active != null && !active.isUnassignment) || (until != null && until.isAfter(now))) {
      final who = active?.driverName;
      return RouteLock._(
        'Route is assigned',
        '${who == null || who.isEmpty ? 'A driver has' : '$who has'} this route. Take it off '
            'every driver first ("Assign driver" → no driver), then delete it.',
        canReassign: true,
      );
    }
    return null;
  }

  static DateTime? _time(Object? raw) => switch (raw) {
    final Timestamp t => t.toDate(),
    final DateTime d => d,
    _ => null,
  };
}
