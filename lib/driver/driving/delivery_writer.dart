import 'dart:typed_data';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:geolocator/geolocator.dart';

import '../../config/infra_config.dart';
import '../../util/app_log.dart';

/// Every write the driving screen makes, in the exact shapes firestore.rules
/// accepts from the assigned driver - one place, as RouteAssigner is for
/// assignments, because a field too many earns a bare permission-denied.
///
///  * Start / End    `delivery_run.driver_started_at` / `driver_ended_at`
///                   (each once, server time; End needs a Start).
///  * Arrived        the stop's `arrived_at`.
///  * Delivered      the stop's `status`, `delivered_at`, where the phone was
///                   (`delivered_lat`/`lng`/`accuracy_m`, which teach the
///                   backend the real drop point), and the photo
///                   (`pod_photo_url`, uploaded first).
///
/// The backend takes it from there: check-deviation records progress and
/// learns from the run, and notify-run tells the owner.
class DeliveryWriter {
  const DeliveryWriter({required this.runId, required this.ownerUid});

  final String runId;
  final String ownerUid;

  DocumentReference<Map<String, dynamic>> get _run =>
      FirebaseFirestore.instance.collection('delivery_run').doc(runId);

  DocumentReference<Map<String, dynamic>> _stop(String stopId) =>
      _run.collection('delivery_stop').doc(stopId);

  /// Whether this build knows where photos go (InfraConfig).
  static bool get photosAvailable => InfraConfig.podPhotosBucket.isNotEmpty;

  Future<void> start() async {
    AppLog.auth('driving: start run', {'runId': runId});
    await _run.update({'driver_started_at': FieldValue.serverTimestamp()});
  }

  /// End needs a Start in the rules; a run begun by its first delivery
  /// rather than the Start button gets one first.
  Future<void> end({required bool hasStart}) async {
    AppLog.auth('driving: end run', {'runId': runId, 'hasStart': hasStart});
    if (!hasStart) await start();
    await _run.update({'driver_ended_at': FieldValue.serverTimestamp()});
  }

  /// "Leave" on the driving screen mid-run; notify-run tells the owners.
  Future<void> left() async {
    AppLog.auth('driving: left run', {'runId': runId});
    await _run.update({'driver_left_at': FieldValue.serverTimestamp()});
  }

  /// Back on the driving screen after leaving; the owners hear that too.
  Future<void> resumed() async {
    AppLog.auth('driving: resumed run', {'runId': runId});
    await _run.update({'driver_resumed_at': FieldValue.serverTimestamp()});
  }

  Future<void> arrived(String stopId) async {
    AppLog.auth('driving: arrived', {'stopId': stopId});
    await _stop(stopId).update({'arrived_at': FieldValue.serverTimestamp()});
  }

  /// Uploads [photo] (if any - already stamped and shrunk by PhotoStamp),
  /// then marks the stop delivered.
  ///
  /// The photo lives at `{ownerUid}/{runId}/{stopId}.jpg`: one folder per
  /// run, so a run's evidence is one listing, and the stop's `pod_photo_url`
  /// points at it.
  Future<void> delivered(String stopId, {Position? position, Uint8List? photo}) async {
    String? photoUrl;
    if (photo != null && photosAvailable) {
      final path = '$ownerUid/$runId/$stopId.jpg';
      final ref = FirebaseStorage.instanceFor(bucket: InfraConfig.podPhotosBucket).ref(path);
      await ref.putData(
        photo,
        SettableMetadata(contentType: 'image/jpeg', customMetadata: {'run_id': runId, 'stop_id': stopId}),
      );
      photoUrl = '${InfraConfig.podPhotosBucket}/$path';
    }
    AppLog.auth('driving: delivered', {
      'stopId': stopId,
      'photo': photoUrl != null,
      'located': position != null,
    });
    await _stop(stopId).update({
      'status': 'delivered',
      'delivered_at': FieldValue.serverTimestamp(),
      'pod_photo_url': ?photoUrl,
      if (position != null) ...{
        'delivered_lat': position.latitude,
        'delivered_lng': position.longitude,
        'delivered_accuracy_m': position.accuracy,
      },
    });
  }
}
