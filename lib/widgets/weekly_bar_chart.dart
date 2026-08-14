import 'package:flutter/material.dart';

import '../theme/app_colors.dart';

/// Mon..Sun payout bars. [heights] are relative magnitudes (any scale); the
/// tallest bar fills [maxHeight] and the rest scale proportionally.
class WeeklyBarChart extends StatelessWidget {
  const WeeklyBarChart({
    super.key,
    required this.heights,
    required this.labels,
    this.highlightedIndex,
    this.maxHeight = 96,
  });

  final List<double> heights;
  final List<String> labels;
  final int? highlightedIndex;
  final double maxHeight;

  @override
  Widget build(BuildContext context) {
    final tallest = heights.reduce((a, b) => a > b ? a : b);
    return SizedBox(
      height: maxHeight + 24,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: List.generate(heights.length, (i) {
          final isHighlighted = i == highlightedIndex;
          final barHeight = (heights[i] / tallest) * maxHeight;
          return Expanded(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 3),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  Container(
                    height: barHeight,
                    decoration: BoxDecoration(
                      color: isHighlighted ? AppColors.brand : AppColors.brandSoft,
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    labels[i],
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: isHighlighted ? AppColors.brand : AppColors.inkMuted,
                    ),
                  ),
                ],
              ),
            ),
          );
        }),
      ),
    );
  }
}
