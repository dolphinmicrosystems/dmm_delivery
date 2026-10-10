import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:geolocator/geolocator.dart';

import '../../util/app_log.dart';

/// The driving screen's "still here", about once a minute while a run is
/// under way: `run_live/{runId}` - {owner_uid, rider_id, last_seen_at, and
/// where the van is}.
///
/// It is what tells a quiet stretch between deliveries (a long drive, a slow
/// drop) from an app that has stopped: the owner's Live now shows "No signal
/// since 6:40 am" (RunTiming), and the backend's run-alerts tells the owner
/// and nudges the driver, after 20 minutes without a beat or a delivery.
///
/// A document of its own rather than a field on the run, so a beat doesn't
/// wake the run's triggers (notify-run, refresh-run) every minute. Only the
/// run's driver may write it, at server time (firestore.rules).
///
/// It beats only while the driving screen is open: a closed app, a dead
/// battery and lost signal all look the same from here - silence - which is
/// exactly what the owner needs to hear about.
class RunHeartbeat {
  RunHeartbeat({required this.runId, required this.ownerUid, required this.riderId});

  static const every = Duration(minutes: 1);

  final String runId;
  final String ownerUid;
  final String riderId;

  Timer? _timer;
  bool _failedOnce = false;

  late final DocumentReference<Map<String, dynamic>> _doc = FirebaseFirestore.instance
      .collection('run_live')
      .doc(runId);

  /// Beats now and then every minute, asking [position] for the latest fix
  /// and [active] whether the run is still under way.
  void start({required Position? Function() position, required bool Function() active}) {
    if (_timer != null) return;
    void tick() {
      if (active()) _beat(position());
    }

    tick();
    _timer = Timer.periodic(every, (_) => tick());
  }

  void stop() {
    _timer?.cancel();
    _timer = null;
  }

  Future<void> _beat(Position? here) async {
    try {
      await _doc.set({
        'owner_uid': ownerUid,
        'rider_id': riderId,
        'last_seen_at': FieldValue.serverTimestamp(),
        if (here != null) ...{
          'lat': here.latitude,
          'lng': here.longitude,
          'accuracy': here.accuracy,
          if (here.heading >= 0) 'heading': here.heading,
          if (here.speed >= 0) 'speed': here.speed,
        },
        // Merged: a beat without a fix keeps the last known position.
      }, SetOptions(merge: true));
    } catch (error, stack) {
      // Offline beats queue in Firestore's cache and go when signal is back.
      // Log a refusal once, not every minute.
      if (!_failedOnce) AppLog.auth.error('heartbeat failed', error, stack);
      _failedOnce = true;
    }
  }
}
