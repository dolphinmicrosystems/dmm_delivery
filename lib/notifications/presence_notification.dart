import 'package:flutter/foundation.dart';

import '../util/app_log.dart';
import 'push_notifications.dart';

/// The driver's own "You're online" from the Online switch, which no longer
/// exists: presence now follows the app being open (DriverPresence). Builds
/// before that left it ongoing in the shade, so it is cleared once.
class PresenceNotification {
  const PresenceNotification._();

  static const _id = 7100;

  static Future<void> clear() async {
    if (kIsWeb) return;
    try {
      final plugin = await PushNotifications.instance.plugin();
      await plugin.cancel(id: _id);
    } catch (error, stack) {
      AppLog.auth.error('presence notification clear failed', error, stack);
    }
  }
}
