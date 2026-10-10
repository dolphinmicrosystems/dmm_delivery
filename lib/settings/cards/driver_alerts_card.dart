import 'package:flutter/material.dart';

import '../settings_store.dart';
import 'switch_setting_card.dart';

/// The owner's alerts about their drivers, each this person's own choice
/// (user_settings), not the business's: another owner of the same business
/// keeps theirs.
class DriverAlertsCard extends StatelessWidget {
  const DriverAlertsCard({super.key, required this.settings});

  final SettingsStore settings;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        SwitchSettingCard(
          title: 'Driver online / offline',
          subtitle: 'A notification when one of your drivers switches online or offline.',
          value: settings.driverPresenceAlerts(),
          onChanged: settings.setDriverPresenceAlerts,
          what: 'presence alerts',
        ),
        const SizedBox(height: 8),
        SwitchSettingCard(
          title: 'Late and stopped runs',
          subtitle:
              "A notification when a driver hasn't started 10 minutes after the start time, is running "
              "15 minutes or more behind, or their app stops reporting for 20 minutes.",
          value: settings.lateStartAlerts(),
          onChanged: settings.setLateStartAlerts,
          what: 'late start alerts',
        ),
      ],
    );
  }
}
