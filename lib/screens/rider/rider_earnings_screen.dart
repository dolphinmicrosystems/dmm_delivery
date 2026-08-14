import 'package:flutter/material.dart';

import '../../models/recent_trip.dart';
import '../../state/app_state.dart';
import '../../theme/app_colors.dart';
import '../../widgets/pill_badge.dart';
import '../../widgets/primary_button.dart';
import '../../widgets/section_label.dart';
import '../../widgets/surface_card.dart';
import '../../widgets/weekly_bar_chart.dart';

class RiderEarningsScreen extends StatelessWidget {
  const RiderEarningsScreen({super.key, required this.appState});

  final AppState appState;

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 24, 20, 100),
      children: [
        SurfaceCard(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('This week', style: TextStyle(fontSize: 13, color: AppColors.inkMuted)),
                      const Text(
                        r'$612.40',
                        style: TextStyle(fontSize: 34, fontWeight: FontWeight.w800, color: AppColors.ink),
                      ),
                      Row(
                        children: const [
                          Icon(Icons.arrow_outward_rounded, size: 16, color: AppColors.success),
                          SizedBox(width: 4),
                          Text(
                            '+18% vs last week',
                            style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: AppColors.success),
                          ),
                        ],
                      ),
                    ],
                  ),
                  Container(
                    width: 48,
                    height: 48,
                    decoration: BoxDecoration(color: AppColors.brandSoft, borderRadius: BorderRadius.circular(16)),
                    child: const Icon(Icons.account_balance_wallet_outlined, color: AppColors.brand),
                  ),
                ],
              ),
              const SizedBox(height: 20),
              WeeklyBarChart(
                heights: AppState.weeklyBarHeights,
                labels: AppState.weekdayLabels,
                highlightedIndex: AppState.highlightedWeekday,
              ),
              const Divider(height: 32),
              const Row(
                children: [
                  Expanded(child: _StatColumn(value: '42', label: 'Trips')),
                  Expanded(child: _StatColumn(value: '26h', label: 'Online')),
                  Expanded(child: _StatColumn(value: r'$48', label: 'Tips')),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 24),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            const SectionLabel('Recent trips'),
            TextButton(onPressed: () {}, child: const Text('See all')),
          ],
        ),
        const SizedBox(height: 8),
        SurfaceCard(
          child: Column(
            children: [
              for (final trip in appState.recentTrips)
                _TripRow(trip: trip, isLast: trip == appState.recentTrips.last),
            ],
          ),
        ),
        const SizedBox(height: 24),
        PrimaryButton(label: 'Cash out to bank', onPressed: () {}),
      ],
    );
  }
}

class _StatColumn extends StatelessWidget {
  const _StatColumn({required this.value, required this.label});

  final String value;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Text(value, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800)),
        const SizedBox(height: 2),
        Text(
          label.toUpperCase(),
          style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600, letterSpacing: 0.8, color: AppColors.inkMuted),
        ),
      ],
    );
  }
}

class _TripRow extends StatelessWidget {
  const _TripRow({required this.trip, required this.isLast});

  final RecentTrip trip;
  final bool isLast;

  @override
  Widget build(BuildContext context) {
    final delivered = trip.status == TripStatus.delivered;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        border: isLast ? null : const Border(bottom: BorderSide(color: AppColors.hairline)),
      ),
      child: Row(
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(color: AppColors.brandSoft, borderRadius: BorderRadius.circular(12)),
            child: const Icon(Icons.storefront_outlined, size: 16, color: AppColors.brand),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(trip.vendor, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
                Text(
                  '${trip.time} · ${trip.distanceKm} km',
                  style: const TextStyle(fontSize: 12, color: AppColors.inkMuted),
                ),
              ],
            ),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                '\$${trip.payout.toStringAsFixed(2)}',
                style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700),
              ),
              PillBadge(
                label: delivered ? 'Delivered' : 'Delayed',
                background: delivered
                    ? AppColors.success.withValues(alpha: 0.12)
                    : AppColors.warning.withValues(alpha: 0.15),
                foreground: delivered ? AppColors.success : AppColors.warning,
              ),
            ],
          ),
        ],
      ),
    );
  }
}
