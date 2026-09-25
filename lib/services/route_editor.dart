import 'package:cloud_firestore/cloud_firestore.dart';

import '../util/app_log.dart';

/// Editing a confirmed route: moving a stop, taking one off, putting it back.
///
/// Each edit is one batch - every stop's new `seq_order` (and `excluded` for a
/// removal) plus one bump of `delivery_run.order_revision` - so the route is
/// never briefly readable half-reordered, and the backend's refresh-run
/// function sees exactly one change to act on: it redraws the road path,
/// re-times the route and updates the route card's stop count.
///
/// These are the only stop fields `firestore.rules` lets the owner change on a
/// confirmed run (`seq_order`, `excluded`), and the revision may only go up by
/// one. Removal is `excluded`, never a delete: the stop came off a real run
/// sheet, and the next upload of this route reads the run with excluded stops
/// left out - so an edit made here carries forward exactly as one made on the
/// review screen does.
class RouteEditor {
  const RouteEditor._();

  static DocumentReference<Map<String, dynamic>> _run(String runId) =>
      FirebaseFirestore.instance.collection('delivery_run').doc(runId);

  /// Writes [orderedStopIds] - every live stop, in the new order - as the
  /// run's sequence. Stops the map cannot place are the caller's to append,
  /// so they keep their place at the end.
  static Future<void> reorder({
    required String runId,
    required List<String> orderedStopIds,
    required int currentRevision,
  }) {
    AppLog.owner('route reordered', {'runId': runId, 'stops': orderedStopIds.length});
    return _commit(runId, currentRevision, (batch, stops) {
      for (final (index, id) in orderedStopIds.indexed) {
        batch.update(stops.doc(id), {'seq_order': index});
      }
    });
  }

  /// Takes [stopId] off the run and closes the gap it leaves.
  static Future<void> remove({
    required String runId,
    required String stopId,
    required List<String> remainingStopIds,
    required int currentRevision,
  }) {
    AppLog.owner('route stop removed', {'runId': runId});
    return _commit(runId, currentRevision, (batch, stops) {
      // Its seq_order is left where it was: harmless, since excluded stops
      // are filtered out everywhere, and it is where Undo puts it back.
      batch.update(stops.doc(stopId), {'excluded': true});
      for (final (index, id) in remainingStopIds.indexed) {
        batch.update(stops.doc(id), {'seq_order': index});
      }
    });
  }

  /// Puts a removed stop back - Undo. [orderedStopIds] includes it, where it goes.
  static Future<void> restore({
    required String runId,
    required String stopId,
    required List<String> orderedStopIds,
    required int currentRevision,
  }) {
    AppLog.owner('route stop restored', {'runId': runId});
    return _commit(runId, currentRevision, (batch, stops) {
      for (final (index, id) in orderedStopIds.indexed) {
        batch.update(stops.doc(id), {'seq_order': index, if (id == stopId) 'excluded': false});
      }
    });
  }

  static Future<void> _commit(
    String runId,
    int currentRevision,
    void Function(WriteBatch batch, CollectionReference<Map<String, dynamic>> stops) write,
  ) async {
    final batch = FirebaseFirestore.instance.batch();
    write(batch, _run(runId).collection('delivery_stop'));
    // Exactly +1, as the rules require - and the order is now the owner's,
    // which replaces any "updated to match the driver" note.
    batch.update(_run(runId), {'order_revision': currentRevision + 1, 'order_source': 'owner'});
    await batch.commit();
  }

  /// A message fit to show for a refused edit.
  static String errorMessage(FirebaseException error) => error.code == 'permission-denied'
      ? 'Editing a confirmed route needs the latest backend rules deployed.'
      : 'Couldn\'t save that change (${error.code}). Check your connection and try again.';
}
