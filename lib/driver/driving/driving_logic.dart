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

  static double metersBetween(LatLng a, LatLng b) => _distance.as(LengthUnit.Meter, a, b);

  /// Close enough to offer "Arrived" without being asked.
  static bool isNear(double meters, {double? accuracy}) =>
      meters <= arriveRadiusMeters + (accuracy ?? 0).clamp(0, maxAccuracyAllowance);

  /// "north-east": the direction from [from] to [to], to eight points.
  static String direction(LatLng from, LatLng to) {
    const names = ['north', 'north-east', 'east', 'south-east', 'south', 'south-west', 'west', 'north-west'];
    final bearing = (_distance.bearing(from, to) + 360) % 360;
    return names[((bearing + 22.5) ~/ 45) % 8];
  }

  /// "600 m", "1.4 km" - for the screen.
  static String distanceLabel(double meters) {
    if (meters < 1000) return '${_roundTo50(meters)} m';
    return '${(meters / 1000).toStringAsFixed(1)} km';
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

  /// Close to the stop: "Approaching Otago Glass. 2 Trim 2L, 1 Blue top. Leave at the back door."
  static String approachLine(RunStop stop) => [
    'Approaching ${stop.customerName.isEmpty ? stop.address : stop.customerName}.',
    if (stop.items.isNotEmpty)
      '${[for (final item in stop.items) '${item.quantity} ${item.product}'].join(', ')}.',
    if (stop.instructions case final note? when note.trim().isNotEmpty) _sentence(note.trim()),
  ].join(' ');

  /// After the last stop: "That's all 60 delivered. Head back to the depot."
  static String doneLine(int stopCount) => "That's all $stopCount delivered. Head back to the depot.";

  static String _who(RunStop stop) => [
    if (stop.customerName.isNotEmpty) stop.customerName,
    if (stop.address.isNotEmpty) stop.address,
  ].join(', ');

  static String _sentence(String text) => RegExp(r'[.!?]$').hasMatch(text) ? text : '$text.';
}
