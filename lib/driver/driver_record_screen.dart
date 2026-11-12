import 'package:flutter/material.dart';

import '../state/auth_state.dart';
import '../theme/app_colors.dart';
import '../widgets/driving_record.dart';
import '../widgets/surface_card.dart';
import 'driver_run_screen.dart';

/// The driver's own record: their totals, best time on each route, and recent
/// runs - the same figures their owner sees on the driver's page.
///
/// Opened from the top of the Past tab and from the menu.
class DriverRecordScreen extends StatelessWidget {
  const DriverRecordScreen({super.key, required this.authState});

  final AuthState authState;

  @override
  Widget build(BuildContext context) {
    final uid = authState.user?.uid;
    final ownerUid = authState.ownerUid;
    return Scaffold(
      backgroundColor: AppColors.surfaceMuted,
      appBar: AppBar(title: const Text('Your record')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
        children: [
          if (uid == null || ownerUid == null)
            const Text('Sign in again to see your record.')
          else
            DrivingRecord(
              ownerUid: ownerUid,
              driverUid: uid,
              ownRecord: true,
              onOpenRun: (run) => Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => DriverRunScreen(
                    authState: authState,
                    runId: run.runId,
                    routeName: run.routeName ?? 'Run',
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// The way in from the Past tab: one line that says what is behind it.
class DriverRecordLink extends StatelessWidget {
  const DriverRecordLink({super.key, required this.authState});

  final AuthState authState;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(20),
      onTap: () => Navigator.of(
        context,
      ).push(MaterialPageRoute(builder: (_) => DriverRecordScreen(authState: authState))),
      child: const SurfaceCard(
        padding: EdgeInsets.fromLTRB(16, 14, 8, 14),
        child: Row(
          children: [
            Icon(Icons.emoji_events_outlined, color: AppColors.warning),
            SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Your record', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
                  SizedBox(height: 2),
                  Text(
                    'Best time on each route, averages and every run',
                    style: TextStyle(fontSize: 12, color: AppColors.inkMuted),
                  ),
                ],
              ),
            ),
            Icon(Icons.chevron_right_rounded, color: AppColors.inkMuted),
          ],
        ),
      ),
    );
  }
}
