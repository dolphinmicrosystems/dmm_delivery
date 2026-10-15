import 'package:flutter/material.dart';

import '../models/driver_stats.dart';
import '../models/run_listing.dart';
import '../state/auth_state.dart';
import '../theme/app_colors.dart';
import '../widgets/load_sheet_view.dart';
import '../widgets/surface_card.dart';
import 'driver_data.dart';

/// The driver's Load tab: what to put on the truck, product by product, in
/// place of reading it off the paper run sheet. Today's runs not yet
/// finished - or, before there are any, the next run, so the truck can be
/// loaded the night before. Tick each product as it goes on; report a
/// shortage and the owner hears at once; the owner's extras and take-offs
/// show here as they are made (LoadSheetView).
///
/// A body, not a Scaffold - it is one of the driver shell's tabs.
class DriverLoadScreen extends StatefulWidget {
  const DriverLoadScreen({super.key, required this.authState, required this.data});

  final AuthState authState;
  final DriverData data;

  @override
  State<DriverLoadScreen> createState() => _DriverLoadScreenState();
}

class _DriverLoadScreenState extends State<DriverLoadScreen> {
  String? _runId;

  /// Today's unfinished runs; else the next upcoming one.
  List<RunListing> _runs(DateTime now) {
    final today = [
      for (final run in widget.data.runs)
        if (run.phase(now) == RunPhase.today && run.finished == null) run,
    ]..sort((a, b) => (a.routeName ?? '').compareTo(b.routeName ?? ''));
    if (today.isNotEmpty) return today;
    final upcoming = [
      for (final run in widget.data.runs)
        if (run.phase(now) == RunPhase.upcoming) run,
    ]..sort((a, b) => (a.date ?? DateTime(9999)).compareTo(b.date ?? DateTime(9999)));
    return upcoming.take(1).toList();
  }

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final runs = _runs(now);
    if (runs.isEmpty) {
      return ListView(
        padding: const EdgeInsets.all(16),
        children: const [
          SurfaceCard(
            padding: EdgeInsets.all(16),
            child: Text(
              "Nothing to load yet. When you have a run with a run sheet, what to put on the truck shows "
              "here - and you'll be told if your owner changes it.",
              style: TextStyle(fontSize: 13, color: AppColors.inkMuted, height: 1.4),
            ),
          ),
        ],
      );
    }
    final selected = runs.firstWhere((run) => run.id == _runId, orElse: () => runs.first);
    final names = widget.data.routeNames;
    return LoadSheetView(
      key: ValueKey(selected.id),
      authState: widget.authState,
      runId: selected.id,
      role: LoadRole.driver,
      header: Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (runs.length > 1)
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final run in runs)
                    ChoiceChip(
                      label: Text(names[run.roundKey] ?? run.routeName ?? 'Run'),
                      selected: run.id == selected.id,
                      onSelected: (_) => setState(() => _runId = run.id),
                    ),
                ],
              )
            else
              Text(
                names[selected.roundKey] ?? selected.routeName ?? 'Run',
                style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800),
              ),
            const SizedBox(height: 4),
            Text(
              '${relativeDayLabel(selected.date, now)} · ${selected.stopCount} stops',
              style: const TextStyle(fontSize: 13, color: AppColors.inkMuted, fontWeight: FontWeight.w600),
            ),
          ],
        ),
      ),
    );
  }
}
