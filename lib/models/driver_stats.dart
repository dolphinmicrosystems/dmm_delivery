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
    this.storedRoutes,
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

  /// `routes` as the backend keeps it - every run ever. Null on a record
  /// written before routes were kept; see [routes].
  final List<RouteRecord>? storedRoutes;

  bool get hasHistory => runsCompleted > 0;

  /// Each route's record, the one driven most first. From the backend's
  /// all-time figures when the record has them, else worked out from
  /// [recentRuns] - the latest 20 - until the driver's next completed run
  /// writes the full ones.
  List<RouteRecord> get routes {
    final routes = storedRoutes ?? RouteRecord.fromRuns(recentRuns);
    return [...routes]..sort((a, b) => b.runs.compareTo(a.runs));
  }

  /// The runs that are their route's best, for a "Best" badge in the history.
  Set<String> get bestRunIds => {for (final route in routes) ?route.bestRunId};

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
      storedRoutes: switch (data['routes']) {
        final Map<Object?, Object?> routes => [
          for (final MapEntry(:key, :value) in routes.entries)
            if (key is String && value is Map) RouteRecord.fromMap(key, value.cast<String, dynamic>()),
        ],
        _ => null,
      },
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
    this.stopsTotal,
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

  /// Every stop the run had; null on runs recorded before it was kept.
  final int? stopsTotal;

  /// Every stop delivered - only such a run can be a route's best.
  bool get isComplete => stopsDelivered >= (stopsTotal ?? stopsDelivered);

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
      stopsTotal: (data['stops_total'] as num?)?.toInt(),
      routeName: data['round'] as String?,
      roundKey: data['round_key'] as String?,
      vehicleName: vehicle is Map ? vehicle['name'] as String? : null,
    );
  }
}

/// One route's record for one driver: how often, how long on average, the
/// last time and the best. `driver_stats.routes.{roundKey}`, written by the
/// backend's domain/driver_stats.py.
///
/// Best is per route - routes differ too much to compare - and only a run
/// with every stop delivered can set it.
class RouteRecord {
  const RouteRecord({
    required this.roundKey,
    required this.routeName,
    required this.runs,
    required this.average,
    this.best,
    this.bestDate,
    this.bestRunId,
    this.last,
    this.lastDate,
  });

  final String roundKey;
  final String routeName;
  final int runs;
  final Duration average;
  final Duration? best;
  final DateTime? bestDate;
  final String? bestRunId;
  final Duration? last;
  final DateTime? lastDate;

  /// How much slower the last run was than the best; null when it was the best.
  Duration? get lastOverBest {
    final last = this.last, best = this.best;
    if (last == null || best == null || last <= best) return null;
    return last - best;
  }

  factory RouteRecord.fromMap(String roundKey, Map<String, dynamic> data) {
    Duration? seconds(String field) =>
        (data[field] as num?) == null ? null : Duration(seconds: (data[field] as num).toInt());
    return RouteRecord(
      roundKey: roundKey,
      routeName: data['round'] as String? ?? 'Route',
      runs: (data['runs'] as num?)?.toInt() ?? 0,
      average: seconds('average_duration_s') ?? Duration.zero,
      best: seconds('best_duration_s'),
      bestDate: DriverStats._date(data['best_date']),
      bestRunId: data['best_run_id'] as String?,
      last: seconds('last_duration_s'),
      lastDate: DriverStats._date(data['last_date']),
    );
  }

  /// The same figures worked out from a run history, newest first - for a
  /// record written before the backend kept them.
  static List<RouteRecord> fromRuns(List<CompletedRun> newestFirst) {
    final byRoute = <String, List<CompletedRun>>{};
    for (final run in newestFirst) {
      final key = run.roundKey ?? run.routeName;
      if (key != null) (byRoute[key] ??= []).add(run);
    }
    return [
      for (final MapEntry(:key, value: runs) in byRoute.entries)
        () {
          final complete = runs.where((run) => run.isComplete);
          final best = complete.isEmpty
              ? null
              : complete.reduce((a, b) => b.duration < a.duration ? b : a);
          final total = runs.fold(Duration.zero, (total, run) => total + run.duration);
          return RouteRecord(
            roundKey: key,
            routeName: runs.first.routeName ?? 'Route',
            runs: runs.length,
            average: Duration(seconds: (total.inSeconds / runs.length).round()),
            best: best?.duration,
            bestDate: best?.date,
            bestRunId: best?.runId,
            last: runs.first.duration,
            lastDate: runs.first.date,
          );
        }(),
    ];
  }
}

const _months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];

/// "18 Sep 2026", or "18 Sep" within [thisYear].
String formatShortDate(DateTime date, {int? thisYear}) {
  final dayMonth = '${date.day} ${_months[date.month - 1]}';
  return date.year == thisYear ? dayMonth : '$dayMonth ${date.year}';
}

/// "Today", "Tomorrow", "Yesterday", else "Thu 8 Oct" - how the Runs tabs
/// (owner's and driver's) name a run's day.
String relativeDayLabel(DateTime? date, DateTime now) {
  if (date == null) return 'No date';
  final today = DateTime(now.year, now.month, now.day);
  final difference = DateTime(date.year, date.month, date.day).difference(today).inDays;
  if (difference == 0) return 'Today';
  if (difference == 1) return 'Tomorrow';
  if (difference == -1) return 'Yesterday';
  final weekday = const ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'][date.weekday - 1];
  return '$weekday ${formatShortDate(date, thisYear: now.year)}';
}
