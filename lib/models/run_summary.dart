import 'run_listing.dart';
import 'run_track.dart';

/// How a finished run went, in figures: the summary the driver sees after
/// "Complete run" and the owner sees on the run (and from the "finished"
/// notification).
///
/// Pure, from the run document, its stops and its track, so it is tested
/// directly (test/run_summary_test.dart).
class RunSummary {
  const RunSummary({
    required this.listing,
    required this.total,
    required this.delivered,
    required this.autoDelivered,
    required this.photos,
    required this.track,
  });

  final RunListing listing;

  /// Stops on the run (excluded ones not counted) and how many were delivered.
  final int total;
  final int delivered;

  /// Delivered by the driving screen's countdown after the van drove away,
  /// not by a tap.
  final int autoDelivered;

  /// Deliveries with a photo.
  final int photos;

  final RunTrack track;

  /// The note the driving screen writes on a stop it marks delivered itself
  /// (DrivingLogic.autoConfirmNote; the backend's AUTO_CONFIRM_NOTE).
  static const autoNote = 'Marked delivered automatically after driving away';

  factory RunSummary.from({
    required RunListing listing,
    required List<Map<String, dynamic>> stops,
    RunTrack track = RunTrack.empty,
  }) {
    final live = [
      for (final stop in stops)
        if (stop['excluded'] != true) stop,
    ];
    final delivered = [
      for (final stop in live)
        if (stop['status'] == 'delivered') stop,
    ];
    return RunSummary(
      listing: listing,
      total: live.length,
      delivered: delivered.length,
      autoDelivered: delivered.where((stop) => stop['rider_note'] == autoNote).length,
      photos: delivered.where((stop) => stop['pod_photo_url'] is String).length,
      track: track,
    );
  }

  bool get isFinished => listing.finished != null;
  bool get allDelivered => total > 0 && delivered >= total;
  int get notDelivered => total - delivered;

  /// Start to finish - the driver's Start (or first delivery) to the last
  /// delivery (or their Complete).
  Duration? get took => listing.totalTime;

  /// Over (positive) or under (negative) the estimate; null without both.
  Duration? get againstEstimate {
    final took = this.took, estimate = listing.estimatedTotal;
    return took == null || estimate == null ? null : took - estimate;
  }

  /// Driven, as far as the phone recorded it; null with no path recorded.
  double? get meters => track.isEmpty ? null : track.meters;

  /// Average time per delivered stop.
  Duration? get perStop {
    final took = this.took;
    return took == null || delivered == 0 ? null : Duration(seconds: (took.inSeconds / delivered).round());
  }
}
