import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import '../../models/driver_invitation.dart';
import '../../models/driver_stats.dart';
import '../../models/owner_today.dart';
import '../../models/run_time.dart';
import '../../models/run_timing.dart';
import '../../models/week_roster.dart';
import '../../settings/settings_screen.dart';
import '../../state/auth_state.dart';
import '../../theme/app_colors.dart';
import '../../util/app_log.dart';
import '../../widgets/run_timing_pill.dart';
import '../../widgets/section_label.dart';
import '../../widgets/surface_card.dart';
import 'live_run_card.dart';
import 'owner_drivers_screen.dart';
import 'owner_roster_screen.dart';
import 'owner_routes_screen.dart';
import 'owner_run_data.dart';
import 'schedule_actions.dart';

/// The owner shell's tabs, for Home's tiles to switch to.
enum OwnerTab { home, routes, runs, drivers }

/// The owner's landing screen: the day at a glance, as tiles.
///
///  * **Today** - runs done, stops delivered, drivers online, and what needs
///    attention; each tile opens the tab behind it.
///  * **Needs attention** - a driver's app gone quiet or the run left, a run
///    late on the road or late to start, and a run today or tomorrow with
///    nobody to drive it (tap to assign).
///  * **Live now** - every run on the road, with its driver and vehicle.
///  * **Coming up** - today's runs still to start, then tomorrow's.
///  * **Quick actions** - roster, scheduling, run sheets, invites, runs, settings.
///
/// Every number is real: the runs and schedule (OwnerRunDataBuilder), the
/// heartbeats (run_live), which drivers have the app open (driver_presence) and
/// the invitations. Nothing is shown that the data can't back - see plan.md.
class OwnerHomeScreen extends StatelessWidget {
  const OwnerHomeScreen({super.key, required this.authState, required this.onOpenTab});

  final AuthState authState;

  /// Switches the owner shell to one of its tabs.
  final ValueChanged<OwnerTab> onOpenTab;

  @override
  Widget build(BuildContext context) {
    AppLog.owner('OwnerHomeScreen build', {'uid': authState.user?.uid, 'role': authState.role?.name});
    final ownerUid = authState.ownerUid;
    if (ownerUid == null) return const SizedBox.shrink();
    return OwnerRunDataBuilder(
      authState: authState,
      ownerUid: ownerUid,
      builder: (context, data) {
        final now = DateTime.now();
        final today = DateTime(now.year, now.month, now.day);
        return RunLiveBuilder(
          ownerUid: ownerUid,
          runIds: [
            for (final run in data.runs)
              if (run.date == today && run.started != null && run.finished == null) run.id,
          ],
          builder: (context, lastSeen) => _InvitationsAndPresence(
            authState: authState,
            ownerUid: ownerUid,
            builder: (context, roster) => _HomeBody(
              authState: authState,
              data: data,
              today: OwnerToday.build(
                runs: data.runs,
                crewFor: (run) {
                  final crew = data.crewFor(run);
                  return (driver: crew.driver, startTime: crew.startTime, endTime: crew.endTime);
                },
                lastSeen: lastSeen,
                now: now,
              ),
              roster: roster,
              now: now,
              onOpenTab: onOpenTab,
            ),
          ),
        );
      },
    );
  }
}

/// The driver roster as Home needs it: who could drive, who is online now,
/// and the invitations waiting.
typedef _Roster = ({int drivers, int online, List<DriverInvitation> invitations});

class _InvitationsAndPresence extends StatelessWidget {
  const _InvitationsAndPresence({required this.authState, required this.ownerUid, required this.builder});

  final AuthState authState;
  final String ownerUid;
  final Widget Function(BuildContext context, _Roster roster) builder;

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: authState.invitations(),
      builder: (context, invitationsSnap) => StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
        // Which drivers have the app open (DriverPresence); the rules let an owner
        // read their own business's.
        stream: FirebaseFirestore.instance
            .collection('driver_presence')
            .where('owner_uid', isEqualTo: ownerUid)
            .where('online', isEqualTo: true)
            .snapshots(),
        builder: (context, presenceSnap) {
          if (presenceSnap.hasError) {
            AppLog.owner.error('presence stream failed', presenceSnap.error, presenceSnap.stackTrace);
          }
          final now = DateTime.now();
          final invitations = [
            for (final doc
                in invitationsSnap.data?.docs ?? const <QueryDocumentSnapshot<Map<String, dynamic>>>[])
              DriverInvitation.fromDoc(doc, now: now),
          ];
          // Working drivers: signed in, not removed, invited as drivers.
          final drivers = {
            for (final i in invitations)
              if (i.status == InvitationStatus.accepted && !i.isOwnerInvite && i.acceptedUid != null)
                i.acceptedUid!,
          };
          final online = {
            for (final doc
                in presenceSnap.data?.docs ?? const <QueryDocumentSnapshot<Map<String, dynamic>>>[])
              if (drivers.contains(doc.id)) doc.id,
          };
          return builder(context, (drivers: drivers.length, online: online.length, invitations: invitations));
        },
      ),
    );
  }
}

class _HomeBody extends StatelessWidget {
  const _HomeBody({
    required this.authState,
    required this.data,
    required this.today,
    required this.roster,
    required this.now,
    required this.onOpenTab,
  });

  final AuthState authState;
  final OwnerRunData data;
  final OwnerToday today;
  final _Roster roster;
  final DateTime now;
  final ValueChanged<OwnerTab> onOpenTab;

  @override
  Widget build(BuildContext context) {
    final week = WeekRoster.build(
      routeNames: data.routeNames,
      assignmentsByRoute: data.assignmentsByRoute,
      driverNames: data.driverNames,
      from: now,
    );
    final waiting = roster.invitations
        .where((i) => i.status == InvitationStatus.pending || i.status == InvitationStatus.expired)
        .length;

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 28),
      children: [
        _Header(authState: authState, today: today, now: now),
        const SizedBox(height: 18),
        _TodayTiles(today: today, roster: roster, onOpenTab: onOpenTab),
        if (today.attention.isNotEmpty) ...[
          const SizedBox(height: 26),
          _SectionHeader('Needs attention', count: today.attention.length),
          const SizedBox(height: 10),
          SurfaceCard(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: Column(
              children: [
                for (final (index, row) in today.attention.indexed) ...[
                  if (index > 0) const Divider(height: 1, indent: 64, color: AppColors.hairline),
                  _AttentionRow(
                    row: row,
                    now: now,
                    onTap: row.hasDriver
                        ? () => openRunDetail(context, authState, row)
                        : () => scheduleRoute(
                            context,
                            authState: authState,
                            roundKey: row.run.roundKey,
                            routeName: row.run.routeName ?? 'this route',
                            assignments: data.assignmentsByRoute[row.run.roundKey] ?? const [],
                            date: row.run.date,
                            oneDay: true,
                          ),
                  ),
                ],
              ],
            ),
          ),
        ],
        if (today.live.isNotEmpty) ...[
          const SizedBox(height: 26),
          _SectionHeader('Live now', count: today.live.length),
          const SizedBox(height: 10),
          for (final row in today.live) ...[
            LiveRunCard(
              run: row.run,
              driver: row.crew.driver,
              vehicle: _vehicleFor(row),
              timing: row.timing,
              onTap: () => openRunDetail(context, authState, row),
            ),
            const SizedBox(height: 10),
          ],
        ],
        if (today.comingUp.isNotEmpty) ...[
          SizedBox(height: today.live.isEmpty ? 26 : 16),
          _SectionHeader('Coming up', action: 'All runs', onAction: () => onOpenTab(OwnerTab.runs)),
          const SizedBox(height: 10),
          SurfaceCard(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: Column(
              children: [
                for (final (index, row) in today.comingUp.take(5).indexed) ...[
                  if (index > 0) const Divider(height: 1, indent: 64, color: AppColors.hairline),
                  _ComingUpRow(
                    row: row,
                    vehicle: _vehicleFor(row),
                    now: now,
                    onTap: () => openRunDetail(context, authState, row),
                  ),
                ],
              ],
            ),
          ),
        ],
        const SizedBox(height: 26),
        const _SectionHeader('Quick actions'),
        const SizedBox(height: 10),
        _TileGrid(
          children: [
            _ActionTile(
              icon: Icons.calendar_month_rounded,
              tint: const Color(0xFF7C3AED),
              title: 'Delivery roster',
              subtitle: week.days.every((d) => d.slots.isEmpty)
                  ? 'No routes yet'
                  : week.unassigned == 0
                  ? 'Every route covered this week'
                  : '${week.unassigned} route-day${week.unassigned == 1 ? '' : 's'} without a driver',
              warn: week.unassigned > 0,
              onTap: () => Navigator.of(
                context,
              ).push(MaterialPageRoute(builder: (_) => OwnerRosterScreen(authState: authState))),
            ),
            _ActionTile(
              icon: Icons.event_available_rounded,
              tint: AppColors.success,
              title: 'Schedule a run',
              subtitle: 'Driver, day and times',
              onTap: () => pickRouteAndSchedule(
                context,
                authState: authState,
                routeNames: data.routeNames,
                assignmentsByRoute: data.assignmentsByRoute,
              ),
            ),
            _ActionTile(
              icon: Icons.upload_file_rounded,
              tint: AppColors.brand,
              title: 'Upload run sheet',
              subtitle: 'New route, or bring one up to date',
              onTap: () => startUpload(context, authState, roundKey: null, roundLabel: null),
            ),
            _ActionTile(
              icon: Icons.person_add_alt_1_rounded,
              tint: const Color(0xFF0891B2),
              title: 'Invite drivers',
              subtitle: waiting == 0
                  ? 'No invites waiting'
                  : DriverInvitation.rosterSummary(roster.invitations),
              warn: roster.invitations.any((i) => i.status == InvitationStatus.expired),
              onTap: () => showInviteDriverDialog(context, authState),
            ),
            _ActionTile(
              icon: Icons.history_rounded,
              tint: const Color(0xFFDB2777),
              title: 'Runs & history',
              subtitle: 'Every run, photos and times',
              onTap: () => onOpenTab(OwnerTab.runs),
            ),
            _ActionTile(
              icon: Icons.tune_rounded,
              tint: AppColors.inkMuted,
              title: 'Settings',
              subtitle: 'Alerts, stop time, invites',
              onTap: () => Navigator.of(
                context,
              ).push(MaterialPageRoute(builder: (_) => SettingsScreen(authState: authState))),
            ),
          ],
        ),
      ],
    );
  }

  String? _vehicleFor(TodayRun row) => data.crewFor(row.run).vehicle?.description;
}

/// "Kia ora, Pawan", the date, and one line on how the day is going.
class _Header extends StatelessWidget {
  const _Header({required this.authState, required this.today, required this.now});

  final AuthState authState;
  final OwnerToday today;
  final DateTime now;

  @override
  Widget build(BuildContext context) {
    // First name only: a greeting that reads out a full name or an email
    // address stops sounding like one.
    final name = authState.user?.displayName?.split(' ').first;
    const weekdays = ['Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday', 'Sunday'];
    const months = [
      'January', 'February', 'March', 'April', 'May', 'June', //
      'July', 'August', 'September', 'October', 'November', 'December',
    ];
    final (summary, tone) = _summary();
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 20),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [AppColors.brand, AppColors.brandDark],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(24),
        boxShadow: [
          BoxShadow(
            color: AppColors.brand.withValues(alpha: 0.28),
            blurRadius: 24,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '${weekdays[now.weekday - 1]} ${now.day} ${months[now.month - 1]}'.toUpperCase(),
            style: const TextStyle(
              fontSize: 11.5,
              fontWeight: FontWeight.w700,
              letterSpacing: 1.1,
              color: Colors.white70,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            name == null ? 'Kia ora' : 'Kia ora, $name',
            style: const TextStyle(
              fontSize: 26,
              fontWeight: FontWeight.w800,
              height: 1.15,
              letterSpacing: -0.5,
              color: Colors.white,
            ),
          ),
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.14),
              borderRadius: BorderRadius.circular(999),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 8,
                  height: 8,
                  decoration: BoxDecoration(color: tone, shape: BoxShape.circle),
                ),
                const SizedBox(width: 8),
                Flexible(
                  child: Text(
                    summary,
                    style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: Colors.white),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  (String, Color) _summary() {
    final attention = today.attention.length;
    if (attention > 0) {
      return ('$attention ${attention == 1 ? 'thing needs' : 'things need'} you', const Color(0xFFFFB4B4));
    }
    if (today.live.isNotEmpty) {
      final n = today.live.length;
      return ('$n ${n == 1 ? 'run' : 'runs'} on the road, all on time', const Color(0xFF86EFAC));
    }
    if (today.runsToday == 0) return ('No runs today', Colors.white70);
    if (today.finishedToday == today.runsToday) {
      return ("All of today's runs are done", const Color(0xFF86EFAC));
    }
    final left = today.runsToday - today.finishedToday;
    return ('$left ${left == 1 ? 'run' : 'runs'} still to go today', Colors.white70);
  }
}

/// Today's four numbers, as tiles.
class _TodayTiles extends StatelessWidget {
  const _TodayTiles({required this.today, required this.roster, required this.onOpenTab});

  final OwnerToday today;
  final _Roster roster;
  final ValueChanged<OwnerTab> onOpenTab;

  @override
  Widget build(BuildContext context) {
    final attention = today.attention.length;
    final stopsShare = today.stopsToday == 0 ? null : today.deliveredToday / today.stopsToday;
    return _TileGrid(
      children: [
        _StatTile(
          icon: Icons.local_shipping_rounded,
          tint: AppColors.brand,
          value: today.runsToday == 0 ? '0' : '${today.finishedToday}/${today.runsToday}',
          label: 'Runs done today',
          progress: today.runsToday == 0 ? null : today.finishedToday / today.runsToday,
          onTap: () => onOpenTab(OwnerTab.runs),
        ),
        _StatTile(
          icon: Icons.inventory_2_rounded,
          tint: AppColors.success,
          value: '${today.deliveredToday}',
          label: today.stopsToday == 0 ? 'Stops delivered' : 'of ${today.stopsToday} stops delivered',
          progress: stopsShare,
          onTap: () => onOpenTab(OwnerTab.runs),
        ),
        _StatTile(
          icon: Icons.wifi_tethering_rounded,
          tint: const Color(0xFF0891B2),
          value: '${roster.online}',
          label: roster.drivers == 0 ? 'Drivers online' : 'of ${roster.drivers} drivers online',
          onTap: () => onOpenTab(OwnerTab.drivers),
        ),
        _StatTile(
          icon: attention == 0 ? Icons.verified_rounded : Icons.error_outline_rounded,
          tint: attention == 0 ? AppColors.success : AppColors.danger,
          value: '$attention',
          label: attention == 0 ? 'All clear' : 'Need attention',
          onTap: () => onOpenTab(OwnerTab.runs),
        ),
      ],
    );
  }
}

/// Two tiles a row, each row as tall as its taller tile.
class _TileGrid extends StatelessWidget {
  const _TileGrid({required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        for (var i = 0; i < children.length; i += 2) ...[
          if (i > 0) const SizedBox(height: 12),
          IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(child: children[i]),
                const SizedBox(width: 12),
                Expanded(child: i + 1 < children.length ? children[i + 1] : const SizedBox.shrink()),
              ],
            ),
          ),
        ],
      ],
    );
  }
}

/// The shared tile shape: white, rounded, a soft shadow, a tinted icon.
class _Tile extends StatelessWidget {
  const _Tile({required this.onTap, required this.child});

  final VoidCallback? onTap;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    // White underneath: a shadow under a see-through box shows through it
    // and greys the tile. The Material is only for the ripple, and names the
    // text style - Material otherwise applies the theme's grey body text.
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppColors.hairline),
        boxShadow: [
          BoxShadow(color: AppColors.ink.withValues(alpha: 0.05), blurRadius: 20, offset: const Offset(0, 6)),
        ],
      ),
      child: Material(
        type: MaterialType.transparency,
        textStyle: const TextStyle(fontFamily: 'Inter', color: AppColors.ink),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(20),
          child: Padding(padding: const EdgeInsets.all(14), child: child),
        ),
      ),
    );
  }
}

class _IconBadge extends StatelessWidget {
  const _IconBadge({required this.icon, required this.tint});

  final IconData icon;
  final Color tint;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 38,
      height: 38,
      decoration: BoxDecoration(color: tint.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(12)),
      child: Icon(icon, color: tint, size: 21),
    );
  }
}

class _StatTile extends StatelessWidget {
  const _StatTile({
    required this.icon,
    required this.tint,
    required this.value,
    required this.label,
    required this.onTap,
    this.progress,
  });

  final IconData icon;
  final Color tint;
  final String value;
  final String label;
  final VoidCallback onTap;

  /// A thin bar under the number, 0..1; none when there is nothing to measure.
  final double? progress;

  @override
  Widget build(BuildContext context) {
    return _Tile(
      onTap: onTap,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _IconBadge(icon: icon, tint: tint),
          const SizedBox(height: 12),
          Text(
            value,
            style: const TextStyle(fontSize: 26, fontWeight: FontWeight.w800, letterSpacing: -0.6, height: 1),
          ),
          const SizedBox(height: 4),
          Text(
            label,
            style: const TextStyle(fontSize: 12, color: AppColors.inkMuted, fontWeight: FontWeight.w600),
          ),
          if (progress != null) ...[
            const Spacer(),
            const SizedBox(height: 10),
            ClipRRect(
              borderRadius: BorderRadius.circular(999),
              child: LinearProgressIndicator(
                value: progress!.clamp(0, 1).toDouble(),
                minHeight: 5,
                backgroundColor: AppColors.hairline,
                color: tint,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _ActionTile extends StatelessWidget {
  const _ActionTile({
    required this.icon,
    required this.tint,
    required this.title,
    required this.subtitle,
    required this.onTap,
    this.warn = false,
  });

  final IconData icon;
  final Color tint;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  /// The subtitle is something to act on (an expired invite, a gap in the roster).
  final bool warn;

  @override
  Widget build(BuildContext context) {
    return _Tile(
      onTap: onTap,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              _IconBadge(icon: icon, tint: tint),
              const Spacer(),
              const Icon(Icons.arrow_forward_rounded, size: 18, color: AppColors.inkMuted),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            title,
            style: const TextStyle(fontSize: 14.5, fontWeight: FontWeight.w700, letterSpacing: -0.2),
          ),
          const SizedBox(height: 3),
          Text(
            subtitle,
            style: TextStyle(
              fontSize: 12,
              height: 1.3,
              color: warn ? const Color(0xFFB7791F) : AppColors.inkMuted,
              fontWeight: warn ? FontWeight.w600 : FontWeight.w400,
            ),
          ),
        ],
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader(this.title, {this.count, this.action, this.onAction});

  final String title;
  final int? count;
  final String? action;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        SectionLabel(title),
        if (count != null)
          Container(
            margin: const EdgeInsets.only(left: 2),
            padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 1),
            decoration: BoxDecoration(
              color: AppColors.surfaceMuted,
              borderRadius: BorderRadius.circular(999),
            ),
            child: Text(
              '$count',
              style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: AppColors.inkMuted),
            ),
          ),
        const Spacer(),
        if (action != null)
          GestureDetector(
            onTap: onAction,
            child: Text(
              action!,
              style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700, color: AppColors.brand),
            ),
          ),
      ],
    );
  }
}

/// One thing to sort out: what is wrong, on which run, and what tapping does.
class _AttentionRow extends StatelessWidget {
  const _AttentionRow({required this.row, required this.now, required this.onTap});

  final TodayRun row;
  final DateTime now;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final noDriver = !row.hasDriver;
    final (icon, tint) = switch (row.timing.kind) {
      _ when noDriver => (Icons.person_off_rounded, AppColors.warning),
      TimingKind.noSignal => (Icons.signal_cellular_connected_no_internet_0_bar_rounded, AppColors.danger),
      TimingKind.left => (Icons.logout_rounded, AppColors.danger),
      TimingKind.lateStart => (Icons.alarm_rounded, AppColors.warning),
      _ => (Icons.schedule_rounded, AppColors.warning),
    };
    final day = relativeDayLabel(row.run.date, now);
    final detail = noDriver
        ? '$day · no driver - tap to assign'
        : [
            row.crew.driver!,
            if (row.run.started != null) '${row.run.deliveredCount}/${row.run.stopCount} stops',
          ].join(' · ');
    return ListTile(
      onTap: onTap,
      contentPadding: const EdgeInsets.symmetric(horizontal: 14),
      leading: _IconBadge(icon: icon, tint: tint),
      title: Text(
        row.run.routeName ?? 'Run',
        style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14.5),
      ),
      subtitle: Text(detail, style: const TextStyle(fontSize: 12.5)),
      trailing: noDriver ? const Icon(Icons.chevron_right_rounded) : RunTimingPill(row.timing),
    );
  }
}

/// A run still to start: when, who, in what.
class _ComingUpRow extends StatelessWidget {
  const _ComingUpRow({required this.row, required this.vehicle, required this.now, required this.onTap});

  final TodayRun row;
  final String? vehicle;
  final DateTime now;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final start = parseStartTime(row.crew.startTime);
    return ListTile(
      onTap: onTap,
      contentPadding: const EdgeInsets.symmetric(horizontal: 14),
      leading: Container(
        width: 38,
        height: 38,
        alignment: Alignment.center,
        decoration: BoxDecoration(color: AppColors.surfaceMuted, borderRadius: BorderRadius.circular(12)),
        child: Text(
          start == null ? '--' : formatClock(start.hour, start.minute).replaceAll(' ', '\n'),
          textAlign: TextAlign.center,
          style: const TextStyle(fontSize: 10.5, height: 1.1, fontWeight: FontWeight.w800),
        ),
      ),
      title: Text(
        row.run.routeName ?? 'Run',
        style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14.5),
      ),
      subtitle: Text(
        [relativeDayLabel(row.run.date, now), row.crew.driver ?? 'No driver', ?vehicle].join(' · '),
        style: const TextStyle(fontSize: 12.5),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      trailing: Text(
        '${row.run.stopCount} stops',
        style: const TextStyle(fontSize: 12, color: AppColors.inkMuted, fontWeight: FontWeight.w600),
      ),
    );
  }
}
