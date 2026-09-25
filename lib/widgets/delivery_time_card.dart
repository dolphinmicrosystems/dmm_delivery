import 'package:flutter/material.dart';

import '../models/delivery_estimate.dart';
import '../theme/app_colors.dart';
import 'surface_card.dart';

/// "About 2 h 40 min" for the whole run, split into driving and time at stops.
///
/// Shared by the review screen, where it re-estimates as stops are dragged,
/// and the confirmed route screen. Says what it is: an estimate, built from
/// distance until drivers have driven the legs, and missing the depot legs
/// when the depot has not been located.
class DeliveryTimeCard extends StatelessWidget {
  const DeliveryTimeCard({
    super.key,
    required this.estimate,
    required this.depotResolved,
    this.inputs = const EstimateInputs(),
  });

  final DeliveryEstimate estimate;
  final bool depotResolved;

  /// What the times were worked out from - so the card can say when they come
  /// from the drivers' own runs rather than from defaults.
  final EstimateInputs inputs;

  @override
  Widget build(BuildContext context) {
    final stops = estimate.arrivalOffsets.length;
    return SurfaceCard(
      padding: const EdgeInsets.all(16),
      child: Row(
        children: [
          const Icon(Icons.schedule_rounded, color: AppColors.brand),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'About ${DeliveryEstimate.format(estimate.total)} to deliver',
                  style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 2),
                Text(
                  '${DeliveryEstimate.format(estimate.drive)} driving · '
                  '${DeliveryEstimate.format(estimate.dwell)} at $stops '
                  '${stops == 1 ? 'stop' : 'stops'}'
                  '${depotResolved ? '' : ' · depot legs not included'}',
                  style: const TextStyle(fontSize: 12, color: AppColors.inkMuted),
                ),
                if (inputs.isLearned) ...[
                  const SizedBox(height: 2),
                  const Text(
                    'Timed from your drivers\' own runs',
                    style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: AppColors.brand),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}
