import 'package:flutter/material.dart';

import '../models/run_stop.dart';
import '../theme/app_colors.dart';
import 'route_preview_map.dart';

/// One stop as a card: where it is in the sequence, who it is, and exactly
/// what milk comes off the van there.
///
/// The products are the reason this card exists. A stop rendered as name +
/// address tells a driver standing at the door the one thing they can
/// already see; the quantities are the job. They come straight from the run
/// sheet's product lines, which the parser has always read and the pipeline
/// has always stored on `delivery_stop.items` - this is the first thing to
/// actually show them.
///
/// Presentation only. The review screen wraps it in drag listeners and
/// passes the handle in as `trailing`; nothing about reordering lives here,
/// so the same card can be reused anywhere a stop needs rendering.
class StopCard extends StatelessWidget {
  const StopCard({super.key, required this.stop, required this.position, this.trailing});

  final RunStop stop;

  /// 1-based position in the current sequence - not `stop.seqOrder`, which
  /// is the stored order and goes stale the moment the list is dragged.
  final int position;

  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final instructions = stop.instructions?.trim();

    return Container(
      padding: const EdgeInsets.fromLTRB(12, 12, 6, 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppColors.hairline),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          StopPin(number: position, compact: true),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Text(
                        stop.customerName,
                        style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700),
                      ),
                    ),
                    if (stop.items.isNotEmpty) ...[
                      const SizedBox(width: 8),
                      // The run sheet's own "Sub Totals" quantity for this
                      // stop, so the per-stop count can be checked against
                      // the paper sheet without adding the chips up.
                      Text(
                        '${stop.unitCount} ${stop.unitCount == 1 ? 'unit' : 'units'}',
                        style: const TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          color: AppColors.inkMuted,
                        ),
                      ),
                    ],
                  ],
                ),
                const SizedBox(height: 2),
                Text(stop.address, style: const TextStyle(fontSize: 12, color: AppColors.inkMuted)),
                if (stop.items.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: [for (final item in stop.items) _ItemChip(label: item.label)],
                  ),
                ] else ...[
                  const SizedBox(height: 8),
                  // Called out rather than left blank: a stop with no
                  // products is either a parse failure or a cancelled order,
                  // and both are worth noticing before the run goes out.
                  const Text(
                    'No products listed on the sheet',
                    style: TextStyle(fontSize: 11, fontStyle: FontStyle.italic, color: AppColors.warning),
                  ),
                ],
                if (instructions != null && instructions.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Icon(Icons.sticky_note_2_outlined, size: 13, color: AppColors.inkMuted),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          instructions,
                          style: const TextStyle(
                            fontSize: 11,
                            color: AppColors.inkMuted,
                            fontStyle: FontStyle.italic,
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ],
            ),
          ),
          ?trailing,
        ],
      ),
    );
  }
}

class _ItemChip extends StatelessWidget {
  const _ItemChip({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(color: AppColors.brandSoft, borderRadius: BorderRadius.circular(8)),
      child: Text(
        label,
        style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: AppColors.brandDark),
      ),
    );
  }
}
