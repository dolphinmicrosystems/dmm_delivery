import 'package:cloud_firestore/cloud_firestore.dart';

/// Which tab of the Runs screen a run belongs in.
enum RunPhase { upcoming, today, past }

/// Where a run has got to, as the card says it.
enum RunStatus {
  notStarted('Not started'),
  onTheRoad('On the road'),
  done('Done'),

  /// Its day has passed with deliveries still outstanding.
  unfinished('Not finished'),

  /// Its day has passed and nothing was delivered.
  notRun('Not run');

  const RunStatus(this.label);

  final String label;
}

/// One run - one route's deliveries for one day - as the Runs tab lists it.
///
/// Read from the run document alone: the backend keeps its live progress
/// there (`delivered_count`, `started_at`, `last_delivered_at`,
/// `completed_at`, `next_stop`, written by check-deviation on every stop
/// marked delivered - domain/run_progress.py), so a list of runs costs one
/// read per run rather than one per stop.
class RunListing {
  const RunListing({
    required this.id,
    required this.roundKey,
    required this.stopCount,
    this.routeName,
    this.date,
    this.riderId,
    this.estimatedTotal,
    this.deliveredCount = 0,
    this.startedAt,
    this.lastDeliveredAt,
    this.completedAt,
    this.nextStopName,
  });

  final String id;
  final String roundKey;
  final String? routeName;

  /// The delivery date printed on the run sheet, local midnight.
  final DateTime? date;

  /// Who the run was given to at confirm; the Runs tab falls back to the
  /// route's assignment for the day when this is empty.
  final String? riderId;

  final int stopCount;
  final Duration? estimatedTotal;
  final int deliveredCount;
  final DateTime? startedAt;
  final DateTime? lastDeliveredAt;
  final DateTime? completedAt;
  final String? nextStopName;

  double get progress => stopCount == 0 ? 0 : (deliveredCount / stopCount).clamp(0, 1).toDouble();

  /// How long it actually took, first delivery to last, once it is done.
  Duration? get actualDuration =>
      startedAt == null || completedAt == null ? null : completedAt!.difference(startedAt!);

  factory RunListing.fromDoc(DocumentSnapshot<Map<String, dynamic>> doc, {String? routeName}) =>
      RunListing.fromMap(doc.id, doc.data() ?? const {}, routeName: routeName);

  factory RunListing.fromMap(String id, Map<String, dynamic> data, {String? routeName}) {
    final total = (data['estimated_total_s'] as num?)?.toInt();
    final next = data['next_stop'];
    return RunListing(
      id: id,
      roundKey: data['round_key'] as String? ?? '',
      routeName: routeName ?? data['round'] as String?,
      date: parseSheetDate(data['delivery_date'] as String?),
      riderId: data['rider_id'] as String?,
      stopCount: (data['stop_count'] as num?)?.toInt() ?? 0,
      estimatedTotal: total == null ? null : Duration(seconds: total),
      deliveredCount: (data['delivered_count'] as num?)?.toInt() ?? 0,
      startedAt: _time(data['started_at']),
      lastDeliveredAt: _time(data['last_delivered_at']),
      completedAt: _time(data['completed_at']),
      nextStopName: next is Map ? next['customer_name'] as String? : null,
    );
  }

  /// Upcoming, today or past, as of [now].
  ///
  /// A finished run is past whatever its date. Otherwise its date decides: a
  /// run under way with no date is "today". A run whose date has passed stays
  /// past even if it was never finished - that is its status, not its tab.
  RunPhase phase(DateTime now) {
    if (completedAt != null) return RunPhase.past;
    final today = DateTime(now.year, now.month, now.day);
    final day = date;
    if (day == null) return startedAt != null ? RunPhase.today : RunPhase.upcoming;
    if (day.isBefore(today)) return RunPhase.past;
    if (day.isAfter(today)) return RunPhase.upcoming;
    return RunPhase.today;
  }

  RunStatus status(DateTime now) {
    if (completedAt != null) return RunStatus.done;
    if (phase(now) == RunPhase.past) return deliveredCount > 0 ? RunStatus.unfinished : RunStatus.notRun;
    return startedAt != null ? RunStatus.onTheRoad : RunStatus.notStarted;
  }

  /// Soonest first for what is coming, most recent first for what is done.
  static List<RunListing> sorted(Iterable<RunListing> runs, RunPhase phase) {
    final list = runs.toList();
    final far = DateTime(9999);
    list.sort((a, b) {
      final byDate = (a.date ?? far).compareTo(b.date ?? far);
      final ordered = phase == RunPhase.past ? -byDate : byDate;
      return ordered != 0 ? ordered : (a.routeName ?? '').compareTo(b.routeName ?? '');
    });
    return list;
  }

  static DateTime? _time(Object? raw) => raw is Timestamp ? raw.toDate() : (raw is DateTime ? raw : null);
}

/// The run sheet's own date format, "25/09/2026" (day first) - as the parser
/// stores it in `delivery_run.delivery_date`. Null for anything else.
DateTime? parseSheetDate(String? value) {
  final match = RegExp(r'^(\d{1,2})/(\d{1,2})/(\d{4})$').firstMatch(value?.trim() ?? '');
  if (match == null) return null;
  final day = int.parse(match.group(1)!), month = int.parse(match.group(2)!), year = int.parse(match.group(3)!);
  if (month < 1 || month > 12 || day < 1 || day > 31) return null;
  return DateTime(year, month, day);
}
