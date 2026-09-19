import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import '../../models/delivery_estimate.dart';
import '../../models/driver_invitation.dart';
import '../../models/driver_stats.dart';
import '../../models/route_assignment.dart';
import '../../models/vehicle.dart';
import '../../models/run_time.dart';
import '../../services/route_assigner.dart';
import '../../services/vehicle_service.dart';
import '../../state/auth_state.dart';
import '../../theme/app_colors.dart';
import '../../util/app_log.dart';
import '../../widgets/pill_badge.dart';
import '../../widgets/section_label.dart';
import '../../widgets/stat_tile.dart';
import '../../widgets/schedule_run_sheet.dart';
import '../../widgets/surface_card.dart';
import 'route_map_screen.dart';

/// One driver: who they are, their driving record, the routes they drive,
/// the vehicle they drive, and their recent runs.
///
/// Everything here is scoped to this one driver - their own `driver_stats`
/// document, the route assignments naming their uid, the vehicle assigned to
/// their uid - so no two drivers' pages ever show each other's data.
///
/// Opened by tapping a driver on the Drivers tab.
class DriverDetailScreen extends StatelessWidget {
  const DriverDetailScreen({super.key, required this.authState, required this.invitation});

  final AuthState authState;
  final DriverInvitation invitation;

  @override
  Widget build(BuildContext context) {
    final uid = invitation.acceptedUid;
    final ownerUid = authState.ownerUid;
    return Scaffold(
      backgroundColor: AppColors.surfaceMuted,
      appBar: AppBar(title: Text(invitation.displayName, overflow: TextOverflow.ellipsis)),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
        children: [
          _Header(invitation: invitation),
          const SizedBox(height: 20),
          if (uid == null || ownerUid == null)
            // No uid means they have never signed in: nothing has been
            // driven, nothing can be assigned to them, and there is no record
            // to read. Saying so beats four empty sections.
            const SurfaceCard(
              padding: EdgeInsets.all(16),
              child: Text(
                'They haven\'t signed in yet. Their driving record, routes and vehicle '
                'appear here once they accept the invitation.',
                style: TextStyle(fontSize: 13, color: AppColors.inkMuted, height: 1.4),
              ),
            )
          else ...[
            _Record(ownerUid: ownerUid, driverUid: uid),
            const SizedBox(height: 20),
            _Schedule(authState: authState, driver: invitation),
            const SizedBox(height: 20),
            const SectionLabel('Vehicle'),
            const SizedBox(height: 8),
            _VehicleCard(ownerUid: ownerUid, driverUid: uid, driverName: invitation.displayName),
          ],
        ],
      ),
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({required this.invitation});

  final DriverInvitation invitation;

  @override
  Widget build(BuildContext context) {
    final name = invitation.displayName;
    final initials = name.trim().split(RegExp(r'\s+')).take(2).map((w) => w.isEmpty ? '' : w[0]).join().toUpperCase();
    final accepted = invitation.acceptedAt;
    return SurfaceCard(
      padding: const EdgeInsets.all(16),
      child: Row(
        children: [
          CircleAvatar(
            radius: 26,
            backgroundColor: AppColors.brandSoft,
            child: Text(
              initials.isEmpty ? '?' : initials,
              style: const TextStyle(fontWeight: FontWeight.w800, color: AppColors.brand),
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(name, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800)),
                const SizedBox(height: 2),
                Text(invitation.email, style: const TextStyle(fontSize: 12.5, color: AppColors.inkMuted)),
                const SizedBox(height: 6),
                Row(
                  children: [
                    PillBadge(label: invitation.statusLabel),
                    if (accepted != null) ...[
                      const SizedBox(width: 8),
                      Text(
                        'Joined ${formatShortDate(accepted.toLocal(), thisYear: DateTime.now().year)}',
                        style: const TextStyle(fontSize: 11.5, color: AppColors.inkMuted),
                      ),
                    ],
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Days driven, runs, average time and stops - and the recent runs behind them.
class _Record extends StatelessWidget {
  const _Record({required this.ownerUid, required this.driverUid});

  final String ownerUid;
  final String driverUid;

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      stream: FirebaseFirestore.instance
          .collection('driver_stats')
          .doc(DriverStats.documentId(ownerUid, driverUid))
          .snapshots(),
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          AppLog.owner.error('driver stats stream failed', snapshot.error, snapshot.stackTrace);
        }
        final stats = snapshot.hasData ? DriverStats.fromSnapshot(snapshot.data!) : DriverStats.empty;
        final year = DateTime.now().year;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const SectionLabel('Driving record'),
            const SizedBox(height: 8),
            SurfaceCard(
              padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 8),
              child: Column(
                children: [
                  Row(
                    children: [
                      Expanded(child: StatTile(value: '${stats.daysDriven}', label: 'Days driven')),
                      Expanded(child: StatTile(value: '${stats.runsCompleted}', label: 'Runs')),
                    ],
                  ),
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      Expanded(
                        child: StatTile(
                          value: stats.averageDuration == null ? '—' : DeliveryEstimate.format(stats.averageDuration!),
                          label: 'Avg run time',
                        ),
                      ),
                      Expanded(child: StatTile(value: '${stats.totalStopsDelivered}', label: 'Stops delivered')),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    child: Text(
                      stats.hasHistory
                          ? 'Driving since ${formatShortDate(stats.firstRunDate!, thisYear: year)} · last run '
                                '${formatShortDate(stats.lastRunDate!, thisYear: year)}. Run time is from the '
                                'first stop delivered to the last.'
                          : 'No completed runs yet. The record starts once a run they drive is fully delivered.',
                      textAlign: TextAlign.center,
                      style: const TextStyle(fontSize: 11.5, color: AppColors.inkMuted, height: 1.4),
                    ),
                  ),
                ],
              ),
            ),
            if (stats.recentRuns.isNotEmpty) ...[
              const SizedBox(height: 20),
              const SectionLabel('Recent runs'),
              const SizedBox(height: 8),
              SurfaceCard(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Column(
                  children: [
                    for (final (i, run) in stats.recentRuns.indexed) ...[
                      if (i > 0) const Divider(height: 1, indent: 16, endIndent: 16, color: AppColors.hairline),
                      _RunRow(run: run, thisYear: year),
                    ],
                  ],
                ),
              ),
            ],
          ],
        );
      },
    );
  }
}

class _RunRow extends StatelessWidget {
  const _RunRow({required this.run, required this.thisYear});

  final CompletedRun run;
  final int thisYear;

  @override
  Widget build(BuildContext context) {
    final details = [
      '${run.stopsDelivered} stops',
      DeliveryEstimate.format(run.duration),
      if (run.vehicleName != null) run.vehicleName!,
    ].join(' · ');
    return ListTile(
      dense: true,
      leading: const Icon(Icons.check_circle_outline_rounded, color: AppColors.success),
      title: Text(
        '${run.date == null ? 'Unknown date' : formatShortDate(run.date!, thisYear: thisYear)} · '
        '${run.routeName ?? 'Route'}',
        style: const TextStyle(fontWeight: FontWeight.w600),
      ),
      subtitle: Text(details),
    );
  }
}

/// What this driver drives and when: their regular routes, runs booked for
/// later (one-day runs and future hand-overs), and days a colleague covers one
/// of their routes - with a button to schedule another run.
class _Schedule extends StatelessWidget {
  const _Schedule({required this.authState, required this.driver});

  final AuthState authState;
  final DriverInvitation driver;

  Future<void> _schedule(BuildContext context) async {
    final ownerUid = authState.ownerUid;
    if (ownerUid == null) return;
    final choice = await showScheduleRunSheet(context, authState: authState, driver: driver);
    if (choice == null || !context.mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    try {
      await RouteAssigner.assign(
        ownerUid: ownerUid,
        roundKey: choice.roundKey,
        effectiveFrom: choice.date,
        driver: choice.driver,
        startTime: choice.startTime,
        oneDay: choice.oneDay,
      );
    } on FirebaseException catch (error, stack) {
      AppLog.owner.error('schedule run failed', error, stack);
      messenger.showSnackBar(SnackBar(content: Text(RouteAssigner.errorMessage(error))));
    }
  }

  @override
  Widget build(BuildContext context) {
    final driverUid = driver.acceptedUid!;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            const Expanded(child: SectionLabel('Schedule')),
            TextButton.icon(
              onPressed: () => _schedule(context),
              icon: const Icon(Icons.add_rounded, size: 18),
              label: const Text('Schedule a run'),
            ),
          ],
        ),
        StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
          stream: authState.routeAssignments(),
          builder: (context, assignmentsSnap) {
            return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
              stream: FirebaseFirestore.instance
                  .collection('circuits')
                  .where('owner_uid', isEqualTo: authState.ownerUid)
                  .snapshots(),
              builder: (context, circuitsSnap) {
                if (!assignmentsSnap.hasData || !circuitsSnap.hasData) {
                  return const SurfaceCard(
                    padding: EdgeInsets.all(16),
                    child: Center(child: CircularProgressIndicator()),
                  );
                }
                // Only routes that still exist: an assignment to a deleted
                // route is history, not work.
                final names = {
                  for (final doc in circuitsSnap.data!.docs) doc.id: doc.data()['round'] as String? ?? 'Route',
                };
                final all = [for (final doc in assignmentsSnap.data!.docs) RouteAssignment.fromDoc(doc)]
                    .where((a) => names.containsKey(a.roundKey))
                    .toList();
                final now = DateTime.now();
                final today = DateTime(now.year, now.month, now.day);
                final byRoute = RouteAssignment.byRoute(all);
                final routes = RouteAssignment.routesFor(driverUid, all, now);

                // Their regular routes, with the start time in force.
                final regular = [
                  for (final key in routes.current)
                    (key: key, row: RouteAssignment.activeAt(byRoute[key]!.where((a) => !a.oneDay), now)!),
                ];
                // Days a colleague is booked onto one of their regular routes.
                final covered = [
                  for (final entry in regular)
                    for (final a in byRoute[entry.key]!)
                      if (a.oneDay && a.driverUid != driverUid && !a.effectiveFrom.isBefore(today)) a,
                ]..sort((a, b) => a.effectiveFrom.compareTo(b.effectiveFrom));

                if (regular.isEmpty && routes.upcoming.isEmpty) {
                  return const SurfaceCard(
                    padding: EdgeInsets.all(16),
                    child: Text(
                      'Nothing scheduled. Use "Schedule a run" to give them a route - every day, or just one day.',
                      style: TextStyle(fontSize: 13, color: AppColors.inkMuted, height: 1.4),
                    ),
                  );
                }
                return SurfaceCard(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  child: Column(
                    children: [
                      for (final entry in regular)
                        _ScheduleRow(
                          icon: Icons.alt_route_rounded,
                          title: names[entry.key]!,
                          when: 'Every day${_at(entry.row.startTime)}',
                          roundKey: entry.key,
                          startTime: entry.row.startTime,
                          onTap: () => Navigator.of(context).push(
                            MaterialPageRoute(
                              builder: (_) => RouteMapScreen(authState: authState, roundKey: entry.key),
                            ),
                          ),
                        ),
                      for (final booking in routes.upcoming)
                        _ScheduleRow(
                          icon: booking.oneDay ? Icons.event_available_rounded : Icons.event_repeat_rounded,
                          title: names[booking.roundKey]!,
                          when: booking.oneDay
                              ? '${_day(booking.effectiveFrom)}${_at(booking.startTime)} · this day only'
                              : 'Every day from ${_day(booking.effectiveFrom)}${_at(booking.startTime)}',
                          roundKey: booking.roundKey,
                          startTime: booking.startTime,
                        ),
                      for (final cover in covered)
                        _ScheduleRow(
                          icon: Icons.swap_horiz_rounded,
                          title: names[cover.roundKey]!,
                          when: cover.isUnassignment
                              ? '${_day(cover.effectiveFrom)} · no driver that day'
                              : '${_day(cover.effectiveFrom)} · covered by ${cover.driverName ?? 'another driver'}',
                          muted: true,
                        ),
                    ],
                  ),
                );
              },
            );
          },
        ),
      ],
    );
  }

  static String _at(String? startTime) => startTime == null ? '' : ' at ${formatStartTime(startTime)}';

  static String _day(DateTime date) {
    final weekday = const ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'][date.weekday - 1];
    return '$weekday ${formatShortDate(date, thisYear: DateTime.now().year)}';
  }
}

class _ScheduleRow extends StatelessWidget {
  const _ScheduleRow({
    required this.icon,
    required this.title,
    required this.when,
    this.roundKey,
    this.startTime,
    this.onTap,
    this.muted = false,
  });

  final IconData icon;
  final String title;
  final String when;

  /// For the expected run time; null for rows that aren't this driver's run.
  final String? roundKey;
  final String? startTime;
  final VoidCallback? onTap;
  final bool muted;

  @override
  Widget build(BuildContext context) {
    final key = roundKey;
    return ListTile(
      onTap: onTap,
      leading: Icon(icon, color: muted ? AppColors.inkMuted : AppColors.brand),
      title: Text(title, style: const TextStyle(fontWeight: FontWeight.w600)),
      subtitle: key == null
          ? Text(when)
          : FutureBuilder<Duration?>(
              future: RouteEstimates.forRoute(key),
              builder: (context, snapshot) {
                final duration = snapshot.data;
                final finish = expectedFinish(startTime, duration);
                final length = duration == null ? '' : ' · about ${DeliveryEstimate.format(duration)}';
                return Text('$when$length${finish == null ? '' : ', back ~$finish'}');
              },
            ),
      trailing: onTap == null ? null : const Icon(Icons.chevron_right_rounded),
    );
  }
}

/// The vehicle this driver drives, with Change / Remove, or Assign.
class _VehicleCard extends StatelessWidget {
  const _VehicleCard({required this.ownerUid, required this.driverUid, required this.driverName});

  final String ownerUid;
  final String driverUid;
  final String driverName;

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<Vehicle>>(
      stream: VehicleService.fleet(ownerUid),
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          AppLog.owner.error('vehicles stream failed', snapshot.error, snapshot.stackTrace);
        }
        final fleet = snapshot.data ?? const <Vehicle>[];
        final mine = fleet.where((v) => v.assignedDriverUid == driverUid).firstOrNull;
        return SurfaceCard(
          padding: const EdgeInsets.fromLTRB(16, 12, 8, 12),
          child: Row(
            children: [
              Icon(
                mine == null ? Icons.no_crash_outlined : _icon(mine.kind),
                color: mine == null ? AppColors.inkMuted : AppColors.brand,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      mine == null ? 'Not driving a vehicle' : mine.description,
                      style: const TextStyle(fontWeight: FontWeight.w700),
                    ),
                    if (mine != null)
                      Text(mine.kind.label, style: const TextStyle(fontSize: 12, color: AppColors.inkMuted)),
                  ],
                ),
              ),
              if (mine != null)
                IconButton(
                  tooltip: 'Take the vehicle off $driverName',
                  icon: const Icon(Icons.close_rounded, color: AppColors.inkMuted),
                  onPressed: () => _guard(context, () => VehicleService.unassign(mine)),
                ),
              TextButton(
                onPressed: () => _pick(context, fleet),
                child: Text(mine == null ? 'Assign' : 'Change'),
              ),
            ],
          ),
        );
      },
    );
  }

  Future<void> _pick(BuildContext context, List<Vehicle> fleet) async {
    final choice = await showModalBottomSheet<_VehicleChoice>(
      context: context,
      isScrollControlled: true,
      builder: (_) => _VehiclePicker(fleet: fleet, driverUid: driverUid),
    );
    if (choice == null || !context.mounted) return;
    if (choice.vehicle != null) {
      await _guard(context, () => VehicleService.assign(choice.vehicle!, driverUid, fleet));
      return;
    }
    final added = await showDialog<_NewVehicle>(context: context, builder: (_) => const _AddVehicleDialog());
    if (added == null || !context.mounted) return;
    await _guard(
      context,
      () => VehicleService.add(
        ownerUid: ownerUid,
        name: added.name,
        kind: added.kind,
        registration: added.registration,
        driverUid: driverUid,
        fleet: fleet,
      ),
    );
  }

  Future<void> _guard(BuildContext context, Future<void> Function() write) async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      await write();
    } on FirebaseException catch (error, stack) {
      AppLog.owner.error('vehicle write failed', error, stack);
      messenger.showSnackBar(SnackBar(content: Text(VehicleService.errorMessage(error))));
    }
  }
}

IconData _icon(VehicleKind kind) => switch (kind) {
  VehicleKind.truck => Icons.local_shipping_rounded,
  VehicleKind.van => Icons.airport_shuttle_rounded,
  VehicleKind.ute => Icons.fire_truck_rounded,
  VehicleKind.car => Icons.directions_car_rounded,
};

/// What the picker came back with: an existing vehicle, or (null) "add a new one".
class _VehicleChoice {
  const _VehicleChoice(this.vehicle);

  final Vehicle? vehicle;
}

class _VehiclePicker extends StatelessWidget {
  const _VehiclePicker({required this.fleet, required this.driverUid});

  final List<Vehicle> fleet;
  final String driverUid;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 12),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text('Which vehicle?', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800)),
            const SizedBox(height: 8),
            if (fleet.isEmpty)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 8),
                child: Text(
                  'No vehicles yet. Add the first one below.',
                  style: TextStyle(fontSize: 13, color: AppColors.inkMuted),
                ),
              ),
            Flexible(
              child: ListView(
                shrinkWrap: true,
                children: [
                  for (final vehicle in fleet)
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: Icon(_icon(vehicle.kind), color: AppColors.brand),
                      title: Text(vehicle.description, style: const TextStyle(fontWeight: FontWeight.w600)),
                      // Moving a vehicle that someone else is driving takes it
                      // off them - said here so the owner isn't surprised.
                      subtitle: Text(switch (vehicle.assignedDriverUid) {
                        null => 'Free',
                        final uid when uid == driverUid => 'Already theirs',
                        _ => 'With another driver — choosing it moves it',
                      }),
                      enabled: vehicle.assignedDriverUid != driverUid,
                      onTap: () => Navigator.pop(context, _VehicleChoice(vehicle)),
                    ),
                ],
              ),
            ),
            const Divider(color: AppColors.hairline),
            TextButton.icon(
              onPressed: () => Navigator.pop(context, const _VehicleChoice(null)),
              icon: const Icon(Icons.add_rounded),
              label: const Text('Add a new vehicle'),
            ),
          ],
        ),
      ),
    );
  }
}

class _NewVehicle {
  const _NewVehicle({required this.name, required this.kind, this.registration});

  final String name;
  final VehicleKind kind;
  final String? registration;
}

class _AddVehicleDialog extends StatefulWidget {
  const _AddVehicleDialog();

  @override
  State<_AddVehicleDialog> createState() => _AddVehicleDialogState();
}

class _AddVehicleDialogState extends State<_AddVehicleDialog> {
  // Owned here and disposed in dispose(), after the dialog has fully closed -
  // see _RenameDialog in owner_routes_screen.dart for what goes wrong otherwise.
  final _name = TextEditingController();
  final _plate = TextEditingController();
  VehicleKind _kind = VehicleKind.truck;
  String? _error;

  @override
  void dispose() {
    _name.dispose();
    _plate.dispose();
    super.dispose();
  }

  void _submit() {
    final name = _name.text.trim();
    final plate = Vehicle.normaliseRegistration(_plate.text);
    if (name.isEmpty) return setState(() => _error = 'Give the vehicle a name.');
    if (plate != null && plate.length > Vehicle.maxRegistrationLength) {
      return setState(() => _error = 'That plate is too long.');
    }
    Navigator.pop(context, _NewVehicle(name: name, kind: _kind, registration: plate));
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Add a vehicle'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          TextField(
            controller: _name,
            autofocus: true,
            maxLength: Vehicle.maxNameLength,
            textCapitalization: TextCapitalization.words,
            decoration: InputDecoration(
              labelText: 'Name',
              hintText: 'e.g. Isuzu truck',
              border: const OutlineInputBorder(),
              errorText: _error,
              counterText: '',
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _plate,
            textCapitalization: TextCapitalization.characters,
            decoration: const InputDecoration(
              labelText: 'Number plate (optional)',
              hintText: 'e.g. ABC123',
              border: OutlineInputBorder(),
            ),
            onSubmitted: (_) => _submit(),
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            children: [
              for (final kind in VehicleKind.values)
                ChoiceChip(
                  label: Text(kind.label),
                  selected: kind == _kind,
                  onSelected: (_) => setState(() => _kind = kind),
                ),
            ],
          ),
        ],
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
        TextButton(onPressed: _submit, child: const Text('Add')),
      ],
    );
  }
}
