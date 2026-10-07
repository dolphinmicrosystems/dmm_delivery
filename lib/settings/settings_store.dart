import 'package:cloud_firestore/cloud_firestore.dart';

import '../models/driver_invitation.dart';
import '../models/run_time.dart';
import '../state/auth_state.dart';
import '../util/app_log.dart';

/// Every setting the app reads and writes, in one place.
///
/// Two kinds, kept in two documents because they belong to different people:
///
///  * **The business's** - `app_settings/{ownerUid}`: how long an invitation
///    lasts, the time allowed at each stop. One answer for everyone in the
///    business; the backend reads them too.
///  * **This person's own** - `user_settings/{uid}`: which alerts an owner
///    wants, and when a driver wants reminding. Two owners of one business can
///    choose differently.
///
/// Both are written merged: each document holds several settings, and a plain
/// set() of one would clear the rest. The Firestore rules accept exact fields,
/// so a new setting needs its field added there (dmm-delivery-app's
/// firestore.rules) before a write of it can succeed.
///
/// Adding a setting: a stream and a setter here, a card in `cards/`, and the
/// card in SettingsScreen.
class SettingsStore {
  const SettingsStore(this._auth);

  final AuthState _auth;

  DocumentReference<Map<String, dynamic>> get _business =>
      FirebaseFirestore.instance.collection('app_settings').doc(_auth.ownerUid ?? '-');

  DocumentReference<Map<String, dynamic>> get _personal =>
      FirebaseFirestore.instance.collection('user_settings').doc(_auth.user?.uid ?? '-');

  // --- The business's -------------------------------------------------------

  /// How long a newly sent invitation stays valid, in days.
  ///
  /// A stream rather than a one-off read because the invite dialog and the
  /// settings control are on screen at the same time - the dialog has to
  /// quote the deadline the owner just changed, not the one it opened with.
  ///
  /// A missing document is not an error: it is a project that has never
  /// changed the setting, and [InvitationTtl.fallback] is what the client
  /// hardcoded before this was configurable.
  Stream<int> invitationTtlDays() =>
      _business.snapshots().map((snap) => InvitationTtl.sanitize(snap.data()?['invitation_ttl_days']));

  /// Writes the invitation validity period.
  ///
  /// Applies to invitations sent *after* it, and to nothing already out
  /// there: `expires_at` is stamped onto each document when it is written, so
  /// shortening the window cannot retroactively expire an invitation somebody
  /// is already holding. Resending is what moves an existing deadline.
  Future<void> setInvitationTtlDays(int days) async {
    AppLog.owner('setting invitation ttl', {'days': days});
    await _business.set({'invitation_ttl_days': days}, SetOptions(merge: true));
  }

  /// How long to allow at a stop for an address nothing has been learned
  /// about yet - the figure the whole estimate rests on until drivers start
  /// delivering through the app.
  Stream<int> defaultStopSeconds() =>
      _business.snapshots().map((snap) => StopTime.sanitize(snap.data()?['default_stop_seconds']));

  /// Writes it. Applies to the next upload and to routes re-timed after it;
  /// addresses drivers have already taught us keep their learned time.
  Future<void> setDefaultStopSeconds(int seconds) async {
    AppLog.owner('setting default stop time', {'seconds': seconds});
    await _business.set({'default_stop_seconds': seconds}, SetOptions(merge: true));
  }

  // --- This person's own ----------------------------------------------------

  /// Whether this person hears "Ana is online" / "Ana is offline". Read by
  /// the backend's notify-presence. Absent means on.
  Stream<bool> driverPresenceAlerts() =>
      _personal.snapshots().map((snap) => snap.data()?['driver_presence_alerts'] != false);

  Future<void> setDriverPresenceAlerts(bool on) async {
    AppLog.owner('setting driver presence alerts', {'on': on});
    await _personal.set({'driver_presence_alerts': on}, SetOptions(merge: true));
  }

  /// Whether this owner hears "Sonia hasn't started Run 3" (run-alerts).
  Stream<bool> lateStartAlerts() =>
      _personal.snapshots().map((snap) => snap.data()?['late_start_alerts'] != false);

  Future<void> setLateStartAlerts(bool on) async {
    AppLog.owner('setting late start alerts', {'on': on});
    await _personal.set({'late_start_alerts': on}, SetOptions(merge: true));
  }

  /// A driver's reminders before each run (run-alerts): on unless turned
  /// off, 30 minutes ahead unless they chose otherwise.
  Stream<RunReminders> runReminders() => _personal.snapshots().map(
    (snap) => RunReminders(
      on: snap.data()?['run_reminders'] != false,
      leadMinutes: RunReminders.sanitize(snap.data()?['reminder_lead_minutes']),
    ),
  );

  Future<void> setRunReminders(bool on) async {
    AppLog.auth('setting run reminders', {'on': on});
    await _personal.set({'run_reminders': on}, SetOptions(merge: true));
  }

  Future<void> setReminderLeadMinutes(int minutes) async {
    AppLog.auth('setting reminder lead', {'minutes': minutes});
    await _personal.set({'reminder_lead_minutes': minutes}, SetOptions(merge: true));
  }
}

/// A driver's reminder choice. The bounds mirror firestore.rules (5 to 240
/// minutes) and the backend's domain/run_alerts.py, whose default is 30.
class RunReminders {
  const RunReminders({required this.on, required this.leadMinutes});

  static const defaultLeadMinutes = 30;
  static const presets = [15, 30, 60, 120];

  final bool on;
  final int leadMinutes;

  static int sanitize(Object? raw) {
    final minutes = (raw as num?)?.toInt();
    return minutes == null || minutes < 5 || minutes > 240 ? defaultLeadMinutes : minutes;
  }

  /// "30 min", "1 h", "2 h".
  static String label(int minutes) => minutes < 60 ? '$minutes min' : '${minutes ~/ 60} h';
}
