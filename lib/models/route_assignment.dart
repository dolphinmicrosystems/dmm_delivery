import 'package:cloud_firestore/cloud_firestore.dart';

import 'run_time.dart';

/// Who drives a route, from when.
///
/// Assignments are append-only and open-ended. Assigning a driver writes a
/// row saying "from this date, this person"; nothing closes it. The driver on
/// a route at any moment is the most recent row that has already taken
/// effect - which is what makes "the owner forgot to reassign" resolve to
/// last week's driver with no mechanism behind it.
///
/// **One-day runs** ([oneDay]) apply on their own calendar day only - "Ben
/// covers South on the 25th" - and beat every regular row that day; the next
/// day the regular rows answer again. [startTime] is when the run starts from
/// that row's date; a one-day row without one keeps the regular row's.
///
/// Mirrors `domain/route_assignment.py`. The two are a contract: the backend
/// resolves the same rows the same way when it stamps `delivery_run.rider_id`
/// at confirm time, and a card here that disagreed with the run the driver
/// actually gets would be worse than showing nothing.
class RouteAssignment {
  const RouteAssignment({
    required this.roundKey,
    required this.effectiveFrom,
    this.driverUid,
    this.driverName,
    this.createdAt,
    this.startTime,
    this.oneDay = false,
  });

  final String roundKey;
  final DateTime effectiveFrom;

  /// Null means the route was deliberately taken off everybody. Unassigning
  /// is an assignment, not a deletion - deleting the row would bring the
  /// previous driver back.
  final String? driverUid;
  final String? driverName;

  final DateTime? createdAt;

  /// When the run starts, 24-hour "HH:MM", or null if never set.
  final String? startTime;

  /// Applies on [effectiveFrom]'s day only.
  final bool oneDay;

  bool get isUnassignment => driverUid == null;

  RouteAssignment _withStartTime(String? time) => RouteAssignment(
    roundKey: roundKey,
    effectiveFrom: effectiveFrom,
    driverUid: driverUid,
    driverName: driverName,
    createdAt: createdAt,
    startTime: time,
    oneDay: oneDay,
  );

  factory RouteAssignment.fromDoc(QueryDocumentSnapshot<Map<String, dynamic>> doc) {
    final data = doc.data();
    return RouteAssignment(
      roundKey: data['round_key'] as String? ?? '',
      // Epoch rather than null: a row with no date has never taken effect,
      // and the alternative is a nullable field every caller has to guard.
      effectiveFrom:
          (data['effective_from'] as Timestamp?)?.toDate() ?? DateTime.fromMillisecondsSinceEpoch(0),
      driverUid: data['driver_uid'] as String?,
      driverName: data['driver_name'] as String?,
      createdAt: (data['created_at'] as Timestamp?)?.toDate(),
      startTime: data['start_time'] as String?,
      oneDay: data['one_day'] == true,
    );
  }

  /// The assignment in force at [at], or null if none has taken effect.
  ///
  /// Rows dated in the future are ignored rather than being an error - that
  /// is how "Ana takes over on the 15th" is entered on the 1st.
  static RouteAssignment? activeAt(Iterable<RouteAssignment> assignments, DateTime at) {
    RouteAssignment? regular;
    RouteAssignment? forToday;
    final today = _day(at);
    for (final assignment in assignments) {
      if (assignment.oneDay) {
        if (_day(assignment.effectiveFrom) != today) continue;
        if (forToday == null || _createdLater(assignment, forToday)) forToday = assignment;
        continue;
      }
      if (assignment.effectiveFrom.isAfter(at)) continue;
      if (regular == null || assignment._outranks(regular)) regular = assignment;
    }
    if (forToday == null) return regular;
    return forToday.startTime == null && regular?.startTime != null
        ? forToday._withStartTime(regular!.startTime)
        : forToday;
  }

  /// The local calendar day - the phone is in New Zealand, where the backend
  /// also counts days (`DELIVERY_TZ`).
  static DateTime _day(DateTime moment) {
    final local = moment.toLocal();
    return DateTime(local.year, local.month, local.day);
  }

  static bool _createdLater(RouteAssignment a, RouteAssignment b) {
    final mine = a.createdAt, theirs = b.createdAt;
    if (mine == null) return false;
    if (theirs == null) return true;
    return mine.isAfter(theirs);
  }

  /// Groups a flat list by route, so one query feeds a whole list of cards
  /// rather than one query per card.
  static Map<String, List<RouteAssignment>> byRoute(Iterable<RouteAssignment> assignments) {
    final grouped = <String, List<RouteAssignment>>{};
    for (final assignment in assignments) {
      grouped.putIfAbsent(assignment.roundKey, () => []).add(assignment);
    }
    return grouped;
  }

  /// The routes [driverUid] drives now, and those they are booked onto from a
  /// later date, across every route's assignment history.
  ///
  /// "Now" is each route's row in force at [at]; "upcoming" is a later row
  /// naming this driver that has not started yet. Only a route's *first*
  /// upcoming row counts - a later one would only take effect after whatever
  /// the first one says.
  static ({List<String> current, List<RouteAssignment> upcoming}) routesFor(
    String driverUid,
    Iterable<RouteAssignment> assignments,
    DateTime at,
  ) {
    final current = <String>[];
    final upcoming = <RouteAssignment>[];
    for (final entry in byRoute(assignments).entries) {
      // Their regular routes - a colleague covering one of them today does not
      // take it off their page.
      final regular = activeAt(entry.value.where((a) => !a.oneDay), at);
      if (regular?.driverUid == driverUid) current.add(entry.key);
      final next = entry.value.where((a) => !a.oneDay && a.effectiveFrom.isAfter(at)).toList()
        ..sort((a, b) => a.effectiveFrom.compareTo(b.effectiveFrom));
      if (next.isNotEmpty && next.first.driverUid == driverUid) upcoming.add(next.first);
      // One-day runs from today on: each is its own booking.
      upcoming.addAll(
        entry.value.where(
          (a) => a.oneDay && a.driverUid == driverUid && !_day(a.effectiveFrom).isBefore(_day(at)),
        ),
      );
    }
    upcoming.sort((a, b) => a.effectiveFrom.compareTo(b.effectiveFrom));
    return (current: current, upcoming: upcoming);
  }

  /// What the route card shows under the route's name.
  static String driverLabel(Iterable<RouteAssignment> assignments, DateTime at) {
    final active = activeAt(assignments, at);
    if (active == null || active.isUnassignment) return 'No driver assigned';
    final time = active.startTime == null ? '' : ' · ${formatStartTime(active.startTime!)}';
    return '${active.driverName ?? 'Assigned'}$time';
  }

  /// Later date wins; `created_at` breaks a tie on the same date, because two
  /// assignments made for the same Monday should resolve to whichever the
  /// owner entered second - the correction, not the mistake.
  bool _outranks(RouteAssignment other) {
    if (effectiveFrom != other.effectiveFrom) return effectiveFrom.isAfter(other.effectiveFrom);
    final mine = createdAt, theirs = other.createdAt;
    if (mine == null) return false;
    if (theirs == null) return true;
    return mine.isAfter(theirs);
  }
}
