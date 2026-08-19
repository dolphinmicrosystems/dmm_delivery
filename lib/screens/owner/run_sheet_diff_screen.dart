import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import '../../state/auth_state.dart';
import '../../theme/app_colors.dart';
import '../../widgets/pill_badge.dart';
import '../../widgets/primary_button.dart';
import '../../widgets/section_label.dart';
import '../../widgets/surface_card.dart';

/// FR2 (DMM-07): shown after process-run-sheet-upload finishes - what
/// changed since the last upload for this route, in the "optimal and user
/// friendly" summary form the diff structure (process_run_sheet_upload.py's
/// diff_doc) is shaped for.
class RunSheetDiffScreen extends StatelessWidget {
  const RunSheetDiffScreen({super.key, required this.authState, required this.uploadId, required this.data});

  final AuthState authState;
  final String uploadId;
  final Map<String, dynamic> data;

  Map<String, dynamic> get _diff => (data['diff'] as Map<String, dynamic>?) ?? const {};

  Future<void> _respond(BuildContext context, String status) async {
    await FirebaseFirestore.instance.collection('run_sheet_upload').doc(uploadId).update({'status': status});
    if (context.mounted) Navigator.of(context).popUntil((r) => r.isFirst);
  }

  @override
  Widget build(BuildContext context) {
    final noChanges = data['status'] == 'no_changes';
    final added = (_diff['added'] as List?) ?? const [];
    final removed = (_diff['removed'] as List?) ?? const [];
    final contentChanged = (_diff['content_changed'] as List?) ?? const [];
    final unchangedCount = _diff['unchanged_count'] as int? ?? 0;
    final roundMismatch = _diff['round_mismatch'] == true;

    return Scaffold(
      backgroundColor: AppColors.surfaceMuted,
      appBar: AppBar(title: Text(data['round'] as String? ?? 'Review changes')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          SurfaceCard(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                Icon(
                  noChanges ? Icons.check_circle_rounded : Icons.fact_check_rounded,
                  color: noChanges ? AppColors.success : AppColors.brand,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    noChanges
                        ? 'No changes captured - $unchangedCount stops, same order.'
                        : (_diff['route_changed'] == true
                            ? 'Route changed - re-optimized.'
                            : 'Route unchanged - reused existing order. ${contentChanged.length} stop${contentChanged.length == 1 ? '' : 's'} updated.'),
                    style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700),
                  ),
                ),
              ],
            ),
          ),
          if (roundMismatch) ...[
            const SizedBox(height: 12),
            SurfaceCard(
              padding: const EdgeInsets.all(12),
              child: Text(
                'Heads up: this PDF says "${_diff['pdf_round']}", which differs from the route you selected.',
                style: const TextStyle(fontSize: 12, color: AppColors.warning),
              ),
            ),
          ],
          if (added.isNotEmpty) ...[
            const SizedBox(height: 20),
            const SectionLabel('Added'),
            const SizedBox(height: 8),
            for (final stop in added) _DiffRow(stop: stop as Map<String, dynamic>, badge: 'NEW', color: AppColors.success),
          ],
          if (removed.isNotEmpty) ...[
            const SizedBox(height: 20),
            const SectionLabel('Removed'),
            const SizedBox(height: 8),
            for (final stop in removed) _DiffRow(stop: stop as Map<String, dynamic>, badge: 'REMOVED', color: Colors.red),
          ],
          if (contentChanged.isNotEmpty) ...[
            const SizedBox(height: 20),
            const SectionLabel('Updated'),
            const SizedBox(height: 8),
            for (final stop in contentChanged) _DiffRow(stop: stop as Map<String, dynamic>, badge: 'UPDATED', color: AppColors.warning),
          ],
          const SizedBox(height: 32),
          PrimaryButton(label: 'Confirm', icon: Icons.check_rounded, onPressed: () => _respond(context, 'confirmed')),
          const SizedBox(height: 8),
          TextButton(onPressed: () => _respond(context, 'discarded'), child: const Text('Discard')),
        ],
      ),
    );
  }
}

class _DiffRow extends StatelessWidget {
  const _DiffRow({required this.stop, required this.badge, required this.color});

  final Map<String, dynamic> stop;
  final String badge;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: SurfaceCard(
        padding: const EdgeInsets.all(12),
        child: Row(
          children: [
            PillBadge(label: badge, background: color.withValues(alpha: 0.12), foreground: color),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(stop['customer_name'] as String? ?? '', style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
                  Text(stop['address'] as String? ?? '', style: const TextStyle(fontSize: 12, color: AppColors.inkMuted)),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
