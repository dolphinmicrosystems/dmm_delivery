import 'package:flutter/material.dart';

import '../state/auth_state.dart';
import '../theme/app_colors.dart';
import '../widgets/section_label.dart';
import 'cards/reminder_card.dart';
import 'settings_store.dart';

/// The driver's settings, from their menu. Smaller than the owner's
/// SettingsScreen: for now, when to be reminded of a run.
class DriverSettingsScreen extends StatelessWidget {
  const DriverSettingsScreen({super.key, required this.authState});

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
          const SectionLabel('Reminders'),
          const SizedBox(height: 8),
          ReminderCard(settings: settings),
        ],
      ),
    );
  }
}
