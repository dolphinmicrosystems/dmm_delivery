import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import '../../models/delivery_estimate.dart';
import '../../models/driver_invitation.dart';
import '../../models/driver_stats.dart';
import '../../models/route_assignment.dart';
import '../../models/run_listing.dart';
import '../../models/run_time.dart';
import '../../state/auth_state.dart';
import '../../theme/app_colors.dart';
import '../../util/app_log.dart';
import '../../widgets/pill_badge.dart';
import '../../widgets/surface_card.dart';
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
                : _RunData(
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

/// Everything the lists need, gathered once for all three tabs.
class _Data {
  const _Data({
    required this.runs,
    required this.routeNames,
    required this.assignmentsByRoute,
    required this.driverNames,
  });

  final List<RunListing> runs;
  final Map<String, String> routeNames;
  final Map<String, List<RouteAssignment>> assignmentsByRoute;
  final Map<String, String> driverNames;

  /// Who drives [run] and from what time. The driver stamped on the run at
  /// confirm wins; otherwise it is whoever the route's schedule names for
  /// that day - which is also where the start time always comes from.
  ({String? driver, String? startTime}) crewFor(RunListing run) {
    final day = run.date ?? DateTime.now();
    final scheduled = RouteAssignment.activeAt(
      assignmentsByRoute[run.roundKey] ?? const [],
      DateTime(day.year, day.month, day.day, 12),
    );
    final uid = run.riderId ?? scheduled?.driverUid;
    return (
      driver: uid == null ? null : (driverNames[uid] ?? scheduled?.driverName),
      startTime: scheduled?.startTime,
    );
  }
}

class _RunData extends StatelessWidget {
  const _RunData({required this.authState, required this.ownerUid, required this.builder});

  final AuthState authState;
  final String ownerUid;
  final Widget Function(BuildContext context, _Data data) builder;

  @override
  Widget build(BuildContext context) {
    // Only confirmed runs: drafts under review and runs a same-day re-upload
    // replaced ('superseded') are not deliveries anyone will make.
    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: FirebaseFirestore.instance
          .collection('delivery_run')
          .where('owner_uid', isEqualTo: ownerUid)
          .where('status', isEqualTo: 'sequenced')
          .snapshots(),
      builder: (context, runsSnap) {
        if (runsSnap.hasError) {
          AppLog.owner.error('runs stream failed', runsSnap.error, runsSnap.stackTrace);
        }
        return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
          stream: FirebaseFirestore.instance
              .collection('circuits')
              .where('owner_uid', isEqualTo: ownerUid)
              .snapshots(),
          builder: (context, circuitsSnap) => StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
            stream: authState.routeAssignments(),
            builder: (context, assignmentsSnap) => StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
              stream: authState.invitations(),
              builder: (context, invitationsSnap) {
                if (!runsSnap.hasData || !circuitsSnap.hasData) {
                  return const Center(child: CircularProgressIndicator());
                }
                final routeNames = {
                  for (final doc in circuitsSnap.data!.docs) doc.id: doc.data()['round'] as String? ?? 'Route',
                };
                final now = DateTime.now();
                final data = _Data(
                  // Runs of deleted routes are left out: the route is gone,
                  // and so is anyone who would drive it.
                  runs: [
                    for (final doc in runsSnap.data!.docs)
                      if (routeNames.containsKey(doc.data()['round_key']))
                        RunListing.fromDoc(doc, routeName: routeNames[doc.data()['round_key']]),
                  ],
                  routeNames: routeNames,
                  assignmentsByRoute: RouteAssignment.byRoute([
                    for (final doc in assignmentsSnap.data?.docs ?? const []) RouteAssignment.fromDoc(doc),
                  ]),
                  driverNames: {
                    for (final doc in invitationsSnap.data?.docs ?? const [])
                      if (DriverInvitation.fromDoc(doc, now: now) case final d when d.acceptedUid != null)
                        d.acceptedUid!: d.displayName,
                  },
                );
                return builder(context, data);
              },
            ),
          ),
        );
      },
    );
  }
}

class _RunList extends StatelessWidget {
  const _RunList({required this.data, required this.phase, required this.authState});

  final _Data data;
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
          Text(
            switch (phase) {
              RunPhase.upcoming => 'No runs coming up. Upload a run sheet on the Routes tab and it '
                  'appears here for the date printed on it.',
              RunPhase.today => 'No runs today.',
              RunPhase.past => 'No past runs yet.',
            },
            style: const TextStyle(fontSize: 13, color: AppColors.inkMuted, height: 1.4),
          ),
        ],
      );
    }
    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
      itemCount: runs.length,
      separatorBuilder: (_, _) => const SizedBox(height: 12),
      itemBuilder: (context, index) {
        final run = runs[index];
        final crew = data.crewFor(run);
        return _RunCard(
          run: run,
          now: now,
          driver: crew.driver,
          startTime: crew.startTime,
          onTap: () => Navigator.of(context).push(
            MaterialPageRoute(
              builder: (_) => RunDetailScreen(
                authState: authState,
                runId: run.id,
                routeName: run.routeName ?? 'Run',
                driver: crew.driver,
                startTime: crew.startTime,
              ),
            ),
          ),
        );
      },
    );
  }
}

class _RunCard extends StatelessWidget {
  const _RunCard({
    required this.run,
    required this.now,
    required this.driver,
    required this.startTime,
    required this.onTap,
  });

  final RunListing run;
  final DateTime now;
  final String? driver;
  final String? startTime;
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
    final finish = expectedFinish(startTime, run.estimatedTotal);

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
                PillBadge(label: status.label, background: soft, foreground: tone),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              [
                _dayLabel(run.date, now),
                if (startTime != null) formatStartTime(startTime!),
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

  static String _dayLabel(DateTime? date, DateTime now) {
    if (date == null) return 'No date';
    final today = DateTime(now.year, now.month, now.day);
    final difference = date.difference(today).inDays;
    if (difference == 0) return 'Today';
    if (difference == 1) return 'Tomorrow';
    if (difference == -1) return 'Yesterday';
    final weekday = const ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'][date.weekday - 1];
    return '$weekday ${formatShortDate(date, thisYear: now.year)}';
  }
}
