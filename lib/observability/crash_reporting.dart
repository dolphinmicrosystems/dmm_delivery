import 'package:firebase_crashlytics/firebase_crashlytics.dart';
import 'package:flutter/foundation.dart';

/// Crash and error reports from the app, through Firebase Crashlytics.
///
/// Release builds only. AppLog's tracing compiles away in release, so without
/// this a crash on a driver's phone would leave no trace anywhere. Debug
/// builds keep Flutter's own red screens and console, and send nothing, so
/// testing doesn't bury real reports.
///
/// What it sends:
///  * every uncaught error - Flutter's ([FlutterError.onError]) and the rest
///    of Dart's ([PlatformDispatcher.onError]) - as a crash;
///  * every error the app catches and logs with `AppLog.<area>.error(...)`,
///    as a non-fatal report, with the log message as its reason and the
///    log's fields attached;
///  * who it happened to: the account id and role ([identify]) - never an
///    email or a name. Keep personal details out of AppLog error fields for
///    the same reason.
///
/// Reports go to the Firebase project the build is configured for
/// (firebase_options.dart), so dev and production builds report separately.
class CrashReporting {
  const CrashReporting._();

  static bool get _enabled => !kIsWeb && !kDebugMode;

  /// Call once, after Firebase.initializeApp and before runApp.
  static Future<void> start() async {
    if (kIsWeb) return;
    await FirebaseCrashlytics.instance.setCrashlyticsCollectionEnabled(_enabled);
    if (!_enabled) return;
    FlutterError.onError = FirebaseCrashlytics.instance.recordFlutterFatalError;
    PlatformDispatcher.instance.onError = (error, stack) {
      FirebaseCrashlytics.instance.recordError(error, stack, fatal: true);
      return true;
    };
  }

  /// Tags every later report with who was signed in; null clears it.
  static Future<void> identify({required String? uid, required String? role}) async {
    if (!_enabled) return;
    await FirebaseCrashlytics.instance.setUserIdentifier(uid ?? '');
    await FirebaseCrashlytics.instance.setCustomKey('role', role ?? 'signed_out');
  }

  /// A caught error, as a non-fatal report. Never throws.
  static void recordError(String reason, Object? error, StackTrace? stack, Map<String, Object?> fields) {
    if (!_enabled || error == null) return;
    FirebaseCrashlytics.instance
        .recordError(
          error,
          stack,
          reason: reason,
          information: [for (final field in fields.entries) '${field.key}=${field.value}'],
        )
        .catchError((Object _) {});
  }

  /// Whether this build offers "Send a test crash" in the owner's menu: only
  /// one built with `--dart-define=CRASH_TEST=true` (and not in debug, where
  /// nothing is sent). For proving the setup end to end on a real phone.
  static bool get testCrashOffered => _enabled && const bool.fromEnvironment('CRASH_TEST');

  /// Crashes the app on purpose; the report appears in the Firebase console's
  /// Crashlytics page within a few minutes of the app being opened again.
  static void testCrash() => FirebaseCrashlytics.instance.crash();
}
