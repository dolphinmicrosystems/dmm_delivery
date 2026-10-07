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
          title: 'Late starts',
          subtitle: "A notification when a driver hasn't started a run 10 minutes after its start time.",
          value: settings.lateStartAlerts(),
          onChanged: settings.setLateStartAlerts,
          what: 'late start alerts',
        ),
      ],
    );
  }
}
