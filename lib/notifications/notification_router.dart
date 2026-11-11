import 'dart:convert';

import 'package:flutter/material.dart';

import '../screens/owner/run_detail_screen.dart';
import '../state/auth_state.dart';
import '../util/app_log.dart';

/// Where a tap on a notification goes: an owner tapping anything about a run
/// (the live notification, "Ana delivered: ...", started, finished) lands on
/// that run's live map.
///
/// Taps arrive three ways - a notification this app drew (its `payload`), one
/// Android drew from a push while the app was in the background (the push's
/// data), and either of those starting the app cold - and all three end up in
/// [openFromData]. A tap that arrives before anyone is signed in waits in
/// [_pending] until [attach] is called.
class NotificationRouter {
  const NotificationRouter._();

  /// The app's navigator (`MaterialApp.navigatorKey`).
  static final navigatorKey = GlobalKey<NavigatorState>();

  static AuthState? _authState;
  static Map<String, dynamic>? _pending;

  /// What a drawn notification carries so a tap can find its run.
  static String? payloadFor(Map<String, dynamic> data) {
    final runId = data['run_id'];
    if (runId is! String || runId.isEmpty) return null;
    return jsonEncode({
      'run_id': runId,
      'route_name': data['route_name'] ?? '',
      'driver_name': data['driver_name'] ?? '',
    });
  }

  static void openFromPayload(String? payload) {
    if (payload == null || payload.isEmpty) return;
    try {
      final data = jsonDecode(payload);
      if (data is Map) openFromData(Map<String, dynamic>.from(data));
    } catch (_) {
      // A payload from an older build, or none worth following.
    }
  }

  static void openFromData(Map<String, dynamic> data) {
    if (data['run_id'] is! String) return;
    _pending = data;
    _flush();
  }

  /// Called once someone is signed in (and again on sign-out, with null).
  static void attach(AuthState? authState) {
    _authState = authState;
    // Not during a build (AuthGate calls this from one).
    WidgetsBinding.instance.addPostFrameCallback((_) => _flush());
  }

  static void _flush() {
    final data = _pending, auth = _authState, navigator = navigatorKey.currentState;
    if (data == null || auth == null || navigator == null) return;
    _pending = null;
    // Runs open on the owner's live map; a driver's notifications open the app.
    if (auth.role == AuthRole.driver) return;
    final name = data['route_name'] as String? ?? '';
    final driver = data['driver_name'] as String? ?? '';
    AppLog.owner('notification opened a run', {'runId': data['run_id']});
    navigator.push(
      MaterialPageRoute(
        builder: (_) => RunDetailScreen(
          authState: auth,
          runId: data['run_id'] as String,
          routeName: name.isEmpty ? 'Run' : name,
          driver: driver.isEmpty ? null : driver,
        ),
      ),
    );
  }
}
