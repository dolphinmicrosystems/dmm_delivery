import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import '../../state/auth_state.dart';
import '../../theme/app_colors.dart';
import '../../util/app_log.dart';
import '../../widgets/primary_button.dart';
import '../../widgets/stage_progress_bar.dart';
import '../../widgets/surface_card.dart';
import 'run_sheet_review_screen.dart';

/// Watches run_sheet_upload/{uploadId} until the backend reaches a terminal
/// status, then hands off to the review screen.
///
/// Every way this can fail looks identical from the outside - the document
/// simply never reaches `ready_for_review` - so all four are reported rather
/// than left to spin:
///
///   * the stream itself failing (permission-denied, no connectivity),
///   * the Storage trigger never firing, so no document is ever created,
///   * the function stalling or being killed mid-stage, which writes no
///     `error` status because a timeout is not a catchable exception,
///   * the function reporting `error` itself, which was already handled.
///
/// The middle two are indistinguishable from "still working" without a clock,
/// which is why [_stallAfter] exists. It only ever *adds* a message and a way
/// out - nothing is cancelled when it fires, and the stream stays live, so an
/// upload that legitimately finishes at four minutes still navigates.
class RunSheetProgressScreen extends StatefulWidget {
  const RunSheetProgressScreen({super.key, required this.authState, required this.uploadId});

  final AuthState authState;
  final String uploadId;

  @override
  State<RunSheetProgressScreen> createState() => _RunSheetProgressScreenState();
}

class _RunSheetProgressScreenState extends State<RunSheetProgressScreen> {
  /// Longer than any healthy stage, not longer than the whole pipeline:
  /// process-run-sheet-upload's own Cloud Function timeout is 300s, and this
  /// is a hint that something is wrong, never a deadline.
  static const _stallAfter = Duration(seconds: 90);

  bool _navigated = false;
  bool _stalled = false;
  String? _lastStatus;
  Timer? _stallTimer;

  @override
  void initState() {
    super.initState();
    // Started before any document exists: "the trigger never fired" is the
    // failure that leaves this screen emptiest, so it needs the clock most.
    _restartStallTimer();
  }

  @override
  void dispose() {
    _stallTimer?.cancel();
    super.dispose();
  }

  /// Restarted on every status change, so "stalled" means no progress for
  /// [_stallAfter] rather than a slow upload overall - a 100-stop sheet
  /// geocoding for three minutes is healthy as long as the stage keeps moving.
  void _restartStallTimer() {
    _stallTimer?.cancel();
    _stallTimer = Timer(_stallAfter, () {
      if (!mounted) return;
      AppLog.owner('run sheet upload stalled', {
        'uploadId': widget.uploadId,
        'status': _lastStatus ?? '<no document>',
        'stalledAfter': _stallAfter.inSeconds,
      });
      setState(() => _stalled = true);
    });
  }

  void _back() => Navigator.of(context).popUntil((r) => r.isFirst);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.surfaceMuted,
      appBar: AppBar(title: const Text('Processing run sheet')),
      body: StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
        stream: FirebaseFirestore.instance.collection('run_sheet_upload').doc(widget.uploadId).snapshots(),
        builder: (context, snapshot) {
          // Checked before the data, not after: a failed stream carries no
          // document, so reading `snapshot.data` first silently turns every
          // error into a permanent spinner.
          if (snapshot.hasError) {
            AppLog.owner.error(
              'run sheet upload stream failed',
              snapshot.error,
              snapshot.stackTrace,
              {'uploadId': widget.uploadId},
            );
            return _ProgressMessage(
              title: 'Could not follow this upload',
              detail: '${snapshot.error}\n\nThe run sheet may still have been processed - '
                  'check the routes list before uploading it again.',
              isError: true,
              onBack: _back,
            );
          }

          final data = snapshot.data?.data();
          if (data == null) {
            // The document is written by the Storage trigger, not by the app,
            // so its absence is normal for a second or two and a symptom
            // after that.
            return _ProgressMessage(
              title: 'Waiting for the upload to be picked up…',
              detail: _stalled
                  ? 'The file uploaded, but nothing has started processing it. That usually '
                      'means the storage trigger did not fire.'
                  : null,
              showSpinner: true,
              onBack: _stalled ? _back : null,
            );
          }

          final status = data['status'] as String? ?? 'parsing';

          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (!mounted) return;
            if (status != _lastStatus) {
              _lastStatus = status;
              _restartStallTimer();
              if (_stalled) setState(() => _stalled = false);
            }
            if (_navigated) return;
            if (status == 'ready_for_review' || status == 'no_changes') {
              _navigated = true;
              _stallTimer?.cancel();
              Navigator.of(context).pushReplacement(
                MaterialPageRoute(
                  builder: (_) => RunSheetReviewScreen(
                    authState: widget.authState,
                    uploadId: widget.uploadId,
                    data: data,
                  ),
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
                        PrimaryButton(label: 'Back to routes', onPressed: _back),
                      ] else if (_stalled) ...[
                        // Deliberately not phrased as a failure: the stage it
                        // is stuck on may still complete, and the stream is
                        // still listening if it does. What the owner needs is
                        // a way off the screen, not a verdict.
                        const SizedBox(height: 16),
                        const Text(
                          'This is taking longer than usual. It may still finish - leaving this '
                          'screen will not cancel it, and the route will appear in your list.',
                          style: TextStyle(color: AppColors.inkMuted, fontSize: 13),
                        ),
                        const SizedBox(height: 16),
                        PrimaryButton(label: 'Back to routes', onPressed: _back),
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

/// The two states that used to render as a bare, permanent spinner: a stream
/// that failed, and a document that never arrives.
class _ProgressMessage extends StatelessWidget {
  const _ProgressMessage({
    required this.title,
    this.detail,
    this.isError = false,
    this.showSpinner = false,
    this.onBack,
  });

  final String title;
  final String? detail;
  final bool isError;
  final bool showSpinner;

  /// Null while waiting is still normal - an escape hatch offered too early
  /// reads as "this is broken" on an upload that is merely a few seconds in.
  final VoidCallback? onBack;

  @override
  Widget build(BuildContext context) {
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
                if (showSpinner) ...[
                  const Center(child: CircularProgressIndicator()),
                  const SizedBox(height: 20),
                ],
                Text(
                  title,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: isError ? Colors.red : AppColors.ink,
                  ),
                ),
                if (detail != null) ...[
                  const SizedBox(height: 10),
                  Text(
                    detail!,
                    textAlign: TextAlign.center,
                    style: const TextStyle(fontSize: 13, color: AppColors.inkMuted),
                  ),
                ],
                if (onBack != null) ...[
                  const SizedBox(height: 20),
                  PrimaryButton(label: 'Back to routes', onPressed: onBack),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}
