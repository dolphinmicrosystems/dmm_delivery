import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:latlong2/latlong.dart';

import '../../models/road_legs.dart';
import 'driving_logic.dart';

/// One step of a route: drive along [points], then make the next step's
/// manoeuvre. Google gives each step the instruction for the manoeuvre that
/// *starts* it ("Turn left onto King Edward St"), so while driving step i the
/// turn ahead is step i + 1's.
class NavStep {
  const NavStep({required this.instruction, required this.maneuver, required this.points});

  final String instruction;

  /// Google's manoeuvre name: TURN_LEFT, ROUNDABOUT_RIGHT, STRAIGHT, ...
  final String maneuver;
  final List<LatLng> points;
}

/// The road route from the van to one stop, turn by turn (Routes API
/// computeRoutes, with navigation instructions).
class NavRoute {
  const NavRoute({
    required this.points,
    required this.steps,
    required this.distanceMeters,
    required this.duration,
  });

  final List<LatLng> points;
  final List<NavStep> steps;
  final double distanceMeters;
  final Duration duration;

  /// From a computeRoutes response; null when it has no route.
  static NavRoute? fromResponse(Map<String, dynamic> json) {
    final routes = json['routes'];
    if (routes is! List || routes.isEmpty) return null;
    final route = routes.first as Map<String, dynamic>;
    final steps = <NavStep>[];
    for (final leg in (route['legs'] as List?) ?? const []) {
      for (final raw in ((leg as Map)['steps'] as List?) ?? const []) {
        final step = raw as Map;
        final instruction = (step['navigationInstruction'] as Map?) ?? const {};
        final encoded = ((step['polyline'] as Map?) ?? const {})['encodedPolyline'] as String?;
        steps.add(
          NavStep(
            instruction: instruction['instructions'] as String? ?? '',
            maneuver: instruction['maneuver'] as String? ?? 'STRAIGHT',
            points: encoded == null ? const [] : decodePolyline(encoded),
          ),
        );
      }
    }
    final encoded = ((route['polyline'] as Map?) ?? const {})['encodedPolyline'] as String?;
    final seconds = int.tryParse('${route['duration'] ?? ''}'.replaceAll('s', '')) ?? 0;
    return NavRoute(
      points: encoded == null ? [for (final s in steps) ...s.points] : decodePolyline(encoded),
      steps: steps,
      distanceMeters: (route['distanceMeters'] as num?)?.toDouble() ?? 0,
      duration: Duration(seconds: seconds),
    );
  }
}

/// Where the van is on a [NavRoute]: which step, how far to the next
/// manoeuvre, and how far off the road it is.
class NavProgress {
  const NavProgress({required this.stepIndex, required this.metersToTurn, required this.offRouteMeters});

  final int stepIndex;
  final double metersToTurn;
  final double offRouteMeters;
}

/// The decisions behind in-app navigation, testable without a GPS or a
/// network: progress along the route, when it has been left, and what the
/// voice says when.
class TurnByTurn {
  const TurnByTurn._();

  /// Off the route by more than this (plus the fix's uncertainty, capped)
  /// on two fixes in a row: ask for a new one.
  static const offRouteMeters = 50.0;

  /// The voice warns of a turn this far ahead, then again at it.
  static const warnMeters = 300.0;
  static const nowMeters = 60.0;

  static NavProgress progress(NavRoute route, LatLng here) {
    var bestDistance = double.infinity;
    var bestStep = 0, bestSegment = 0;
    var bestFraction = 0.0;
    for (var s = 0; s < route.steps.length; s++) {
      final points = route.steps[s].points;
      for (var i = 0; i + 1 < points.length; i++) {
        final (distance, fraction) = _toSegment(here, points[i], points[i + 1]);
        if (distance < bestDistance) {
          (bestDistance, bestStep, bestSegment, bestFraction) = (distance, s, i, fraction);
        }
      }
    }
    if (bestDistance == double.infinity) {
      return const NavProgress(stepIndex: 0, metersToTurn: 0, offRouteMeters: 0);
    }
    // What is left of the current step: the rest of this segment, then the
    // segments after it.
    final points = route.steps[bestStep].points;
    var remaining =
        DrivingLogic.metersBetween(points[bestSegment], points[bestSegment + 1]) * (1 - bestFraction);
    for (var i = bestSegment + 1; i + 1 < points.length; i++) {
      remaining += DrivingLogic.metersBetween(points[i], points[i + 1]);
    }
    return NavProgress(stepIndex: bestStep, metersToTurn: remaining, offRouteMeters: bestDistance);
  }

  /// How far is left to the stop: the rest of this step, then every step
  /// after it.
  static double remainingMeters(NavRoute route, NavProgress progress) {
    var meters = progress.metersToTurn;
    for (var s = progress.stepIndex + 1; s < route.steps.length; s++) {
      final points = route.steps[s].points;
      for (var i = 0; i + 1 < points.length; i++) {
        meters += DrivingLogic.metersBetween(points[i], points[i + 1]);
      }
    }
    return meters;
  }

  /// How long is left: the route's own time, in proportion to the distance
  /// left - Google's pace for this route, so a fast road stays fast.
  static Duration remainingTime(NavRoute route, NavProgress progress) {
    if (route.distanceMeters <= 0) return route.duration;
    final share = (remainingMeters(route, progress) / route.distanceMeters).clamp(0.0, 1.0);
    return Duration(seconds: (route.duration.inSeconds * share).round());
  }

  static bool isOffRoute(NavProgress progress, {double? accuracy}) =>
      progress.offRouteMeters > offRouteMeters + math.min(accuracy ?? 0, 30);

  /// The manoeuvre ahead while driving step [progress.stepIndex]: the next
  /// step's instruction, or arriving at [destination] on the last step.
  static ({String instruction, String maneuver}) ahead(
    NavRoute route,
    NavProgress progress,
    String destination,
  ) {
    final next = progress.stepIndex + 1;
    if (next < route.steps.length) {
      final step = route.steps[next];
      return (instruction: step.instruction, maneuver: step.maneuver);
    }
    return (instruction: 'Arrive at $destination', maneuver: 'DESTINATION');
  }

  /// What to say now, if anything, given what has already been said
  /// ([spoken] holds "step:stage" keys, and is added to).
  static String? cue(NavRoute route, NavProgress progress, String destination, Set<String> spoken) {
    final turn = ahead(route, progress, destination);
    final instruction = _sentence(turn.instruction.replaceAll('\n', ' '));
    final step = progress.stepIndex;
    if (progress.metersToTurn <= nowMeters) {
      return spoken.add('$step:now') ? instruction : null;
    }
    if (progress.metersToTurn <= warnMeters) {
      spoken.add('$step:far'); // too late for the long warning now
      return spoken.add('$step:warn')
          ? 'In ${DrivingLogic.spokenDistance(progress.metersToTurn)}, ${_lowerFirst(instruction)}'
          : null;
    }
    // A long stretch: say so once, so silence doesn't read as lost.
    return spoken.add('$step:far')
        ? 'Continue for ${DrivingLogic.spokenDistance(progress.metersToTurn)}, '
              'then ${_lowerFirst(instruction)}'
        : null;
  }

  static IconData icon(String maneuver) => switch (maneuver) {
    'TURN_LEFT' => Icons.turn_left_rounded,
    'TURN_RIGHT' => Icons.turn_right_rounded,
    'TURN_SLIGHT_LEFT' || 'FORK_LEFT' || 'RAMP_LEFT' => Icons.turn_slight_left_rounded,
    'TURN_SLIGHT_RIGHT' || 'FORK_RIGHT' || 'RAMP_RIGHT' => Icons.turn_slight_right_rounded,
    'TURN_SHARP_LEFT' => Icons.turn_sharp_left_rounded,
    'TURN_SHARP_RIGHT' => Icons.turn_sharp_right_rounded,
    'UTURN_LEFT' => Icons.u_turn_left_rounded,
    'UTURN_RIGHT' => Icons.u_turn_right_rounded,
    'ROUNDABOUT_LEFT' || 'ROUNDABOUT_RIGHT' => Icons.roundabout_left_rounded,
    'MERGE' => Icons.merge_rounded,
    'DESTINATION' => Icons.place_rounded,
    _ => Icons.straight_rounded,
  };

  /// Distance from [p] to the segment [a]-[b] in metres, and how far along it
  /// the nearest point is (0..1). Flat-earth maths: exact enough across a city
  /// block, and cheap enough to run on every fix.
  static (double, double) _toSegment(LatLng p, LatLng a, LatLng b) {
    final metersPerDegLat = 111320.0;
    final metersPerDegLng = 111320.0 * math.cos(p.latitude * math.pi / 180);
    final ax = (a.longitude - p.longitude) * metersPerDegLng,
        ay = (a.latitude - p.latitude) * metersPerDegLat;
    final bx = (b.longitude - p.longitude) * metersPerDegLng,
        by = (b.latitude - p.latitude) * metersPerDegLat;
    final dx = bx - ax, dy = by - ay;
    final lengthSquared = dx * dx + dy * dy;
    final t = lengthSquared == 0 ? 0.0 : (-(ax * dx + ay * dy) / lengthSquared).clamp(0.0, 1.0);
    final x = ax + t * dx, y = ay + t * dy;
    return (math.sqrt(x * x + y * y), t);
  }

  static String _sentence(String text) =>
      RegExp(r'[.!?]$').hasMatch(text.trim()) ? text.trim() : '${text.trim()}.';

  static String _lowerFirst(String text) => text.isEmpty ? text : text[0].toLowerCase() + text.substring(1);
}
