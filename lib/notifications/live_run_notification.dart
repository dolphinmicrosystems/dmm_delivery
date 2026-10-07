import 'package:flutter_local_notifications/flutter_local_notifications.dart';

import 'notification_channels.dart';

/// The owner's live notification of a run being driven: "South Runsheet · Ana"
/// / "23 of 60 delivered · Next: Otago Glass", a progress bar, a clock running
/// from the start, and "Back ~7:30 am".
///
/// The backend's notify-run sends it as *data* (`type: run_live`, or
/// `run_live_end` when the run finishes), because only the app can draw a
/// progress bar and a running clock. It is drawn from the foreground listener
/// while the app is open and from the background handler while it is closed.
class LiveRunNotification {
  const LiveRunNotification._();

  /// One id for every live run; the run id is the tag, so each run has its
  /// own notification and each update replaces it in place.
  static const _id = 7001;

  /// Draws (or clears) the notification for a notify-run message. Returns
  /// false for any other message, so the caller can try something else.
  ///
  /// It is ongoing - it stays put while the run is driven, like a delivery
  /// app's - but times out 30 minutes after its last update, so a lost
  /// "finished" can never leave one stuck in the shade.
  static Future<bool> handle(FlutterLocalNotificationsPlugin plugin, Map<String, dynamic> data) async {
    final runId = data['run_id'] as String?;
    if (runId == null) return false;
    switch (data['type']) {
      case 'run_live_end':
        await plugin.cancel(id: _id, tag: runId);
        return true;
      case 'run_live':
        final progress = int.tryParse('${data['progress']}') ?? 0;
        final max = int.tryParse('${data['max']}') ?? 0;
        final startedMs = int.tryParse('${data['started_ms']}') ?? 0;
        final sub = data['sub'] as String? ?? '';
        const channel = NotificationChannels.liveRuns;
        await plugin.show(
          id: _id,
          title: data['title'] as String?,
          body: data['body'] as String?,
          notificationDetails: NotificationDetails(
            android: AndroidNotificationDetails(
              channel.id,
              channel.name,
              channelDescription: channel.description,
              importance: Importance.low,
              priority: Priority.low,
              tag: runId,
              icon: NotificationChannels.icon,
              color: NotificationChannels.brandColor,
              largeIcon: NotificationChannels.largeIcon,
              ongoing: true,
              autoCancel: false,
              onlyAlertOnce: true,
              showProgress: max > 0,
              maxProgress: max,
              progress: progress.clamp(0, max),
              // A clock counting up from the start, ticking on the phone
              // between updates: "1:12:05 on the road".
              usesChronometer: startedMs > 0,
              when: startedMs > 0 ? startedMs : null,
              subText: sub.isEmpty ? null : sub,
              category: AndroidNotificationCategory.progress,
              timeoutAfter: const Duration(minutes: 30).inMilliseconds,
            ),
          ),
        );
        return true;
    }
    return false;
  }
}
