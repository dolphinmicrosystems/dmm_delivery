import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import '../../state/auth_state.dart';
import '../../theme/app_colors.dart';
import '../../widgets/primary_button.dart';
import '../../widgets/stage_progress_bar.dart';
import '../../widgets/surface_card.dart';
import 'run_sheet_diff_screen.dart';

class RunSheetProgressScreen extends StatefulWidget {
  const RunSheetProgressScreen({super.key, required this.authState, required this.uploadId});

  final AuthState authState;
  final String uploadId;

  @override
  State<RunSheetProgressScreen> createState() => _RunSheetProgressScreenState();
}

class _RunSheetProgressScreenState extends State<RunSheetProgressScreen> {
  bool _navigated = false;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.surfaceMuted,
      appBar: AppBar(title: const Text('Processing run sheet')),
      body: StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
        stream: FirebaseFirestore.instance.collection('run_sheet_upload').doc(widget.uploadId).snapshots(),
        builder: (context, snapshot) {
          final data = snapshot.data?.data();
          if (data == null) {
            return const Center(child: CircularProgressIndicator());
          }

          final status = data['status'] as String? ?? 'parsing';

          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (_navigated || !mounted) return;
            if (status == 'ready_for_review' || status == 'no_changes') {
              _navigated = true;
              Navigator.of(context).pushReplacement(
                MaterialPageRoute(
                  builder: (_) => RunSheetDiffScreen(authState: widget.authState, uploadId: widget.uploadId, data: data),
                ),
              );
            }
          });

          return Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                SurfaceCard(
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      StageProgressBar(status: status),
                      if (status == 'error') ...[
                        const SizedBox(height: 16),
                        Text(
                          data['error_message'] as String? ?? 'Unknown error.',
                          style: const TextStyle(color: Colors.red, fontSize: 13),
                        ),
                        const SizedBox(height: 16),
                        PrimaryButton(label: 'Back to routes', onPressed: () => Navigator.of(context).popUntil((r) => r.isFirst)),
                      ],
                    ],
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}
