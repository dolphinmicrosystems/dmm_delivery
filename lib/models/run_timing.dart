import 'run_listing.dart';
import 'run_time.dart';

/// Where a run stands against its schedule.
enum TimingKind {
  /// Before its start time, or no start time set.
  notStarted,

  /// Its start time is [RunTiming.lateStartAfter] past, and nothing has happened.
  lateStart,

  /// Under way and on course to finish by the expected time.
  onTime,

  /// Under way, but at this pace it finishes after the expected time.
  late,

  /// Under way, but the driver's app hasn't been heard from in
  /// [RunTiming.silentAfter] - closed, out of battery, or out of signal.
  noSignal,

  /// Under way, but the driver tapped "Leave" on the driving screen and
  /// hasn't come back.
  left,

  done,

  /// Its day is over and it wasn't finished.
  unfinished,
}

/// One run against its schedule, as the owner's Home and Runs tab, the
/// driver's Home and the driving screen all say it - so the driver and the
/// owner always see the same answer.
///
///  * The **expected finish** is the owner's finish time for the day, else the
///    start plus the run's estimate.
///  * The **projected finish**, once under way, is now plus the estimate's
///    share for the stops left: rough, but it moves as the driver falls behind
///    or catches up.
///  * **Last heard** is the latest of the driving screen's heartbeat
///    (`run_live.last_seen_at`), the last delivery and the start.
///
/// The thresholds mirror the backend's domain/run_alerts.py, which sends the
/// matching alerts; change both together.
class RunTiming {
  const RunTiming(this.kind, {this.by, this.since, this.expectedFinish, this.projectedFinish});

  static const lateStartAfter = Duration(minutes: 10);
  static const silentAfter = Duration(minutes: 20);

  /// Projected past expected by less than this still reads as on time.
  static const lateMargin = Duration(minutes: 5);

  final TimingKind kind;

  /// How late (a late start, or behind schedule).
  final Duration? by;

  /// When the app was last heard from ([TimingKind.noSignal]), or when the
  /// driver left ([TimingKind.left]).
  final DateTime? since;

  final DateTime? expectedFinish;
  final DateTime? projectedFinish;

  bool get isProblem =>
      kind == TimingKind.lateStart ||
      kind == TimingKind.late ||
      kind == TimingKind.noSignal ||
      kind == TimingKind.left ||
      kind == TimingKind.unfinished;

  /// "On time", "12 min late", "Not started - 15 min late", "No signal since 6:40 am".
  String get label => switch (kind) {
    TimingKind.notStarted => 'Not started',
    TimingKind.lateStart => 'Not started - ${_minutes(by!)} late',
    TimingKind.onTime => 'On time',
    TimingKind.late => '${_minutes(by!)} late',
    TimingKind.noSignal => 'No signal since ${formatClock(since!.hour, since!.minute)}',
    TimingKind.left => 'Left at ${formatClock(since!.hour, since!.minute)}',
    TimingKind.done => by == null ? 'Finished' : 'Finished ${_minutes(by!)} late',
    TimingKind.unfinished => 'Not finished',
  };

  static RunTiming of({
    required RunListing run,
    String? startTime,
    String? endTime,
    DateTime? lastSeen,
    required DateTime now,
  }) {
    final today = DateTime(now.year, now.month, now.day);
    final day = run.date ?? today;
    final start = _at(day, startTime);
    var expected = _at(day, endTime);
    if (start != null && expected != null && !expected.isAfter(start)) {
      expected = expected.add(const Duration(days: 1)); // finishes after midnight
    }
    if (expected == null && start != null && run.estimatedTotal != null) {
      expected = start.add(run.estimatedTotal!);
    }

    final finished = run.finished?.toLocal();
    if (finished != null) {
      final over = expected == null ? null : finished.difference(expected);
      return RunTiming(
        TimingKind.done,
        by: over != null && over > lateMargin ? over : null,
        expectedFinish: expected,
      );
    }
    if (day.isBefore(today)) return RunTiming(TimingKind.unfinished, expectedFinish: expected);

    final started = run.started?.toLocal();
    if (started == null) {
      if (start != null && now.isAfter(start.add(lateStartAfter))) {
        return RunTiming(TimingKind.lateStart, by: now.difference(start), expectedFinish: expected);
      }
      return RunTiming(TimingKind.notStarted, expectedFinish: expected);
    }

    if (run.hasLeft) {
      return RunTiming(TimingKind.left, since: run.driverLeftAt!.toLocal(), expectedFinish: expected);
    }

    final heard = [
      started,
      ?run.lastDeliveredAt?.toLocal(),
      ?lastSeen?.toLocal(),
    ].reduce((a, b) => a.isAfter(b) ? a : b);
    if (now.difference(heard) >= silentAfter) {
      return RunTiming(TimingKind.noSignal, since: heard, expectedFinish: expected);
    }

    final estimate = run.estimatedTotal;
    final total = run.stopCount;
    final projected = estimate == null || total == 0
        ? null
        : now.add(estimate * ((total - run.deliveredCount).clamp(0, total) / total));
    if (expected != null && projected != null && projected.isAfter(expected.add(lateMargin))) {
      return RunTiming(
        TimingKind.late,
        by: projected.difference(expected),
        expectedFinish: expected,
        projectedFinish: projected,
      );
    }
    return RunTiming(TimingKind.onTime, expectedFinish: expected, projectedFinish: projected);
  }

  static DateTime? _at(DateTime day, String? hhmm) {
    final time = parseStartTime(hhmm);
    return time == null ? null : DateTime(day.year, day.month, day.day, time.hour, time.minute);
  }

  static String _minutes(Duration d) {
    final minutes = d.inMinutes;
    return minutes < 60
        ? '$minutes min'
        : '${minutes ~/ 60} h ${(minutes % 60).toString().padLeft(2, '0')} min';
  }
}
