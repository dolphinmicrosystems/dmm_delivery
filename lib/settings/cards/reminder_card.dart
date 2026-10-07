import 'package:flutter/material.dart';

import '../../theme/app_colors.dart';
import '../../util/app_log.dart';
import '../../widgets/surface_card.dart';
import '../settings_store.dart';
import 'save_setting.dart';

/// A driver's reminders: on or off, and how long before a run starts.
///
/// The backend's run-alerts sends them (and, when a run is late to start, a
/// nudge - also off with this switch). Their owner is told about a late start
/// whatever this says.
class ReminderCard extends StatelessWidget {
  const ReminderCard({super.key, required this.settings});

  final SettingsStore settings;

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<RunReminders>(
      stream: settings.runReminders(),
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          AppLog.auth.error('reminders stream failed', snapshot.error, snapshot.stackTrace);
        }
        final reminders =
            snapshot.data ?? const RunReminders(on: true, leadMinutes: RunReminders.defaultLeadMinutes);
        return SurfaceCard(
          padding: const EdgeInsets.fromLTRB(16, 6, 8, 14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                value: reminders.on,
                onChanged: snapshot.hasData
                    ? (on) => saveSetting(context, 'reminders', () => settings.setRunReminders(on))
                    : null,
                title: const Text(
                  'Remind me before a run',
                  style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700),
                ),
                subtitle: const Text(
                  'A notification with the start time, finish time and vehicle - and one if a run is late to start.',
                  style: TextStyle(fontSize: 12, color: AppColors.inkMuted, height: 1.4),
                ),
              ),
              if (reminders.on) ...[
                const SizedBox(height: 4),
                const Text('How long before', style: TextStyle(fontSize: 12.5, color: AppColors.inkMuted)),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (final minutes in RunReminders.presets)
                      ChoiceChip(
                        label: Text(RunReminders.label(minutes)),
                        selected: minutes == reminders.leadMinutes,
                        onSelected: (selected) {
                          if (!selected || minutes == reminders.leadMinutes) return;
                          saveSetting(
                            context,
                            'reminder lead',
                            () => settings.setReminderLeadMinutes(minutes),
                          );
                        },
                      ),
                  ],
                ),
              ],
            ],
          ),
        );
      },
    );
  }
}
