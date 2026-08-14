import 'package:flutter/material.dart';

import '../../models/rider_job.dart';
import '../../state/app_state.dart';
import '../../theme/app_colors.dart';
import '../../widgets/pill_badge.dart';
import '../../widgets/primary_button.dart';
import '../../widgets/section_label.dart';
import '../../widgets/stat_tile.dart';
import '../../widgets/surface_card.dart';

class RiderOrdersScreen extends StatefulWidget {
  const RiderOrdersScreen({super.key, required this.appState});

  final AppState appState;

  @override
  State<RiderOrdersScreen> createState() => _RiderOrdersScreenState();
}

class _RiderOrdersScreenState extends State<RiderOrdersScreen> {
  bool online = true;

  @override
  Widget build(BuildContext context) {
    final appState = widget.appState;
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 24, 20, 100),
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text('Orders', style: Theme.of(context).textTheme.headlineMedium),
            Row(
              children: [
                Text(
                  online ? 'Online' : 'Offline',
                  style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
                ),
                Switch(
                  value: online,
                  activeThumbColor: AppColors.brand,
                  onChanged: (value) => setState(() => online = value),
                ),
              ],
            ),
          ],
        ),
        const SizedBox(height: 8),
        Row(
          children: const [
            PillBadge(label: r'$11'),
            SizedBox(width: 8),
            PillBadge(label: r'$14'),
            SizedBox(width: 8),
            PillBadge(label: r'$10'),
          ],
        ),
        const SizedBox(height: 20),
        Row(
          children: [
            Expanded(
              child: SurfaceCard(
                padding: const EdgeInsets.symmetric(vertical: 16),
                child: const StatTile(value: r'$86.40', label: 'Today · 7 deliveries'),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: SurfaceCard(
                padding: const EdgeInsets.symmetric(vertical: 16),
                child: const StatTile(value: '94%', label: 'Acceptance · 7 days'),
              ),
            ),
          ],
        ),
        const SizedBox(height: 24),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            const SectionLabel('Nearby orders'),
            TextButton.icon(
              onPressed: () {},
              icon: const Icon(Icons.map_outlined, size: 16),
              label: const Text('Map view'),
            ),
          ],
        ),
        const SizedBox(height: 8),
        if (appState.nearbyJobs.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 24),
            child: Text(
              'No orders nearby right now.',
              style: Theme.of(context).textTheme.bodyMedium,
              textAlign: TextAlign.center,
            ),
          )
        else
          for (final job in appState.nearbyJobs) ...[
            _JobCard(job: job, onAccept: () => appState.acceptJob(job.id)),
            const SizedBox(height: 12),
          ],
      ],
    );
  }
}

class _JobCard extends StatelessWidget {
  const _JobCard({required this.job, required this.onAccept});

  final RiderJob job;
  final VoidCallback onAccept;

  @override
  Widget build(BuildContext context) {
    return SurfaceCard(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Row(
                  children: [
                    Text(job.vendor, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
                    if (job.badge != null) ...[
                      const SizedBox(width: 8),
                      PillBadge(
                        label: job.badge!,
                        background: AppColors.warning.withValues(alpha: 0.15),
                        foreground: AppColors.warning,
                      ),
                    ],
                  ],
                ),
              ),
              Text(
                '\$${job.payout.toStringAsFixed(2)}',
                style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800),
              ),
            ],
          ),
          const SizedBox(height: 2),
          Text('#${job.id}', style: const TextStyle(fontSize: 12, color: AppColors.inkMuted)),
          const SizedBox(height: 10),
          Text(
            '${job.routeFrom} → ${job.routeTo}',
            style: const TextStyle(fontSize: 13, color: AppColors.inkMuted),
          ),
          const SizedBox(height: 4),
          Row(
            children: [
              Text('${job.distanceKm} km', style: const TextStyle(fontSize: 12, color: AppColors.inkMuted)),
              const SizedBox(width: 12),
              Text('${job.etaMinutes}m', style: const TextStyle(fontSize: 12, color: AppColors.inkMuted)),
            ],
          ),
          const SizedBox(height: 14),
          PrimaryButton(label: 'Accept order', onPressed: onAccept),
        ],
      ),
    );
  }
}
