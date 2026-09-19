// Start times and expected finishes for scheduled runs.
//
// A start time is stored as 24-hour "HH:MM" (`route_assignments.start_time`,
// checked by that pattern in firestore.rules) and shown as "5:00 am".

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
