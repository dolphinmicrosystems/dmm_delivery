import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import '../models/delivery_estimate.dart';
import '../models/driver_stats.dart';
import '../theme/app_colors.dart';
import '../util/app_log.dart';
import 'pill_badge.dart';
import 'section_label.dart';
import 'stat_tile.dart';
import 'surface_card.dart';

/// A driver's record: the totals, each route's best, average and last time,
/// and the recent runs behind them - each one opening that run.
///
/// The same on the owner's page for a driver and on the driver's own "Your
/// record": both read `driver_stats/{ownerUid}_{driverUid}`, which the rules
/// let exactly those two read.
class DrivingRecord extends StatelessWidget {
  const DrivingRecord({
    super.key,
    required this.ownerUid,
    required this.driverUid,
    required this.onOpenRun,
    this.ownRecord = false,
  });

  final String ownerUid;
  final String driverUid;
  final void Function(CompletedRun run) onOpenRun;

  /// Worded to the driver ("your") rather than about them.
  final bool ownRecord;

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      stream: FirebaseFirestore.instance
          .collection('driver_stats')
          .doc(DriverStats.documentId(ownerUid, driverUid))
          .snapshots(),
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          AppLog.owner.error('driver stats stream failed', snapshot.error, snapshot.stackTrace);
        }
        final stats = snapshot.hasData ? DriverStats.fromSnapshot(snapshot.data!) : DriverStats.empty;
        final year = DateTime.now().year;
        final best = stats.bestRunIds;
        final routes = stats.routes;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const SectionLabel('Driving record'),
            const SizedBox(height: 8),
            SurfaceCard(
              padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 8),
              child: Column(
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: StatTile(value: '${stats.daysDriven}', label: 'Days driven'),
                      ),
                      Expanded(
                        child: StatTile(value: '${stats.runsCompleted}', label: 'Runs'),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      Expanded(
                        child: StatTile(
                          value: stats.averageDuration == null
                              ? '—'
                              : DeliveryEstimate.format(stats.averageDuration!),
                          label: 'Avg run time',
                        ),
                      ),
                      Expanded(
                        child: StatTile(value: '${stats.totalStopsDelivered}', label: 'Stops delivered'),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    child: Text(
                      stats.hasHistory
                          ? 'Driving since ${formatShortDate(stats.firstRunDate!, thisYear: year)} · last run '
                                '${formatShortDate(stats.lastRunDate!, thisYear: year)}. Run time is from the '
                                'first stop delivered to the last.'
                          : ownRecord
                          ? 'No completed runs yet. Your record starts once you deliver every stop on a run.'
                          : 'No completed runs yet. The record starts once a run they drive is fully delivered.',
                      textAlign: TextAlign.center,
                      style: const TextStyle(fontSize: 11.5, color: AppColors.inkMuted, height: 1.4),
                    ),
                  ),
                ],
              ),
            ),
            if (routes.isNotEmpty) ...[
              const SizedBox(height: 20),
              const SectionLabel('Best time by route'),
              const SizedBox(height: 8),
              SurfaceCard(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Column(
                  children: [
                    for (final (i, route) in routes.indexed) ...[
                      if (i > 0)
                        const Divider(height: 1, indent: 16, endIndent: 16, color: AppColors.hairline),
                      _RouteRow(route: route, thisYear: year),
                    ],
                  ],
                ),
              ),
            ],
            if (stats.recentRuns.isNotEmpty) ...[
              const SizedBox(height: 20),
              const SectionLabel('Recent runs'),
              const SizedBox(height: 8),
              SurfaceCard(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Column(
                  children: [
                    for (final (i, run) in stats.recentRuns.indexed) ...[
                      if (i > 0)
                        const Divider(height: 1, indent: 16, endIndent: 16, color: AppColors.hairline),
                      _RunRow(
                        run: run,
                        thisYear: year,
                        isBest: best.contains(run.runId),
                        onTap: run.runId.isEmpty ? null : () => onOpenRun(run),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ],
        );
      },
    );
  }
}

/// "Mosgiel · 6 runs" - best 2 h 41 min (18 Oct), average and last beside it.
class _RouteRow extends StatelessWidget {
  const _RouteRow({required this.route, required this.thisYear});

  final RouteRecord route;
  final int thisYear;

  @override
  Widget build(BuildContext context) {
    final best = route.best;
    final slower = route.lastOverBest;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
      child: Row(
        children: [
          const Icon(Icons.emoji_events_outlined, color: AppColors.warning),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${route.routeName} · ${route.runs} ${route.runs == 1 ? 'run' : 'runs'}',
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 2),
                Text(
                  [
                    'Average ${DeliveryEstimate.format(route.average)}',
                    if (route.last != null)
                      'last ${DeliveryEstimate.format(route.last!)}'
                          '${slower == null ? '' : ' (+${DeliveryEstimate.format(slower)})'}',
                  ].join(' · '),
                  style: const TextStyle(fontSize: 12, color: AppColors.inkMuted),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                best == null ? '—' : DeliveryEstimate.format(best),
                style: const TextStyle(fontWeight: FontWeight.w800, color: AppColors.brandDark),
              ),
              Text(
                route.bestDate == null
                    ? 'best'
                    : 'best · ${formatShortDate(route.bestDate!, thisYear: thisYear)}',
                style: const TextStyle(fontSize: 11, color: AppColors.inkMuted),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _RunRow extends StatelessWidget {
  const _RunRow({required this.run, required this.thisYear, required this.isBest, this.onTap});

  final CompletedRun run;
  final int thisYear;
  final bool isBest;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final details = [
      run.stopsTotal != null && !run.isComplete
          ? '${run.stopsDelivered} of ${run.stopsTotal} stops'
          : '${run.stopsDelivered} stops',
      DeliveryEstimate.format(run.duration),
      if (run.vehicleName != null) run.vehicleName!,
    ].join(' · ');
    return ListTile(
      dense: true,
      onTap: onTap,
      leading: const Icon(Icons.check_circle_outline_rounded, color: AppColors.success),
      title: Text(
        '${run.date == null ? 'Unknown date' : formatShortDate(run.date!, thisYear: thisYear)} · '
        '${run.routeName ?? 'Route'}',
        style: const TextStyle(fontWeight: FontWeight.w600),
      ),
      subtitle: Text(details),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (isBest)
            const PillBadge(label: 'Best', background: Color(0xFFFFF4DC), foreground: Color(0xFF8A5A00)),
          if (onTap != null) const Icon(Icons.chevron_right_rounded, color: AppColors.inkMuted),
        ],
      ),
    );
  }
}
