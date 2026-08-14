import 'package:flutter/material.dart';

import '../../state/app_state.dart';
import '../../theme/app_colors.dart';
import '../../widgets/pill_badge.dart';
import '../../widgets/primary_button.dart';
import '../../widgets/surface_card.dart';

class RiderActiveScreen extends StatelessWidget {
  const RiderActiveScreen({super.key, required this.appState});

  final AppState appState;

  @override
  Widget build(BuildContext context) {
    final job = appState.activeJob;
    if (job == null) {
      return _EmptyActive(appState: appState);
    }
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 24, 20, 100),
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              'In transit · #${job.id}',
              style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
            ),
            const StatusDot(label: 'Active', color: AppColors.brand),
          ],
        ),
        const SizedBox(height: 16),
        SurfaceCard(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'NEXT STEP',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  letterSpacing: 1.2,
                  color: AppColors.inkMuted,
                ),
              ),
              const SizedBox(height: 6),
              Row(
                children: [
                  const Icon(Icons.turn_right_rounded, size: 26, color: AppColors.brand),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      job.nextStepInstruction,
                      style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
                    ),
                  ),
                  Text(
                    '${job.nextStepDistanceM} m',
                    style: const TextStyle(fontSize: 13, color: AppColors.inkMuted),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              const Divider(height: 1),
              const SizedBox(height: 16),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.baseline,
                    textBaseline: TextBaseline.alphabetic,
                    children: [
                      Text(
                        '${job.activeEtaMinutes}',
                        style: const TextStyle(fontSize: 28, fontWeight: FontWeight.w800),
                      ),
                      const SizedBox(width: 6),
                      const Text('min', style: TextStyle(fontSize: 13, color: AppColors.inkMuted)),
                    ],
                  ),
                  Text(
                    job.activeEtaTime,
                    style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
                  ),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        SurfaceCard(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _StepRow(
                icon: Icons.storefront_outlined,
                title: 'Picked up · ${job.vendor}',
                subtitle: null,
                done: true,
              ),
              const SizedBox(height: 12),
              _StepRow(
                icon: Icons.person_outline_rounded,
                title: 'Deliver to ${job.customerName}',
                subtitle: job.dropoffAddress,
                done: false,
              ),
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: AppColors.surfaceMuted,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.sticky_note_2_outlined, size: 16, color: AppColors.inkMuted),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(job.dropoffNotes, style: const TextStyle(fontSize: 13, color: AppColors.inkMuted)),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                    child: SecondaryButton(label: 'Chat', onPressed: () {}),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: SecondaryButton(label: 'Call', onPressed: () {}),
                  ),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        SurfaceCard(
          padding: const EdgeInsets.all(16),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Payout', style: TextStyle(fontSize: 12, color: AppColors.inkMuted)),
                  Text(
                    '\$${job.payout.toStringAsFixed(2)}',
                    style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800),
                  ),
                ],
              ),
              Text(
                '${job.distanceKm} km · ${job.contactlessDropoff ? "Contactless drop-off" : "Signature required"}',
                style: const TextStyle(fontSize: 12, color: AppColors.inkMuted),
              ),
            ],
          ),
        ),
        const SizedBox(height: 24),
        PrimaryButton(label: 'Mark as delivered', onPressed: appState.completeActiveJob),
      ],
    );
  }
}

class _StepRow extends StatelessWidget {
  const _StepRow({required this.icon, required this.title, required this.subtitle, required this.done});

  final IconData icon;
  final String title;
  final String? subtitle;
  final bool done;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 32,
          height: 32,
          decoration: BoxDecoration(
            color: done ? AppColors.success.withValues(alpha: 0.12) : AppColors.brandSoft,
            borderRadius: BorderRadius.circular(10),
          ),
          child: Icon(icon, size: 16, color: done ? AppColors.success : AppColors.brand),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
              if (subtitle != null)
                Text(subtitle!, style: const TextStyle(fontSize: 12, color: AppColors.inkMuted)),
            ],
          ),
        ),
      ],
    );
  }
}

class _EmptyActive extends StatelessWidget {
  const _EmptyActive({required this.appState});

  final AppState appState;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.pedal_bike_outlined, size: 40, color: AppColors.inkMuted),
            const SizedBox(height: 12),
            Text('No active delivery', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 4),
            Text(
              'Accept an order from Orders to get started.',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodyMedium,
            ),
            const SizedBox(height: 16),
            TextButton(
              onPressed: () => appState.setRiderTab(0),
              child: const Text('Go to Orders'),
            ),
          ],
        ),
      ),
    );
  }
}
