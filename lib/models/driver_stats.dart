import 'package:cloud_firestore/cloud_firestore.dart';

/// A driver's record: `driver_stats/{ownerUid}_{driverUid}`, written by the
/// backend's learn_from_run.py once per completed run (domain/driver_stats.py).
///
/// One document per driver per business, so a driver's page only ever shows
/// their own runs. Missing entirely until the driver completes a first run.
class DriverStats {
  const DriverStats({
    this.runsCompleted = 0,
    this.daysDriven = 0,
    this.averageDuration,
    this.totalStopsDelivered = 0,
    this.firstRunDate,
    this.lastRunDate,
    this.recentRuns = const [],
  });

  static const empty = DriverStats();

  final int runsCompleted;

  /// Calendar days in New Zealand with at least one completed run.
  final int daysDriven;

  /// First delivery to last, averaged over every run - see
  /// [CompletedRun.duration] for why the depot legs are not in it.
  final Duration? averageDuration;

  final int totalStopsDelivered;
  final DateTime? firstRunDate;
  final DateTime? lastRunDate;

  /// Newest first, the latest 20. The totals above cover every run.
  final List<CompletedRun> recentRuns;

  bool get hasHistory => runsCompleted > 0;

  static String documentId(String ownerUid, String driverUid) => '${ownerUid}_$driverUid';

  factory DriverStats.fromSnapshot(DocumentSnapshot<Map<String, dynamic>> snap) =>
      DriverStats.fromMap(snap.exists ? snap.data() : null);

  factory DriverStats.fromMap(Map<String, dynamic>? data) {
    if (data == null) return empty;
    final average = (data['average_duration_s'] as num?)?.toInt();
    return DriverStats(
      runsCompleted: (data['runs_completed'] as num?)?.toInt() ?? 0,
      daysDriven: (data['days_driven'] as num?)?.toInt() ?? 0,
      averageDuration: average == null ? null : Duration(seconds: average),
      totalStopsDelivered: (data['total_stops_delivered'] as num?)?.toInt() ?? 0,
      firstRunDate: _date(data['first_run_date']),
      lastRunDate: _date(data['last_run_date']),
      recentRuns: [
        for (final run in (data['recent_runs'] as List?) ?? const [])
          if (run is Map) CompletedRun.fromMap(run.cast<String, dynamic>()),
      ],
    );
  }

  static DateTime? _date(Object? raw) => raw is String ? DateTime.tryParse(raw) : null;
}

/// One line of a driver's history.
class CompletedRun {
  const CompletedRun({
    required this.runId,
    required this.date,
    required this.duration,
    required this.stopsDelivered,
    this.routeName,
    this.roundKey,
    this.vehicleName,
  });

  final String runId;
  final DateTime? date;

  /// First stop delivered to last. The drive out from the depot and back is
  /// not included: nothing records when the van leaves yet.
  final Duration duration;

  final int stopsDelivered;
  final String? routeName;
  final String? roundKey;

  /// What they drove that day, if a vehicle was assigned to them at the time.
  final String? vehicleName;

  factory CompletedRun.fromMap(Map<String, dynamic> data) {
    final vehicle = data['vehicle'];
    return CompletedRun(
      runId: data['run_id'] as String? ?? '',
      date: data['date'] is String ? DateTime.tryParse(data['date'] as String) : null,
      duration: Duration(seconds: (data['duration_s'] as num?)?.toInt() ?? 0),
      stopsDelivered: (data['stops_delivered'] as num?)?.toInt() ?? 0,
      routeName: data['round'] as String?,
      roundKey: data['round_key'] as String?,
      vehicleName: vehicle is Map ? vehicle['name'] as String? : null,
    );
  }
}

const _months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];

/// "18 Sep 2026", or "18 Sep" within [thisYear].
String formatShortDate(DateTime date, {int? thisYear}) {
  final dayMonth = '${date.day} ${_months[date.month - 1]}';
  return date.year == thisYear ? dayMonth : '$dayMonth ${date.year}';
}
