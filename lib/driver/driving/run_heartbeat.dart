import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';

import '../../models/run_track.dart';
import '../../util/app_log.dart';

/// The driving screen's "still here", every 15 seconds while a run is
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
/// It also records the path driven: [record] keeps a point each time the van
/// has moved [RunTrack.minStepMeters], and each beat appends the points kept
/// since the last one to `run_track/{runId}` - the line the run's summary
/// draws over the planned route. A document of its own so the owner's live
/// map, which streams run_live, isn't sent the whole path every 15 seconds.
///
/// It beats only while the driving screen is open: a closed app, a dead
/// battery and lost signal all look the same from here - silence - which is
/// exactly what the owner needs to hear about.
class RunHeartbeat {
  RunHeartbeat({required this.runId, required this.ownerUid, required this.riderId});

  /// Often enough for the owner's live map to show the van moving.
  static const every = Duration(seconds: 15);

  final String runId;
  final String ownerUid;
  final String riderId;

  Timer? _timer;
  bool _failedOnce = false;

  /// Points kept and not yet written, the last one kept, and how many so far.
  final List<Map<String, Object>> _pending = [];
  LatLng? _lastKept;
  int _kept = 0;

  late final DocumentReference<Map<String, dynamic>> _track = FirebaseFirestore.instance
      .collection('run_track')
      .doc(runId);

  late final DocumentReference<Map<String, dynamic>> _doc = FirebaseFirestore.instance
      .collection('run_live')
      .doc(runId);

  /// Beats now and then every minute, asking [position] for the latest fix
  /// and [active] whether the run is still under way.
  void start({required Position? Function() position, required bool Function() active}) {
    if (_timer != null) return;
    void tick() {
      if (!active()) return;
      _beat(position());
      flushTrack();
    }

    tick();
    _timer = Timer.periodic(every, (_) => tick());
  }

  void stop() {
    _timer?.cancel();
    _timer = null;
    flushTrack();
  }

  /// A new fix from the driving screen, while the run is under way.
  void record(Position here) {
    final point = LatLng(here.latitude, here.longitude);
    if (_kept >= RunTrack.maxPoints || !RunTrack.keeps(_lastKept, point, accuracy: here.accuracy)) return;
    _lastKept = point;
    _kept++;
    _pending.add({'lat': here.latitude, 'lng': here.longitude, 't': here.timestamp.millisecondsSinceEpoch});
  }

  /// Writes the points kept since the last write. Not awaited by callers:
  /// offline, the write waits in Firestore's queue and goes with signal.
  void flushTrack() {
    if (_pending.isEmpty) return;
    final points = List.of(_pending);
    _pending.clear();
    _track
        .set({
          'owner_uid': ownerUid,
          'rider_id': riderId,
          'updated_at': FieldValue.serverTimestamp(),
          'points': FieldValue.arrayUnion(points),
        }, SetOptions(merge: true))
        .catchError((Object error, StackTrace stack) {
          AppLog.auth.error('track write failed', error, stack);
        });
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
