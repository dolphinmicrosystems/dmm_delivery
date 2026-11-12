import 'package:flutter/material.dart';

import '../models/delivery_estimate.dart';
import '../models/run_summary.dart';
import '../models/run_track.dart';
import '../theme/app_colors.dart';
import 'stat_tile.dart';
import 'surface_card.dart';

/// A finished run in figures, above its map: time, distance, deliveries, and
/// how it went against the estimate - with a key to the two lines on the map
/// (green: the path driven; faded blue: the plan).
///
/// The same card on the driver's run screen (opened straight after "Complete
/// run") and on the owner's.
class RunSummaryCard extends StatelessWidget {
  const RunSummaryCard({super.key, required this.summary});

  final RunSummary summary;

  @override
  Widget build(BuildContext context) {
    final took = summary.took;
    final meters = summary.meters;
    final perStop = summary.perStop;
    final against = summary.againstEstimate;
    final tiles = <(String, String)>[
      (took == null ? '—' : DeliveryEstimate.format(took), 'Time taken'),
      (meters == null ? '—' : formatDistance(meters), 'Driven'),
      ('${summary.delivered}/${summary.total}', 'Delivered'),
      (perStop == null ? '—' : DeliveryEstimate.format(perStop), 'Per stop'),
      if (against != null) (_against(against), 'vs estimate'),
      ('${summary.photos}', summary.photos == 1 ? 'Photo' : 'Photos'),
    ];
    final (headline, tone) = summary.allDelivered
        ? ('Completed · all ${summary.total} delivered', AppColors.success)
        : ('Completed · ${summary.notDelivered} not delivered', AppColors.warning);

    return SurfaceCard(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(summary.allDelivered ? Icons.flag_rounded : Icons.outlined_flag_rounded, color: tone),
              const SizedBox(width: 8),
              Expanded(
                child: Text(headline, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w800)),
              ),
            ],
          ),
          const SizedBox(height: 14),
          // Three a row: six figures fit two short rows on a phone.
          for (var row = 0; row < tiles.length; row += 3) ...[
            if (row > 0) const SizedBox(height: 14),
            Row(
              children: [
                for (var i = row; i < row + 3; i++)
                  Expanded(
                    child: i < tiles.length
                        ? StatTile(value: tiles[i].$1, label: tiles[i].$2)
                        : const SizedBox(),
                  ),
              ],
            ),
          ],
          if (summary.autoDelivered > 0) ...[
            const SizedBox(height: 12),
            Text(
              '${summary.autoDelivered} ${summary.autoDelivered == 1 ? 'stop was' : 'stops were'} marked '
              'delivered automatically after driving away.',
              style: const TextStyle(fontSize: 12, color: AppColors.inkMuted),
            ),
          ],
          const SizedBox(height: 12),
          Row(
            children: [
              const _Key(color: AppColors.success, label: 'Path driven'),
              const SizedBox(width: 16),
              _Key(color: AppColors.brand.withValues(alpha: 0.35), label: 'Planned route'),
            ],
          ),
          if (meters == null)
            const Padding(
              padding: EdgeInsets.only(top: 6),
              child: Text(
                'No path was recorded for this run - it is drawn from runs driven with this '
                'version of the app.',
                style: TextStyle(fontSize: 11.5, color: AppColors.inkMuted),
              ),
            ),
        ],
      ),
    );
  }

  /// "+12 min" over, "-8 min" under, "on time" within a minute.
  static String _against(Duration difference) {
    if (difference.inMinutes.abs() < 1) return 'On time';
    final sign = difference.isNegative ? '−' : '+';
    return '$sign${DeliveryEstimate.format(difference.abs())}';
  }
}

class _Key extends StatelessWidget {
  const _Key({required this.color, required this.label});

  final Color color;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 18,
          height: 4,
          decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(2)),
        ),
        const SizedBox(width: 6),
        Text(label, style: const TextStyle(fontSize: 11.5, color: AppColors.inkMuted)),
      ],
    );
  }
}
