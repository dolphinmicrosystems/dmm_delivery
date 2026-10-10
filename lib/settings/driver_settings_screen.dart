import 'package:flutter/material.dart';

import '../state/auth_state.dart';
import '../theme/app_colors.dart';
import '../widgets/section_label.dart';
import 'cards/reminder_card.dart';
import 'cards/switch_setting_card.dart';
import 'settings_store.dart';

/// The driver's settings, from their menu. Smaller than the owner's
/// SettingsScreen: when to be reminded of a run, and the voice while driving.
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
          const SizedBox(height: 24),
          const SectionLabel('Driving'),
          const SizedBox(height: 8),
          SwitchSettingCard(
            title: 'Voice prompts',
            subtitle: 'Speaks the next stop, and what to deliver as you get close. '
                'Also a mute button while driving.',
            value: settings.voicePrompts(),
            onChanged: settings.setVoicePrompts,
            what: 'voice prompts',
          ),
        ],
      ),
    );
  }
}
