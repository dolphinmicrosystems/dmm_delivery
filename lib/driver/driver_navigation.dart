import 'package:flutter/material.dart';

import '../models/run_listing.dart';
import '../state/auth_state.dart';
import 'driver_route_screen.dart';
import 'driver_run_screen.dart';
import 'driving/driving_screen.dart';
import 'driver_schedule.dart';

/// Opens what a driver's card stands for: the day's run when its run sheet
/// exists (DriverRunScreen), else the route as planned (DriverRouteScreen).
/// Every card the driver sees opens - none is a dead end.
void openDriverCard(BuildContext context, AuthState authState, DriverRunCard card, {String? vehicle}) {
  final run = card.run;
  final past = run != null && run.phase(DateTime.now()) == RunPhase.past;
  Navigator.of(context).push(
    MaterialPageRoute(
      builder: (_) => run != null
          ? DriverRunScreen(
              authState: authState,
              runId: run.id,
              routeName: card.routeName,
              startTime: card.start,
              endTime: card.end,
              // History doesn't record which vehicle was used.
              vehicle: past ? null : vehicle,
            )
          : DriverRouteScreen(
              roundKey: card.booking!.roundKey,
              routeName: card.routeName,
              startTime: card.start,
              endTime: card.end,
              vehicle: vehicle,
            ),
    ),
  );
}

/// Opens one of the driver's routes as planned.
void openDriverRoute(BuildContext context, DriverRoute route, {String? vehicle}) {
  Navigator.of(context).push(
    MaterialPageRoute(
      builder: (_) => DriverRouteScreen(
        roundKey: route.roundKey,
        routeName: route.name,
        startTime: route.startTime,
        endTime: route.endTime,
        vehicle: vehicle,
      ),
    ),
  );
}

/// Opens the driving screen for [card]'s run: the map following the van,
/// Arrived, the photo, Delivered.
void openDriving(BuildContext context, AuthState authState, DriverRunCard card, {String? vehicle}) {
  Navigator.of(context).push(
    MaterialPageRoute(
      builder: (_) => DrivingScreen(
        authState: authState,
        runId: card.run!.id,
        routeName: card.routeName,
        vehicle: vehicle,
      ),
    ),
  );
}

/// Whether [card] is a run that can be driven now: today's, or one already
/// under way, and not finished.
bool canDrive(DriverRunCard card, DateTime now) {
  final run = card.run;
  if (run == null) return false;
  final phase = run.phase(now);
  return phase == RunPhase.today && run.finished == null;
}
