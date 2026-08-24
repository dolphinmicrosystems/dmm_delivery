import 'package:flutter/material.dart';

import '../theme/app_colors.dart';

/// Animated stepper over a run_sheet_upload.status value - see
/// process_run_sheet_upload.py for the exact status sequence this mirrors.
class StageProgressBar extends StatelessWidget {
  const StageProgressBar({super.key, required this.status});

  final String status;

  static const _stages = ['parsing', 'geocoding', 'optimizing', 'diffing'];

  /// Both route-reuse statuses occupy the optimizer's slot in the stepper:
  /// they are the same stage of the same pipeline, reached without a routing
  /// call. Only the label below distinguishes them, because only the label
  /// needs to.
  static const _optimizeStageAliases = ['reusing_route', 'merging_route'];

  int get _stageIndex {
    final normalized = _optimizeStageAliases.contains(status) ? 'optimizing' : status;
    final idx = _stages.indexOf(normalized);
    if (idx >= 0) return idx;
    if (const ['ready_for_review', 'no_changes', 'confirmed'].contains(status)) return _stages.length;
    return 0;
  }

  String get _label => switch (status) {
        'parsing' => 'Reading run sheet…',
        'geocoding' => 'Locating addresses…',
        'optimizing' => 'Optimizing route…',
        'reusing_route' => 'Reusing your stop order…',
        'merging_route' => 'Keeping your stop order…',
        'diffing' => 'Comparing with last upload…',
        'ready_for_review' => 'Ready to review',
        'no_changes' => 'No changes captured',
        'error' => 'Something went wrong',
        _ => 'Starting…',
      };

  @override
  Widget build(BuildContext context) {
    final isError = status == 'error';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            for (var i = 0; i < _stages.length; i++) ...[
              Expanded(
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 350),
                  curve: Curves.easeOut,
                  height: 6,
                  decoration: BoxDecoration(
                    color: isError
                        ? (i == 0 ? AppColors.warning : AppColors.hairline)
                        : (i <= _stageIndex ? AppColors.brand : AppColors.hairline),
                    borderRadius: BorderRadius.circular(3),
                  ),
                ),
              ),
              if (i != _stages.length - 1) const SizedBox(width: 6),
            ],
          ],
        ),
        const SizedBox(height: 12),
        AnimatedSwitcher(
          duration: const Duration(milliseconds: 250),
          child: Text(
            _label,
            key: ValueKey(status),
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: isError ? AppColors.warning : AppColors.inkMuted,
            ),
          ),
        ),
      ],
    );
  }
}
