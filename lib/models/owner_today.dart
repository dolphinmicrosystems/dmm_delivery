import 'run_listing.dart';
import 'run_timing.dart';

/// Who drives a run and when, as the owner's screens work it out
/// (OwnerRunData.crewFor): the run's own driver, else the schedule's.
typedef RunCrew = ({String? driver, String? startTime, String? endTime});

/// One run on the owner's Home, with its crew and where it stands.
class TodayRun {
  const TodayRun({required this.run, required this.crew, required this.timing});

  final RunListing run;
  final RunCrew crew;
  final RunTiming timing;

  bool get hasDriver => crew.driver != null;
}

/// The owner's day at a glance, for Home: the numbers on its tiles, the runs
/// that need them now, what is on the road and what is still to come.
///
/// Pure - built from runs the screen already streams - so the counting is
/// tested (test/owner_today_test.dart) rather than living in a build method.
class OwnerToday {
  const OwnerToday({
    required this.runsToday,
    required this.finishedToday,
    required this.stopsToday,
    required this.deliveredToday,
    required this.attention,
    required this.live,
    required this.comingUp,
  });

  /// Today's runs, and how many of them are finished.
  final int runsToday;
  final int finishedToday;

  /// Stops on today's runs, and how many are delivered.
  final int stopsToday;
  final int deliveredToday;

  /// Runs that need the owner now, worst first: no signal or left, late,
  /// late to start, and today's or tomorrow's runs nobody is driving.
  final List<TodayRun> attention;

  /// Today's runs under way, problems first.
  final List<TodayRun> live;

  /// Today's runs not started (and not yet late), then tomorrow's, by start time.
  final List<TodayRun> comingUp;

  static OwnerToday build({
    required Iterable<RunListing> runs,
    required RunCrew Function(RunListing run) crewFor,
    Map<String, DateTime> lastSeen = const {},
    required DateTime now,
  }) {
    final today = DateTime(now.year, now.month, now.day);
    final tomorrow = today.add(const Duration(days: 1));
    bool on(RunListing run, DateTime day) {
      final date = run.date;
      return date != null && DateTime(date.year, date.month, date.day) == day;
    }

    TodayRun row(RunListing run) {
      final crew = crewFor(run);
      return TodayRun(
        run: run,
        crew: crew,
        timing: RunTiming.of(
          run: run,
          startTime: crew.startTime,
          endTime: crew.endTime,
          lastSeen: lastSeen[run.id],
          now: now,
        ),
      );
    }

    final todays = [
      for (final run in runs)
        if (on(run, today)) row(run),
    ];
    final tomorrows = [
      for (final run in runs)
        if (on(run, tomorrow)) row(run),
    ];

    final live = [
      for (final r in todays)
        if (r.run.started != null && r.run.finished == null) r,
    ]..sort(_worstFirst);
    final attention = [
      for (final r in todays)
        if (r.run.finished == null &&
            (r.timing.kind == TimingKind.noSignal ||
                r.timing.kind == TimingKind.left ||
                r.timing.kind == TimingKind.late ||
                r.timing.kind == TimingKind.lateStart ||
                !r.hasDriver))
          r,
      for (final r in tomorrows)
        if (!r.hasDriver) r,
    ]..sort(_worstFirst);
    final comingUp = [
      for (final r in todays)
        if (r.run.started == null && r.run.finished == null && r.timing.kind == TimingKind.notStarted) r,
      ...tomorrows,
    ]..sort(_byStart);

    return OwnerToday(
      runsToday: todays.length,
      finishedToday: todays.where((r) => r.run.finished != null).length,
      stopsToday: todays.fold(0, (sum, r) => sum + r.run.stopCount),
      deliveredToday: todays.fold(0, (sum, r) => sum + r.run.deliveredCount),
      attention: attention,
      live: live,
      comingUp: comingUp,
    );
  }

  /// Worst first, then by route name.
  static int _worstFirst(TodayRun a, TodayRun b) {
    final bySeverity = _severity(b).compareTo(_severity(a));
    return bySeverity != 0 ? bySeverity : (a.run.routeName ?? '').compareTo(b.run.routeName ?? '');
  }

  static int _severity(TodayRun r) => switch (r.timing.kind) {
    TimingKind.noSignal || TimingKind.left => 5,
    TimingKind.lateStart => 4,
    TimingKind.late => 3,
    _ when !r.hasDriver => 2,
    _ => 0,
  };

  /// Earlier days first, then the earlier start; no start time last.
  static int _byStart(TodayRun a, TodayRun b) {
    final byDay = (a.run.date ?? DateTime(9999)).compareTo(b.run.date ?? DateTime(9999));
    if (byDay != 0) return byDay;
    return (a.crew.startTime ?? '99:99').compareTo(b.crew.startTime ?? '99:99');
  }
}
