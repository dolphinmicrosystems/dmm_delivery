import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/widgets.dart';

import '../notifications/presence_notification.dart';

import '../util/app_log.dart';

/// Whether a driver has the app open. There is no switch: the driver's shell
/// marks them online as the app opens or comes back to the front, and offline
/// as it is left (DriverPresenceTracker), and on sign-out.
///
/// Stored as `driver_presence/{uid}` - {owner_uid, online, changed_at} - which
/// the driver alone writes (firestore.rules). Owners see it on Home ("1 of 2
/// drivers online"). The backend's notify-presence tells the owners who asked
/// - in Settings for every driver, or on one driver's page - when a driver
/// opens the app after at least half an hour away; leaving is never sent.
///
/// No document means offline - a driver who has never opened the app.
class DriverPresence {
  const DriverPresence._();

  static DocumentReference<Map<String, dynamic>> _doc(String uid) =>
      FirebaseFirestore.instance.collection('driver_presence').doc(uid);

  static Stream<bool> watch(String uid) =>
      _doc(uid).snapshots().map((snap) => snap.data()?['online'] == true);

  static Future<void> set({required String uid, required String ownerUid, required bool online}) async {
    await _doc(
      uid,
    ).set({'owner_uid': ownerUid, 'online': online, 'changed_at': FieldValue.serverTimestamp()});
    AppLog.auth('presence set', {'online': online});
  }

  /// Signing out ends the shift: an owner would otherwise see somebody
  /// "online" who has handed the phone back. Never blocks the sign-out.
  static Future<void> goOfflineOnSignOut({required String uid, required String? ownerUid}) async {
    if (ownerUid == null) return;
    try {
      final snap = await _doc(uid).get();
      if (snap.data()?['online'] == true) {
        await _doc(
          uid,
        ).set({'owner_uid': ownerUid, 'online': false, 'changed_at': FieldValue.serverTimestamp()});
      }
    } catch (error, stack) {
      AppLog.auth.error('presence offline on sign-out failed', error, stack);
    }
  }
}

/// Keeps `driver_presence` in step with the app: online while it is in front,
/// offline once it is left. Wraps the driver's shell, which exists only while
/// a driver is signed in.
class DriverPresenceTracker extends StatefulWidget {
  const DriverPresenceTracker({super.key, required this.uid, required this.ownerUid, required this.child});

  final String uid;
  final String ownerUid;
  final Widget child;

  @override
  State<DriverPresenceTracker> createState() => _DriverPresenceTrackerState();
}

class _DriverPresenceTrackerState extends State<DriverPresenceTracker> with WidgetsBindingObserver {
  /// The last state written, so hidden-then-paused writes once.
  bool? _online;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    PresenceNotification.clear();
    _set(true);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    switch (state) {
      case AppLifecycleState.resumed:
        _set(true);
      case AppLifecycleState.hidden || AppLifecycleState.paused || AppLifecycleState.detached:
        _set(false);
      case AppLifecycleState.inactive:
        break; // a dialog, the notification shade: still here
    }
  }

  Future<void> _set(bool online) async {
    if (_online == online) return;
    _online = online;
    try {
      await DriverPresence.set(uid: widget.uid, ownerUid: widget.ownerUid, online: online);
    } catch (error, stack) {
      // Offline, the write waits in Firestore's queue; anything else is
      // logged, and the next open or leave tries again.
      AppLog.auth.error('presence update failed', error, stack);
      if (_online == online) _online = null;
    }
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
