import 'package:dmm_delivery/models/rider_map_data.dart';
import 'package:flutter_test/flutter_test.dart';

/// The decoder is the one place a backend change can put the route silently
/// in the wrong place rather than failing, so its behaviour is pinned here.
void main() {
  group('decodePolyline', () {
    test('decodes a precision-6 shape to the right coordinates', () {
      // Encoded from (-45.8716648, 170.5220401) and (-45.882208, 170.5058972)
      // with the same algorithm the backend uses.
      const shape = '`bxnvAozyfdI|qS|o^';
      final points = decodePolyline(shape);

      expect(points.length, 2);
      expect(points.first.latitude, closeTo(-45.8716648, 1e-6));
      expect(points.first.longitude, closeTo(170.5220401, 1e-6));
      expect(points.last.latitude, closeTo(-45.882208, 1e-6));
      expect(points.last.longitude, closeTo(170.5058972, 1e-6));
    });

    test('precision changes the result by an order of magnitude', () {
      // Why shape_format travels with the payload instead of being assumed.
      const shape = '`bxnvAozyfdI|qS|o^';
      final six = decodePolyline(shape);
      final five = decodePolyline(shape, precision: 5);
      expect(five.first.latitude, closeTo(six.first.latitude * 10, 1e-3));
    });

    test('an empty shape yields no points rather than throwing', () {
      expect(decodePolyline(''), isEmpty);
    });
  });

  group('RiderMapData.fromJson', () {
    Map<String, dynamic> payload({String source = 'static-mock'}) => {
      'rider_key': 'tama-r.',
      'driver_name': 'Tama R.',
      'route': {'shape': '`bxnvAozyfdI|qS|o^', 'shape_format': 'polyline6', 'source': source},
      'position': {'lat': -45.875, 'lng': 170.51, 'bearing': 143.2, 'source': 'randomised-mock'},
      'bounds': {'min_lat': -45.9, 'max_lat': -45.87, 'min_lng': 170.5, 'max_lng': 170.53},
      'stops': [
        {'lat': -45.8716648, 'lng': 170.5220401, 'address': '33 Wickliffe Street, Dunedin'},
      ],
    };

    test('reads the route, position and stops', () {
      final data = RiderMapData.fromJson(payload());
      expect(data.driverName, 'Tama R.');
      expect(data.route.length, 2);
      expect(data.position.latitude, closeTo(-45.875, 1e-9));
      expect(data.bearing, closeTo(143.2, 1e-9));
      expect(data.stops.single.address, '33 Wickliffe Street, Dunedin');
    });

    test('flags mock provenance so the UI can say so', () {
      expect(RiderMapData.fromJson(payload()).isMock, isTrue);
    });

    test('a real route with a real position is not flagged as mock', () {
      final live = payload(source: 'valhalla');
      (live['position'] as Map<String, dynamic>)['source'] = 'gps';
      expect(RiderMapData.fromJson(live).isMock, isFalse);
    });

    test('survives a payload missing the optional pieces', () {
      final data = RiderMapData.fromJson({'rider_key': 'x', 'driver_name': 'X'});
      expect(data.route, isEmpty);
      expect(data.stops, isEmpty);
      expect(data.bearing, 0);
    });
  });
}
