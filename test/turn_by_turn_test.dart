import 'package:dmm_delivery/driver/driving/turn_by_turn.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';

// A made-up L-shaped drive in Dunedin: ~550 m east, then turn left, ~330 m north.
const start = LatLng(-45.8800, 170.5000);
const corner = LatLng(-45.8800, 170.5070);
const end = LatLng(-45.8770, 170.5070);

NavRoute route() => const NavRoute(
  points: [start, corner, end],
  steps: [
    NavStep(instruction: 'Head east on Princes St', maneuver: 'DEPART', points: [start, corner]),
    NavStep(instruction: 'Turn left onto King St', maneuver: 'TURN_LEFT', points: [corner, end]),
  ],
  distanceMeters: 880,
  duration: Duration(minutes: 3),
);

void main() {
  test('progress: which step, and how far to the turn', () {
    const halfway = LatLng(-45.8800, 170.5035);

    final progress = TurnByTurn.progress(route(), halfway);

    expect(progress.stepIndex, 0);
    expect(progress.metersToTurn, closeTo(272, 10));
    expect(progress.offRouteMeters, lessThan(1));
    expect(TurnByTurn.ahead(route(), progress, 'Otago Glass').instruction, 'Turn left onto King St');
  });

  test('the last step leads to the stop', () {
    final progress = TurnByTurn.progress(route(), const LatLng(-45.8785, 170.5070));

    expect(progress.stepIndex, 1);
    expect(TurnByTurn.ahead(route(), progress, 'Otago Glass').instruction, 'Arrive at Otago Glass');
  });

  test('100 m off the road is off route; a few metres is not', () {
    final off = TurnByTurn.progress(route(), const LatLng(-45.8791, 170.5035)); // ~100 m north
    final on = TurnByTurn.progress(route(), const LatLng(-45.88003, 170.5035));

    expect(TurnByTurn.isOffRoute(off), isTrue);
    expect(TurnByTurn.isOffRoute(on), isFalse);
  });

  test('the voice: a long stretch once, a warning at 300 m, the turn at it - each once', () {
    final spoken = <String>{};
    String? at(double lng) =>
        TurnByTurn.cue(route(), TurnByTurn.progress(route(), LatLng(-45.8800, lng)), 'X', spoken);

    expect(at(170.5002), 'Continue for 550 metres, then turn left onto King St.');
    expect(at(170.5003), isNull);
    expect(at(170.5040), 'In 250 metres, turn left onto King St.');
    expect(at(170.5045), isNull);
    expect(at(170.5066), 'Turn left onto King St.');
    expect(at(170.5067), isNull);
  });

  test('reads a computeRoutes response', () {
    final parsed = NavRoute.fromResponse({
      'routes': [
        {
          'distanceMeters': 880,
          'duration': '183s',
          'polyline': {'encodedPolyline': '_p~iF~ps|U_ulLnnqC'},
          'legs': [
            {
              'steps': [
                {
                  'navigationInstruction': {'maneuver': 'TURN_LEFT', 'instructions': 'Turn left'},
                  'polyline': {'encodedPolyline': '_p~iF~ps|U'},
                },
              ],
            },
          ],
        },
      ],
    })!;

    expect(parsed.distanceMeters, 880);
    expect(parsed.duration, const Duration(seconds: 183));
    expect(parsed.steps.single.maneuver, 'TURN_LEFT');
    expect(parsed.points, hasLength(2));
    expect(NavRoute.fromResponse({'routes': []}), isNull);
  });

  test('what is left: distance along the road, and time at the route\'s pace', () {
    final halfway = TurnByTurn.progress(route(), const LatLng(-45.8800, 170.5035));

    expect(TurnByTurn.remainingMeters(route(), halfway), closeTo(272 + 334, 15));
    // 880 m in 3 min: ~606 m left is ~124 s.
    expect(TurnByTurn.remainingTime(route(), halfway).inSeconds, closeTo(124, 6));
  });
}
