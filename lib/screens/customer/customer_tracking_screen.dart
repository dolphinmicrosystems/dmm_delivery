import 'package:flutter/material.dart';

import '../../state/app_state.dart';
import '../../theme/app_colors.dart';
import '../../widgets/pill_badge.dart';
import '../../widgets/surface_card.dart';

class CustomerTrackingScreen extends StatelessWidget {
  const CustomerTrackingScreen({super.key, required this.appState});

  final AppState appState;

  @override
  Widget build(BuildContext context) {
    final order = appState.activeCustomerOrder;
    if (order == null) {
      return const _EmptyTracking();
    }
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 24, 20, 100),
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              'Order #${order.id}',
              style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
            ),
            const StatusDot(label: 'On the way', color: AppColors.brand),
          ],
        ),
        const SizedBox(height: 24),
        SurfaceCard(
          padding: const EdgeInsets.all(20),
          child: Column(
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Arriving in',
                        style: TextStyle(fontSize: 13, color: AppColors.inkMuted),
                      ),
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.baseline,
                        textBaseline: TextBaseline.alphabetic,
                        children: [
                          Text(
                            '${order.etaMinutes}',
                            style: const TextStyle(
                              fontSize: 40,
                              fontWeight: FontWeight.w800,
                              color: AppColors.ink,
                            ),
                          ),
                          const SizedBox(width: 6),
                          const Text(
                            'min',
                            style: TextStyle(fontSize: 15, color: AppColors.inkMuted),
                          ),
                        ],
                      ),
                    ],
                  ),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      const Text(
                        'ETA',
                        style: TextStyle(fontSize: 13, color: AppColors.inkMuted),
                      ),
                      Text(
                        order.etaTime,
                        style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700),
                      ),
                    ],
                  ),
                ],
              ),
              const SizedBox(height: 16),
              const Divider(height: 1),
              const SizedBox(height: 16),
              Row(
                children: [
                  const Icon(Icons.location_on_outlined, size: 16, color: AppColors.inkMuted),
                  const SizedBox(width: 6),
                  Text(
                    '${order.distanceKm} km away',
                    style: const TextStyle(fontSize: 13, color: AppColors.inkMuted),
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
              Row(
                children: [
                  CircleAvatar(
                    radius: 22,
                    backgroundColor: AppColors.brandSoft,
                    child: Text(
                      order.riderInitials,
                      style: const TextStyle(fontWeight: FontWeight.w700, color: AppColors.brand),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Text(
                              order.riderName,
                              style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
                            ),
                            const SizedBox(width: 6),
                            const Icon(Icons.star_rounded, size: 14, color: AppColors.warning),
                            Text(
                              '${order.riderRating}',
                              style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
                            ),
                          ],
                        ),
                        Text(
                          '${order.riderVehicle} · ${order.riderPlate}',
                          style: const TextStyle(fontSize: 13, color: AppColors.inkMuted),
                        ),
                      ],
                    ),
                  ),
                  IconButton.filledTonal(
                    onPressed: () {},
                    icon: const Icon(Icons.chat_bubble_outline_rounded),
                  ),
                  const SizedBox(width: 4),
                  IconButton.filledTonal(
                    onPressed: () {},
                    icon: const Icon(Icons.call_outlined),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              Text(
                'Contact details are masked for your safety.',
                style: Theme.of(context).textTheme.bodyMedium,
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        SurfaceCard(
          child: Column(
            children: const [
              _ActionRow(icon: Icons.edit_location_alt_outlined, label: 'Change drop-off'),
              Divider(height: 1),
              _ActionRow(icon: Icons.sticky_note_2_outlined, label: 'Delivery notes'),
            ],
          ),
        ),
      ],
    );
  }
}

class _ActionRow extends StatelessWidget {
  const _ActionRow({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: Icon(icon, color: AppColors.inkMuted, size: 20),
      title: Text(label, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
      trailing: const Icon(Icons.chevron_right_rounded, color: AppColors.inkMuted),
    );
  }
}

class _EmptyTracking extends StatelessWidget {
  const _EmptyTracking();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.local_shipping_outlined, size: 40, color: AppColors.inkMuted),
            const SizedBox(height: 12),
            Text(
              'No active order',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 4),
            Text(
              'Confirm a drop-off on Home to start tracking.',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodyMedium,
            ),
          ],
        ),
      ),
    );
  }
}
