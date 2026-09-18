import 'package:latlong2/latlong.dart';

/// The run's road path, from `delivery_run.road_legs` - written by the
/// backend's application/road_legs.py from the Google Routes API.
///
/// Keyed by leg id, `"<from address_key>>" "<to address_key>"` with the depot
/// as `depot` (the same ids as learned legs, see DeliveryEstimate). By address
/// pair rather than by position so a stop dragged on the review screen keeps
/// the road shape of every leg that still exists; only the legs the drag
/// created are drawn straight until the new order is confirmed and the
/// backend redraws it.
class RoadLegs {
  const RoadLegs({this.shapes = const {}, this.seconds = const {}});

  /// Leg id -> the points of the road between its two ends.
  final Map<String, List<LatLng>> shapes;

  /// Leg id -> driving time on that road.
  final Map<String, double> seconds;

  bool get isEmpty => shapes.isEmpty;

  /// Reads the run document's field, skipping any leg that is malformed rather
  /// than refusing the lot: one bad leg costs one straight segment.
  factory RoadLegs.fromRun(Object? raw) {
    if (raw is! Map) return const RoadLegs();
    final shapes = <String, List<LatLng>>{};
    final seconds = <String, double>{};
    for (final entry in raw.entries) {
      final leg = entry.value;
      if (leg is! Map) continue;
      final key = entry.key.toString();
      final encoded = leg['polyline'];
      if (encoded is String && encoded.isNotEmpty) {
        final points = decodePolyline(encoded);
        if (points.length >= 2) shapes[key] = points;
      }
      final duration = leg['duration_s'];
      if (duration is num) seconds[key] = duration.toDouble();
    }
    return RoadLegs(shapes: shapes, seconds: seconds);
  }
}

/// Just the driving times off the run document, without decoding any road
/// geometry - for the time estimate, which needs nothing else.
Map<String, double> roadSecondsFromRun(Object? raw) {
  if (raw is! Map) return const {};
  return {
    for (final entry in raw.entries)
      if (entry.value is Map && (entry.value as Map)['duration_s'] is num)
        entry.key.toString(): ((entry.value as Map)['duration_s'] as num).toDouble(),
  };
}

/// Google's encoded polyline format at precision 5, which is what the Routes
/// API returns. Each coordinate is a zig-zag-encoded delta from the previous
/// one, five bits to a character.
///
/// The precision is not a detail. The rider map's backend shape is precision
/// 6 - decode one as the other and nothing fails, the line just lands in the
/// wrong hemisphere - so this decoder is for road legs only.
List<LatLng> decodePolyline(String encoded, {int precision = 5}) {
  final factor = _pow10(precision);
  final points = <LatLng>[];
  var index = 0;
  var lat = 0;
  var lng = 0;

  int? next() {
    var result = 0;
    var shift = 0;
    int byte;
    do {
      if (index >= encoded.length) return null;
      byte = encoded.codeUnitAt(index++) - 63;
      result |= (byte & 0x1f) << shift;
      shift += 5;
    } while (byte >= 0x20);
    return (result & 1) != 0 ? ~(result >> 1) : result >> 1;
  }

  while (index < encoded.length) {
    final dLat = next();
    final dLng = next();
    if (dLat == null || dLng == null) break; // truncated input: keep what decoded
    lat += dLat;
    lng += dLng;
    points.add(LatLng(lat / factor, lng / factor));
  }
  return points;
}

double _pow10(int exponent) {
  var value = 1.0;
  for (var i = 0; i < exponent; i++) {
    value *= 10;
  }
  return value;
}
