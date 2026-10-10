import 'package:flutter/material.dart';

import '../../models/delivery_estimate.dart';
import '../../models/driver_stats.dart';
import '../../models/run_listing.dart';
import '../../models/run_time.dart';
import '../../models/run_timing.dart';
import '../../state/auth_state.dart';
import '../../theme/app_colors.dart';
import '../../widgets/pill_badge.dart';
import '../../widgets/run_timing_pill.dart';
import '../../widgets/surface_card.dart';
import 'owner_run_data.dart';
import 'run_detail_screen.dart';

/// The Runs tab: every run - one route's deliveries for one day - split into
/// Upcoming, Today and Past, with who drives it, when, and how far along it is.
///
/// Replaces the old "Maps" board, which showed a fabricated route shape and
/// a randomised driver position (rider-board's mock data). Everything here is
/// real: the runs are the confirmed run sheets, dated by the sheet itself;
/// the driver and start time come from the route's schedule for that day; the
/// progress is what the backend writes onto the run as stops are marked
/// delivered (domain/run_progress.py).
///
/// A body, not a Scaffold - it is one of the owner shell's tabs.
class RunsScreen extends StatelessWidget {
  const RunsScreen({super.key, required this.authState});

  final AuthState authState;

  @override
  Widget build(BuildContext context) {
    final ownerUid = authState.ownerUid;
    return DefaultTabController(
      length: 3,
      initialIndex: 1, // Today: what the owner opens this to see
      child: Column(
        children: [
          const TabBar(
            tabs: [
              Tab(text: 'Upcoming'),
              Tab(text: 'Today'),
              Tab(text: 'Past'),
            ],
          ),
          Expanded(
            child: ownerUid == null
                ? const SizedBox.shrink()
                : OwnerRunDataBuilder(
                    authState: authState,
                    ownerUid: ownerUid,
                    builder: (context, data) => TabBarView(
                      children: [
                        _RunList(data: data, phase: RunPhase.upcoming, authState: authState),
                        _RunList(data: data, phase: RunPhase.today, authState: authState),
                        _RunList(data: data, phase: RunPhase.past, authState: authState),
                      ],
                    ),
                  ),
          ),
        ],
      ),
    );
  }
}

class _RunList extends StatelessWidget {
  const _RunList({required this.data, required this.phase, required this.authState});

  final OwnerRunData data;
  final RunPhase phase;
  final AuthState authState;

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final runs = RunListing.sorted(data.runs.where((run) => run.phase(now) == phase), phase);
    if (runs.isEmpty) {
      return ListView(
        padding: const EdgeInsets.all(24),
        children: [
          Text(switch (phase) {
            RunPhase.upcoming =>
              'No runs coming up. Upload a run sheet on the Routes tab and it '
                  'appears here for the date printed on it.',
            RunPhase.today => 'No runs today.',
            RunPhase.past => 'No past runs yet.',
          }, style: const TextStyle(fontSize: 13, color: AppColors.inkMuted, height: 1.4)),
        ],
      );
    }
    // Today's runs on the road also read their heartbeat (run_live), for
    // "No signal since ...".
    return RunLiveBuilder(
      ownerUid: authState.ownerUid ?? '',
      runIds: [
        if (phase == RunPhase.today)
          for (final run in runs)
            if (run.started != null && run.finished == null) run.id,
      ],
      builder: (context, lastSeen) => ListView.separated(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
        itemCount: runs.length,
        separatorBuilder: (_, _) => const SizedBox(height: 12),
        itemBuilder: (context, index) {
          final run = runs[index];
          final crew = data.crewFor(run);
          return _RunCard(
            run: run,
            now: now,
            timing: RunTiming.of(
              run: run,
              startTime: crew.startTime,
              endTime: crew.endTime,
              lastSeen: lastSeen[run.id],
              now: now,
            ),
            driver: crew.driver,
            startTime: crew.startTime,
            endTime: crew.endTime,
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute(
                builder: (_) => RunDetailScreen(
                  authState: authState,
                  runId: run.id,
                  routeName: run.routeName ?? 'Run',
                  driver: crew.driver,
                  startTime: crew.startTime,
                  endTime: crew.endTime,
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

class _RunCard extends StatelessWidget {
  const _RunCard({
    required this.run,
    required this.now,
    required this.timing,
    required this.driver,
    required this.startTime,
    required this.endTime,
    required this.onTap,
  });

  final RunListing run;
  final DateTime now;
  final RunTiming timing;
  final String? driver;
  final String? startTime;
  final String? endTime;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final status = run.status(now);
    final (tone, soft) = switch (status) {
      RunStatus.onTheRoad => (AppColors.brand, AppColors.brandSoft),
      RunStatus.done => (AppColors.success, const Color(0x1A1FA971)),
      RunStatus.unfinished || RunStatus.notRun => (AppColors.warning, const Color(0x1AE4A83A)),
      RunStatus.notStarted => (AppColors.inkMuted, AppColors.surfaceMuted),
    };
    // The owner's own finish time when they set one, else start + estimate.
    final finish = endTime == null
        ? expectedFinish(startTime, run.estimatedTotal)
        : formatStartTime(endTime!);

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(20),
      child: SurfaceCard(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    run.routeName ?? 'Run',
                    style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
                  ),
                ),
                // Against the schedule where that says more than the status:
                // "12 min late", "No signal since 6:40 am", "Finished 20 min late".
                if (_showTiming)
                  RunTimingPill(timing)
                else
                  PillBadge(label: status.label, background: soft, foreground: tone),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              [
                relativeDayLabel(run.date, now),
                ?formatWindow(startTime, endTime),
                driver ?? 'No driver',
              ].join(' · '),
              style: TextStyle(
                fontSize: 12.5,
                color: driver == null ? AppColors.warning : AppColors.inkMuted,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 10),
            if (run.startedAt != null) ...[
              ClipRRect(
                borderRadius: BorderRadius.circular(999),
                child: LinearProgressIndicator(
                  value: run.progress,
                  minHeight: 6,
                  backgroundColor: AppColors.hairline,
                  color: tone,
                ),
              ),
              const SizedBox(height: 6),
            ],
            Text(_detail(status, finish), style: const TextStyle(fontSize: 12, color: AppColors.inkMuted)),
          ],
        ),
      ),
    );
  }

  bool get _showTiming => switch (timing.kind) {
    TimingKind.onTime || TimingKind.late || TimingKind.noSignal || TimingKind.left || TimingKind.lateStart => true,
    TimingKind.done => timing.by != null,
    TimingKind.notStarted || TimingKind.unfinished => false,
  };

  String _detail(RunStatus status, String? finish) {
    final took = run.actualDuration;
    final estimate = run.estimatedTotal;
    return switch (status) {
      RunStatus.done =>
        '${run.stopCount} stops delivered${took == null ? '' : ' in ${DeliveryEstimate.format(took)}'}',
      RunStatus.onTheRoad =>
        '${run.deliveredCount} of ${run.stopCount} delivered'
            '${run.nextStopName == null ? '' : ' · next: ${run.nextStopName}'}',
      RunStatus.unfinished => '${run.deliveredCount} of ${run.stopCount} delivered',
      RunStatus.notRun => '${run.stopCount} stops · nothing marked delivered',
      RunStatus.notStarted =>
        '${run.stopCount} stops'
            '${estimate == null ? '' : ' · about ${DeliveryEstimate.format(estimate)}'}'
            '${finish == null ? '' : ', back ~$finish'}',
    };
  }
}
