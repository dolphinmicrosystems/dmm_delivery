import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import '../../models/rider_job.dart';
import '../../services/driver_presence.dart';
import '../../state/app_state.dart';
import '../../state/auth_state.dart';
import '../../theme/app_colors.dart';
import '../../util/app_log.dart';
import '../../widgets/pill_badge.dart';
import '../../widgets/primary_button.dart';
import '../../widgets/section_label.dart';
import '../../widgets/stat_tile.dart';
import '../../widgets/surface_card.dart';

class RiderOrdersScreen extends StatefulWidget {
  const RiderOrdersScreen({super.key, required this.appState, required this.authState});

  final AppState appState;
  final AuthState authState;

  @override
  State<RiderOrdersScreen> createState() => _RiderOrdersScreenState();
}

class _RiderOrdersScreenState extends State<RiderOrdersScreen> {
  /// What the driver just chose, shown until Firestore confirms it, so the
  /// switch moves under their thumb rather than a beat later.
  bool? _pending;

  late final Stream<bool> _presence = DriverPresence.watch(widget.authState.user!.uid);

  Future<void> _setOnline(bool online) async {
    final messenger = ScaffoldMessenger.of(context);
    setState(() => _pending = online);
    try {
      await DriverPresence.set(
        uid: widget.authState.user!.uid,
        ownerUid: widget.authState.ownerUid!,
        online: online,
      );
    } on FirebaseException catch (error, stack) {
      AppLog.auth.error('presence write failed', error, stack, {'online': online});
      messenger.showSnackBar(
        SnackBar(content: Text("Couldn't switch ${online ? 'online' : 'offline'}. Check your connection.")),
      );
    } finally {
      if (mounted) setState(() => _pending = null);
    }
  }

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
            // Real, unlike the rest of this mock tab: driver_presence/{uid}.
            StreamBuilder<bool>(
              stream: _presence,
              builder: (context, snapshot) {
                final online = _pending ?? snapshot.data ?? false;
                return Row(
                  children: [
                    Text(
                      online ? 'Online' : 'Offline',
                      style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
                    ),
                    Switch(
                      value: online,
                      activeThumbColor: AppColors.brand,
                      onChanged: snapshot.hasData ? _setOnline : null,
                    ),
                  ],
                );
              },
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
