import 'package:flutter/material.dart';

import '../../models/driver_stats.dart';
import '../../models/run_time.dart';
import '../../models/week_roster.dart';
import '../../state/auth_state.dart';
import '../../theme/app_colors.dart';
import '../../widgets/pill_badge.dart';
import '../../widgets/surface_card.dart';
import 'owner_run_data.dart';
import 'schedule_actions.dart';

/// The delivery roster: the next seven days, and who drives each route on
/// each of them (WeekRoster, from `route_assignments`). A day with a route
/// nobody drives is marked; tapping a route opens the scheduling sheet on
/// that day, set to "this day only" - covering a day is the usual change.
class OwnerRosterScreen extends StatefulWidget {
  const OwnerRosterScreen({super.key, required this.authState});

  final AuthState authState;

  @override
  State<OwnerRosterScreen> createState() => _OwnerRosterScreenState();
}

class _OwnerRosterScreenState extends State<OwnerRosterScreen> {
  int _day = 0;

  @override
  Widget build(BuildContext context) {
    final ownerUid = widget.authState.ownerUid;
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(title: const Text('Delivery roster')),
      body: ownerUid == null
          ? const SizedBox.shrink()
          : OwnerRunDataBuilder(
              authState: widget.authState,
              ownerUid: ownerUid,
              builder: (context, data) {
                final now = DateTime.now();
                final roster = WeekRoster.build(
                  routeNames: data.routeNames,
                  assignmentsByRoute: data.assignmentsByRoute,
                  driverNames: data.driverNames,
                  from: now,
                );
                final day = roster.days[_day];
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    SizedBox(
                      height: 84,
                      child: ListView.separated(
                        scrollDirection: Axis.horizontal,
                        padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
                        itemCount: roster.days.length,
                        separatorBuilder: (_, _) => const SizedBox(width: 8),
                        itemBuilder: (context, index) => _DayChip(
                          day: roster.days[index],
                          now: now,
                          selected: index == _day,
                          onTap: () => setState(() => _day = index),
                        ),
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(20, 4, 20, 8),
                      child: Text(
                        day.slots.isEmpty
                            ? 'No routes yet'
                            : day.unassigned == 0
                            ? 'Every route has a driver'
                            : '${day.unassigned} of ${day.slots.length} '
                                  '${day.slots.length == 1 ? 'route has' : 'routes have'} no driver',
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: day.unassigned == 0 ? AppColors.inkMuted : AppColors.warning,
                        ),
                      ),
                    ),
                    Expanded(
                      child: ListView.separated(
                        padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
                        itemCount: day.slots.length,
                        separatorBuilder: (_, _) => const SizedBox(height: 10),
                        itemBuilder: (context, index) {
                          final slot = day.slots[index];
                          return _SlotCard(
                            slot: slot,
                            onTap: () => scheduleRoute(
                              context,
                              authState: widget.authState,
                              roundKey: slot.roundKey,
                              routeName: slot.routeName,
                              assignments: data.assignmentsByRoute[slot.roundKey] ?? const [],
                              date: day.date,
                              oneDay: true,
                            ),
                          );
                        },
                      ),
                    ),
                  ],
                );
              },
            ),
    );
  }
}

class _DayChip extends StatelessWidget {
  const _DayChip({required this.day, required this.now, required this.selected, required this.onTap});

  final RosterDay day;
  final DateTime now;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final weekday = const ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'][day.date.weekday - 1];
    final label = switch (relativeDayLabel(day.date, now)) {
      'Today' => 'Today',
      'Tomorrow' => 'Tmrw',
      _ => weekday,
    };
    final foreground = selected ? Colors.white : AppColors.ink;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Container(
        width: 58,
        decoration: BoxDecoration(
          color: selected ? AppColors.brand : AppColors.surfaceMuted,
          borderRadius: BorderRadius.circular(16),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              label,
              style: TextStyle(
                fontSize: 11.5,
                fontWeight: FontWeight.w600,
                color: selected ? Colors.white70 : AppColors.inkMuted,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              '${day.date.day}',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: foreground),
            ),
            const SizedBox(height: 3),
            // A dot when a route that day has nobody driving.
            Container(
              width: 6,
              height: 6,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: day.unassigned == 0 ? Colors.transparent : AppColors.warning,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SlotCard extends StatelessWidget {
  const _SlotCard({required this.slot, required this.onTap});

  final RosterSlot slot;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final window = formatWindow(slot.startTime, slot.endTime);
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(20),
      child: SurfaceCard(
        padding: const EdgeInsets.fromLTRB(16, 14, 12, 14),
        child: Row(
          children: [
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: slot.hasDriver ? AppColors.brandSoft : const Color(0x1AE4A83A),
                borderRadius: BorderRadius.circular(14),
              ),
              child: Icon(
                slot.hasDriver ? Icons.person_rounded : Icons.person_off_rounded,
                color: slot.hasDriver ? AppColors.brand : AppColors.warning,
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(slot.routeName, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
                  const SizedBox(height: 2),
                  Text(
                    [slot.driverName ?? 'No driver - tap to assign', ?window].join(' · '),
                    style: TextStyle(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w600,
                      color: slot.hasDriver ? AppColors.inkMuted : AppColors.warning,
                    ),
                  ),
                ],
              ),
            ),
            if (slot.cover && slot.hasDriver) ...[
              const PillBadge(label: 'This day'),
              const SizedBox(width: 4),
            ],
            const Icon(Icons.chevron_right_rounded, color: AppColors.inkMuted),
          ],
        ),
      ),
    );
  }
}
