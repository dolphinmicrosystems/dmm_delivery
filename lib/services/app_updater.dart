import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:in_app_update/in_app_update.dart';

import '../models/app_update_step.dart';
import '../util/app_log.dart';

/// Tells people about a new version on Google Play and installs it, without
/// sending them to the Play Store.
///
/// Uses Play's *flexible* in-app update: Play shows its own "Update
/// available" dialog, downloads in the background while the app keeps
/// working, and then a bar here offers "Restart". Nothing restarts on its
/// own - a driver halfway through a run decides when.
///
/// Checks when the app starts and whenever it comes back to the front (at
/// most every [checkEvery]). Only a copy installed from Google Play can
/// update this way; a build installed from a computer just logs that Play
/// won't, and the app carries on.
class AppUpdater extends StatefulWidget {
  const AppUpdater({super.key, required this.messengerKey, required this.child});

  /// The app's ScaffoldMessenger, for the "Update ready" bar: this widget
  /// sits above every screen, so it has no Scaffold of its own to use.
  final GlobalKey<ScaffoldMessengerState> messengerKey;
  final Widget child;

  static const checkEvery = Duration(hours: 1);

  @override
  State<AppUpdater> createState() => _AppUpdaterState();
}

class _AppUpdaterState extends State<AppUpdater> with WidgetsBindingObserver {
  DateTime? _lastCheck;
  bool _asked = false;
  bool _checking = false;
  bool _readyShown = false;
  StreamSubscription<InstallStatus>? _installStatus;

  /// Play only updates Android installs it made, and debug builds aren't.
  static bool get _supported => !kIsWeb && !kDebugMode && defaultTargetPlatform == TargetPlatform.android;

  @override
  void initState() {
    super.initState();
    if (!_supported) return;
    WidgetsBinding.instance.addObserver(this);
    // A download finishing while the app is open arrives here.
    _installStatus = InAppUpdate.installUpdateListener.listen((status) {
      AppLog.update('install status', {'status': status.name});
      if (status == InstallStatus.downloaded) _showReady();
    }, onError: (Object _) {});
    WidgetsBinding.instance.addPostFrameCallback((_) => _check());
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _installStatus?.cancel();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _check();
  }

  Future<void> _check() async {
    final now = DateTime.now();
    if (_checking || (_lastCheck != null && now.difference(_lastCheck!) < AppUpdater.checkEvery)) return;
    _checking = true;
    _lastCheck = now;
    try {
      final info = await InAppUpdate.checkForUpdate();
      final step = AppUpdateStep.decide(
        availability: info.updateAvailability.name,
        installStatus: info.installStatus.name,
        flexibleAllowed: info.flexibleUpdateAllowed,
        alreadyAsked: _asked,
      );
      AppLog.update('checked Play', {
        'availability': info.updateAvailability.name,
        'installStatus': info.installStatus.name,
        'availableVersionCode': info.availableVersionCode,
        'step': step.name,
      });
      switch (step) {
        case AppUpdateStep.none:
          break;
        case AppUpdateStep.install:
          _showReady();
        case AppUpdateStep.download:
          _asked = true;
          // Play's own dialog; returns once the person has answered, and the
          // download carries on in the background (installUpdateListener).
          final result = await InAppUpdate.startFlexibleUpdate();
          AppLog.update('update offered', {'result': result.name});
      }
    } catch (e) {
      // Not from Play (a build installed from a computer), Play Store
      // missing or signed out, no network: nothing to update, nothing for
      // the person to do. Logged, not reported - every non-Play install
      // would otherwise send one.
      AppLog.update('update check unavailable', {'error': e.toString()});
    } finally {
      _checking = false;
    }
  }

  void _showReady() {
    if (_readyShown) return;
    final messenger = widget.messengerKey.currentState;
    if (messenger == null) return;
    _readyShown = true;
    messenger.showSnackBar(
      SnackBar(
        content: const Text('A new version is ready.'),
        // Stays until answered: an update nobody notices is an update
        // nobody installs. Closing it leaves the update for the next start.
        duration: const Duration(days: 1),
        persist: true,
        showCloseIcon: true,
        action: SnackBarAction(
          label: 'Restart',
          onPressed: () {
            AppLog.update('restarting into the update');
            InAppUpdate.completeFlexibleUpdate().catchError((Object e) {
              AppLog.update.error('installing the update failed', e, null, {});
            });
          },
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
