import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import '../state/auth_state.dart';
import '../util/app_log.dart';
import 'driving/driving_screen.dart';

/// "Start this route today": asks the backend for today's run of the route
/// and opens the driving screen on it.
///
/// The app can't create a run itself (the rules refuse it), so it writes a
/// request - `run_starts/{id}` - and waits on that document for the
/// start-route-run function's answer: `ready` with the run (today's sheet if
/// the owner uploaded one, else a copy of the route's last sheet) or `refused`
/// with why (not scheduled today, a colleague has it, no sheet ever).
Future<void> startRouteToday(
  BuildContext context, {
  required AuthState authState,
  required String roundKey,
  required String routeName,
  String? vehicle,
}) async {
  final uid = authState.user?.uid, ownerUid = authState.ownerUid;
  if (uid == null || ownerUid == null) return;

  final go = await showDialog<bool>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      title: Text('Start $routeName now?'),
      content: const Text(
        "If today's run sheet hasn't been uploaded, your run uses the stops and quantities from the "
        'last sheet. Check with your owner if today is different.',
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(dialogContext, false), child: const Text('Not yet')),
        FilledButton(onPressed: () => Navigator.pop(dialogContext, true), child: const Text('Start')),
      ],
    ),
  );
  if (go != true || !context.mounted) return;

  final navigator = Navigator.of(context);
  final messenger = ScaffoldMessenger.of(context);
  showDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (_) => const AlertDialog(
      content: Row(
        children: [
          SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2.5)),
          SizedBox(width: 16),
          Expanded(child: Text('Getting your run ready...')),
        ],
      ),
    ),
  );

  Map<String, dynamic>? answer;
  try {
    final request = await FirebaseFirestore.instance.collection('run_starts').add({
      'owner_uid': ownerUid,
      'round_key': roundKey,
      'requested_by': uid,
      'requested_at': FieldValue.serverTimestamp(),
    });
    AppLog.auth('route start requested', {'roundKey': roundKey});
    answer = await request
        .snapshots()
        .map((snap) => snap.data())
        .firstWhere((data) => data?['status'] != null)
        .timeout(const Duration(seconds: 45));
  } on TimeoutException {
    answer = {'status': 'refused', 'reason': 'No answer yet - check your connection and try again.'};
  } catch (error, stack) {
    AppLog.auth.error('route start failed', error, stack);
    answer = {
      'status': 'refused',
      'reason': "Couldn't start the route. Check your connection and try again.",
    };
  }
  navigator.pop(); // the progress dialog

  if (answer?['status'] == 'ready' && answer?['run_id'] is String) {
    navigator.push(
      MaterialPageRoute(
        builder: (_) => DrivingScreen(
          authState: authState,
          runId: answer!['run_id'] as String,
          routeName: routeName,
          vehicle: vehicle,
        ),
      ),
    );
  } else {
    messenger.showSnackBar(
      SnackBar(content: Text(answer?['reason'] as String? ?? "Couldn't start the route.")),
    );
  }
}
