import 'package:flutter_test/flutter_test.dart';

import 'package:dmm_delivery/models/rider_map_data.dart';

/// One rider's round, as the map screen reads it.
///
/// This used to decode an encoded polyline from a fixed file and place a
/// randomised marker on it. The stops and their order are real now; the line
/// between them and the absent position are what these tests hold honest.
Map<String, dynamic> payload({
  List<Map<String, dynamic>>? stops,
  String source = 'stops',
  Map<String, dynamic>? position,
  int? total,
  int? located,
}) {
  final list =
      stops ??
      [
        {'seq_order': 0, 'lat': -45.9, 'lng': 170.4, 'address': '1 George St', 'customer_name': 'A'},
        {'seq_order': 1, 'lat': -45.8, 'lng': 170.6, 'address': '2 George St', 'customer_name': 'B'},
      ];
  return {
    'rider_key': 'uid-1',
    'driver_name': 'Pawan',
    'round': 'Run 2',
    'run_id': 'run-1',
    'route': {'source': source},
    'stops': list,
    'position': position,
    'stops_total': total ?? list.length,
    'stops_located': located ?? list.length,
  };
}

void main() {
  group('RiderMapData', () {
    test('the route is the stops themselves, in order', () {
      final data = RiderMapData.fromJson(payload());

      expect(data.route, hasLength(2));
      expect(data.route.first.latitude, -45.9);
      expect(data.stops.first.customerName, 'A');
    });

    test('carries which run these stops belong to', () {
      final data = RiderMapData.fromJson(payload());

      expect(data.round, 'Run 2');
      expect(data.runId, 'run-1');
    });

    test('no position is null, not a point at the origin', () {
      // (0, 0) is in the Atlantic. A marker there is worse than no marker.
      expect(RiderMapData.fromJson(payload()).position, isNull);
    });

    test('a position is read when one is actually sent', () {
      final data = RiderMapData.fromJson(payload(position: {'lat': -45.87, 'lng': 170.5}));

      expect(data.position?.latitude, -45.87);
    });

    test('a stop-joined line is flagged as a sequence, not a driven path', () {
      expect(RiderMapData.fromJson(payload()).isSequenceOnly, isTrue);
    });

    test('only a routed provenance clears the flag', () {
      // Read as "anything but valhalla" so a new non-routed source the client
      // has never heard of still reads as a sequence rather than as a path.
      expect(RiderMapData.fromJson(payload(source: 'valhalla')).isSequenceOnly, isFalse);
      expect(RiderMapData.fromJson(payload(source: 'something-new')).isSequenceOnly, isTrue);
    });

    test('says when the run has stops the map cannot place', () {
      // A map quietly missing three drops looks identical to a round with
      // three fewer.
      final data = RiderMapData.fromJson(payload(total: 12, located: 9));

      expect(data.missingStopsNotice, '3 stops have no map location yet');
    });

    test('one missing stop reads in the singular', () {
      expect(
        RiderMapData.fromJson(payload(total: 3, located: 2)).missingStopsNotice,
        '1 stop has no map location yet',
      );
    });

    test('nothing missing says nothing', () {
      expect(RiderMapData.fromJson(payload()).missingStopsNotice, isNull);
    });

    test('a driver with nothing assigned is an empty map, not a crash', () {
      final data = RiderMapData.fromJson(payload(stops: const [], total: 0, located: 0));

      expect(data.hasStops, isFalse);
      expect(data.route, isEmpty);
      expect(data.position, isNull);
    });

    test('a delivered stop is marked as such', () {
      final data = RiderMapData.fromJson(
        payload(
          stops: [
            {'seq_order': 0, 'lat': -45.9, 'lng': 170.4, 'address': 'x', 'status': 'delivered'},
          ],
        ),
      );

      expect(data.stops.single.isDelivered, isTrue);
    });
  });
}
