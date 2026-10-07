import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

import '../util/app_log.dart';
import 'live_run_notification.dart';
import 'notification_channels.dart';

/// Push notifications: registering this phone, and showing what arrives.
///
/// The backend sends to *people*, not to topics: its notify-* functions look
/// up the phones registered under a person's uid in
/// `user_devices/{uid}/tokens/{token}` and send to each. So this class's job
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
/// The rest of this folder: [NotificationChannels] (the kinds, and the Blue
/// Dot look), [LiveRunNotification] (the owner's live run, sent as data) and
/// PresenceNotification (the driver's own "You're online").
class PushNotifications {
  PushNotifications._();

  static final instance = PushNotifications._();

  final _local = FlutterLocalNotificationsPlugin();
  bool _prepared = false;
  StreamSubscription<String>? _tokenRefresh;
  StreamSubscription<RemoteMessage>? _foreground;
  String? _registeredUid;
  String? _token;

  /// The plugin that draws notifications, initialised with every channel.
  Future<FlutterLocalNotificationsPlugin> plugin() async {
    if (!_prepared) {
      await NotificationChannels.prepare(_local);
      _prepared = true;
    }
    return _local;
  }

  /// Registers this phone for [uid]. Safe to call again for the same user.
  Future<void> register({required String uid, required String? ownerUid, required String role}) async {
    if (kIsWeb || _registeredUid == uid) return;
    _registeredUid = uid;
    try {
      await plugin();

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
    if (await LiveRunNotification.handle(_local, message.data)) return;
    final notification = message.notification;
    if (notification == null) return;
    final channel = NotificationChannels.byId(notification.android?.channelId);
    await _local.show(
      id: message.messageId.hashCode,
      title: notification.title,
      body: notification.body,
      notificationDetails: NotificationDetails(
        android: AndroidNotificationDetails(
          channel.id,
          channel.name,
          channelDescription: channel.description,
          importance: Importance.high,
          priority: Priority.high,
          icon: NotificationChannels.icon,
          color: NotificationChannels.brandColor,
          largeIcon: NotificationChannels.largeIcon,
          styleInformation: BigTextStyleInformation(notification.body ?? ''),
        ),
      ),
    );
  }
}

/// Firebase calls this, in a fresh isolate, for a data message that arrives
/// while the app is in the background or closed. Registered in main().
@pragma('vm:entry-point')
Future<void> pushBackgroundHandler(RemoteMessage message) async {
  final plugin = FlutterLocalNotificationsPlugin();
  await NotificationChannels.prepare(plugin);
  await LiveRunNotification.handle(plugin, message.data);
}
