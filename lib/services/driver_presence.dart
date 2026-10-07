import 'package:cloud_firestore/cloud_firestore.dart';

import '../notifications/presence_notification.dart';
import '../util/app_log.dart';

/// Whether a driver is online: the Online switch on the driver's home tab.
///
/// Stored as `driver_presence/{uid}` - {owner_uid, online, changed_at} - which
/// the driver alone writes (firestore.rules). Every change tells the
/// business's owners "Ana is online" / "Ana is offline" (the backend's
/// notify-presence), and the driver's own phone says so too: an ongoing
/// "You're online" while on, replaced by "You're offline" when off.
///
/// No document means offline - a driver who has never switched on.
class DriverPresence {
  const DriverPresence._();

  static DocumentReference<Map<String, dynamic>> _doc(String uid) =>
      FirebaseFirestore.instance.collection('driver_presence').doc(uid);

  static Stream<bool> watch(String uid) => _doc(uid).snapshots().map((snap) => snap.data()?['online'] == true);

  static Future<void> set({required String uid, required String ownerUid, required bool online}) async {
    await _doc(uid).set({'owner_uid': ownerUid, 'online': online, 'changed_at': FieldValue.serverTimestamp()});
    AppLog.auth('presence set', {'online': online});
    await PresenceNotification.show(online: online);
  }

  /// Signing out ends the shift: an owner would otherwise see somebody
  /// "online" who has handed the phone back. Never blocks the sign-out.
  static Future<void> goOfflineOnSignOut({required String uid, required String? ownerUid}) async {
    if (ownerUid == null) return;
    try {
      final snap = await _doc(uid).get();
      if (snap.data()?['online'] == true) {
        await _doc(uid).set({'owner_uid': ownerUid, 'online': false, 'changed_at': FieldValue.serverTimestamp()});
      }
    } catch (error, stack) {
      AppLog.auth.error('presence offline on sign-out failed', error, stack);
    }
  }
}
