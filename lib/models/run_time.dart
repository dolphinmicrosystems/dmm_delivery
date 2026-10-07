// Start times and expected finishes for scheduled runs.
//
// A start time is stored as 24-hour "HH:MM" (`route_assignments.start_time`,
// checked by that pattern in firestore.rules) and shown as "5:00 am".

/// How long to allow at a stop before drivers have taught us the address.
///
/// The backend's `DWELL_SECONDS` is the same 60 s, and `firestore.rules` caps
/// the setting at the range below - the same range a *learned* stop time is
/// clamped to, so a default can't be set to something no measurement could be.
class StopTime {
  const StopTime._();

  static const fallbackSeconds = 60;
  static const minSeconds = 15;
  static const maxSeconds = 900;
  static const presetSeconds = [60, 120, 180, 300];

  static int sanitize(Object? raw) {
    final seconds = (raw as num?)?.toInt();
    if (seconds == null || seconds < minSeconds || seconds > maxSeconds) return fallbackSeconds;
    return seconds;
  }

  /// "1 min", "2 min 30", "45 sec".
  static String label(int seconds) {
    if (seconds < 60) return '$seconds sec';
    final minutes = seconds ~/ 60;
    final rest = seconds % 60;
    return rest == 0 ? '$minutes min' : '$minutes min $rest';
  }
}

/// "05:00" -> (5, 0); null for anything that isn't a valid 24-hour time.
({int hour, int minute})? parseStartTime(String? value) {
  final match = RegExp(r'^([01]\d|2[0-3]):([0-5]\d)$').firstMatch(value ?? '');
  if (match == null) return null;
  return (hour: int.parse(match.group(1)!), minute: int.parse(match.group(2)!));
}

/// (5, 0) -> "05:00", the stored form.
String encodeStartTime(int hour, int minute) =>
    '${hour.toString().padLeft(2, '0')}:${minute.toString().padLeft(2, '0')}';

/// "05:00" -> "5:00 am". Returns the input unchanged if it isn't a valid time.
String formatStartTime(String value) {
  final time = parseStartTime(value);
  return time == null ? value : formatClock(time.hour, time.minute);
}

/// (17, 5) -> "5:05 pm".
String formatClock(int hour, int minute) {
  final h = hour % 12 == 0 ? 12 : hour % 12;
  return '$h:${minute.toString().padLeft(2, '0')} ${hour < 12 ? 'am' : 'pm'}';
}

/// When a run that starts at [startTime] and takes [duration] should be back:
/// "7:16 am", or "7:16 am next day" past midnight.
String? expectedFinish(String? startTime, Duration? duration) {
  final start = parseStartTime(startTime);
  if (start == null || duration == null) return null;
  final total = start.hour * 60 + start.minute + (duration.inSeconds / 60).round();
  final finish = formatClock((total ~/ 60) % 24, total % 60);
  return total >= 24 * 60 ? '$finish next day' : finish;
}

/// "8:00 pm - 10:44 pm" for a start and an end, "8:00 pm" for a start alone,
/// null for neither.
String? formatWindow(String? startTime, String? endTime) {
  if (startTime == null) return null;
  final start = formatStartTime(startTime);
  return endTime == null ? start : '$start - ${formatStartTime(endTime)}';
}

/// The "HH:MM" [duration] after [startTime], wrapping past midnight - the end
/// time the scheduling sheet suggests from the route's estimate.
String? addToStartTime(String? startTime, Duration? duration) {
  final start = parseStartTime(startTime);
  if (start == null || duration == null) return null;
  final total = start.hour * 60 + start.minute + (duration.inSeconds / 60).round();
  return encodeStartTime((total ~/ 60) % 24, total % 60);
}

/// How long the window from [startTime] to [endTime] is (an end at or before
/// the start being the next morning), or null if either is missing.
Duration? windowLength(String? startTime, String? endTime) {
  final start = parseStartTime(startTime), end = parseStartTime(endTime);
  if (start == null || end == null) return null;
  var minutes = (end.hour * 60 + end.minute) - (start.hour * 60 + start.minute);
  if (minutes <= 0) minutes += 24 * 60;
  return Duration(minutes: minutes);
}
