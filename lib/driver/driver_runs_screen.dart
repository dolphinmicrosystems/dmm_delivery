import 'package:flutter/material.dart';

import '../models/delivery_estimate.dart';
import '../models/driver_stats.dart';
import '../models/run_listing.dart';
import '../models/run_time.dart';
import '../state/auth_state.dart';
import '../theme/app_colors.dart';
import '../widgets/pill_badge.dart';
import '../widgets/surface_card.dart';
import 'driver_data.dart';
import 'driver_navigation.dart';
import 'driver_schedule.dart';

/// The driver's Runs tab: Upcoming, Today and Past, opening on Today.
///
/// Upcoming and Today say when to start ("Tomorrow · starts 5:00 am"); Past
/// says how each run went, and opens its full history. Built by
/// DriverSchedule from the driver's runs and the business's schedule.
///
/// A body, not a Scaffold - it is one of the driver shell's tabs.
class DriverRunsScreen extends StatelessWidget {
  const DriverRunsScreen({super.key, required this.authState, required this.data});

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
    return DefaultTabController(
      length: 3,
      initialIndex: 1, // Today: what a driver opens the app to see
      child: Column(
        children: [
          TabBar(
            tabs: [
              Tab(text: _label('Upcoming', cards[RunPhase.upcoming]!)),
              Tab(text: _label('Today', cards[RunPhase.today]!)),
              const Tab(text: 'Past'),
            ],
          ),
          Expanded(
            child: TabBarView(
              children: [
                for (final phase in RunPhase.values)
                  _CardList(
                    authState: authState,
                    cards: cards[phase]!,
                    phase: phase,
                    now: now,
                    vehicle: data.vehicle?.description,
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  static String _label(String tab, List<DriverRunCard> cards) =>
      cards.isEmpty ? tab : '$tab (${cards.length})';
}

class _CardList extends StatelessWidget {
  const _CardList({
    required this.authState,
    required this.cards,
    required this.phase,
    required this.now,
    required this.vehicle,
  });

  final AuthState authState;
  final List<DriverRunCard> cards;
  final RunPhase phase;
  final DateTime now;

  /// The vehicle the owner assigned this driver, shown on runs still to come.
  final String? vehicle;

  @override
  Widget build(BuildContext context) {
    if (cards.isEmpty) {
      return ListView(
        padding: const EdgeInsets.all(24),
        children: [
          Text(switch (phase) {
            RunPhase.upcoming =>
              'Nothing coming up. When your owner gives you a route or a day, '
                  "it appears here - and you'll get a notification.",
            RunPhase.today => 'No runs for you today.',
            RunPhase.past => 'Runs you have driven appear here, with how long each took.',
          }, style: const TextStyle(fontSize: 13, color: AppColors.inkMuted, height: 1.4)),
        ],
      );
    }
    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
      itemCount: cards.length,
      separatorBuilder: (_, _) => const SizedBox(height: 12),
      itemBuilder: (context, index) {
        final card = cards[index];
        final run = card.run;
        return run == null
            ? _BookingCard(
                card: card,
                now: now,
                vehicle: vehicle,
                onTap: () => openDriverCard(
                  context,
                  authState,
                  card,
                  vehicle: vehicle,
                  canStartToday: phase == RunPhase.today,
                ),
              )
            : _RunCard(
                card: card,
                run: run,
                now: now,
                // The vehicle is for runs still to drive; history doesn't
                // record which one was used.
                vehicle: phase == RunPhase.past ? null : vehicle,
                onTap: () => openDriverCard(context, authState, card, vehicle: vehicle),
              );
      },
    );
  }
}

class _RunCard extends StatelessWidget {
  const _RunCard({
    required this.card,
    required this.run,
    required this.now,
    required this.vehicle,
    required this.onTap,
  });

  final DriverRunCard card;
  final RunListing run;
  final DateTime now;
  final String? vehicle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final status = run.status(now);
    final (tone, soft) = runStatusColors(status);
    final start = card.start;
    // The owner's finish when they set one, else start + estimate.
    final finish = card.end == null ? expectedFinish(start, run.estimatedTotal) : null;
    final took = run.totalTime;
    final estimate = run.estimatedTotal;

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
                    card.routeName,
                    style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
                  ),
                ),
                PillBadge(label: status.label, background: soft, foreground: tone),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              [relativeDayLabel(run.date, now), ?formatWindow(start, card.end)].join(' · '),
              style: const TextStyle(fontSize: 12.5, color: AppColors.inkMuted, fontWeight: FontWeight.w600),
            ),
            if (vehicle != null) _VehicleLine(vehicle!),
            const SizedBox(height: 10),
            if (run.started != null && status != RunStatus.notStarted) ...[
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
            Text(switch (status) {
              RunStatus.done =>
                'All ${run.stopCount} delivered${took == null ? '' : ' · took ${DeliveryEstimate.format(took)}'}',
              RunStatus.unfinished =>
                '${run.deliveredCount} of ${run.stopCount} delivered'
                    '${took == null ? '' : ' · ${DeliveryEstimate.format(took)}'}',
              RunStatus.notRun => '${run.stopCount} stops · not driven',
              RunStatus.onTheRoad =>
                '${run.deliveredCount} of ${run.stopCount} delivered'
                    '${run.nextStopName == null ? '' : ' · next: ${run.nextStopName}'}',
              RunStatus.notStarted =>
                '${run.stopCount} stops'
                    '${estimate == null ? '' : ' · about ${DeliveryEstimate.format(estimate)}'}'
                    '${finish == null ? '' : ', back ~$finish'}',
            }, style: const TextStyle(fontSize: 12, color: AppColors.inkMuted)),
          ],
        ),
      ),
    );
  }
}

/// A day the schedule gives the driver before its run sheet exists.
class _BookingCard extends StatelessWidget {
  const _BookingCard({required this.card, required this.now, required this.vehicle, required this.onTap});

  final DriverRunCard card;
  final DateTime now;
  final String? vehicle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final booking = card.booking!;
    final start = card.start;
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
                    card.routeName,
                    style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
                  ),
                ),
                PillBadge(
                  label: booking.oneDay ? 'Covering' : 'Your route',
                  background: AppColors.brandSoft,
                  foreground: AppColors.brand,
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              [
                booking.oneDay ? relativeDayLabel(card.day, now) : 'From ${relativeDayLabel(card.day, now)}',
                ?formatWindow(start, card.end),
              ].join(' · '),
              style: const TextStyle(fontSize: 12.5, color: AppColors.inkMuted, fontWeight: FontWeight.w600),
            ),
            if (vehicle != null) _VehicleLine(vehicle!),
            const SizedBox(height: 6),
            const Text(
              'Tap to see the route. What to deliver shows once the run sheet is uploaded.',
              style: TextStyle(fontSize: 12, color: AppColors.inkMuted),
            ),
          ],
        ),
      ),
    );
  }
}

/// "Isuzu truck · ABC123" with a truck icon: the vehicle to drive.
class _VehicleLine extends StatelessWidget {
  const _VehicleLine(this.vehicle);

  final String vehicle;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 4),
      child: Row(
        children: [
          const Icon(Icons.local_shipping_outlined, size: 15, color: AppColors.inkMuted),
          const SizedBox(width: 6),
          Expanded(
            child: Text(vehicle, style: const TextStyle(fontSize: 12.5, color: AppColors.inkMuted)),
          ),
        ],
      ),
    );
  }
}

/// The colour of a run's status pill, as on the owner's Runs tab.
(Color, Color) runStatusColors(RunStatus status) => switch (status) {
  RunStatus.onTheRoad => (AppColors.brand, AppColors.brandSoft),
  RunStatus.done => (AppColors.success, const Color(0x1A1FA971)),
  RunStatus.unfinished || RunStatus.notRun => (AppColors.warning, const Color(0x1AE4A83A)),
  RunStatus.notStarted => (AppColors.inkMuted, AppColors.surfaceMuted),
};
