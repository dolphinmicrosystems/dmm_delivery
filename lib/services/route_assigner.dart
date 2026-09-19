import 'package:cloud_firestore/cloud_firestore.dart';

import '../models/driver_invitation.dart';
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
    bool oneDay = false,
  }) async {
    AppLog.owner('assigning route', {
      'roundKey': roundKey,
      'assigned': driver != null,
      'from': effectiveFrom.toIso8601String(),
      'startTime': startTime,
      'oneDay': oneDay,
    });

    await FirebaseFirestore.instance.collection('route_assignments').add({
      'owner_uid': ownerUid,
      'round_key': roundKey,
      // The uid, not the email: it is what confirm-run-sheet stamps onto
      // delivery_run.rider_id, and what firestore.rules compares against
      // request.auth.uid when the driver opens their run.
      'driver_uid': driver?.acceptedUid,
      'driver_name': driver?.displayName,
      'effective_from': Timestamp.fromDate(effectiveFrom),
      // 24-hour "HH:MM" (run_time.dart), or left out to keep the time that
      // applied before. Both shapes are what the rules accept.
      'start_time': ?startTime,
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
