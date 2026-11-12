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

  group('RouteRecord', () {
    Map<String, Object> run(String id, String date, int minutes, {String key = 'mosgiel', int? total}) => {
      'run_id': id,
      'date': date,
      'round': key == 'mosgiel' ? 'Mosgiel' : 'South',
      'round_key': key,
      'duration_s': minutes * 60,
      'stops_delivered': 70,
      'stops_total': ?total,
    };

    test("reads each route's all-time record from the backend", () {
      final stats = DriverStats.fromMap({
        'routes': {
          'mosgiel': {
            'round': 'Mosgiel',
            'runs': 9,
            'average_duration_s': 9000,
            'best_duration_s': 8100,
            'best_date': '2026-10-18',
            'best_run_id': 'r4',
            'last_duration_s': 9300,
            'last_date': '2026-11-10',
          },
        },
      });

      final mosgiel = stats.routes.single;
      expect(mosgiel.runs, 9);
      expect(mosgiel.best, const Duration(minutes: 135));
      expect(mosgiel.lastOverBest, const Duration(minutes: 20));
      expect(stats.bestRunIds, {'r4'});
    });

    test('works it out from recent runs for a record written before routes were kept', () {
      final stats = DriverStats.fromMap({
        'recent_runs': [
          run('r3', '2026-11-10', 160),
          run('r2', '2026-11-09', 150),
          run('r1', '2026-11-08', 170),
          run('s1', '2026-11-07', 60, key: 'south'),
        ],
      });

      final mosgiel = stats.routes.first; // driven most
      expect(mosgiel.routeName, 'Mosgiel');
      expect(mosgiel.runs, 3);
      expect(mosgiel.best, const Duration(minutes: 150));
      expect(mosgiel.bestRunId, 'r2');
      expect(mosgiel.average, const Duration(minutes: 160));
      expect(mosgiel.last, const Duration(minutes: 160));
      expect(stats.bestRunIds, {'r2', 's1'});
    });

    test('a run with stops left undelivered is never the best', () {
      final stats = DriverStats.fromMap({
        'recent_runs': [run('half', '2026-11-10', 40, total: 74), run('full', '2026-11-09', 150, total: 70)],
      });

      expect(stats.routes.single.bestRunId, 'full');
    });
  });
}
