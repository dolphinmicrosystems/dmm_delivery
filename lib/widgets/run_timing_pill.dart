import 'package:flutter/material.dart';

import '../models/run_timing.dart';
import '../theme/app_colors.dart';
import 'pill_badge.dart';

/// A run against its schedule as a pill: "On time", "12 min late", "No
/// signal since 6:40 am" - the same words for the owner and the driver.
class RunTimingPill extends StatelessWidget {
  const RunTimingPill(this.timing, {super.key});

  final RunTiming timing;

  @override
  Widget build(BuildContext context) {
    final (foreground, background) = colors(timing.kind);
    return PillBadge(label: timing.label, background: background, foreground: foreground);
  }

  /// (text, fill) for each state: red when the app has gone quiet or the
  /// driver left the run, amber when late, green on time.
  static (Color, Color) colors(TimingKind kind) => switch (kind) {
    TimingKind.noSignal || TimingKind.left => (AppColors.danger, const Color(0x1AD64545)),
    TimingKind.late ||
    TimingKind.lateStart ||
    TimingKind.unfinished => (const Color(0xFFB7791F), const Color(0x1AE4A83A)),
    TimingKind.onTime || TimingKind.done => (AppColors.success, const Color(0x1A1FA971)),
    TimingKind.notStarted => (AppColors.inkMuted, AppColors.surfaceMuted),
  };
}
