import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import '../../models/driver_invitation.dart';
import '../../models/run_time.dart';
import '../../models/owner_profile.dart';
import '../../services/driver_inviter.dart';
import '../../state/auth_state.dart';
import '../../theme/app_colors.dart';
import '../../util/app_log.dart';
import '../../widgets/section_label.dart';
import '../../widgets/surface_card.dart';
import 'owner_profile_screen.dart';

/// Reached from the hamburger menu: the owner's own account, and how long a
/// driver has to accept an invitation. The roster itself is the Drivers tab
/// (OwnerDriversScreen).
class OwnerSettingsScreen extends StatelessWidget {
  const OwnerSettingsScreen({super.key, required this.authState});

  final AuthState authState;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.surfaceMuted,
      appBar: AppBar(title: const Text('Settings')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _AccountCard(authState: authState),
          const SizedBox(height: 24),
          const SectionLabel('Delivery times'),
          const SizedBox(height: 8),
          _StopTimeCard(authState: authState),
          const SizedBox(height: 24),
          const SectionLabel('Driver invitations'),
          const SizedBox(height: 8),
          _InvitationDeadlineCard(authState: authState),
          const SizedBox(height: 24),
        ],
      ),
    );
  }
}

/// The account card, which is also the way into the profile.
///
/// Streamed rather than read once so the summary line updates the moment the
/// profile screen saves - the owner comes straight back to this card, and a
/// stale line under their own name is the first thing they would notice.
class _AccountCard extends StatelessWidget {
  const _AccountCard({required this.authState});

  final AuthState authState;

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<OwnerProfile>(
      stream: authState.profile(),
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          AppLog.owner.error('profile stream failed', snapshot.error, snapshot.stackTrace);
        }
        final profile = snapshot.data ?? OwnerProfile.empty;
        // The owner's own choice beats the name Google supplied, the same
        // precedence rule route names and driver names follow.
        final name = profile.displayName ?? authState.user?.displayName ?? authState.user?.email ?? 'Owner';

        return SurfaceCard(
          padding: EdgeInsets.zero,
          child: Column(
            children: [
              InkWell(
                onTap: () {
                  AppLog.owner('open OwnerProfileScreen');
                  Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => OwnerProfileScreen(authState: authState, initial: profile),
                    ),
                  );
                },
                borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Row(
                    children: [
                      const CircleAvatar(radius: 20, child: Icon(Icons.person_rounded)),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              name,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(fontWeight: FontWeight.w700),
                            ),
                            Text(
                              authState.user?.email ?? '',
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(fontSize: 12, color: AppColors.inkMuted),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              profile.summary,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(fontSize: 12, color: AppColors.inkMuted),
                            ),
                          ],
                        ),
                      ),
                      const Icon(Icons.chevron_right_rounded, color: AppColors.inkMuted),
                    ],
                  ),
                ),
              ),
              const Divider(height: 1, color: AppColors.hairline),
              Align(
                alignment: Alignment.centerLeft,
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  child: TextButton(onPressed: authState.signOut, child: const Text('Sign out')),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

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
class _InvitationDeadlineCard extends StatelessWidget {
  const _InvitationDeadlineCard({required this.authState});

  final AuthState authState;

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<int>(
      stream: authState.invitationTtlDays(),
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
                        _set(context, preset);
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

  Future<void> _set(BuildContext context, int days) async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      await authState.setInvitationTtlDays(days);
    } on FirebaseException catch (error, stack) {
      AppLog.owner.error('invitation ttl write failed', error, stack, {'days': days});
      messenger.showSnackBar(SnackBar(content: Text(DriverInviter.errorMessage(error))));
    }
  }
}

/// How long to allow at a stop before drivers have taught us the address.
///
/// The figure every route's "about 2 h 16 min" rests on until real deliveries
/// arrive: a minute a stop across 60 stops is an hour of the estimate. Learned
/// stop times replace it address by address, which is what the second line
/// says - so an owner who sets three minutes today is not surprised when a
/// route later says something else.
class _StopTimeCard extends StatelessWidget {
  const _StopTimeCard({required this.authState});

  final AuthState authState;

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<int>(
      stream: authState.defaultStopSeconds(),
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          AppLog.owner.error('stop time stream failed', snapshot.error, snapshot.stackTrace);
        }
        final seconds = snapshot.data ?? StopTime.fallbackSeconds;
        return SurfaceCard(
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Time at each stop', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700)),
              const SizedBox(height: 4),
              const Text(
                'Used in route time estimates until your drivers have delivered to '
                'an address a few times - then its own average is used.',
                style: TextStyle(fontSize: 12, color: AppColors.inkMuted, height: 1.4),
              ),
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final preset in StopTime.presetSeconds)
                    ChoiceChip(
                      label: Text(StopTime.label(preset)),
                      selected: preset == seconds,
                      onSelected: (selected) {
                        if (!selected || preset == seconds) return;
                        _set(context, preset);
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

  Future<void> _set(BuildContext context, int seconds) async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      await authState.setDefaultStopSeconds(seconds);
    } on FirebaseException catch (error, stack) {
      AppLog.owner.error('stop time write failed', error, stack, {'seconds': seconds});
      messenger.showSnackBar(SnackBar(content: Text(DriverInviter.errorMessage(error))));
    }
  }
}
