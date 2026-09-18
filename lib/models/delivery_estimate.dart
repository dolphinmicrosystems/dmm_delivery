import 'dart:math' as math;

import 'package:latlong2/latlong.dart';

import 'run_stop.dart';

/// How long a run takes in a given order: driving between stops plus a minute
/// parked at each one.
///
/// A mirror of `domain/travel_time.py` in the backend repo, the way
/// `DepotLocator.addressKey` mirrors `firestore_paths.address_key`. The backend
/// estimates the order it proposes; this re-estimates on the device the
/// moment the owner drags a stop, without a round trip. The constants and the
/// formula are a contract - change one side and you must change the other,
/// or the figure jumps when the screen is reopened.
///
/// Learned leg times - how long drivers have really taken between two
/// addresses - arrive on the run document as `learned_legs` and win over the
/// distance estimate for the legs they cover, exactly as they do server-side.
class DeliveryEstimate {
  const DeliveryEstimate({
    required this.arrivalOffsets,
    required this.drive,
    required this.dwell,
  });

  /// Time spent at each place the van stops. Counted once per place: two
  /// accounts at one address are one stop for the van.
  static const dwellPerStop = Duration(seconds: 60);

  /// Roads are longer than the straight line between two points.
  static const roadFactor = 1.35;

  /// Door-to-door average for stop-start delivery driving in town.
  static const urbanSpeedKmh = 30.0;

  /// The key the depot is recorded under in learned legs.
  static const depotKey = 'depot';

  /// For each stop, how long after leaving the depot the van gets there.
  final List<Duration> arrivalOffsets;
  final Duration drive;
  final Duration dwell;

  Duration get total => drive + dwell;

  static String legKey(String from, String to) => '$from>$to';

  static double estimatedLegSeconds(LatLng a, LatLng b) =>
      _haversineKm(a, b) * roadFactor / urbanSpeedKmh * 3600;

  /// Depot to depot when [depot] is known; stop to stop otherwise, which
  /// understates the run by its two depot legs and is labelled as such by
  /// the screens that show it.
  factory DeliveryEstimate.forRun({
    required LatLng? depot,
    required List<RunStop> stops,
    Map<String, double> learnedLegs = const {},
  }) {
    double legSeconds(LatLng a, String? aKey, LatLng b, String? bKey) {
      if (a == b) return 0;
      if (aKey != null && bKey != null) {
        final known = learnedLegs[legKey(aKey, bKey)];
        if (known != null) return known;
      }
      return estimatedLegSeconds(a, b);
    }

    final arrivals = <Duration>[];
    var clock = 0.0;
    var drive = 0.0;
    var dwell = 0.0;
    LatLng? previous = depot;
    String? previousKey = depot == null ? null : depotKey;
    var fromDepot = true;
    for (final stop in stops) {
      final leg = previous == null ? 0.0 : legSeconds(previous, previousKey, stop.location, stop.addressKey);
      clock += leg;
      drive += leg;
      arrivals.add(Duration(seconds: clock.round()));
      if (fromDepot || leg > 0) {
        clock += dwellPerStop.inSeconds;
        dwell += dwellPerStop.inSeconds;
      }
      previous = stop.location;
      previousKey = stop.addressKey;
      fromDepot = false;
    }
    if (depot != null && stops.isNotEmpty) {
      drive += legSeconds(stops.last.location, stops.last.addressKey, depot, depotKey);
    }
    return DeliveryEstimate(
      arrivalOffsets: arrivals,
      drive: Duration(seconds: drive.round()),
      dwell: Duration(seconds: dwell.round()),
    );
  }

  /// Reads the run document's `learned_legs` map, ignoring anything malformed.
  static Map<String, double> learnedLegsFrom(Object? raw) {
    if (raw is! Map) return const {};
    return {
      for (final entry in raw.entries)
        if (entry.value is num) entry.key.toString(): (entry.value as num).toDouble(),
    };
  }

  /// "2 h 05 min", "48 min", "under a minute". Rounded to the minute: the
  /// estimate is not good to the second, and showing seconds would say it is.
  static String format(Duration duration) {
    final minutes = (duration.inSeconds / 60).round();
    if (minutes < 1) return 'under a minute';
    if (minutes < 60) return '$minutes min';
    final hours = minutes ~/ 60;
    return '$hours h ${(minutes % 60).toString().padLeft(2, '0')} min';
  }

  static double _haversineKm(LatLng a, LatLng b) {
    const earthRadiusKm = 6371.0;
    double rad(double degrees) => degrees * math.pi / 180;
    final lat1 = rad(a.latitude), lat2 = rad(b.latitude);
    final dLat = lat2 - lat1, dLng = rad(b.longitude) - rad(a.longitude);
    final h = math.pow(math.sin(dLat / 2), 2) + math.cos(lat1) * math.cos(lat2) * math.pow(math.sin(dLng / 2), 2);
    return 2 * earthRadiusKm * math.asin(math.sqrt(h));
  }
}
