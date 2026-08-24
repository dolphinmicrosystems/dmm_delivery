import 'package:cloud_firestore/cloud_firestore.dart';

import '../util/app_log.dart';

/// Renaming an existing route, in one place because two screens do it: the
/// route list's rename dialog, and the update screen when an owner backs out
/// having changed the name but not chosen a PDF.
///
/// The field set is not a detail that may drift between call sites -
/// `firestore.rules` accepts a `circuits` update whose affected keys are
/// **exactly** `round` and `round_source`, so a caller that adds a timestamp
/// or omits the source gets a bare `permission-denied`. One function, one
/// write, one message for when it's refused.
///
/// Deliberately not used by the review screen: that screen sends the name
/// with its confirm write to `run_sheet_upload`, because the circuit it would
/// name may not exist yet - `circuits/{roundKey}` is created by
/// confirm-run-sheet, not by the upload.
class RouteRenamer {
  const RouteRenamer._();

  /// Writes the owner's chosen name to `circuits/{roundKey}`.
  ///
  /// `round_source: 'owner'` is what stops the next upload's parsed "Run 2"
  /// reclaiming the name - see `_resolve_route_name` in
  /// process_run_sheet_upload.py. A rename that set only `round` would
  /// silently revert on the next sheet.
  ///
  /// Note what is *not* written: `updated_at`. The route list orders by it,
  /// and renaming a route is not activity on it - a rename should not jump a
  /// dormant route to the top of the list. The rules would reject the field
  /// anyway, which is the same decision enforced from the other side.
  static Future<void> rename({required String roundKey, required String name}) async {
    AppLog.owner('renaming route', {'roundKey': roundKey});
    await FirebaseFirestore.instance.collection('circuits').doc(roundKey).update({
      'round': name,
      'round_source': 'owner',
    });
    AppLog.owner('route renamed', {'roundKey': roundKey});
  }

  /// The sentence to show a person when [rename] is refused. A rejected
  /// rename is almost always the rules not being deployed yet, and a bare
  /// "permission denied" reads as a sign-in problem.
  static String errorMessage(FirebaseException error) {
    return error.code == 'permission-denied'
        ? 'Renaming a route needs the backend rules update deployed first.'
        : 'Could not rename this route: ${error.message ?? error.code}';
  }
}
