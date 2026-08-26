import 'package:cloud_firestore/cloud_firestore.dart';

/// Who drives a route, from when.
///
/// Assignments are append-only and open-ended. Assigning a driver writes a
/// row saying "from this date, this person"; nothing closes it. The driver on
/// a route at any moment is the most recent row that has already taken
/// effect - which is what makes "the owner forgot to reassign" resolve to
/// last week's driver with no mechanism behind it.
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
  });

  final String roundKey;
  final DateTime effectiveFrom;

  /// Null means the route was deliberately taken off everybody. Unassigning
  /// is an assignment, not a deletion - deleting the row would bring the
  /// previous driver back.
  final String? driverUid;
  final String? driverName;

  final DateTime? createdAt;

  bool get isUnassignment => driverUid == null;

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
    );
  }

  /// The assignment in force at [at], or null if none has taken effect.
  ///
  /// Rows dated in the future are ignored rather than being an error - that
  /// is how "Ana takes over on the 15th" is entered on the 1st.
  static RouteAssignment? activeAt(Iterable<RouteAssignment> assignments, DateTime at) {
    RouteAssignment? best;
    for (final assignment in assignments) {
      if (assignment.effectiveFrom.isAfter(at)) continue;
      if (best == null || assignment._outranks(best)) best = assignment;
    }
    return best;
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

  /// What the route card shows under the route's name.
  static String driverLabel(Iterable<RouteAssignment> assignments, DateTime at) {
    final active = activeAt(assignments, at);
    if (active == null) return 'No driver assigned';
    if (active.isUnassignment) return 'No driver assigned';
    return active.driverName ?? 'Assigned';
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
