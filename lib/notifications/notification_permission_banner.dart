import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

import '../theme/app_colors.dart';
import 'push_notifications.dart';

/// A strip across the top of the driver's screens while notifications are
/// off: without them a driver never hears about a new route.
///
/// Notifications are the only permission this needs. Android delivers a
/// push and shows it itself with the app closed - no "run in the background"
/// permission is involved - but from Android 13 only if the person allowed
/// notifications. If they said no, this says so and offers to ask again; once
/// Android stops asking (two refusals), it says where to turn them on.
///
/// It doesn't block the app: a driver with notifications off can still see
/// their runs, and would be stuck if this were a wall.
class NotificationPermissionBanner extends StatefulWidget {
  const NotificationPermissionBanner({super.key});

  @override
  State<NotificationPermissionBanner> createState() => _NotificationPermissionBannerState();
}

class _NotificationPermissionBannerState extends State<NotificationPermissionBanner>
    with WidgetsBindingObserver {
  bool? _allowed;
  bool _askedAgain = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _check();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  // Coming back from Android's settings is how most people fix it.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _check();
  }

  Future<void> _check() async {
    if (kIsWeb) return;
    final settings = await FirebaseMessaging.instance.getNotificationSettings();
    if (mounted) setState(() => _allowed = settings.authorizationStatus != AuthorizationStatus.denied);
  }

  Future<void> _askAgain() async {
    final plugin = await PushNotifications.instance.plugin();
    final granted = await plugin
        .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>()
        ?.requestNotificationsPermission();
    if (!mounted) return;
    setState(() {
      _askedAgain = true;
      _allowed = granted ?? _allowed;
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_allowed != false) return const SizedBox.shrink();
    return Material(
      color: const Color(0x1AE4A83A),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 10, 8, 10),
        child: Row(
          children: [
            const Icon(Icons.notifications_off_outlined, color: AppColors.warning, size: 20),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                _askedAgain
                    ? 'Notifications are still off. Turn them on in Settings > Apps > Blue Dot > Notifications.'
                    : "Notifications are off - you won't hear when you're given a route.",
                style: const TextStyle(fontSize: 12.5, height: 1.35),
              ),
            ),
            if (!_askedAgain) TextButton(onPressed: _askAgain, child: const Text('Turn on')),
          ],
        ),
      ),
    );
  }
}
