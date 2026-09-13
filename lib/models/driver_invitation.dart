import 'package:cloud_firestore/cloud_firestore.dart';

/// What signing in against an invitation grants.
///
/// Owners and drivers are invited through the same flow, because they need
/// the same things: an expiry, an email, and a record of who accepted. Before
/// this, the only way to make a second owner was a Terraform apply.
///
/// The wire values are the backend's vocabulary, not the app's: `rider` is
/// what `firestore.rules`, `handle_sign_in.py` and the API all call the role
/// this app shows as "Driver". Both spellings are load-bearing - see
/// AuthRole.driver - so the label and the stored value differ on purpose.
enum InvitationRole {
  rider('rider', 'Driver'),
  owner('owner', 'Owner');

  const InvitationRole(this.wire, this.label);

  final String wire;
  final String label;

  /// Anything unrecognised - including absent, which is every invitation
  /// written before owners could be invited - reads as the lesser role.
  /// `Invitation.granted_role` in the backend resolves the same way, and for
  /// the same reason: a typo must cost someone access, never grant it.
  static InvitationRole parse(String? raw) {
    for (final role in InvitationRole.values) {
      if (role.wire == raw) return role;
    }
    return InvitationRole.rider;
  }
}

/// Where an invitation has got to.
///
/// Four states, not two. The app used to partition `driver_invitations` into
/// pending and accepted, which left an invitation that had quietly run out of
/// time reading as "still waiting" - the one state that actually needs the
/// owner to do something was the one state they couldn't see.
enum InvitationStatus {
  /// Sent, still inside its window, not yet signed in against.
  pending,

  /// Past `expires_at` and never accepted. `handle_sign_in.py` will now
  /// reject this driver's sign-in rather than grant them a role, so the
  /// owner has to re-invite before they can join.
  expired,

  /// The invited address signed in with Google while the invitation was
  /// live. Set server-side by `before_sign_in_fn.py`; a client cannot claim
  /// it (firestore.rules requires `accepted_at == null` on every client write).
  accepted,

  /// The owner switched this person off. Their record is intact - name,
  /// address, acceptance date and uid all still here - and restoring them is
  /// clearing one field, not re-inviting a colleague who never really left.
  ///
  /// Checked before every other state, and before expiry in particular. A
  /// driver who was removed and whose invitation then lapsed is removed, not
  /// expired: "expired" invites a resend, and a resend would quietly re-hire
  /// them. `handle_sign_in.resolve_sign_in` orders the two the same way.
  removed,
}

/// One row of the Owner's driver list.
///
/// There is no invitation link anywhere in this system and nothing for a
/// driver to click: the `driver_invitations` document *is* the credential,
/// and `before_sign_in_fn.py` authorises the invited address on its next
/// Google sign-in whether or not the email ever arrived. Expiry is therefore
/// a property of this document - `expires_at` compared against the clock -
/// rather than of any token having gone stale.
///
/// `now` is injected rather than read from `DateTime.now()` inside, because
/// every label on this class is a function of the clock and none of them
/// would otherwise be testable.
class DriverInvitation {
  const DriverInvitation({
    required this.email,
    required this.now,
    this.role = InvitationRole.rider,
    this.driverName,
    this.driverNameSource,
    this.acceptedUid,
    this.invitedAt,
    this.expiresAt,
    this.acceptedAt,
    this.removedAt,
    this.inviteCount14d,
    this.firstInviteInWindowAt,
    this.inviteNumberLifetime,
  });

  /// Lowercased invited address, which is also the document id.
  final String email;
  final DateTime now;

  /// What this invitation grants once accepted.
  final InvitationRole role;

  /// What to call this driver. Written either by the owner when inviting or
  /// by `before_sign_in_fn.py` from the Google account's display name -
  /// [driverNameSource] says which, and the owner's wins. Null until either
  /// happens, which is why [displayName] can still fall back to the address.
  final String? driverName;
  final String? driverNameSource;

  /// The driver's Firebase uid, recorded at acceptance. The identity route
  /// assignment and the live board key on; null until they sign in.
  final String? acceptedUid;

  final DateTime? invitedAt;
  final DateTime? expiresAt;
  final DateTime? acceptedAt;

  /// Rate-limit counters, written by the `backfill_invite_counters` Cloud
  /// Function after a successful client write. The Security Rules require
  /// them to be present (firestore.rules `isInvite()`); the Flutter app reads
  /// them to gate the "Resend" button so a tap during the 1-day spacing
  /// window never reaches Firestore. See docs/techdesign.md.
  final int? inviteCount14d;
  final DateTime? firstInviteInWindowAt;
  final int? inviteNumberLifetime;

  /// When the owner switched this person off, or null while they work here.
  ///
  /// Written by the `driver-access` function under the Admin SDK, never by
  /// this app: removing somebody is two writes to two systems - this field
  /// and the Firebase account - and doing only one of them is what leaves a
  /// removed driver still delivering. `firestore.rules` refuses a client
  /// write that sets it to anything but null.
  final DateTime? removedAt;

  bool get isRemoved => removedAt != null;

  /// The name the owner typed beats the one Google supplied, which beats a
  /// guess from the address. Same precedence rule as a route's name and a
  /// stop's instructions - the owner is the only person who reads this list,
  /// so it is their vocabulary that has to survive a driver signing in.
  bool get isOwnerNamed => driverNameSource == 'owner' && (driverName?.trim().isNotEmpty ?? false);

  String get displayName {
    final name = driverName?.trim();
    if (name != null && name.isNotEmpty) return name;
    return nameFromEmail(email);
  }

  InvitationStatus get status {
    // First, and ahead of expiry: see InvitationStatus.removed.
    if (isRemoved) return InvitationStatus.removed;
    if (acceptedAt != null) return InvitationStatus.accepted;
    final expiry = expiresAt;
    // Strictly after, mirroring `Invitation.is_expired` in
    // ports/invitation_repository.py (`now > self.expires_at`). An
    // invitation sitting exactly on its deadline is still accepted by the
    // server, and a client that greyed it out would tell the owner to resend
    // something that was about to work.
    if (expiry != null && now.isAfter(expiry)) return InvitationStatus.expired;
    return InvitationStatus.pending;
  }

  /// Resending is renewing: it rewrites the document with a fresh deadline.
  ///
  /// Deliberately refused for an accepted driver. `isInvite()` in
  /// firestore.rules only asserts that the *incoming* document is unaccepted,
  /// so a resend aimed at someone who had already joined would write
  /// `accepted_at` back to null - they would keep their role claim and keep
  /// driving while the owner's list said they had never signed in. The rules
  /// block it too; this stops the app offering a button that always fails.
  bool get canResend {
    if (status == InvitationStatus.accepted || status == InvitationStatus.removed) {
      return false;
    }
    final invited = invitedAt;
    if (invited != null && !_canResendBySpacing(invited)) return false;
    final count = inviteCount14d;
    if (count != null && count >= 14) return false;
    return true;
  }

  /// When the next resend becomes available, or null if it is available now.
  /// Drives the greyed-out button label ("Resend in 7h").
  DateTime? get resendAvailableAt {
    if (status == InvitationStatus.accepted || status == InvitationStatus.removed) {
      return null;
    }
    final invited = invitedAt;
    if (invited != null) {
      final next = invited.add(const Duration(days: 1));
      if (next.isAfter(now)) return next;
    }
    if (inviteCount14d != null && inviteCount14d! >= 14) {
      final windowEnd = firstInviteInWindowAt?.add(const Duration(days: 14));
      return windowEnd?.add(const Duration(days: 1));
    }
    return null;
  }

  bool _canResendBySpacing(DateTime lastInvite) {
    return now.difference(lastInvite) >= const Duration(days: 1);
  }

  /// Renaming works in every state, including accepted - it is display text,
  /// and it travels as its own narrow write for exactly that reason.
  ///
  /// Removed rows are the exception, and not because the rules refuse it:
  /// renaming somebody who no longer works here is an edit with no reader,
  /// and offering it implies the row is still live.
  bool get canRename => !isRemoved;

  /// Whether Restore is the action this row offers instead of the others.
  bool get canRestore => isRemoved;

  /// The short state word on the row.
  /// Whether this invitation hands over the keys. Worth its own name: the
  /// roster badges it, and the invite dialog confirms it, because inviting an
  /// owner and inviting a driver are not the same size of decision.
  bool get isOwnerInvite => role == InvitationRole.owner;

  String get statusLabel => switch (status) {
    // Named by role, so a roster of both reads as a roster of both rather
    // than calling an owner a driver.
    InvitationStatus.accepted => 'Active ${role.label.toLowerCase()}',
    InvitationStatus.pending => 'Invited',
    InvitationStatus.expired => 'Invitation expired',
    InvitationStatus.removed => 'Removed',
  };

  /// The line under it: when this happened, or when it runs out.
  String get detailLabel => switch (status) {
    InvitationStatus.accepted => acceptedAt == null ? 'Accepted' : 'Accepted ${_ago(acceptedAt!)}',
    InvitationStatus.expired => expiresAt == null ? 'Expired' : 'Expired ${_ago(expiresAt!)}',
    InvitationStatus.pending => expiresAt == null ? 'Awaiting sign-in' : 'Expires ${_ahead(expiresAt!)}',
    // Says when, because the question an owner asks about this row is "when
    // did they leave" rather than anything about the invitation.
    InvitationStatus.removed => removedAt == null ? 'Removed' : 'Removed ${_ago(removedAt!)}',
  };

  /// What the owner has to act on, first. An expired invitation is the only
  /// row that is actually stuck - the driver cannot sign in until it is
  /// resent - so it sorts above one that is merely still waiting, and both
  /// sort above drivers who are already working.
  int get sortRank => switch (status) {
    InvitationStatus.expired => 0,
    InvitationStatus.pending => 1,
    InvitationStatus.accepted => 2,
    // Last, and in practice in its own section: nothing about a removed row
    // needs doing, and a roster that opens on former staff buries the people
    // who currently drive.
    InvitationStatus.removed => 3,
  };

  /// Newest first inside each group, so a fresh invite doesn't land at the
  /// bottom of a long roster.
  static int compare(DriverInvitation a, DriverInvitation b) {
    if (a.sortRank != b.sortRank) return a.sortRank.compareTo(b.sortRank);
    final at = a.invitedAt, bt = b.invitedAt;
    if (at != null && bt != null) return bt.compareTo(at);
    return a.displayName.toLowerCase().compareTo(b.displayName.toLowerCase());
  }

  /// The one line the Owner home quick action shows under "Invite riders".
  ///
  /// Expired comes first because it is the half that needs doing something
  /// about: a pending invitation is simply someone who hasn't got round to
  /// signing in, while an expired one cannot be accepted at all until the
  /// owner resends it. A single count covering both would say "3 invites
  /// pending acceptance" about invitations that can no longer be accepted.
  static String rosterSummary(Iterable<DriverInvitation> invitations) {
    var expired = 0;
    var pending = 0;
    for (final invitation in invitations) {
      if (invitation.status == InvitationStatus.expired) expired++;
      if (invitation.status == InvitationStatus.pending) pending++;
    }

    if (expired == 0 && pending == 0) return 'No invites pending acceptance';

    return [
      if (expired > 0) expired == 1 ? '1 invite expired' : '$expired invites expired',
      if (pending > 0) pending == 1 ? '1 invite pending' : '$pending invites pending',
    ].join(' \u00b7 ');
  }

  factory DriverInvitation.fromDoc(QueryDocumentSnapshot<Map<String, dynamic>> doc, {required DateTime now}) {
    final data = doc.data();
    return DriverInvitation(
      email: data['driver_email'] as String? ?? doc.id,
      now: now,
      role: InvitationRole.parse(data['role'] as String?),
      driverName: data['driver_name'] as String?,
      driverNameSource: data['driver_name_source'] as String?,
      acceptedUid: data['accepted_uid'] as String?,
      invitedAt: (data['invited_at'] as Timestamp?)?.toDate(),
      expiresAt: (data['expires_at'] as Timestamp?)?.toDate(),
      acceptedAt: (data['accepted_at'] as Timestamp?)?.toDate(),
      removedAt: (data['removed_at'] as Timestamp?)?.toDate(),
      // Counters are optional in older docs that predate the rate-limit
      // policy; null means "no information" and `canResend` treats null
      // counts as the most permissive value so an unsynced doc never
      // locks the owner out.
      inviteCount14d: (data['invite_count_14d'] as num?)?.toInt(),
      firstInviteInWindowAt: (data['first_invite_in_window_at'] as Timestamp?)?.toDate(),
      inviteNumberLifetime: (data['invite_number_lifetime'] as num?)?.toInt(),
    );
  }

  /// "aimee.grant@wae.co.nz" -> "Aimee Grant". The last resort, used only
  /// until somebody supplies a real name. Public and static because
  /// `RiderBoardEntry` needs the identical guess - a driver spelled two ways
  /// across two screens reads as two drivers.
  static String nameFromEmail(String email) {
    final local = email.split('@').first;
    final words = local.split(RegExp(r'[._\-+]+')).where((w) => w.isNotEmpty);
    if (words.isEmpty) return email;
    return words.map((w) => w[0].toUpperCase() + w.substring(1)).join(' ');
  }

  String _ago(DateTime then) => switch (_wholeDays(then, now)) {
    <= 0 => 'today',
    1 => 'yesterday',
    final days => '$days days ago',
  };

  String _ahead(DateTime then) => switch (_wholeDays(now, then)) {
    <= 0 => 'today',
    1 => 'tomorrow',
    final days => 'in $days days',
  };

  /// Calendar-day difference, not elapsed 24-hour periods. An invitation
  /// sent at 9pm and read at 8am the next morning is "yesterday" to the
  /// person reading it, however few hours have actually passed.
  static int _wholeDays(DateTime from, DateTime to) {
    final a = DateTime(from.year, from.month, from.day);
    final b = DateTime(to.year, to.month, to.day);
    return b.difference(a).inDays;
  }
}

/// How long a new invitation stays valid, in days.
///
/// The bounds mirror `firestore.rules` the way `RouteName.maxLength` does:
/// the settings screen must not offer a value every write then rejects, and
/// an out-of-range write comes back as a bare `permission-denied` that reads
/// as a sign-in failure.
class InvitationTtl {
  const InvitationTtl._();

  static const int min = 1;
  static const int max = 90;

  /// What a project with no `app_settings/invitations` document uses. Matches
  /// the value the client hardcoded before this was configurable, so turning
  /// the setting on changes nothing until somebody moves it.
  static const int fallback = 7;

  /// The choices the settings screen offers. A slider over 1..90 implies a
  /// precision nobody wants; these are the intervals people actually mean.
  static const List<int> presets = [3, 7, 14, 30];

  static bool isValid(int days) => days >= min && days <= max;

  /// Clamps whatever is stored into range rather than throwing. A value
  /// outside the bounds can only come from a hand-edited document, and an
  /// unopenable settings screen is a worse outcome than a corrected number.
  static int sanitize(Object? raw) {
    final days = raw is int ? raw : int.tryParse('$raw');
    if (days == null || !isValid(days)) return fallback;
    return days;
  }

  static String label(int days) => days == 1 ? '1 day' : '$days days';
}

/// Validation for the two fields the invite form collects, kept beside the
/// model so both are testable without pumping a dialog.
///
/// Both limits mirror `firestore.rules`. An over-long name or a malformed
/// address comes back from Firestore as a bare `permission-denied`, which on
/// screen reads as "you are not signed in" - catching them here is what makes
/// the message describe what the person actually did wrong.
class InviteForm {
  const InviteForm._();

  /// `driver_invitations.driver_name.size() <= 80` in the rules.
  static const int maxNameLength = 80;

  /// Deliberately permissive. This is a sanity check against a typo, not an
  /// attempt to decide which addresses exist - RFC 5322 admits far stranger
  /// addresses than any regex here would, and the real verification is that
  /// the person can sign in to this Google account.
  static final RegExp _email = RegExp(r'^[^@\s]+@[^@\s.]+\.[^@\s]+$');

  static String normalizeEmail(String raw) => raw.trim().toLowerCase();

  /// Null when acceptable.
  static String? emailError(String raw) {
    final email = normalizeEmail(raw);
    if (email.isEmpty) return 'Enter the driver\'s email address.';
    if (!_email.hasMatch(email)) return 'That doesn\'t look like an email address.';
    return null;
  }

  /// Collapses runs of whitespace, so "Pawan  Arora" and "Pawan Arora" are
  /// one name rather than two rows that look identical.
  static String normalizeName(String raw) => raw.trim().replaceAll(RegExp(r'\s+'), ' ');

  /// Null when acceptable. An empty name is not an error - it means "I don't
  /// know it yet", and Google's display name will fill it in on acceptance.
  static String? nameError(String raw) {
    final name = normalizeName(raw);
    if (name.length > maxNameLength) {
      return 'Keep the name to $maxNameLength characters or fewer.';
    }
    return null;
  }

  /// The value to write, or null to leave the field unset.
  static String? nameToSubmit(String raw) {
    final name = normalizeName(raw);
    return name.isEmpty ? null : name;
  }

  /// Whether [value] actually renames [current], as opposed to being the same
  /// name respaced or typed back. Mirrors `RouteName.isRenameOf` - a dialog
  /// that saves when nothing changed writes for no reason, and a confirmation
  /// that fires when nothing changed teaches people to dismiss it unread.
  static bool isRenameOf(String value, String? current) {
    final next = normalizeName(value);
    if (next.isEmpty) return false;
    return next != (current?.trim() ?? '');
  }
}
