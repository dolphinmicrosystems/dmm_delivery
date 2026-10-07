import 'package:flutter/material.dart';

import '../../models/driver_invitation.dart';
import '../../theme/app_colors.dart';
import '../../util/app_log.dart';
import '../../widgets/surface_card.dart';
import '../settings_store.dart';
import 'save_setting.dart';

/// How long a driver has to accept an invitation.
///
/// Worth a control rather than a constant because the right answer is a
/// judgement about people, not about software: an owner onboarding a driver
/// who starts on Monday wants a short window, and one inviting a relief
/// driver for the season wants a long one.
///
/// The explanation on the card is deliberately complete, because the setting
/// is easy to misread as "how long a driver keeps access". It is not: the
/// deadline only governs *accepting* - handle_sign_in.py checks expiry only
/// for an account that has never signed in - so a driver who has joined
/// keeps working until they are removed, whatever this says.
class InvitationDeadlineCard extends StatelessWidget {
  const InvitationDeadlineCard({super.key, required this.settings});

  final SettingsStore settings;

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<int>(
      stream: settings.invitationTtlDays(),
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          AppLog.owner.error('invitation ttl stream failed', snapshot.error, snapshot.stackTrace);
        }
        final days = snapshot.data ?? InvitationTtl.fallback;

        return SurfaceCard(
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Invitation deadline',
                style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 4),
              // Kept to one line on purpose - an earlier four-point version
              // went unread. The one thing it must not be mistaken for is
              // "how long a driver keeps access", so that is what it says.
              const Text(
                'Days a driver has to sign in after being invited. '
                'Once signed in, they keep access.',
                style: TextStyle(fontSize: 12, color: AppColors.inkMuted, height: 1.4),
              ),
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final preset in InvitationTtl.presets)
                    ChoiceChip(
                      label: Text(InvitationTtl.label(preset)),
                      selected: preset == days,
                      onSelected: (selected) {
                        if (!selected || preset == days) return;
                        saveSetting(context, 'invitation ttl', () => settings.setInvitationTtlDays(preset));
                      },
                    ),
                ],
              ),
            ],
          ),
        );
      },
    );
  }
}
