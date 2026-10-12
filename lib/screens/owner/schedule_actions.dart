import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import '../../models/route_assignment.dart';
import '../../services/route_assigner.dart';
import '../../state/auth_state.dart';
import '../../theme/app_colors.dart';
import '../../util/app_log.dart';
import '../../widgets/schedule_run_sheet.dart';

/// Opens the scheduling sheet for one route and saves what the owner picks,
/// as the Routes tab does - from Home's attention list and the roster, which
/// already know the route (and the day).
Future<void> scheduleRoute(
  BuildContext context, {
  required AuthState authState,
  required String roundKey,
  required String routeName,
  List<RouteAssignment> assignments = const [],
  DateTime? date,
  bool oneDay = false,
}) async {
  final ownerUid = authState.ownerUid;
  if (ownerUid == null) return;
  final messenger = ScaffoldMessenger.of(context);
  final choice = await showScheduleRunSheet(
    context,
    authState: authState,
    roundKey: roundKey,
    routeName: routeName,
    current: RouteAssignment.activeAt(assignments, date ?? DateTime.now()),
    date: date,
    oneDay: oneDay,
  );
  if (choice == null) return;
  try {
    await RouteAssigner.assign(
      ownerUid: ownerUid,
      roundKey: choice.roundKey,
      effectiveFrom: choice.date,
      driver: choice.driver,
      startTime: choice.startTime,
      endTime: choice.endTime,
      oneDay: choice.oneDay,
    );
  } on FirebaseException catch (error, stack) {
    AppLog.owner.error('schedule route failed', error, stack, {'roundKey': roundKey});
    messenger.showSnackBar(SnackBar(content: Text(RouteAssigner.errorMessage(error))));
  }
}

/// Home's "Schedule a run": pick the route first, then the same sheet.
Future<void> pickRouteAndSchedule(
  BuildContext context, {
  required AuthState authState,
  required Map<String, String> routeNames,
  required Map<String, List<RouteAssignment>> assignmentsByRoute,
}) async {
  if (routeNames.isEmpty) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('No routes yet. Upload a run sheet on the Routes tab first.')),
    );
    return;
  }
  final routes = routeNames.entries.toList()..sort((a, b) => a.value.compareTo(b.value));
  final roundKey = await showModalBottomSheet<String>(
    context: context,
    showDragHandle: true,
    builder: (sheetContext) => SafeArea(
      child: ListView(
        shrinkWrap: true,
        padding: const EdgeInsets.only(bottom: 12),
        children: [
          const Padding(
            padding: EdgeInsets.fromLTRB(20, 0, 20, 8),
            child: Text('Schedule which route?', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700)),
          ),
          for (final route in routes)
            ListTile(
              leading: const Icon(Icons.alt_route_rounded, color: AppColors.brand),
              title: Text(route.value, style: const TextStyle(fontWeight: FontWeight.w600)),
              subtitle: Text(_currentDriver(assignmentsByRoute[route.key] ?? const [])),
              trailing: const Icon(Icons.chevron_right_rounded),
              onTap: () => Navigator.pop(sheetContext, route.key),
            ),
        ],
      ),
    ),
  );
  if (roundKey == null || !context.mounted) return;
  await scheduleRoute(
    context,
    authState: authState,
    roundKey: roundKey,
    routeName: routeNames[roundKey]!,
    assignments: assignmentsByRoute[roundKey] ?? const [],
  );
}

String _currentDriver(List<RouteAssignment> assignments) {
  final active = RouteAssignment.activeAt(assignments, DateTime.now());
  return active?.driverUid == null ? 'No driver' : 'Now: ${active!.driverName ?? 'a driver'}';
}
