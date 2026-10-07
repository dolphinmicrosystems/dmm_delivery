import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

/// Every kind of Blue Dot notification, and the Blue Dot look they share.
///
/// Each channel is a separate switch in Android's settings for the app, so a
/// driver can silence one kind without silencing the rest. The ids are a
/// contract with the backend (`ports/user_push.py` in dmm-delivery-app) and,
/// for `assignments`, with the manifest's FCM default: rename one side only
/// and Android files the notification under a channel nobody created.
///
/// Adding a kind: a channel here, in [all], and the same id in the backend.
class NotificationChannels {
  const NotificationChannels._();

  /// Drivers: a route given, a day's cover, a new start time, taken off one.
  static const assignments = AndroidNotificationChannel(
    'assignments',
    'Route assignments',
    description: "When you are given a route, a day's cover, or taken off one.",
    importance: Importance.high,
  );

  /// Owners: "Ana started South Runsheet", "Ana finished South Runsheet".
  static const runs = AndroidNotificationChannel(
    'runs',
    'Runs started and finished',
    description: 'When a driver starts or finishes a run.',
    importance: Importance.high,
  );

  /// Owners: the ongoing notification of a run being driven. Low importance:
  /// it is redrawn on every delivery and must never buzz.
  static const liveRuns = AndroidNotificationChannel(
    'live_runs',
    'Live runs',
    description: 'Progress of each run while it is being driven.',
    importance: Importance.low,
    playSound: false,
    enableVibration: false,
  );

  /// Owners: "Ana is online" / "Ana is offline". Also switchable in the app's
  /// own Settings (user_settings.driver_presence_alerts).
  static const drivers = AndroidNotificationChannel(
    'drivers',
    'Drivers online and offline',
    description: 'When one of your drivers goes online or offline.',
    importance: Importance.high,
  );

  /// Drivers: their own "You're online" / "You're offline". Quiet: they just
  /// flipped the switch themselves.
  static const status = AndroidNotificationChannel(
    'status',
    'Your online status',
    description: "Shows while you're online.",
    importance: Importance.low,
    playSound: false,
    enableVibration: false,
  );

  static const all = [assignments, runs, liveRuns, drivers, status];

  /// The channel a pushed notification names, or [assignments] for one that
  /// names none (the manifest's default).
  static AndroidNotificationChannel byId(String? id) =>
      all.firstWhere((channel) => channel.id == id, orElse: () => assignments);

  /// The monochrome dot in the status bar (`res/drawable/ic_stat_bluedot.xml`).
  static const icon = 'ic_stat_bluedot';

  /// The brand blue, also `@color/bluedot_brand` in the manifest.
  static const brandColor = Color(0xFF1A56DB);

  /// The full-colour logo beside the text (`res/drawable-nodpi`).
  static const largeIcon = DrawableResourceAndroidBitmap('bluedot_large');

  /// Initialises [plugin] and creates every channel. Needed once per isolate:
  /// the background message handler runs in its own.
  static Future<void> prepare(FlutterLocalNotificationsPlugin plugin) async {
    await plugin.initialize(settings: const InitializationSettings(android: AndroidInitializationSettings(icon)));
    final android = plugin.resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>();
    for (final channel in all) {
      await android?.createNotificationChannel(channel);
    }
  }
}
