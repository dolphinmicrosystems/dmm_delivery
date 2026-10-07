import 'package:flutter/material.dart';

import '../../theme/app_colors.dart';
import '../../util/app_log.dart';
import '../../widgets/surface_card.dart';
import '../settings_store.dart';
import 'save_setting.dart';

/// "Ana is online" / "Ana is offline" on this owner's phones, or not.
///
/// This person's own choice (user_settings), not the business's: another
/// owner of the same business keeps hearing them.
class DriverAlertsCard extends StatelessWidget {
  const DriverAlertsCard({super.key, required this.settings});

  final SettingsStore settings;

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<bool>(
      stream: settings.driverPresenceAlerts(),
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          AppLog.owner.error('presence alerts stream failed', snapshot.error, snapshot.stackTrace);
        }
        final on = snapshot.data ?? true;
        return SurfaceCard(
          padding: const EdgeInsets.fromLTRB(16, 6, 8, 6),
          child: SwitchListTile(
            contentPadding: EdgeInsets.zero,
            value: on,
            onChanged: snapshot.hasData
                ? (value) => saveSetting(context, 'presence alerts', () => settings.setDriverPresenceAlerts(value))
                : null,
            title: const Text(
              'Driver online / offline',
              style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700),
            ),
            subtitle: const Text(
              'A notification when one of your drivers switches online or offline.',
              style: TextStyle(fontSize: 12, color: AppColors.inkMuted, height: 1.4),
            ),
          ),
        );
      },
    );
  }
}
