import 'package:flutter/material.dart';

import '../state/auth_state.dart';
import '../theme/app_colors.dart';
import '../widgets/section_label.dart';
import 'cards/account_card.dart';
import 'cards/driver_alerts_card.dart';
import 'cards/invitation_deadline_card.dart';
import 'cards/stop_time_card.dart';
import 'settings_store.dart';

/// Reached from the owner's hamburger menu: their account, and every setting,
/// one card each (`cards/`), grouped under a label. The settings themselves
/// are read and written by [SettingsStore]. The driver roster is not here: it
/// is the Drivers tab.
class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key, required this.authState});

  final AuthState authState;

  @override
  Widget build(BuildContext context) {
    final settings = SettingsStore(authState);
    return Scaffold(
      backgroundColor: AppColors.surfaceMuted,
      appBar: AppBar(title: const Text('Settings')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          AccountCard(authState: authState),
          const SizedBox(height: 24),
          const SectionLabel('Notifications'),
          const SizedBox(height: 8),
          DriverAlertsCard(settings: settings),
          const SizedBox(height: 24),
          const SectionLabel('Delivery times'),
          const SizedBox(height: 8),
          StopTimeCard(settings: settings),
          const SizedBox(height: 24),
          const SectionLabel('Driver invitations'),
          const SizedBox(height: 8),
          InvitationDeadlineCard(settings: settings),
          const SizedBox(height: 24),
        ],
      ),
    );
  }
}
