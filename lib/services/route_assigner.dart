import 'package:cloud_firestore/cloud_firestore.dart';

import '../models/driver_invitation.dart';
import '../models/route_assignment.dart';
import '../util/app_log.dart';

/// Assigning a driver to a route.
///
/// One place, like `RouteRenamer` and `DriverInviter`, because
/// `firestore.rules` accepts an exact field set here and a caller that adds
/// one gets a bare `permission-denied`.
///
/// Every assignment is a **new document**. There is no update and no delete,
/// and the rules refuse both: history is the point. Who drove this route in
/// March stays answerable, a correction is a new row dated the same day
/// rather than an edit that erases what it replaced, and unassigning is a row
/// with no driver rather than a deletion - deleting would bring the previous
/// driver back, which is the opposite of what it means.
class RouteAssigner {
  const RouteAssigner._();

  /// Assigns [driver] to [roundKey] from [effectiveFrom].
  ///
  /// Pass a null [driver] to take the route off everybody.
  ///
  /// Nothing has to be closed off first. The route's driver is whichever row
  /// has most recently taken effect, so this single write is the whole
  /// operation - and it is also why forgetting to reassign next week keeps
  /// the same driver rather than dropping the route.
  static Future<void> assign({
    required String ownerUid,
    required String roundKey,
    required DateTime effectiveFrom,
    DriverInvitation? driver,
    String? startTime,
    String? endTime,
    bool oneDay = false,
  }) => _write(
    ownerUid: ownerUid,
    roundKey: roundKey,
    effectiveFrom: effectiveFrom,
    driverUid: driver?.acceptedUid,
    driverName: driver?.displayName,
    startTime: startTime,
    endTime: endTime,
    oneDay: oneDay,
  );

  /// Takes [roundKey] off whoever drives it, from [from] on: the route has no
  /// driver until the owner assigns one. The driver is notified
  /// (notify-assignment: "No longer on ...").
  static Future<void> removeDriver({
    required String ownerUid,
    required String roundKey,
    required DateTime from,
  }) => _write(ownerUid: ownerUid, roundKey: roundKey, effectiveFrom: from, driverUid: null, driverName: null);

  /// Cancels [booking] - a day's cover, or a handover from a later date - by
  /// writing the row that gives it back (RouteAssignment.replacementFor).
  /// Both drivers are notified: "Cover cancelled" / "Back on", or
  /// "Still on" / "called off".
  static Future<void> cancelBooking({
    required String ownerUid,
    required RouteAssignment booking,
    required Iterable<RouteAssignment> routeRows,
  }) {
    final back = RouteAssignment.replacementFor(booking, routeRows);
    return _write(
      ownerUid: ownerUid,
      roundKey: booking.roundKey,
      effectiveFrom: booking.effectiveFrom,
      driverUid: back.driverUid,
      driverName: back.driverName,
      startTime: back.startTime,
      endTime: back.endTime,
      oneDay: booking.oneDay,
    );
  }

  static Future<void> _write({
    required String ownerUid,
    required String roundKey,
    required DateTime effectiveFrom,
    required String? driverUid,
    required String? driverName,
    String? startTime,
    String? endTime,
    bool oneDay = false,
  }) async {
    AppLog.owner('assigning route', {
      'roundKey': roundKey,
      'assigned': driverUid != null,
      'from': effectiveFrom.toIso8601String(),
      'startTime': startTime,
      'endTime': endTime,
      'oneDay': oneDay,
    });

    await FirebaseFirestore.instance.collection('route_assignments').add({
      'owner_uid': ownerUid,
      'round_key': roundKey,
      // The uid, not the email: it is what confirm-run-sheet stamps onto
      // delivery_run.rider_id, and what firestore.rules compares against
      // request.auth.uid when the driver opens their run.
      'driver_uid': driverUid,
      'driver_name': driverName,
      'effective_from': Timestamp.fromDate(effectiveFrom),
      // 24-hour "HH:MM" (run_time.dart), or left out to keep the time that
      // applied before. Both shapes are what the rules accept.
      'start_time': ?startTime,
      // When the owner expects it finished, "HH:MM" - only with a start time
      // (the rules check both). The driver sees it as "finish by".
      if (startTime != null) 'end_time': ?endTime,
      // Only on effective_from's day; see RouteAssignment.oneDay.
      if (oneDay) 'one_day': true,
      'created_at': FieldValue.serverTimestamp(),
      'created_by': ownerUid,
    });

    AppLog.owner('route assigned', {'roundKey': roundKey});
  }

  /// The sentence to show when the write is refused.
  static String errorMessage(FirebaseException error) {
    return error.code == 'permission-denied'
        ? 'Assigning a driver needs the backend rules update deployed first.'
        : 'Couldn\'t assign this route: ${error.message ?? error.code}';
  }
}
