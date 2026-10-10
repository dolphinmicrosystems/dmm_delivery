import 'package:flutter/material.dart';

import '../../models/run_listing.dart';
import '../../models/run_time.dart';
import '../../models/run_timing.dart';
import '../../state/auth_state.dart';
import '../../theme/app_colors.dart';
import '../../widgets/run_timing_pill.dart';
import '../../widgets/section_label.dart';
import '../../widgets/surface_card.dart';
import 'owner_run_data.dart';
import 'run_detail_screen.dart';

/// Home's "Live now": every run on the road today - who is driving it, in
/// which vehicle, how far along, the next stop and whether it is on time -
/// and every run that should have started and hasn't. Problems first.
///
/// Nothing at all when there is nothing to watch, so a quiet afternoon shows
/// the plain Home.
class LiveRunsSection extends StatelessWidget {
  const LiveRunsSection({super.key, required this.authState});

  final AuthState authState;

  @override
  Widget build(BuildContext context) {
    final ownerUid = authState.ownerUid;
    if (ownerUid == null) return const SizedBox.shrink();
    return OwnerRunDataBuilder(
      authState: authState,
      ownerUid: ownerUid,
      loading: const SizedBox.shrink(),
      builder: (context, data) {
        final now = DateTime.now();
        final today = data.runs.where((run) => run.phase(now) == RunPhase.today && run.finished == null);
        return RunLiveBuilder(
          ownerUid: ownerUid,
          runIds: [
            for (final run in today)
              if (run.started != null) run.id,
          ],
          builder: (context, lastSeen) {
            final rows =
                [
                      for (final run in today)
                        if (data.crewFor(run) case final crew)
                          (
                            run: run,
                            crew: crew,
                            timing: RunTiming.of(
                              run: run,
                              startTime: crew.startTime,
                              endTime: crew.endTime,
                              lastSeen: lastSeen[run.id],
                              now: now,
                            ),
                          ),
                    ]
                    .where((row) => row.run.started != null || row.timing.kind == TimingKind.lateStart)
                    .toList()
                  ..sort((a, b) {
                    final problem = (b.timing.isProblem ? 1 : 0) - (a.timing.isProblem ? 1 : 0);
                    return problem != 0 ? problem : (a.run.routeName ?? '').compareTo(b.run.routeName ?? '');
                  });
            if (rows.isEmpty) return const SizedBox.shrink();
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const SectionLabel('Live now'),
                const SizedBox(height: 12),
                for (final row in rows) ...[
                  _LiveRunCard(
                    run: row.run,
                    driver: row.crew.driver,
                    vehicle: row.crew.vehicle?.description,
                    timing: row.timing,
                    onTap: () => Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => RunDetailScreen(
                          authState: authState,
                          runId: row.run.id,
                          routeName: row.run.routeName ?? 'Run',
                          driver: row.crew.driver,
                          startTime: row.crew.startTime,
                          endTime: row.crew.endTime,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                ],
                const SizedBox(height: 8),
              ],
            );
          },
        );
      },
    );
  }
}

class _LiveRunCard extends StatelessWidget {
  const _LiveRunCard({
    required this.run,
    required this.driver,
    required this.vehicle,
    required this.timing,
    required this.onTap,
  });

  final RunListing run;
  final String? driver;
  final String? vehicle;
  final RunTiming timing;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final (tone, _) = RunTimingPill.colors(timing.kind);
    final started = run.started != null;
    final projected = timing.projectedFinish, expected = timing.expectedFinish;
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
                RunTimingPill(timing),
              ],
            ),
            const SizedBox(height: 6),
            _Line(icon: Icons.person_rounded, text: driver ?? 'No driver', warn: driver == null),
            const SizedBox(height: 2),
            _Line(icon: Icons.local_shipping_rounded, text: vehicle ?? 'No vehicle assigned'),
            const SizedBox(height: 10),
            if (started) ...[
              ClipRRect(
                borderRadius: BorderRadius.circular(999),
                child: LinearProgressIndicator(
                  value: run.progress,
                  minHeight: 6,
                  backgroundColor: AppColors.hairline,
                  color: timing.kind == TimingKind.onTime ? AppColors.brand : tone,
                ),
              ),
              const SizedBox(height: 6),
            ],
            Text(
              [
                if (started)
                  '${run.deliveredCount} of ${run.stopCount} delivered'
                else
                  '${run.stopCount} stops',
                if (started && run.nextStopName != null) 'next: ${run.nextStopName}',
                if (projected != null && !{TimingKind.noSignal, TimingKind.left}.contains(timing.kind))
                  'back ~${formatClock(projected.hour, projected.minute)}'
                else if (expected != null)
                  'due back ${formatClock(expected.hour, expected.minute)}',
              ].join(' · '),
              style: const TextStyle(fontSize: 12, color: AppColors.inkMuted),
            ),
          ],
        ),
      ),
    );
  }
}

class _Line extends StatelessWidget {
  const _Line({required this.icon, required this.text, this.warn = false});

  final IconData icon;
  final String text;
  final bool warn;

  @override
  Widget build(BuildContext context) {
    final color = warn ? AppColors.warning : AppColors.inkMuted;
    return Row(
      children: [
        Icon(icon, size: 15, color: color),
        const SizedBox(width: 6),
        Expanded(
          child: Text(
            text,
            style: TextStyle(fontSize: 12.5, color: color, fontWeight: FontWeight.w600),
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    );
  }
}
