import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/widgets.dart';

import '../models/run_track.dart';
import '../util/app_log.dart';

/// Follows a run's recorded path (`run_track/{runId}`) for a screen that
/// draws it, from the moment [watchTrack] is first called - which a screen
/// does only once the run has started, so a run nobody has driven reads
/// nothing.
mixin RunTrackWatcher<T extends StatefulWidget> on State<T> {
  RunTrack track = RunTrack.empty;
  StreamSubscription<DocumentSnapshot<Map<String, dynamic>>>? _trackSub;

  void watchTrack(String runId) {
    if (_trackSub != null) return;
    _trackSub = FirebaseFirestore.instance.collection('run_track').doc(runId).snapshots().listen(
      (snap) {
        if (mounted) setState(() => track = RunTrack.fromMap(snap.data()));
      },
      // No path recorded yet reads as "not allowed" (the rules check the
      // document's owner): the summary says no path, which is right.
      onError: (Object error) => AppLog.auth('run track unavailable', {'runId': runId}),
    );
  }

  @override
  void dispose() {
    _trackSub?.cancel();
    super.dispose();
  }
}
