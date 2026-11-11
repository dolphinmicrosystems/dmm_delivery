import 'package:latlong2/latlong.dart';

import '../../models/run_stop.dart';

/// The decisions behind the driving screen, kept apart from it so they are
/// testable: which stop is next, when "Arrived" is offered, and what the voice
/// says. The screen supplies positions and stops; this never touches
/// Firebase, the GPS or the speaker.
class DrivingLogic {
  const DrivingLogic._();

  /// "Arrived" is offered within this distance of the stop's pin, plus the
  /// fix's own uncertainty (capped): a pin is the geocoded or learned drop
  /// point, so the van stops a few houses short as often as on it.
  static const arriveRadiusMeters = 60.0;
  static const maxAccuracyAllowance = 40.0;

  /// The voice says "Approaching ..." with what to deliver once, this close.
  static const approachMeters = 150.0;

  static const _distance = Distance();

  /// The first stop in route order (by id) not yet delivered; null when all
  /// are. Ids, not pins: a stop the geocoder couldn't place is still on the run.
  static int? currentIndex(List<String> stopIds, Set<String> deliveredIds) {
    for (var i = 0; i < stopIds.length; i++) {
      if (!deliveredIds.contains(stopIds[i])) return i;
    }
    return null;
  }

  /// Where to go once [justDelivered] is done, when stops are being delivered
  /// out of the planned order. Two sensible answers: the earliest stop still
  /// skipped, or the next one after the stop just delivered. Whichever is
  /// nearer the van wins ([metersTo]; null for a stop with no pin) - a driver
  /// who did stop 3 on the way past goes back for 1, one who jumped across
  /// town carries on from there. In order, the two are the same stop.
  ///
  /// Decided once, at the delivery - not on every GPS fix, which would swap
  /// the target as the van moved.
  static String? nextAfterDelivery(
    List<String> stopIds,
    Set<String> deliveredIds,
    String justDelivered, {
    double? Function(String stopId)? metersTo,
  }) {
    final left = [
      for (final id in stopIds)
        if (!deliveredIds.contains(id) && id != justDelivered) id,
    ];
    if (left.isEmpty) return null;
    final earliest = left.first;
    final at = stopIds.indexOf(justDelivered);
    final onward = left.where((id) => stopIds.indexOf(id) > at).firstOrNull ?? earliest;
    if (onward == earliest || metersTo == null) return earliest;
    final toEarliest = metersTo(earliest), toOnward = metersTo(onward);
    if (toEarliest == null || toOnward == null) return earliest;
    return toOnward < toEarliest ? onward : earliest;
  }

  /// The stops still to do, as they will be driven: [currentId] first, then
  /// the rest in the planned order - for the line drawn ahead of the van.
  static List<String> remainingOrder(List<String> stopIds, Set<String> deliveredIds, String? currentId) => [
    if (currentId != null && stopIds.contains(currentId) && !deliveredIds.contains(currentId)) currentId,
    for (final id in stopIds)
      if (id != currentId && !deliveredIds.contains(id)) id,
  ];

  static double metersBetween(LatLng a, LatLng b) => _distance.as(LengthUnit.Meter, a, b);

  /// Close enough to offer "Arrived" without being asked.
  static bool isNear(double meters, {double? accuracy}) =>
      meters <= arriveRadiusMeters + (accuracy ?? 0).clamp(0, maxAccuracyAllowance);

  /// The van counts as having stopped at a stop when it is within the arrive
  /// radius and (nearly) standing still - driving past one doesn't count.
  static const stoppedSpeed = 1.5; // m/s

  static bool hasStoppedAt(double meters, {double? accuracy, double? speed}) =>
      isNear(meters, accuracy: accuracy) && (speed == null || speed < 0 || speed <= stoppedSpeed);

  /// Driven away from a stop: well clear of the arrive radius, whatever the
  /// fix's uncertainty, so GPS drift at the kerb never reads as leaving.
  static const leaveRadiusMeters = 150.0;

  static bool hasLeft(double meters, {double? accuracy}) =>
      meters > leaveRadiusMeters + (accuracy ?? 0).clamp(0, maxAccuracyAllowance);

  /// How long "Delivered to ...?" waits before answering itself.
  static const autoConfirmSeconds = 10;

  /// Saved on a stop marked delivered by the countdown, not by a tap.
  static const autoConfirmNote = 'Marked delivered automatically after driving away';

  /// "north-east": the direction from [from] to [to], to eight points.
  static String direction(LatLng from, LatLng to) {
    const names = ['north', 'north-east', 'east', 'south-east', 'south', 'south-west', 'west', 'north-west'];
    final bearing = (_distance.bearing(from, to) + 360) % 360;
    return names[((bearing + 22.5) ~/ 45) % 8];
  }

  /// "600 m", "1.4 km", "11,426 km" - for the screen.
  static String distanceLabel(double meters) {
    if (meters < 1000) return '${_roundTo50(meters)} m';
    if (meters < 100000) return '${(meters / 1000).toStringAsFixed(1)} km';
    final km = (meters / 1000).round().toString();
    return '${km.replaceAllMapped(RegExp(r'\B(?=(\d{3})+$)'), (_) => ',')} km';
  }

  /// "600 metres", "1.4 kilometres" - for the voice.
  static String spokenDistance(double meters) {
    if (meters < 1000) return '${_roundTo50(meters)} metres';
    return '${(meters / 1000).toStringAsFixed(1)} kilometres';
  }

  static int _roundTo50(double meters) => meters < 50 ? meters.round() : (meters / 50).round() * 50;

  // --- What the voice says -------------------------------------------------

  /// On Start: "Starting Run 3. 60 stops. First: Otago Glass, 12 Orari Street."
  static String startLine(String routeName, int stopCount, RunStop? first) => [
    'Starting $routeName.',
    '$stopCount ${stopCount == 1 ? 'stop' : 'stops'}.',
    if (first != null) 'First: ${_who(first)}.',
  ].join(' ');

  /// Where to go: "Next: Otago Glass, 12 Orari Street. 600 metres north-east."
  static String nextLine(RunStop stop, {double? meters, String? direction}) => [
    'Next: ${_who(stop)}.',
    if (meters != null && direction != null) '${spokenDistance(meters)} $direction.',
  ].join(' ');

  /// Close to the stop: "Approaching Otago Glass." What to deliver is said on
  /// arrival ([arriveLine]), when the driver is about to pick it up.
  static String approachLine(RunStop stop) => 'Approaching ${_name(stop)}.';

  /// At the stop: "You have arrived at Otago Glass. Deliver 2 Trim 2L, 1 Blue
  /// top 1L. Leave at the back door." - the items, then the owner's note.
  static String arriveLine(RunStop stop) => [
    'You have arrived at ${_name(stop)}.',
    if (stop.items.isNotEmpty)
      'Deliver ${[for (final item in stop.items) '${item.quantity} ${item.product}'].join(', ')}.',
    if (stop.instructions case final note? when note.trim().isNotEmpty) _sentence(note.trim()),
  ].join(' ');

  /// Driven away without a tap: "Did you deliver to Otago Glass?"
  static String leftLine(RunStop stop) => 'Did you deliver to ${_name(stop)}?';

  static String _name(RunStop stop) => stop.customerName.isEmpty ? stop.address : stop.customerName;

  /// After the last stop: "That's all 60 delivered. Head back to the depot."
  static String doneLine(int stopCount) => "That's all $stopCount delivered. Head back to the depot.";

  static String _who(RunStop stop) => [
    if (stop.customerName.isNotEmpty) stop.customerName,
    if (stop.address.isNotEmpty) stop.address,
  ].join(', ');

  static String _sentence(String text) => RegExp(r'[.!?]$').hasMatch(text) ? text : '$text.';
}
