import 'package:flutter/material.dart';

import '../models/driver_stats.dart';
import '../models/run_time.dart';
import '../state/auth_state.dart';
import '../theme/app_colors.dart';
import '../widgets/pill_badge.dart';
import '../widgets/surface_card.dart';
import 'driver_data.dart';
import 'driver_navigation.dart';
import 'driver_schedule.dart';

/// The driver's Routes tab: the routes the owner has given them, each with
/// its start time, and any they take over from a later date. Days they only
/// cover are on the Runs tab, not here - a cover is a day, not their route.
///
/// A body, not a Scaffold - it is one of the driver shell's tabs.
class DriverRoutesScreen extends StatelessWidget {
  const DriverRoutesScreen({super.key, required this.authState, required this.data});

  final AuthState authState;
  final DriverData data;

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final routes = DriverSchedule.routes(
      driverUid: authState.user!.uid,
      assignments: data.assignments,
      routeNames: data.routeNames,
      now: now,
    );
    if (routes.isEmpty) {
      return ListView(
        padding: const EdgeInsets.all(24),
        children: const [
          Text(
            "You don't have a route yet. When your owner assigns you one, it appears here "
            "and you'll get a notification.",
            style: TextStyle(fontSize: 13, color: AppColors.inkMuted, height: 1.4),
          ),
        ],
      );
    }
    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
      itemCount: routes.length,
      separatorBuilder: (_, _) => const SizedBox(height: 12),
      itemBuilder: (context, index) {
        final route = routes[index];
        final from = route.from;
        return InkWell(
          onTap: () => openDriverRoute(
            context,
            route,
            authState: authState,
            vehicle: data.vehicle?.description,
            canStartToday: DriverSchedule.scheduledToday(
              authState.user!.uid,
              data.assignments,
              route.roundKey,
              now,
            ),
          ),
          borderRadius: BorderRadius.circular(20),
          child: SurfaceCard(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                const CircleAvatar(
                  radius: 18,
                  backgroundColor: AppColors.brandSoft,
                  child: Icon(Icons.alt_route_rounded, color: AppColors.brand, size: 18),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(route.name, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
                      const SizedBox(height: 2),
                      Text(
                        formatWindow(route.startTime, route.endTime) ?? 'No start time set',
                        style: const TextStyle(fontSize: 12.5, color: AppColors.inkMuted),
                      ),
                      if (data.vehicle != null)
                        Text(
                          'Vehicle: ${data.vehicle!.description}',
                          style: const TextStyle(fontSize: 12.5, color: AppColors.inkMuted),
                        ),
                    ],
                  ),
                ),
                if (from != null)
                  PillBadge(
                    label: 'From ${relativeDayLabel(from, now)}',
                    background: AppColors.brandSoft,
                    foreground: AppColors.brand,
                  ),
              ],
            ),
          ),
        );
      },
    );
  }
}
