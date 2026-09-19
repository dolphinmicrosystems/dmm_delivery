import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import '../models/delivery_estimate.dart';
import '../models/driver_invitation.dart';
import '../models/driver_stats.dart';
import '../models/route_assignment.dart';
import '../models/run_time.dart';
import '../state/auth_state.dart';
import '../theme/app_colors.dart';
import 'primary_button.dart';
import 'section_label.dart';

/// What the scheduling sheet came back with - written as one
/// `route_assignments` row by RouteAssigner.
class ScheduleChoice {
  const ScheduleChoice({
    required this.roundKey,
    required this.date,
    required this.oneDay,
    this.driver,
    this.startTime,
  });

  final String roundKey;

  /// Null takes the route off the driver (for that day, or from then on).
  final DriverInvitation? driver;

  /// Local midnight of the chosen day.
  final DateTime date;

  /// "HH:MM", or null to keep the time that applied before.
  final String? startTime;

  final bool oneDay;
}

/// Schedules a run: who drives which route, from (or only on) which day, and
/// at what time - with how long the route takes and when it should finish.
///
/// Opened two ways, and the same sheet either way:
///  * from a route on the Routes tab - the route is fixed, pick the driver;
///  * from a driver's page - the driver is fixed, pick the route.
Future<ScheduleChoice?> showScheduleRunSheet(
  BuildContext context, {
  required AuthState authState,
  String? roundKey,
  String? routeName,
  DriverInvitation? driver,
  RouteAssignment? current,
}) {
  assert(roundKey != null || driver != null, 'Fix the route, the driver, or both');
  return showModalBottomSheet<ScheduleChoice>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (_) => _ScheduleRunSheet(
      authState: authState,
      fixedRoundKey: roundKey,
      fixedRouteName: routeName,
      fixedDriver: driver,
      current: current,
    ),
  );
}

/// How long a route takes, from its latest run's estimate
/// (`delivery_run.estimated_total_s`, road times where the backend had them).
/// Read once per route per app session.
class RouteEstimates {
  RouteEstimates._();

  static final Map<String, Future<Duration?>> _cache = {};

  static Future<Duration?> forRoute(String roundKey) => _cache.putIfAbsent(roundKey, () async {
    final db = FirebaseFirestore.instance;
    final circuit = await db.collection('circuits').doc(roundKey).get();
    final runId = circuit.data()?['latest_run_id'] as String?;
    if (runId == null) return null;
    final run = await db.collection('delivery_run').doc(runId).get();
    final seconds = (run.data()?['estimated_total_s'] as num?)?.toInt();
    return seconds == null ? null : Duration(seconds: seconds);
  });
}

class _ScheduleRunSheet extends StatefulWidget {
  const _ScheduleRunSheet({
    required this.authState,
    this.fixedRoundKey,
    this.fixedRouteName,
    this.fixedDriver,
    this.current,
  });

  final AuthState authState;
  final String? fixedRoundKey;
  final String? fixedRouteName;
  final DriverInvitation? fixedDriver;
  final RouteAssignment? current;

  @override
  State<_ScheduleRunSheet> createState() => _ScheduleRunSheetState();
}

class _ScheduleRunSheetState extends State<_ScheduleRunSheet> {
  late DateTime _date = _today();
  late String? _startTime = widget.current?.startTime;
  bool _oneDay = false;
  String? _roundKey;
  String? _routeName;
  DriverInvitation? _driver;

  @override
  void initState() {
    super.initState();
    _roundKey = widget.fixedRoundKey;
    _routeName = widget.fixedRouteName;
    _driver = widget.fixedDriver;
  }

  static DateTime _today() {
    final now = DateTime.now();
    // Midnight, not now: "from today" has to cover a run confirmed at 5am.
    return DateTime(now.year, now.month, now.day);
  }

  String get _dateLabel {
    final today = _today();
    final weekday = const ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'][_date.weekday - 1];
    final day = '$weekday ${formatShortDate(_date, thisYear: today.year)}';
    if (_date == today) return 'Today, $day';
    if (_date == today.add(const Duration(days: 1))) return 'Tomorrow, $day';
    return day;
  }

  Future<void> _pickDate() async {
    final today = _today();
    final picked = await showDatePicker(
      context: context,
      initialDate: _date,
      firstDate: today,
      lastDate: today.add(const Duration(days: 365)),
    );
    if (picked != null && mounted) setState(() => _date = picked);
  }

  Future<void> _pickTime() async {
    final current = parseStartTime(_startTime);
    final picked = await showTimePicker(
      context: context,
      initialTime: TimeOfDay(hour: current?.hour ?? 5, minute: current?.minute ?? 0),
    );
    if (picked != null && mounted) setState(() => _startTime = encodeStartTime(picked.hour, picked.minute));
  }

  bool get _fixedRoute => widget.fixedRoundKey != null;
  bool get _fixedDriver => widget.fixedDriver != null;
  bool get _ready => _roundKey != null && _driver != null;

  void _submit({bool remove = false}) {
    Navigator.pop(
      context,
      ScheduleChoice(
        roundKey: _roundKey!,
        driver: remove ? null : _driver,
        date: _date,
        startTime: _startTime,
        oneDay: _oneDay,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final currentName = widget.current?.isUnassignment == false ? widget.current?.driverName : null;
    return SafeArea(
      child: Container(
        constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(context).height * 0.9),
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Center(
              child: Container(
                width: 36,
                height: 4,
                decoration: BoxDecoration(color: AppColors.hairline, borderRadius: BorderRadius.circular(999)),
              ),
            ),
            const SizedBox(height: 16),
            Text(
              _fixedDriver ? 'Schedule ${widget.fixedDriver!.displayName}' : 'Schedule ${_routeName ?? 'this route'}',
              style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800, letterSpacing: -0.2),
            ),
            const SizedBox(height: 12),
            // When: day, start time, and whether it repeats.
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: _pickDate,
                    icon: const Icon(Icons.event_rounded, size: 18),
                    label: Text(_dateLabel, overflow: TextOverflow.ellipsis),
                  ),
                ),
                const SizedBox(width: 8),
                OutlinedButton.icon(
                  onPressed: _pickTime,
                  icon: const Icon(Icons.schedule_rounded, size: 18),
                  label: Text(_startTime == null ? 'Start time' : formatStartTime(_startTime!)),
                ),
              ],
            ),
            const SizedBox(height: 8),
            SegmentedButton<bool>(
              segments: const [
                ButtonSegment(value: false, label: Text('Every day from then')),
                ButtonSegment(value: true, label: Text('This day only')),
              ],
              selected: {_oneDay},
              showSelectedIcon: false,
              onSelectionChanged: (value) => setState(() => _oneDay = value.first),
            ),
            const SizedBox(height: 14),
            SectionLabel(_fixedDriver ? 'Route' : 'Driver'),
            const SizedBox(height: 4),
            Flexible(
              child: _fixedDriver
                  ? _RoutePicker(
                      authState: widget.authState,
                      selected: _roundKey,
                      onSelected: (key, name) => setState(() {
                        _roundKey = key;
                        _routeName = name;
                      }),
                    )
                  : _DriverPicker(
                      authState: widget.authState,
                      selected: _driver?.acceptedUid,
                      currentUid: widget.current?.driverUid,
                      onSelected: (driver) => setState(() => _driver = driver),
                    ),
            ),
            if (_roundKey != null) ...[
              const SizedBox(height: 10),
              _ExpectedRun(roundKey: _roundKey!, startTime: _startTime),
            ],
            const SizedBox(height: 12),
            PrimaryButton(
              label: _ready ? 'Schedule' : (_fixedDriver ? 'Choose a route' : 'Choose a driver'),
              icon: Icons.check_rounded,
              onPressed: _ready ? _submit : null,
            ),
            // Taking the route off its current driver, from a route only:
            // from a driver's page the question is what they drive, not who
            // else doesn't.
            if (_fixedRoute && currentName != null)
              TextButton.icon(
                onPressed: () => _submit(remove: true),
                icon: const Icon(Icons.person_remove_outlined, size: 18),
                label: Text(
                  _oneDay ? 'No driver on this day' : 'Remove $currentName from this route',
                  overflow: TextOverflow.ellipsis,
                ),
                style: TextButton.styleFrom(foregroundColor: Colors.red.shade700),
              ),
          ],
        ),
      ),
    );
  }
}

/// "About 2 h 16 min · starting 5:00 am, back around 7:16 am".
class _ExpectedRun extends StatelessWidget {
  const _ExpectedRun({required this.roundKey, required this.startTime});

  final String roundKey;
  final String? startTime;

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<Duration?>(
      future: RouteEstimates.forRoute(roundKey),
      builder: (context, snapshot) {
        final duration = snapshot.data;
        final String text;
        if (snapshot.connectionState != ConnectionState.done) {
          text = 'Working out how long it takes…';
        } else if (duration == null) {
          text = 'No time estimate for this route yet - upload its run sheet to get one.';
        } else {
          final finish = expectedFinish(startTime, duration);
          text = 'Takes about ${DeliveryEstimate.format(duration)}'
              '${finish == null ? '' : ' · starting ${formatStartTime(startTime!)}, back around $finish'}';
        }
        return Row(
          children: [
            const Icon(Icons.timelapse_rounded, size: 18, color: AppColors.brand),
            const SizedBox(width: 8),
            Expanded(child: Text(text, style: const TextStyle(fontSize: 12.5, color: AppColors.inkMuted))),
          ],
        );
      },
    );
  }
}

class _DriverPicker extends StatelessWidget {
  const _DriverPicker({
    required this.authState,
    required this.selected,
    required this.currentUid,
    required this.onSelected,
  });

  final AuthState authState;
  final String? selected;
  final String? currentUid;
  final void Function(DriverInvitation driver) onSelected;

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: authState.invitations(),
      builder: (context, snapshot) {
        if (!snapshot.hasData) {
          return const Padding(padding: EdgeInsets.all(20), child: Center(child: CircularProgressIndicator()));
        }
        final now = DateTime.now();
        // Only drivers who have signed in and still work here: nothing can be
        // assigned to an invitation with no uid, or to a removed driver.
        final drivers = [
          for (final doc in snapshot.data!.docs) DriverInvitation.fromDoc(doc, now: now),
        ].where((d) => d.status == InvitationStatus.accepted).toList()..sort(DriverInvitation.compare);
        if (drivers.isEmpty) {
          return const Padding(
            padding: EdgeInsets.symmetric(vertical: 12),
            child: Text(
              'No drivers have accepted yet. Register one on the Drivers tab; they appear here once they sign in.',
              style: TextStyle(fontSize: 13, color: AppColors.inkMuted, height: 1.4),
            ),
          );
        }
        return RadioGroup<String>(
          groupValue: selected,
          onChanged: (uid) => onSelected(drivers.firstWhere((d) => d.acceptedUid == uid)),
          child: ListView(
          shrinkWrap: true,
          children: [
            for (final driver in drivers)
              RadioListTile<String>(
                contentPadding: EdgeInsets.zero,
                value: driver.acceptedUid!,
                title: Text(driver.displayName, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
                subtitle: Text(
                  driver.acceptedUid == currentUid ? 'Drives this route now' : driver.email,
                  style: const TextStyle(fontSize: 11.5),
                ),
              ),
          ],
          ),
        );
      },
    );
  }
}

class _RoutePicker extends StatelessWidget {
  const _RoutePicker({required this.authState, required this.selected, required this.onSelected});

  final AuthState authState;
  final String? selected;
  final void Function(String roundKey, String name) onSelected;

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: FirebaseFirestore.instance
          .collection('circuits')
          .where('owner_uid', isEqualTo: authState.ownerUid)
          .snapshots(),
      builder: (context, snapshot) {
        if (!snapshot.hasData) {
          return const Padding(padding: EdgeInsets.all(20), child: Center(child: CircularProgressIndicator()));
        }
        final routes = [for (final doc in snapshot.data!.docs) (key: doc.id, name: doc.data()['round'] as String? ?? 'Route')]
          ..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
        if (routes.isEmpty) {
          return const Padding(
            padding: EdgeInsets.symmetric(vertical: 12),
            child: Text(
              'No routes yet. Upload a run sheet on the Routes tab first.',
              style: TextStyle(fontSize: 13, color: AppColors.inkMuted),
            ),
          );
        }
        return RadioGroup<String>(
          groupValue: selected,
          onChanged: (key) => onSelected(key!, routes.firstWhere((r) => r.key == key).name),
          child: ListView(
          shrinkWrap: true,
          children: [
            for (final route in routes)
              RadioListTile<String>(
                contentPadding: EdgeInsets.zero,
                value: route.key,
                title: Text(route.name, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
                subtitle: FutureBuilder<Duration?>(
                  future: RouteEstimates.forRoute(route.key),
                  builder: (context, estimate) => Text(
                    estimate.data == null ? ' ' : 'About ${DeliveryEstimate.format(estimate.data!)}',
                    style: const TextStyle(fontSize: 11.5),
                  ),
                ),
              ),
          ],
          ),
        );
      },
    );
  }
}
