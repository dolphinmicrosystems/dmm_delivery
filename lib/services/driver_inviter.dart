import 'package:cloud_firestore/cloud_firestore.dart';

import '../models/driver_invitation.dart';
import '../util/app_log.dart';

/// Every write the Owner app makes to `driver_invitations`, in one place.
///
/// Same reason `RouteRenamer` exists: `firestore.rules` accepts these writes
/// only in exact shapes, and a caller that adds a field or drops a source
/// gets back a bare `permission-denied`. Four screens' worth of call sites
/// each assembling their own map is how those shapes drift apart.
///
/// The shapes the rules allow, and why:
///
///  * **invite / resend** - the whole document, `accepted_at` null and
///    `expires_at` inside the 90-day ceiling. These are the same write:
///    resending *is* renewing, because there is no link to re-send and the
///    document is the credential.
///  * **rename** - `driver_name` + `driver_name_source` and nothing else.
///    Separate precisely so it can apply to a driver who has already
///    accepted; routed through the invite shape it would blank their
///    `accepted_at` and drop them out of the roster.
///
/// Removing and restoring a driver are *not* here, and not writes at all -
/// see `DriverAccessApi`. They need the Admin SDK to disable the Firebase
/// account, which is the only half that stops a driver who is already signed
/// in, and the rules refuse a client write that sets `removed_at`.
class DriverInviter {
  const DriverInviter._();

  static CollectionReference<Map<String, dynamic>> get _collection =>
      FirebaseFirestore.instance.collection('driver_invitations');

  /// Creates or renews an invitation. The document id is the lowercased
  /// address, so re-inviting the same person renews rather than accumulating
  /// a second row.
  ///
  /// [name] is what the owner typed, and may be null - they don't always know
  /// it, and Google's display name fills the gap on acceptance. When they did
  /// type one it is written with source `owner`, which is what stops signing
  /// in from overwriting it (see `handle_sign_in.resolve_driver_name`).
  static Future<void> invite({
    required String email,
    required String ownerUid,
    required int ttlDays,
    String? name,
    InvitationRole role = InvitationRole.rider,
  }) async {
    final normalized = InviteForm.normalizeEmail(email);
    AppLog.owner('inviting', {'ttlDays': ttlDays, 'named': name != null, 'role': role.wire});

    await _collection.doc(normalized).set({
      'driver_email': normalized,
      // Doubles as the tenant key: this is the business the driver joins, and
      // handle_sign_in reads this exact field to mint their owner_uid claim.
      'invited_by': ownerUid,
      'invited_at': FieldValue.serverTimestamp(),
      // Client-computed rather than a server timestamp: the rules compare it
      // against request.time, and a sentinel has no value to compare. A day
      // of headroom absorbs any plausible clock skew.
      'expires_at': Timestamp.fromDate(DateTime.now().add(Duration(days: ttlDays))),
      'accepted_at': null,
      // Always written, even for a driver. An absent role reads as rider
      // everywhere, so omitting it would work - but a roster where some rows
      // state their role and others imply it is a roster nobody trusts.
      'role': role.wire,
      'driver_name': ?name,
      if (name != null) 'driver_name_source': 'owner',
      // The three rate-limit counter fields (invite_count_14d,
      // first_invite_in_window_at, invite_number_lifetime) are intentionally
      // NOT written here. They are stamped by the `backfill_invite_counters`
      // Cloud Function inside a transaction after this write succeeds; doing
      // them client-side opens a race when two owners invite the same email
      // at the same time. firestore.rules requires the counters to be present
      // and within bounds, so the function must finish before any subsequent
      // write to the same doc.
      'removed_at': null,
    });

    AppLog.owner('invite written', {'ttlDays': ttlDays, 'role': role.wire});
  }

  /// Renews an invitation that is pending or expired, keeping whatever the
  /// driver is already called.
  ///
  /// The name is carried across explicitly because this is a whole-document
  /// write, not a merge - a resend that dropped it would silently un-name
  /// someone the owner had labelled. Only an owner-sourced name is carried:
  /// a name Google supplied belongs to an acceptance that, by definition,
  /// hasn't happened on a row being resent.
  static Future<void> resend({
    required DriverInvitation invitation,
    required String ownerUid,
    required int ttlDays,
  }) {
    AppLog.owner('resending invite', {
      'status': invitation.status.name,
      'ttlDays': ttlDays,
      'role': invitation.role.wire,
    });
    return invite(
      email: invitation.email,
      ownerUid: ownerUid,
      ttlDays: ttlDays,
      name: invitation.isOwnerNamed ? invitation.driverName : null,
      // Carried across explicitly: this is a whole-document write, and a
      // resend that silently downgraded an owner invitation to a driver one
      // would be found out only when they signed in to the wrong app.
      role: invitation.role,
    );
  }

  /// Renames a driver. Works in every state, accepted included.
  ///
  /// Exactly two fields, like `RouteRenamer.rename` - the rules match on
  /// `affectedKeys().hasOnly([...])`, so an added timestamp is rejected
  /// outright rather than ignored.
  static Future<void> rename({required String email, required String name}) async {
    AppLog.owner('renaming driver', {'chars': name.length});
    await _collection.doc(InviteForm.normalizeEmail(email)).update({
      'driver_name': name,
      'driver_name_source': 'owner',
    });
    AppLog.owner('driver renamed', {});
  }

  // Removing and restoring a driver used to live here, as a document delete.
  // Both moved to `DriverAccessApi`, and the delete is gone entirely:
  //
  //  * it was only half a removal - an accepted driver keeps the role claim
  //    minted at sign-in, so deleting the row took them off the owner's list
  //    while they carried on delivering; and
  //  * `delivery_run.rider_id` and `route_assignments.driver_uid` point at
  //    the uid that document carries, so deleting it turned every round they
  //    ever drove into a dangling id.
  //
  // `firestore.rules` now refuses a `driver_invitations` delete outright, so
  // reinstating it here would fail rather than regress quietly.

  /// The sentence to show when one of these writes is refused.
  ///
  /// `permission-denied` is the one worth translating: it is what the rules
  /// return for an over-long name, an out-of-range expiry, and a resend
  /// aimed at a driver who has already accepted - none of which read as a
  /// permission problem to the person who triggered them.
  static String errorMessage(FirebaseException error) {
    if (error.code != 'permission-denied') {
      return 'Couldn\'t save that: ${error.message ?? error.code}';
    }
    return 'That change was rejected. Check the name length and that this '
        'driver hasn\'t already accepted, then try again.';
  }
}
