import 'package:latlong2/latlong.dart';

/// The path a van actually drove on a run: `run_track/{runId}.points`, a list
/// of {lat, lng, t (ms since epoch)} appended by the driving screen
/// (RunHeartbeat) and drawn over the planned route once the run is done.
///
/// Thinned as it is recorded ([keeps]): a point only when the van has moved
/// far enough from the last one kept, and only from a fix good enough to
/// trust. A three-hour run comes to a few hundred points - well inside one
/// document - instead of one every few metres.
class RunTrack {
  const RunTrack(this.points);

  static const empty = RunTrack([]);

  /// Closer than this to the last point kept adds nothing to the picture.
  static const minStepMeters = 25.0;

  /// A fix vaguer than this would draw the van through houses.
  static const maxAccuracyMeters = 40.0;

  /// Stops recording past this, so a phone left on all day can't outgrow the
  /// document (firestore.rules allows the same).
  static const maxPoints = 4000;

  final List<LatLng> points;

  bool get isEmpty => points.length < 2;

  static const _distance = Distance();

  /// Whether a fix at [candidate] should be added after [lastKept].
  static bool keeps(LatLng? lastKept, LatLng candidate, {required double accuracy}) {
    if (accuracy > maxAccuracyMeters) return false;
    if (lastKept == null) return true;
    return _distance.as(LengthUnit.Meter, lastKept, candidate) >= minStepMeters;
  }

  /// Along the points in order - what the van drove, as far as the phone saw.
  double get meters {
    var total = 0.0;
    for (var i = 1; i < points.length; i++) {
      total += _distance.as(LengthUnit.Meter, points[i - 1], points[i]);
    }
    return total;
  }

  factory RunTrack.fromMap(Map<String, dynamic>? data) {
    final raw = (data?['points'] as List?) ?? const [];
    final timed = <(int, LatLng)>[
      for (final point in raw)
        if (point is Map && point['lat'] is num && point['lng'] is num)
          (
            (point['t'] as num?)?.toInt() ?? 0,
            LatLng((point['lat'] as num).toDouble(), (point['lng'] as num).toDouble()),
          ),
    ];
    // In time order: points queued offline can land after later ones.
    timed.sort((a, b) => a.$1.compareTo(b.$1));
    return RunTrack([for (final (_, point) in timed) point]);
  }
}

/// "38.2 km", "850 m".
String formatDistance(double meters) =>
    meters < 1000 ? '${meters.round()} m' : '${(meters / 1000).toStringAsFixed(1)} km';
