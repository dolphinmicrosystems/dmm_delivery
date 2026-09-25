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
/// Three sources for a leg, best first, the same order the backend uses:
///  * `learnedLegs` - how long drivers have really taken between two
///    addresses. Used as they stand: they already include how that driver
///    drives.
///  * `roadSeconds` - Google's road time for the leg (`road_legs`), scaled by
///    [speedFactor], the assigned driver's pace against Google.
///  * the straight-line estimate below, scaled the same way.
///
/// Time at each stop comes from `dwellByKey` - what each address has been
/// learned to take, or the business's default - not a flat minute.
class DeliveryEstimate {
  const DeliveryEstimate({
    required this.arrivalOffsets,
    required this.stopTimes,
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

  /// The time allowed at each stop, in the same order. Zero for a second
  /// order at a door the van is already standing at.
  final List<Duration> stopTimes;
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
    Map<String, double> roadSeconds = const {},
    Map<String, double> dwellByKey = const {},
    double speedFactor = 1.0,
    Duration defaultStopTime = dwellPerStop,
  }) {
    double legSeconds(LatLng a, String? aKey, LatLng b, String? bKey) {
      if (a == b) return 0;
      if (aKey != null && bKey != null) {
        final key = legKey(aKey, bKey);
        final driven = learnedLegs[key];
        if (driven != null) return driven;
        final road = roadSeconds[key];
        if (road != null) return road * speedFactor;
      }
      return estimatedLegSeconds(a, b) * speedFactor;
    }

    double stopSeconds(RunStop stop) =>
        dwellByKey[stop.addressKey] ?? defaultStopTime.inSeconds.toDouble();

    final arrivals = <Duration>[];
    final stopTimes = <Duration>[];
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
      // A second order at the same door is delivered in the same stop.
      final atStop = fromDepot || leg > 0 ? stopSeconds(stop) : 0.0;
      stopTimes.add(Duration(seconds: atStop.round()));
      clock += atStop;
      dwell += atStop;
      previous = stop.location;
      previousKey = stop.addressKey;
      fromDepot = false;
    }
    if (depot != null && stops.isNotEmpty) {
      drive += legSeconds(stops.last.location, stops.last.addressKey, depot, depotKey);
    }
    return DeliveryEstimate(
      arrivalOffsets: arrivals,
      stopTimes: stopTimes,
      drive: Duration(seconds: drive.round()),
      dwell: Duration(seconds: dwell.round()),
    );
  }

  /// Reads a map of seconds off the run document (`learned_legs`,
  /// `dwell_by_key`), ignoring anything malformed.
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

/// The figures a run document carries so the app can re-estimate a dragged
/// order exactly as the backend did: what each address takes, the assigned
/// driver's pace, and the business's default stop time.
class EstimateInputs {
  const EstimateInputs({
    this.learnedLegs = const {},
    this.roadSeconds = const {},
    this.dwellByKey = const {},
    this.speedFactor = 1.0,
    this.defaultStopTime = DeliveryEstimate.dwellPerStop,
  });

  final Map<String, double> learnedLegs;
  final Map<String, double> roadSeconds;
  final Map<String, double> dwellByKey;
  final double speedFactor;
  final Duration defaultStopTime;

  /// True when some of this came from drivers rather than from defaults.
  bool get isLearned => speedFactor != 1.0 || dwellByKey.values.any((s) => s != defaultStopTime.inSeconds);

  factory EstimateInputs.fromRun(Map<String, dynamic>? run, {Map<String, double> roadSeconds = const {}}) {
    final defaultStop = (run?['default_dwell_s'] as num?)?.toInt();
    return EstimateInputs(
      learnedLegs: DeliveryEstimate.learnedLegsFrom(run?['learned_legs']),
      roadSeconds: roadSeconds,
      dwellByKey: DeliveryEstimate.learnedLegsFrom(run?['dwell_by_key']),
      speedFactor: (run?['speed_factor'] as num?)?.toDouble() ?? 1.0,
      defaultStopTime: defaultStop == null ? DeliveryEstimate.dwellPerStop : Duration(seconds: defaultStop),
    );
  }

  DeliveryEstimate estimate({required LatLng? depot, required List<RunStop> stops}) => DeliveryEstimate.forRun(
    depot: depot,
    stops: stops,
    learnedLegs: learnedLegs,
    roadSeconds: roadSeconds,
    dwellByKey: dwellByKey,
    speedFactor: speedFactor,
    defaultStopTime: defaultStopTime,
  );
}
