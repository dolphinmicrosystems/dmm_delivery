import 'package:flutter/foundation.dart';

/// Debug-only structured logging for the auth and owner flows.
///
/// Every line is prefixed with `[BlueDot/<area>]` so a single filter picks
/// out this app's own tracing from the wall of GMS/Firebase noise the
/// platform emits around sign-in:
///
///   adb logcat | grep "BlueDot/"
///
/// Uses [debugPrint] rather than `dart:developer`'s `log`: the latter only
/// travels over the VM service, so it misses a plain `adb logcat` session,
/// while debugPrint lands in logcat as `I/flutter` where it's greppable
/// alongside the native Firebase/GMS lines it usually needs correlating
/// with. debugPrint also rate-limits, so a burst of lines can't drop the
/// tail the way raw `print` would.
///
/// Calls compile away in release builds (`kDebugMode` guard), so these are
/// safe to leave in place rather than adding and stripping them each time
/// something needs tracing.
class AppLog {
  AppLog._();

  /// Auth lifecycle: sign-in attempts, token/claim changes, gate routing.
  static const auth = _Area('auth');

  /// Owner screens: navigation, Firestore streams, run-sheet uploads.
  static const owner = _Area('owner');
}

class _Area {
  const _Area(this.name);

  final String name;

  /// A normal step in a flow. [fields] keeps values greppable and readable
  /// (`key=value`) rather than baked into free-form prose.
  void call(String message, [Map<String, Object?> fields = const {}]) {
    if (!kDebugMode) return;
    debugPrint('[BlueDot/$name] $message${_format(fields)}');
  }

  /// A failure. Same channel, but carries the error/stack so they land in
  /// one place instead of being split across a log line and a red screen.
  void error(String message, Object? error, [StackTrace? stackTrace, Map<String, Object?> fields = const {}]) {
    if (!kDebugMode) return;
    debugPrint('[BlueDot/$name] ERROR $message${_format(fields)} error=$error');
    if (stackTrace != null) debugPrint('[BlueDot/$name] $stackTrace');
  }

  String _format(Map<String, Object?> fields) {
    if (fields.isEmpty) return '';
    return ' ${fields.entries.map((e) => '${e.key}=${e.value}').join(' ')}';
  }
}
