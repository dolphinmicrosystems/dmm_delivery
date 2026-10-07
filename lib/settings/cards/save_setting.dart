import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import '../../services/driver_inviter.dart';
import '../../util/app_log.dart';

/// Runs one settings write, and says so on screen if it fails.
///
/// Every card saves the moment the owner taps - there is no Save button - so a
/// refused write (offline, or the rules rejecting a value) must show up, or
/// the control would quietly snap back with no explanation.
Future<void> saveSetting(BuildContext context, String what, Future<void> Function() write) async {
  final messenger = ScaffoldMessenger.of(context);
  try {
    await write();
  } on FirebaseException catch (error, stack) {
    AppLog.owner.error('$what write failed', error, stack);
    messenger.showSnackBar(SnackBar(content: Text(DriverInviter.errorMessage(error))));
  }
}
