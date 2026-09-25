import 'package:flutter_test/flutter_test.dart';

import 'package:dmm_delivery/models/driver_invitation.dart';

/// A fixed clock, so every label below is a fact rather than a race.
final now = DateTime(2026, 8, 25, 14, 30);

DriverInvitation invitation({
  String email = 'driver@gmail.com',
  InvitationRole role = InvitationRole.rider,
  String? driverName,
  String? driverNameSource,
  String? acceptedUid,
  DateTime? invitedAt,
  DateTime? expiresAt,
  DateTime? acceptedAt,
  DateTime? removedAt,
}) {
  return DriverInvitation(
    email: email,
    now: now,
    role: role,
    driverName: driverName,
    driverNameSource: driverNameSource,
    acceptedUid: acceptedUid,
    invitedAt: invitedAt ?? now.subtract(const Duration(days: 2)),
    expiresAt: expiresAt ?? now.add(const Duration(days: 5)),
    acceptedAt: acceptedAt,
    removedAt: removedAt,
  );
}

void main() {
  group('status', () {
    test('a live invitation nobody has signed in against is pending', () {
      expect(invitation().status, InvitationStatus.pending);
    });

    test('a signed-in invitation is accepted', () {
      final accepted = invitation(acceptedAt: now.subtract(const Duration(days: 1)));

      expect(accepted.status, InvitationStatus.accepted);
    });

    test('past its deadline and never accepted is expired', () {
      final stale = invitation(expiresAt: now.subtract(const Duration(days: 4)));

      expect(stale.status, InvitationStatus.expired);
    });

    test('acceptance outranks the deadline', () {
      // Accepting stops the clock mattering. A driver who joined last month
      // is not "expired" because the invitation that let them in has aged
      // out - they already have the role claim.
      final accepted = invitation(
        expiresAt: now.subtract(const Duration(days: 30)),
        acceptedAt: now.subtract(const Duration(days: 31)),
      );

      expect(accepted.status, InvitationStatus.accepted);
    });

    test('an invitation sitting exactly on its deadline is still pending', () {
      // Mirrors `Invitation.is_expired` in the backend, which is `now >
      // expires_at` - strictly after. Greying this row out would tell the
      // owner to resend something the server would still accept.
      expect(invitation(expiresAt: now).status, InvitationStatus.pending);
    });

    test('an invitation with no deadline at all is pending, not expired', () {
      // Defensive: every document written by this app has one, but a missing
      // field must not lock a driver out of a roster they are really on.
      final undated = DriverInvitation(email: 'd@x.com', now: now);

      expect(undated.status, InvitationStatus.pending);
    });
  });

  group('displayName', () {
    test('uses the name somebody supplied', () {
      expect(invitation(driverName: 'Pawan Arora').displayName, 'Pawan Arora');
    });

    test('falls back to a guess from the address', () {
      expect(invitation(email: 'aimee.grant@wae.co.nz').displayName, 'Aimee Grant');
    });

    test('a blank name does not render as an empty row', () {
      expect(invitation(driverName: '   ').displayName, 'Driver');
    });

    test('an address with nothing to split on is shown as it is', () {
      expect(DriverInvitation.nameFromEmail('@nowhere.com'), '@nowhere.com');
    });

    test('splits on the separators addresses actually use', () {
      expect(DriverInvitation.nameFromEmail('mele_f-t+work@x.co'), 'Mele F T Work');
    });
  });

  group('isOwnerNamed', () {
    test('true only when a person chose the name', () {
      expect(invitation(driverName: 'Pawan A.', driverNameSource: 'owner').isOwnerNamed, isTrue);
    });

    test('a name Google supplied is not the owner\'s', () {
      // The distinction drives two things: whether signing in may overwrite
      // it, and whether a resend carries it across.
      expect(invitation(driverName: 'pawan', driverNameSource: 'google').isOwnerNamed, isFalse);
    });

    test('a source without a name claims nothing', () {
      expect(invitation(driverNameSource: 'owner').isOwnerNamed, isFalse);
    });
  });

  group('canResend', () {
    test('a pending invitation can be renewed', () {
      expect(invitation().canResend, isTrue);
    });

    test('an expired one especially can', () {
      expect(invitation(expiresAt: now.subtract(const Duration(days: 1))).canResend, isTrue);
    });

    test('an accepted one cannot, because resending would un-accept them', () {
      // firestore.rules refuses it as well; this is what stops the app
      // offering a menu item that always fails.
      expect(invitation(acceptedAt: now).canResend, isFalse);
    });
  });

  group('labels', () {
    test('an accepted owner is called an owner, not a driver', () {
      final owner = invitation(role: InvitationRole.owner, acceptedAt: now);

      expect(owner.statusLabel, 'Active owner');
    });

    test('an accepted driver reads as active', () {
      final accepted = invitation(acceptedAt: now.subtract(const Duration(days: 3)));

      expect(accepted.statusLabel, 'Active driver');
      expect(accepted.detailLabel, 'Accepted 3 days ago');
    });

    test('a pending invitation says when it runs out', () {
      expect(invitation().detailLabel, 'Expires in 5 days');
    });

    test('an expired one says how long ago', () {
      final stale = invitation(expiresAt: now.subtract(const Duration(days: 4)));

      expect(stale.statusLabel, 'Invitation expired');
      expect(stale.detailLabel, 'Expired 4 days ago');
    });

    test('today and tomorrow are said, not counted', () {
      expect(invitation(expiresAt: now.add(const Duration(hours: 4))).detailLabel, 'Expires today');
      expect(invitation(expiresAt: DateTime(2026, 8, 26, 9)).detailLabel, 'Expires tomorrow');
      expect(invitation(acceptedAt: DateTime(2026, 8, 24, 21)).detailLabel, 'Accepted yesterday');
    });

    test('counts calendar days, not elapsed hours', () {
      // Sent at 9pm, read at 2:30pm the next day: five and a half hours short
      // of a full day, but "yesterday" to the person reading it.
      final lastNight = invitation(acceptedAt: DateTime(2026, 8, 24, 21, 0));

      expect(lastNight.detailLabel, 'Accepted yesterday');
    });

    test('a pending invitation with no deadline still says something', () {
      final undated = DriverInvitation(email: 'd@x.com', now: now);

      expect(undated.detailLabel, 'Awaiting sign-in');
    });
  });

  group('ordering', () {
    test('expired first, then pending, then working drivers', () {
      // The owner scans this list for what is stuck. An expired invitation
      // is the only row that cannot proceed without them.
      final rows = [
        invitation(email: 'active@x.com', acceptedAt: now),
        invitation(email: 'waiting@x.com'),
        invitation(email: 'stale@x.com', expiresAt: now.subtract(const Duration(days: 1))),
      ]..sort(DriverInvitation.compare);

      expect(rows.map((r) => r.email), ['stale@x.com', 'waiting@x.com', 'active@x.com']);
    });

    test('newest first within a group', () {
      final rows = [
        invitation(email: 'older@x.com', invitedAt: now.subtract(const Duration(days: 6))),
        invitation(email: 'newer@x.com', invitedAt: now.subtract(const Duration(days: 1))),
      ]..sort(DriverInvitation.compare);

      expect(rows.map((r) => r.email), ['newer@x.com', 'older@x.com']);
    });

    test('rows with no invite date fall back to name order rather than shuffling', () {
      final rows = [
        DriverInvitation(email: 'zoe@x.com', now: now),
        DriverInvitation(email: 'adam@x.com', now: now),
      ]..sort(DriverInvitation.compare);

      expect(rows.map((r) => r.email), ['adam@x.com', 'zoe@x.com']);
    });
  });

  group('rosterSummary', () {
    test('an empty roster says so', () {
      expect(DriverInvitation.rosterSummary([]), 'No invites pending acceptance');
    });

    test('accepted drivers are not pending anything', () {
      final roster = [invitation(acceptedAt: now), invitation(acceptedAt: now)];

      expect(DriverInvitation.rosterSummary(roster), 'No invites pending acceptance');
    });

    test('counts pending in the plural and the singular', () {
      expect(DriverInvitation.rosterSummary([invitation()]), '1 invite pending');
      expect(DriverInvitation.rosterSummary([invitation(), invitation()]), '2 invites pending');
    });

    test('expired is named separately and leads', () {
      // A single count covering both would say "3 invites pending
      // acceptance" about invitations that can no longer be accepted.
      final roster = [
        invitation(),
        invitation(expiresAt: now.subtract(const Duration(days: 1))),
        invitation(expiresAt: now.subtract(const Duration(days: 9))),
      ];

      expect(DriverInvitation.rosterSummary(roster), '2 invites expired · 1 invite pending');
    });
  });

  group('InviteForm', () {
    test('lowercases and trims the address, because it is the document id', () {
      expect(InviteForm.normalizeEmail('  Driver@Gmail.COM '), 'driver@gmail.com');
    });

    test('rejects an empty address with a sentence about the address', () {
      expect(InviteForm.emailError('  '), isNotNull);
    });

    test('rejects text that is plainly not an address', () {
      expect(InviteForm.emailError('pawan'), isNotNull);
      expect(InviteForm.emailError('pawan@localhost'), isNotNull);
      expect(InviteForm.emailError('a b@c.com'), isNotNull);
    });

    test('accepts ordinary addresses', () {
      expect(InviteForm.emailError('driver@gmail.com'), isNull);
      expect(InviteForm.emailError('a.b+tag@sub.example.co.nz'), isNull);
    });

    test('collapses whitespace in a name', () {
      expect(InviteForm.normalizeName('  Pawan   Arora '), 'Pawan Arora');
    });

    test('accepts a name at the limit firestore.rules enforces', () {
      expect(InviteForm.nameError('x' * InviteForm.maxNameLength), isNull);
    });

    test('rejects one past it client-side, rather than as a permission-denied', () {
      expect(InviteForm.nameError('x' * (InviteForm.maxNameLength + 1)), isNotNull);
    });

    test('an empty name is allowed - it means "I don\'t know it yet"', () {
      expect(InviteForm.nameError(''), isNull);
      expect(InviteForm.nameToSubmit('   '), isNull);
    });

    test('submits the collapsed form', () {
      expect(InviteForm.nameToSubmit(' Pawan   Arora '), 'Pawan Arora');
    });

    group('isRenameOf', () {
      test('a different name is a rename', () {
        expect(InviteForm.isRenameOf('Pawan A.', 'Pawan Arora'), isTrue);
      });

      test('the same name typed back is not', () {
        expect(InviteForm.isRenameOf('Pawan Arora', 'Pawan Arora'), isFalse);
      });

      test('respacing is not', () {
        expect(InviteForm.isRenameOf(' Pawan  Arora ', 'Pawan Arora'), isFalse);
      });

      test('naming someone who had no name is', () {
        expect(InviteForm.isRenameOf('Pawan Arora', null), isTrue);
      });

      test('clearing the field is not a rename', () {
        expect(InviteForm.isRenameOf('', 'Pawan Arora'), isFalse);
      });
    });
  });

  group('InvitationTtl', () {
    test('a missing setting falls back to what the client used to hardcode', () {
      expect(InvitationTtl.sanitize(null), InvitationTtl.fallback);
    });

    test('keeps a value inside the range the rules accept', () {
      expect(InvitationTtl.sanitize(15), 15);
      expect(InvitationTtl.sanitize(InvitationTtl.min), InvitationTtl.min);
      expect(InvitationTtl.sanitize(InvitationTtl.max), InvitationTtl.max);
    });

    test('corrects a value outside it rather than throwing', () {
      // Only reachable from a hand-edited document, and an unopenable
      // settings screen is worse than a corrected number.
      expect(InvitationTtl.sanitize(0), InvitationTtl.fallback);
      expect(InvitationTtl.sanitize(9999), InvitationTtl.fallback);
      expect(InvitationTtl.sanitize('nonsense'), InvitationTtl.fallback);
    });

    test('reads a number stored as a string', () {
      expect(InvitationTtl.sanitize('15'), 15);
    });

    test('every preset is a value the rules will accept', () {
      // The presets are what the settings screen offers; one outside the
      // range would be a chip whose every write comes back denied.
      for (final preset in InvitationTtl.presets) {
        expect(InvitationTtl.isValid(preset), isTrue, reason: '$preset is out of range');
      }
    });

    test('says one day in the singular', () {
      expect(InvitationTtl.label(1), '1 day');
      expect(InvitationTtl.label(14), '14 days');
    });
  });

  group('InvitationRole', () {
    test('round-trips through the wire value the backend and rules use', () {
      expect(InvitationRole.parse('owner'), InvitationRole.owner);
      expect(InvitationRole.parse('rider'), InvitationRole.rider);
    });

    test('the app says Driver where the wire says rider', () {
      // Both spellings are load-bearing - the backend, firestore.rules and the
      // API all say `rider`, and the app has always shown "Driver".
      expect(InvitationRole.rider.wire, 'rider');
      expect(InvitationRole.rider.label, 'Driver');
    });

    test('anything unrecognised resolves down to the lesser role', () {
      // Mirrors Invitation.granted_role() in the backend. A typo, a hand-edited
      // document, or a newer client writing a role this build has never heard
      // of must cost someone access rather than grant it.
      for (final bogus in ['Owner', 'OWNER', 'admin', 'superuser', '', null]) {
        expect(InvitationRole.parse(bogus), InvitationRole.rider, reason: '\$bogus escalated');
      }
    });

    test('an invitation written before roles existed reads as a driver', () {
      // Documents already in Firestore have no `role` field at all.
      expect(invitation().role, InvitationRole.rider);
      expect(invitation().isOwnerInvite, isFalse);
    });

    test('isOwnerInvite names the rows worth badging', () {
      expect(invitation(role: InvitationRole.owner).isOwnerInvite, isTrue);
    });
  });

  group('removal', () {
    test('a removed driver reads as removed, whatever else is true of them', () {
      final gone = invitation(
        acceptedAt: now.subtract(const Duration(days: 40)),
        removedAt: now.subtract(const Duration(days: 1)),
      );

      expect(gone.status, InvitationStatus.removed);
    });

    test('removal is reported ahead of expiry', () {
      // Mirrors handle_sign_in.resolve_sign_in, which checks the same two in
      // the same order. "Expired" invites a resend, and a resend aimed at
      // somebody the owner removed would quietly re-hire them.
      final gone = invitation(
        expiresAt: now.subtract(const Duration(days: 10)),
        removedAt: now.subtract(const Duration(days: 20)),
      );

      expect(gone.status, InvitationStatus.removed);
    });

    test('a removed row offers restore and nothing else', () {
      final gone = invitation(removedAt: now.subtract(const Duration(days: 3)));

      expect(gone.canRestore, isTrue);
      // Both are edits to a live invitation. Renaming somebody who no longer
      // works here is an edit with no reader, and resending would be a re-hire
      // dressed up as a reminder.
      expect(gone.canRename, isFalse);
      expect(gone.canResend, isFalse);
    });

    test('a working driver offers everything except restore', () {
      final working = invitation(acceptedAt: now.subtract(const Duration(days: 5)));

      expect(working.canRestore, isFalse);
      expect(working.canRename, isTrue);
    });

    test('the detail line says when they left, not when the invite lapsed', () {
      // The question an owner asks about this row is "when did they go?". The
      // invitation's own dates stopped being interesting the moment somebody
      // was removed.
      final gone = invitation(
        expiresAt: now.subtract(const Duration(days: 30)),
        removedAt: now.subtract(const Duration(days: 1)),
      );

      expect(gone.statusLabel, 'Removed');
      expect(gone.detailLabel, 'Removed yesterday');
    });

    test('removed rows sort below everyone still working', () {
      final rows = [
        invitation(email: 'gone@gmail.com', removedAt: now.subtract(const Duration(days: 1))),
        invitation(email: 'working@gmail.com', acceptedAt: now.subtract(const Duration(days: 5))),
        invitation(email: 'stuck@gmail.com', expiresAt: now.subtract(const Duration(days: 2))),
      ]..sort(DriverInvitation.compare);

      // Expired first: the only row that is actually stuck.
      expect(rows.map((r) => r.email), ['stuck@gmail.com', 'working@gmail.com', 'gone@gmail.com']);
    });

    test('a removed invitation is not counted as pending on the home card', () {
      // Otherwise the Owner home reports work outstanding for people who have
      // left, and the count never goes down.
      final summary = DriverInvitation.rosterSummary([
        invitation(email: 'gone@gmail.com', removedAt: now.subtract(const Duration(days: 1))),
      ]);

      expect(summary, 'No invites pending acceptance');
    });
  });

  group('the 14-in-14 resend limit agrees with firestore.rules windowOk()', () {
    DriverInvitation withCounters({required int count, required Duration windowAge}) => DriverInvitation(
      email: 'driver@gmail.com',
      now: now,
      invitedAt: now.subtract(const Duration(days: 2)),
      expiresAt: now.subtract(const Duration(days: 1)),
      inviteCount14d: count,
      firstInviteInWindowAt: now.subtract(windowAge),
    );

    test('13 invites in the window still allows one more', () {
      expect(withCounters(count: 13, windowAge: const Duration(days: 5)).canResend, isTrue);
    });

    test('14 invites in a live window blocks, and says when it opens again', () {
      final full = withCounters(count: 14, windowAge: const Duration(days: 5));
      expect(full.canResend, isFalse);
      expect(full.resendAvailableAt, now.add(const Duration(days: 9, seconds: 1)));
    });

    test('once the window has run out, 14 no longer blocks', () {
      final stale = withCounters(count: 14, windowAge: const Duration(days: 20));
      expect(stale.canResend, isTrue);
      expect(stale.resendAvailableAt, isNull);
    });
  });
}
