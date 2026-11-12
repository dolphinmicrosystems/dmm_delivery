import 'package:dmm_delivery/models/run_listing.dart';
import 'package:dmm_delivery/models/run_summary.dart';
import 'package:dmm_delivery/models/run_track.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';

final _depot = const LatLng(-45.8877, 170.4594);
final _mosgiel = const LatLng(-45.8752, 170.3484);

RunListing _run({int estimateMinutes = 180}) => RunListing.fromMap('r1', {
  'driver_started_at': DateTime(2026, 11, 12, 19),
  'driver_ended_at': DateTime(2026, 11, 12, 21, 50),
  'estimated_total_s': estimateMinutes * 60,
  'stop_count': 4,
});

Map<String, dynamic> _stop({
  bool delivered = true,
  bool photo = false,
  bool auto = false,
  bool excluded = false,
}) => {
  'status': delivered ? 'delivered' : 'pending',
  if (photo) 'pod_photo_url': 'gs://b/p.jpg',
  if (auto) 'rider_note': RunSummary.autoNote,
  if (excluded) 'excluded': true,
};

void main() {
  group('RunTrack', () {
    test('keeps a point only after the van has moved, and only from a good fix', () {
      expect(RunTrack.keeps(null, _depot, accuracy: 10), isTrue);
      expect(RunTrack.keeps(_depot, const LatLng(-45.8878, 170.4594), accuracy: 10), isFalse); // ~11 m
      expect(RunTrack.keeps(_depot, _mosgiel, accuracy: 10), isTrue);
      expect(RunTrack.keeps(_depot, _mosgiel, accuracy: 120), isFalse);
    });

    test('reads points in time order and measures the path', () {
      final track = RunTrack.fromMap({
        'points': [
          {'lat': _mosgiel.latitude, 'lng': _mosgiel.longitude, 't': 2},
          {'lat': _depot.latitude, 'lng': _depot.longitude, 't': 1},
          {'lat': _depot.latitude, 'lng': _depot.longitude, 't': 3},
          'junk',
        ],
      });

      expect(track.points.first, _depot);
      expect(track.meters / 1000, closeTo(17.5, 0.2)); // there and back
      expect(formatDistance(track.meters), '17.5 km');
      expect(formatDistance(850), '850 m');
    });
  });

  group('RunSummary', () {
    test('counts deliveries, photos and the stops marked automatically', () {
      final summary = RunSummary.from(
        listing: _run(),
        stops: [
          _stop(photo: true),
          _stop(auto: true),
          _stop(),
          _stop(delivered: false),
          _stop(excluded: true), // taken off the route: not a stop at all
        ],
      );

      expect(summary.total, 4);
      expect(summary.delivered, 3);
      expect(summary.notDelivered, 1);
      expect(summary.allDelivered, isFalse);
      expect(summary.photos, 1);
      expect(summary.autoDelivered, 1);
    });

    test('times the run and compares it with the estimate', () {
      final summary = RunSummary.from(listing: _run(estimateMinutes: 180), stops: [_stop(), _stop()]);

      expect(summary.took, const Duration(hours: 2, minutes: 50));
      expect(summary.againstEstimate, const Duration(minutes: -10));
      expect(summary.perStop, const Duration(minutes: 85));
    });

    test('has no distance until a path was recorded', () {
      expect(RunSummary.from(listing: _run(), stops: [_stop()]).meters, isNull);
      final driven = RunSummary.from(listing: _run(), stops: [_stop()], track: RunTrack([_depot, _mosgiel]));
      expect(driven.meters, greaterThan(8000));
    });
  });
}
