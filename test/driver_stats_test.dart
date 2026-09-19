import 'package:dmm_delivery/models/driver_stats.dart';
import 'package:dmm_delivery/models/vehicle.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('DriverStats', () {
    test('reads the record the backend writes', () {
      final stats = DriverStats.fromMap({
        'runs_completed': 12,
        'days_driven': 10,
        'average_duration_s': 5400,
        'total_stops_delivered': 700,
        'first_run_date': '2026-08-02',
        'last_run_date': '2026-09-18',
        'recent_runs': [
          {
            'run_id': 'r12',
            'date': '2026-09-18',
            'round': 'South Runsheet',
            'round_key': 'south',
            'duration_s': 5100,
            'stops_delivered': 60,
            'vehicle': {'id': 'v1', 'name': 'Isuzu truck'},
          },
          'not a run',
        ],
      });

      expect(stats.hasHistory, isTrue);
      expect(stats.daysDriven, 10);
      expect(stats.averageDuration, const Duration(minutes: 90));
      expect(stats.lastRunDate, DateTime(2026, 9, 18));
      expect(stats.recentRuns.single.vehicleName, 'Isuzu truck');
      expect(stats.recentRuns.single.duration, const Duration(minutes: 85));
    });

    test('a driver with no record yet reads as empty, not broken', () {
      final stats = DriverStats.fromMap(null);
      expect(stats.hasHistory, isFalse);
      expect(stats.averageDuration, isNull);
    });

    test('each driver has their own document per business', () {
      expect(DriverStats.documentId('owner-1', 'ana'), 'owner-1_ana');
      expect(DriverStats.documentId('owner-1', 'ana'), isNot(DriverStats.documentId('owner-1', 'ben')));
    });
  });

  group('formatShortDate', () {
    test('drops the year when it is this year', () {
      expect(formatShortDate(DateTime(2026, 9, 18), thisYear: 2026), '18 Sep');
      expect(formatShortDate(DateTime(2025, 12, 3), thisYear: 2026), '3 Dec 2025');
    });
  });

  group('Vehicle', () {
    test('tidies a typed number plate', () {
      expect(Vehicle.normaliseRegistration(' abc 123 '), 'ABC123');
      expect(Vehicle.normaliseRegistration('   '), isNull);
    });

    test('an unknown kind reads as a van rather than hiding the vehicle', () {
      expect(VehicleKind.parse('hovercraft'), VehicleKind.van);
      expect(VehicleKind.parse('truck'), VehicleKind.truck);
    });

    test('describes itself by name and plate', () {
      const v = Vehicle(id: 'v1', name: 'Isuzu truck', kind: VehicleKind.truck, registration: 'ABC123');
      expect(v.description, 'Isuzu truck · ABC123');
      expect(const Vehicle(id: 'v2', name: 'Spare van', kind: VehicleKind.van).description, 'Spare van');
    });
  });
}
