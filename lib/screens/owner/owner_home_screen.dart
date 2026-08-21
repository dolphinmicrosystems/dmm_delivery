import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import '../../state/auth_state.dart';
import '../../theme/app_colors.dart';
import '../../widgets/primary_button.dart';
import '../../widgets/section_label.dart';
import '../../widgets/surface_card.dart';
import 'route_map_screen.dart';
import 'upload_run_sheet_screen.dart';

/// FR3 (DMM-08-10) lite: the owner's real landing screen, replacing the
/// mock Customer/Rider tabs. One card per circuit ("latest state per
/// route" - see circuits/{roundKey} in dmm-delivery-app), ordered most
/// recently updated first, so the owner never scans a list of dates to
/// remember.
class OwnerHomeScreen extends StatelessWidget {
  const OwnerHomeScreen({super.key, required this.authState});

  final AuthState authState;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.surfaceMuted,
      body: SafeArea(
        child: RefreshIndicator(
          onRefresh: () async {},
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              const SectionLabel('Your routes'),
              const SizedBox(height: 8),
              _CircuitList(authState: authState),
              const SizedBox(height: 24),
              PrimaryButton(
                label: 'New route',
                icon: Icons.add_rounded,
                onPressed: () => _startUpload(context, roundKey: null, roundLabel: null),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _startUpload(BuildContext context, {required String? roundKey, required String? roundLabel}) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => UploadRunSheetScreen(authState: authState, roundKey: roundKey, roundLabel: roundLabel),
      ),
    );
  }
}

class _CircuitList extends StatelessWidget {
  const _CircuitList({required this.authState});

  final AuthState authState;

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: FirebaseFirestore.instance.collection('circuits').orderBy('updated_at', descending: true).snapshots(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: Padding(padding: EdgeInsets.all(24), child: CircularProgressIndicator()));
        }
        final docs = snapshot.data?.docs ?? [];
        if (docs.isEmpty) {
          return const SurfaceCard(
            padding: EdgeInsets.all(16),
            child: Text(
              'No routes yet. Upload your first run sheet to get started.',
              style: TextStyle(color: AppColors.inkMuted, fontSize: 13),
            ),
          );
        }
        return Column(
          children: [
            for (final doc in docs) ...[
              _CircuitCard(roundKey: doc.id, data: doc.data(), authState: authState),
              const SizedBox(height: 12),
            ],
          ],
        );
      },
    );
  }
}

class _CircuitCard extends StatefulWidget {
  const _CircuitCard({required this.roundKey, required this.data, required this.authState});

  final String roundKey;
  final Map<String, dynamic> data;
  final AuthState authState;

  @override
  State<_CircuitCard> createState() => _CircuitCardState();
}

class _CircuitCardState extends State<_CircuitCard> {
  bool _revealDelete = false;

  Future<void> _confirmDelete(BuildContext context, String round) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Delete route?'),
        content: Text('"$round" will be removed from your list. This can\'t be undone.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialogContext, false), child: const Text('Cancel')),
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Delete', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
    if (confirmed != true) {
      if (mounted) setState(() => _revealDelete = false);
      return;
    }
    await FirebaseFirestore.instance.collection('circuits').doc(widget.roundKey).delete();
  }

  @override
  Widget build(BuildContext context) {
    final round = widget.data['round'] as String? ?? 'Unnamed route';
    final stopCount = widget.data['stop_count'] as int? ?? 0;

    return InkWell(
      onTap: () {
        if (_revealDelete) {
          setState(() => _revealDelete = false);
          return;
        }
        Navigator.of(context).push(
          MaterialPageRoute(builder: (_) => RouteMapScreen(authState: widget.authState, roundKey: widget.roundKey)),
        );
      },
      onLongPress: () => setState(() => _revealDelete = true),
      borderRadius: BorderRadius.circular(20),
      child: SurfaceCard(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(color: AppColors.brandSoft, borderRadius: BorderRadius.circular(12)),
              alignment: Alignment.center,
              child: const Icon(Icons.alt_route_rounded, color: AppColors.brand),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(round, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
                  const SizedBox(height: 2),
                  Text('$stopCount stops', style: const TextStyle(fontSize: 12, color: AppColors.inkMuted)),
                ],
              ),
            ),
            if (_revealDelete)
              IconButton(
                onPressed: () => _confirmDelete(context, round),
                icon: const Icon(Icons.delete_outline_rounded, color: Colors.red),
                tooltip: 'Delete route',
              )
            else
              TextButton(
                onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) =>
                        UploadRunSheetScreen(authState: widget.authState, roundKey: widget.roundKey, roundLabel: round),
                  ),
                ),
                child: const Text('Upload sheet'),
              ),
          ],
        ),
      ),
    );
  }
}
