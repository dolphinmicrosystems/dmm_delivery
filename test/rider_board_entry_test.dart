import 'package:dmm_delivery/models/rider_board_entry.dart';
import 'package:flutter_test/flutter_test.dart';

/// The board's card text is the one place where a missing backend field
/// turns into something the owner reads as fact, so the fallbacks are
/// pinned here rather than left to whatever the first live document
/// happens to contain.
void main() {
  RiderBoardEntry entry({
    RiderPresence presence = RiderPresence.onRoute,
    String? customer,
    String? address,
    int? eta,
  }) => RiderBoardEntry(
    riderKey: 'uid',
    driverName: 'Mele F.',
    presence: presence,
    nextCustomerName: customer,
    nextAddress: address,
    etaMinutes: eta,
  );

  group('subtitle', () {
    test('joins company then address', () {
      expect(
        entry(customer: 'WAE Engineering Limited', address: '63 Sturdee St Dunedin 9016').subtitle,
        'WAE Engineering Limited · 63 Sturdee St Dunedin 9016',
      );
    });

    test('drops a missing half rather than leaving a dangling separator', () {
      expect(entry(customer: 'Fulton Hogan Ltd').subtitle, 'Fulton Hogan Ltd');
      expect(entry(address: '200 Fryatt St Dunedin').subtitle, '200 Fryatt St Dunedin');
    });

    test('describes the state when there is no next drop', () {
      expect(entry(presence: RiderPresence.offline).subtitle, 'Awaiting run');
      expect(entry().subtitle, 'No next drop');
    });
  });

  group('etaLabel', () {
    test('shows minutes for a driver on route', () {
      expect(entry(eta: 8).etaLabel, '8 min');
    });

    test('shows an em dash for an offline driver even if an ETA lingers', () {
      // A stale eta_minutes on a driver who has gone offline would otherwise
      // read as a live arrival time.
      expect(entry(presence: RiderPresence.offline, eta: 8).etaLabel, '—');
    });

    test('shows an em dash when the ETA is unknown', () {
      expect(entry().etaLabel, '—');
    });
  });

  group('presence parsing', () {
    test('only on_route is live; anything else is offline', () {
      expect(RiderPresence.parse('on_route'), RiderPresence.onRoute);
      expect(RiderPresence.parse('picking_up'), RiderPresence.offline);
      expect(RiderPresence.parse(null), RiderPresence.offline);
    });
  });

  group('fromBoardDoc', () {
    test('reads the nested next_stop map', () {
      final e = RiderBoardEntry.fromBoardDoc('uid-1', {
        'driver_name': 'Tama R.',
        'presence': 'on_route',
        'eta_minutes': 8,
        'drops_left': 3,
        'next_stop': {'customer_name': 'Abbott Steel Ltd', 'address': '752 Kaikorai Valley Road'},
      });
      expect(e.driverName, 'Tama R.');
      expect(e.presence, RiderPresence.onRoute);
      expect(e.dropsLeft, 3);
      expect(e.subtitle, 'Abbott Steel Ltd · 752 Kaikorai Valley Road');
      expect(e.etaLabel, '8 min');
    });

    test('survives a document with only the fields the backend has so far', () {
      final e = RiderBoardEntry.fromBoardDoc('uid-2', {});
      expect(e.presence, RiderPresence.offline);
      expect(e.dropsLeft, 0);
      expect(e.etaLabel, '—');
    });
  });

  // --- the board as a whole -------------------------------------------------
  //
  // Added when the board stopped being a walk of the run_sheets bucket and
  // became this owner's own roster, read from Firestore. `unassigned_runs` is
  // new in that response: a route nobody is driving used to be invisible,
  // because the board only ever drew driver cards.

  group('RiderBoard', () {
    RiderBoard board(Map<String, dynamic> json) => RiderBoard.fromJson(json);

    test('an empty response is an empty board, not a crash', () {
      expect(board({}).riders, isEmpty);
      expect(board({}).unassignedRuns, isEmpty);
      expect(board({}).unassignedNotice, isNull);
    });

    test('counts drivers who are actually on route', () {
      final result = board({
        'riders': [
          {'rider_key': 'a', 'driver_name': 'Ana', 'presence': 'on_route'},
          {'rider_key': 'b', 'driver_name': 'Ben', 'presence': 'offline'},
        ],
      });

      expect(result.liveCount, 1);
    });

    test('says nothing when every route has a driver', () {
      expect(board({'unassigned_runs': []}).unassignedNotice, isNull);
    });

    test('names one unassigned route in the singular', () {
      final result = board({
        'unassigned_runs': [
          {'run_id': 'r1', 'round': 'Run 2', 'stop_count': 12},
        ],
      });

      expect(result.unassignedNotice, '1 route has no driver · 12 stops');
    });

    test('adds the stops up across several', () {
      final result = board({
        'unassigned_runs': [
          {'run_id': 'r1', 'round': 'Run 2', 'stop_count': 12},
          {'run_id': 'r2', 'round': 'Run 3', 'stop_count': 8},
        ],
      });

      expect(result.unassignedNotice, '2 routes have no driver · 20 stops');
    });

    test('omits a stop count nobody supplied rather than saying 0 stops', () {
      final result = board({
        'unassigned_runs': [
          {'run_id': 'r1'},
        ],
      });

      expect(result.unassignedNotice, '1 route has no driver');
    });

    test('an unnamed route still reads as something', () {
      final run = UnassignedRun.fromJson({'run_id': 'r1'});

      expect(run.label, 'Untitled route');
    });
  });
}
