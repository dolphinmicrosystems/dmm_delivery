import '../models/route_assignment.dart';
import '../models/run_listing.dart';

/// One card on the driver's Runs tabs: either a run (a confirmed run sheet,
/// given to this driver), or a *booking* - a day the schedule puts them on a
/// route whose run sheet has not been uploaded yet.
class DriverRunCard {
  const DriverRunCard.run(
    RunListing this.run, {
    required this.routeName,
    required this.day,
    this.startTime,
    this.endTime,
  }) : booking = null;

  const DriverRunCard.booking(RouteAssignment this.booking, {required this.routeName, required this.day})
    : run = null,
      startTime = null,
      endTime = null;

  final RunListing? run;
  final RouteAssignment? booking;
  final String routeName;

  /// The local day it is for; null only for a run with no date on its sheet.
  final DateTime? day;

  final String? startTime;
  final String? endTime;

  /// When to start ("HH:MM"): the schedule's for a run's day; a booking
  /// carries its own.
  String? get start => startTime ?? booking?.startTime;

  /// When the owner expects it finished ("HH:MM"), if they set one.
  String? get end => endTime ?? booking?.endTime;
}

/// The driver's Upcoming, Today and Past, from their runs and the business's
/// schedule. Pure, so the tabs are testable without Firestore.
///
///  * **Runs** are the ones the backend has given this driver (`rider_id`),
///    in the tab their date and progress put them in (RunListing.phase).
///  * **Bookings** come from the schedule (RouteAssignment.routesFor): a
///    route they take over from a later date, or a day they cover. They show
///    until the run sheet for that day exists, which then replaces them -
///    so a driver sees "Covering Run 3 on Thu" before the owner uploads it.
///
/// Start times come from the schedule for the run's own day, as on the
/// owner's Runs tab.
class DriverSchedule {
  const DriverSchedule._();

  static Map<RunPhase, List<DriverRunCard>> build({
    required String driverUid,
    required Iterable<RunListing> runs,
    required Iterable<RouteAssignment> assignments,
    required Map<String, String> routeNames,
    required DateTime now,
  }) {
    final byRoute = RouteAssignment.byRoute(assignments);
    final today = _day(now);
    final cards = {for (final phase in RunPhase.values) phase: <DriverRunCard>[]};

    final runDays = <String>{};
    for (final run in runs) {
      final name = routeNames[run.roundKey];
      if (name == null) continue; // a deleted route: nobody will drive it
      final day = run.date;
      if (day != null) runDays.add('${run.roundKey}|${_day(day)}');
      final scheduled = RouteAssignment.activeAt(
        byRoute[run.roundKey] ?? const [],
        DateTime((day ?? now).year, (day ?? now).month, (day ?? now).day, 12),
      );
      cards[run.phase(now)]!.add(
        DriverRunCard.run(
          run,
          routeName: name,
          day: day,
          startTime: scheduled?.startTime,
          endTime: scheduled?.endTime,
        ),
      );
    }

    for (final booking in RouteAssignment.routesFor(driverUid, assignments, now).upcoming) {
      final name = routeNames[booking.roundKey];
      if (name == null) continue;
      final day = _day(booking.effectiveFrom);
      if (runDays.contains('${booking.roundKey}|$day')) continue; // its run sheet is here
      cards[day == today ? RunPhase.today : RunPhase.upcoming]!.add(
        DriverRunCard.booking(booking, routeName: name, day: day),
      );
    }

    final far = DateTime(9999);
    for (final entry in cards.entries) {
      entry.value.sort((a, b) {
        final byDay = (a.day ?? far).compareTo(b.day ?? far);
        final ordered = entry.key == RunPhase.past ? -byDay : byDay;
        if (ordered != 0) return ordered;
        final byStart = (a.start ?? '99:99').compareTo(b.start ?? '99:99');
        return byStart != 0 ? byStart : a.routeName.compareTo(b.routeName);
      });
    }
    return cards;
  }

  /// The routes the driver has now, each with its start time, then those
  /// they take over from a later date - the Routes tab.
  static List<DriverRoute> routes({
    required String driverUid,
    required Iterable<RouteAssignment> assignments,
    required Map<String, String> routeNames,
    required DateTime now,
  }) {
    final byRoute = RouteAssignment.byRoute(assignments);
    final mine = RouteAssignment.routesFor(driverUid, assignments, now);
    return [
      for (final key in mine.current)
        if (routeNames[key] case final name?)
          if (RouteAssignment.activeAt(byRoute[key]!.where((a) => !a.oneDay), now) case final regular)
            DriverRoute(roundKey: key, name: name, startTime: regular?.startTime, endTime: regular?.endTime),
      for (final booking in mine.upcoming)
        if (!booking.oneDay)
          if (routeNames[booking.roundKey] case final name?)
            DriverRoute(
              roundKey: booking.roundKey,
              name: name,
              startTime: booking.startTime,
              endTime: booking.endTime,
              from: _day(booking.effectiveFrom),
            ),
    ]..sort((a, b) => (a.from ?? DateTime(0)).compareTo(b.from ?? DateTime(0)));
  }

  static DateTime _day(DateTime moment) {
    final local = moment.toLocal();
    return DateTime(local.year, local.month, local.day);
  }
}

/// A route the driver has: now, or [from] a later date.
class DriverRoute {
  const DriverRoute({required this.roundKey, required this.name, this.startTime, this.endTime, this.from});

  final String roundKey;
  final String name;
  final String? startTime;
  final String? endTime;
  final DateTime? from;
}
