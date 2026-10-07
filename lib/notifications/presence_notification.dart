import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

import '../util/app_log.dart';
import 'notification_channels.dart';
import 'push_notifications.dart';

/// The driver's own "You're online" / "You're offline", drawn on their phone
/// the moment they flip the Online switch (DriverPresence). Their owners hear
/// about it separately, from the backend's notify-presence.
///
/// Online stays in the shade (ongoing) for as long as they are online, with a
/// clock counting up, like a delivery app's; going offline replaces it with a
/// dismissable "You're offline".
class PresenceNotification {
  const PresenceNotification._();

  static const _id = 7100;

  static Future<void> show({required bool online}) async {
    if (kIsWeb) return;
    try {
      final plugin = await PushNotifications.instance.plugin();
      const channel = NotificationChannels.status;
      await plugin.show(
        id: _id,
        title: online ? "You're online" : "You're offline",
        body: online
            ? 'Your owner can see you are available. Switch off in the app when you finish.'
            : 'Your owner has been told you are no longer available.',
        notificationDetails: NotificationDetails(
          android: AndroidNotificationDetails(
            channel.id,
            channel.name,
            channelDescription: channel.description,
            importance: Importance.low,
            priority: Priority.low,
            icon: NotificationChannels.icon,
            color: NotificationChannels.brandColor,
            largeIcon: NotificationChannels.largeIcon,
            ongoing: online,
            autoCancel: !online,
            showWhen: true,
            usesChronometer: online,
            timeoutAfter: online ? null : const Duration(minutes: 5).inMilliseconds,
          ),
        ),
      );
    } catch (error, stack) {
      AppLog.auth.error('presence notification failed', error, stack);
    }
  }
}
