import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

import '../util/app_log.dart';

/// Push notifications: registering this phone, and showing what arrives.
///
/// The backend sends to *people*, not to topics: its notify-assignment
/// function looks up the phones registered under a driver's uid in
/// `user_devices/{uid}/tokens/{token}` and sends to each. So this class's job
/// is to keep that list true for whoever is signed in on this phone:
///
///  * on sign-in, ask permission (Android 13+), and register the token;
///  * when Firebase rotates the token, register the new one;
///  * on sign-out, remove it - a shared depot phone must stop receiving the
///    last driver's notifications the moment they sign out.
///
/// Android shows a push itself while the app is in the background or closed,
/// with the icon, colour and channel the backend sets (and the manifest's
/// defaults). While the app is *open* it does not - Firebase hands the
/// message to the app instead - so [_showInForeground] draws it the same way.
///
/// The one exception is the live run notification (owners only): the backend
/// sends it as data, because only the app can draw a progress bar and a
/// running clock. [drawLiveRun] does that, from [pushBackgroundHandler] when
/// the app is closed and from the foreground listener when it is open.
class PushNotifications {
  PushNotifications._();

  static final instance = PushNotifications._();

  /// Every Blue Dot notification goes through this channel: Android's
  /// per-app setting ("Route assignments") lets a driver silence it without
  /// silencing the app. Its id is what the backend and the manifest name.
  static const channel = AndroidNotificationChannel(
    'assignments',
    'Route assignments',
    description: "When you are given a route, a day's cover, or taken off one.",
    importance: Importance.high,
  );

  /// "Ana started South Runsheet", "Ana finished South Runsheet".
  static const runsChannel = AndroidNotificationChannel(
    'runs',
    'Runs started and finished',
    description: 'When a driver starts or finishes a run.',
    importance: Importance.high,
  );

  /// The ongoing notification of a run being driven. Low importance: it is
  /// redrawn on every delivery and must never buzz.
  static const liveChannel = AndroidNotificationChannel(
    'live_runs',
    'Live runs',
    description: 'Progress of each run while it is being driven.',
    importance: Importance.low,
    playSound: false,
    enableVibration: false,
  );

  static const _channels = {'assignments': channel, 'runs': runsChannel, 'live_runs': liveChannel};

  final _local = FlutterLocalNotificationsPlugin();
  StreamSubscription<String>? _tokenRefresh;
  StreamSubscription<RemoteMessage>? _foreground;
  String? _registeredUid;
  String? _token;

  /// Registers this phone for [uid]. Safe to call again for the same user.
  Future<void> register({required String uid, required String? ownerUid, required String role}) async {
    if (kIsWeb || _registeredUid == uid) return;
    _registeredUid = uid;
    try {
      await _prepare(_local);

      final permission = await FirebaseMessaging.instance.requestPermission();
      AppLog.auth('push permission', {'status': permission.authorizationStatus.name});
      if (permission.authorizationStatus == AuthorizationStatus.denied) return;

      final token = await FirebaseMessaging.instance.getToken();
      if (token != null) await _save(uid, ownerUid, role, token);

      await _tokenRefresh?.cancel();
      _tokenRefresh = FirebaseMessaging.instance.onTokenRefresh.listen((fresh) async {
        final old = _token;
        await _save(uid, ownerUid, role, fresh);
        if (old != null && old != fresh) await _tokenDoc(uid, old).delete();
      });

      await _foreground?.cancel();
      _foreground = FirebaseMessaging.onMessage.listen(_showInForeground);
    } catch (error, stack) {
      // Never let notifications stop someone using the app.
      AppLog.auth.error('push registration failed', error, stack);
    }
  }

  /// Removes this phone from the signed-in user's list. Called before
  /// signing out, while the rules still know who is asking.
  Future<void> unregister() async {
    final uid = _registeredUid, token = _token;
    _registeredUid = null;
    _token = null;
    await _tokenRefresh?.cancel();
    await _foreground?.cancel();
    // A live run belongs to the business, not to this phone: don't leave it
    // in the shade of whoever signs in next.
    await _local.cancelAll();
    if (uid == null || token == null) return;
    try {
      await _tokenDoc(uid, token).delete();
      await FirebaseMessaging.instance.deleteToken();
    } catch (error, stack) {
      AppLog.auth.error('push unregister failed', error, stack);
    }
  }

  static DocumentReference<Map<String, dynamic>> _tokenDoc(String uid, String token) =>
      FirebaseFirestore.instance.collection('user_devices').doc(uid).collection('tokens').doc(token);

  Future<void> _save(String uid, String? ownerUid, String role, String token) async {
    _token = token;
    // The token itself is the document id; it is a credential of sorts, so
    // it is logged by presence only.
    await _tokenDoc(uid, token).set({
      'owner_uid': ownerUid,
      'role': role,
      'platform': defaultTargetPlatform.name,
      'updated_at': FieldValue.serverTimestamp(),
    });
    AppLog.auth('push token registered', {'hasToken': true, 'role': role});
  }

  Future<void> _showInForeground(RemoteMessage message) async {
    if (await drawLiveRun(_local, message.data)) return;
    final notification = message.notification;
    if (notification == null) return;
    final channelFor = _channels[notification.android?.channelId] ?? channel;
    await _local.show(
      id: message.messageId.hashCode,
      title: notification.title,
      body: notification.body,
      notificationDetails: NotificationDetails(
        android: AndroidNotificationDetails(
          channelFor.id,
          channelFor.name,
          channelDescription: channelFor.description,
          importance: Importance.high,
          priority: Priority.high,
          icon: _icon,
          color: _brand,
          largeIcon: const DrawableResourceAndroidBitmap('bluedot_large'),
          styleInformation: BigTextStyleInformation(notification.body ?? ''),
        ),
      ),
    );
  }

  static const _icon = 'ic_stat_bluedot';
  static const _brand = Color(0xFF1A56DB);

  /// One id for every live run; the run id is the tag, so each run has its
  /// own notification and each update replaces it in place.
  static const _liveId = 7001;

  /// Initialises [plugin] and creates the channels. Needed once per isolate:
  /// the background handler runs in its own.
  static Future<void> _prepare(FlutterLocalNotificationsPlugin plugin) async {
    await plugin.initialize(settings: const InitializationSettings(android: AndroidInitializationSettings(_icon)));
    final android = plugin.resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>();
    for (final each in _channels.values) {
      await android?.createNotificationChannel(each);
    }
  }

  /// Draws (or clears) the live run notification from notify-run's data
  /// message. Returns false for any other message.
  ///
  /// It is ongoing - it stays put while the run is driven, like a delivery
  /// app's - but times out 30 minutes after its last update, so a lost
  /// "finished" can never leave one stuck in the shade.
  static Future<bool> drawLiveRun(FlutterLocalNotificationsPlugin plugin, Map<String, dynamic> data) async {
    final runId = data['run_id'] as String?;
    if (runId == null) return false;
    switch (data['type']) {
      case 'run_live_end':
        await plugin.cancel(id: _liveId, tag: runId);
        return true;
      case 'run_live':
        final progress = int.tryParse('${data['progress']}') ?? 0;
        final max = int.tryParse('${data['max']}') ?? 0;
        final startedMs = int.tryParse('${data['started_ms']}') ?? 0;
        final sub = data['sub'] as String? ?? '';
        await plugin.show(
          id: _liveId,
          title: data['title'] as String?,
          body: data['body'] as String?,
          notificationDetails: NotificationDetails(
            android: AndroidNotificationDetails(
              liveChannel.id,
              liveChannel.name,
              channelDescription: liveChannel.description,
              importance: Importance.low,
              priority: Priority.low,
              tag: runId,
              icon: _icon,
              color: _brand,
              largeIcon: const DrawableResourceAndroidBitmap('bluedot_large'),
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

/// Firebase calls this, in a fresh isolate, for a data message that arrives
/// while the app is in the background or closed. Registered in main().
@pragma('vm:entry-point')
Future<void> pushBackgroundHandler(RemoteMessage message) async {
  final plugin = FlutterLocalNotificationsPlugin();
  await PushNotifications._prepare(plugin);
  await PushNotifications.drawLiveRun(plugin, message.data);
}
