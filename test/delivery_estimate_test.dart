import 'package:dmm_delivery/models/delivery_estimate.dart';
import 'package:dmm_delivery/models/run_stop.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';

RunStop _stop(String id, String key, double lat, double lng) => RunStop(
  id: id,
  seqOrder: 0,
  customerName: id,
  address: '',
  location: LatLng(lat, lng),
  items: const [],
  addressKey: key,
);

void main() {
  const depot = LatLng(-45.8883702, 170.4589281); // 24 Donald St
  final a = _stop('a', 'a', -45.8904177, 170.5036811); // 5 Orari St
  final b = _stop('b', 'b', -45.8903073, 170.5042403); // 7 Orari St
  final bSecondAccount = _stop('b2', 'b', -45.8903073, 170.5042403);

  // The expected numbers are what the backend's domain/travel_time.py
  // estimate_run returns for the same inputs. The two are a contract: if one
  // of these fails, the figure on screen no longer matches the one the
  // pipeline wrote, and it jumps when the review screen is reopened.
  test('matches the backend estimate for the same run', () {
    final estimate = DeliveryEstimate.forRun(depot: depot, stops: [a, b, bSecondAccount]);

    expect([for (final d in estimate.arrivalOffsets) d.inSeconds], [562, 630, 690]);
    expect(estimate.drive.inSeconds, 1139);
    expect(estimate.dwell.inSeconds, 120);
    expect(estimate.total.inSeconds, 1259);
  });

  test('learned leg times win over the distance estimate, as on the backend', () {
    final estimate = DeliveryEstimate.forRun(
      depot: depot,
      stops: [a, b],
      learnedLegs: {'a>b': 200.0, 'depot>a': 100.0},
    );

    expect([for (final d in estimate.arrivalOffsets) d.inSeconds], [100, 360]);
    expect(estimate.drive.inSeconds, 869);
  });

  test('a dragged order re-estimates', () {
    final far = _stop('far', 'far', -45.8716578, 170.5219969); // 33 Wickliffe St
    final sensible = DeliveryEstimate.forRun(depot: depot, stops: [a, b, far]);
    final zigzag = DeliveryEstimate.forRun(depot: depot, stops: [a, far, b]);

    expect(zigzag.drive, greaterThan(sensible.drive));
    expect(zigzag.dwell, sensible.dwell);
  });

  test('reads learned legs off the run document, skipping anything malformed', () {
    expect(DeliveryEstimate.learnedLegsFrom({'a>b': 90, 'c>d': 'soon', 'e>f': 12.5}), {'a>b': 90.0, 'e>f': 12.5});
    expect(DeliveryEstimate.learnedLegsFrom(null), isEmpty);
  });

  test('formats to the minute', () {
    expect(DeliveryEstimate.format(const Duration(seconds: 20)), 'under a minute');
    expect(DeliveryEstimate.format(const Duration(minutes: 48, seconds: 10)), '48 min');
    expect(DeliveryEstimate.format(const Duration(hours: 2, minutes: 5)), '2 h 05 min');
  });

  test('an unrecognised precision reads as exact, and only rough pins carry a warning', () {
    expect(PinPrecision.parse(null), PinPrecision.exact);
    expect(PinPrecision.parse('something-new'), PinPrecision.exact);
    expect(PinPrecision.parse('learned').caution, isNull);
    expect(PinPrecision.parse('business').caution, isNull);
    expect(PinPrecision.parse('street').caution, isNotNull);
    expect(PinPrecision.parse('area').caution, isNotNull);
  });
}
