import 'package:dmm_delivery/models/road_legs.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('decodes Google\'s reference polyline', () {
    // The worked example from Google's encoded polyline documentation.
    final points = decodePolyline('_p~iF~ps|U_ulLnnqC_mqNvxq`@');

    expect(points.length, 3);
    expect(points[0].latitude, closeTo(38.5, 1e-9));
    expect(points[0].longitude, closeTo(-120.2, 1e-9));
    expect(points[1].latitude, closeTo(40.7, 1e-9));
    expect(points[1].longitude, closeTo(-120.95, 1e-9));
    expect(points[2].latitude, closeTo(43.252, 1e-9));
    expect(points[2].longitude, closeTo(-126.453, 1e-9));
  });

  test('a truncated polyline keeps the points it had', () {
    expect(decodePolyline('_p~iF~ps|U_ulL').length, 1);
  });

  test('reads road legs off the run document, skipping malformed ones', () {
    final legs = RoadLegs.fromRun({
      'depot>a': {'polyline': '_p~iF~ps|U_ulLnnqC_mqNvxq`@', 'duration_s': 452, 'distance_m': 3286},
      'a>b': {'polyline': '', 'duration_s': 128.5},
      'b>depot': 'not a leg',
    });

    expect(legs.shapes.keys, ['depot>a']);
    expect(legs.seconds, {'depot>a': 452.0, 'a>b': 128.5});
  });

  test('no road path on the run is simply empty', () {
    expect(RoadLegs.fromRun(null).isEmpty, isTrue);
  });

  test('driving times can be read without decoding the road shapes', () {
    expect(roadSecondsFromRun({'a>b': {'polyline': 'garbage', 'duration_s': 90}, 'c>d': 3}), {'a>b': 90.0});
  });
}
