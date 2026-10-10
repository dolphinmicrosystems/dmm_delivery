import 'package:flutter/material.dart';

import '../models/delivery_estimate.dart';
import '../models/driver_stats.dart';
import '../models/run_time.dart';
import '../models/run_timing.dart';
import '../state/auth_state.dart';
import '../theme/app_colors.dart';
import '../widgets/run_timing_pill.dart';
import '../widgets/section_label.dart';
import '../widgets/surface_card.dart';
import 'driver_data.dart';
import 'driver_navigation.dart';
import 'driver_schedule.dart';
import 'route_starter.dart';

/// The driver's Home tab: the run that is live now, big - or, with none under
/// way, the next one to drive and when it starts - then what follows.
///
/// "Live" is a run started (Start tapped, or a stop delivered) and not yet
/// finished; it updates as stops are delivered, from the progress the backend
/// writes onto the run. Picked by DriverSchedule.home.
///
/// A body, not a Scaffold - it is one of the driver shell's tabs.
class DriverHomeScreen extends StatelessWidget {
  const DriverHomeScreen({super.key, required this.authState, required this.data});

  final AuthState authState;
  final DriverData data;

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final cards = DriverSchedule.build(
      driverUid: authState.user!.uid,
      runs: data.runs,
      assignments: data.assignments,
      routeNames: data.routeNames,
      now: now,
    );
    final home = DriverSchedule.home(cards, now);
    final vehicle = data.vehicle?.description;
    bool isToday(DateTime? day) => day != null && relativeDayLabel(day, now) == 'Today';
    void open(DriverRunCard card) {
      if (canDrive(card, now)) {
        openDriving(context, authState, card, vehicle: vehicle);
      } else if (card.run == null && isToday(card.day)) {
        // Booked today with no run sheet yet: start it all the same.
        startRouteToday(
          context,
          authState: authState,
          roundKey: card.booking!.roundKey,
          routeName: card.routeName,
          vehicle: vehicle,
        );
      } else {
        openDriverCard(context, authState, card, vehicle: vehicle);
      }
    }

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 20, 16, 24),
      children: [
        if (home.live case final live?) ...[
          const SectionLabel('Live now'),
          const SizedBox(height: 8),
          _LiveCard(card: live, now: now, vehicle: vehicle, onOpen: () => open(live)),
          const SizedBox(height: 24),
        ],
        if (home.next case final next?) ...[
          SectionLabel(home.live == null ? 'Next up' : 'After this'),
          const SizedBox(height: 8),
          _NextCard(card: next, now: now, vehicle: vehicle, onOpen: () => open(next)),
        ] else if (home.live == null)
          const SurfaceCard(
            padding: EdgeInsets.all(16),
            child: Text(
              "Nothing to drive right now. When your owner gives you a route or a day, it shows here - "
              "and you'll get a notification.",
              style: TextStyle(fontSize: 13, color: AppColors.inkMuted, height: 1.4),
            ),
          ),
        if (home.later.isNotEmpty) ...[
          const SizedBox(height: 24),
          const SectionLabel('Later'),
          const SizedBox(height: 8),
          SurfaceCard(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: Column(
              children: [
                for (final card in home.later)
                  ListTile(
                    onTap: () => open(card),
                    leading: const Icon(Icons.event_note_rounded, color: AppColors.brand),
                    title: Text(card.routeName, style: const TextStyle(fontWeight: FontWeight.w600)),
                    subtitle: Text(
                      [relativeDayLabel(card.day, now), ?formatWindow(card.start, card.end)].join(' · '),
                    ),
                    trailing: const Icon(Icons.chevron_right_rounded),
                  ),
              ],
            ),
          ),
        ],
      ],
    );
  }
}

/// The run being driven: progress, the next stop, and a way in.
class _LiveCard extends StatelessWidget {
  const _LiveCard({required this.card, required this.now, required this.vehicle, required this.onOpen});

  final DriverRunCard card;
  final DateTime now;
  final String? vehicle;
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) {
    final run = card.run!;
    final started = run.started?.toLocal();
    // The same "On time" / "12 min late" the owner sees.
    final timing = RunTiming.of(run: run, startTime: card.start, endTime: card.end, now: now);
    final projected = timing.projectedFinish;
    return SurfaceCard(
      padding: const EdgeInsets.all(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  card.routeName,
                  style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
                ),
              ),
              RunTimingPill(timing),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            [
              if (started != null) 'Started ${formatClock(started.hour, started.minute)}',
              if (card.end case final end?) 'finish by ${formatStartTime(end)}',
              if (projected != null && !{TimingKind.noSignal, TimingKind.left}.contains(timing.kind))
                'at this pace ~${formatClock(projected.hour, projected.minute)}',
            ].join(' · '),
            style: const TextStyle(fontSize: 13, color: AppColors.inkMuted, fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 12),
          ClipRRect(
            borderRadius: BorderRadius.circular(999),
            child: LinearProgressIndicator(
              value: run.progress,
              minHeight: 8,
              backgroundColor: AppColors.hairline,
              color: AppColors.brand,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            '${run.deliveredCount} of ${run.stopCount} delivered',
            style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700),
          ),
          if (run.nextStopName case final next?)
            Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Text('Next: $next', style: const TextStyle(fontSize: 13, color: AppColors.inkMuted)),
            ),
          if (vehicle != null)
            Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Text(
                'Vehicle: $vehicle',
                style: const TextStyle(fontSize: 13, color: AppColors.inkMuted),
              ),
            ),
          const SizedBox(height: 14),
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              onPressed: onOpen,
              icon: const Icon(Icons.navigation_rounded),
              label: const Text('Drive'),
            ),
          ),
        ],
      ),
    );
  }
}

/// The next run (or booked day): when, how long, which vehicle.
class _NextCard extends StatelessWidget {
  const _NextCard({required this.card, required this.now, required this.vehicle, required this.onOpen});

  final DriverRunCard card;
  final DateTime now;
  final String? vehicle;
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) {
    final run = card.run;
    final estimate = run?.estimatedTotal;
    final countdown = _countdown(card, now);
    // Past its start with nothing done: "Not started - 15 min late".
    final timing = run == null
        ? null
        : RunTiming.of(run: run, startTime: card.start, endTime: card.end, now: now);
    final lateStart = timing?.kind == TimingKind.lateStart ? timing : null;
    return SurfaceCard(
      padding: const EdgeInsets.all(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(card.routeName, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
          const SizedBox(height: 4),
          Text(
            [
              card.booking != null && !card.booking!.oneDay
                  ? 'From ${relativeDayLabel(card.day, now)}'
                  : relativeDayLabel(card.day, now),
              ?formatWindow(card.start, card.end),
            ].join(' · '),
            style: const TextStyle(fontSize: 13, color: AppColors.inkMuted, fontWeight: FontWeight.w600),
          ),
          if (lateStart != null)
            Padding(padding: const EdgeInsets.only(top: 8), child: RunTimingPill(lateStart))
          else if (countdown != null)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text(countdown, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
            ),
          const SizedBox(height: 8),
          for (final line in [
            if (run != null)
              '${run.stopCount} stops'
                  '${estimate == null ? '' : ' · about ${DeliveryEstimate.format(estimate)}'}'
            else
              'Run sheet not uploaded yet - you can see the route',
            if (vehicle != null) 'Vehicle: $vehicle',
          ])
            Text(line, style: const TextStyle(fontSize: 13, color: AppColors.inkMuted)),
          const SizedBox(height: 14),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: onOpen,
              icon: const Icon(Icons.map_outlined),
              label: Text(switch ((run, canDrive(card, now))) {
                (null, _) when relativeDayLabel(card.day, now) == 'Today' => 'Start route',
                (null, _) => 'See the route',
                (_, true) => 'Start run',
                _ => 'Open run',
              }),
            ),
          ),
        ],
      ),
    );
  }

  /// "Starts in 2 h 10 min" on the day itself; null otherwise.
  static String? _countdown(DriverRunCard card, DateTime now) {
    final day = card.day, start = parseStartTime(card.start);
    if (day == null || start == null) return null;
    final at = DateTime(day.year, day.month, day.day, start.hour, start.minute);
    final left = at.difference(now);
    if (left.isNegative || left > const Duration(hours: 12)) return null;
    return left.inMinutes < 1 ? 'Starts now' : 'Starts in ${DeliveryEstimate.format(left)}';
  }
}
