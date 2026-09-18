import 'package:flutter/material.dart';

import '../../models/owner_profile.dart';
import '../../state/auth_state.dart';
import '../../theme/app_colors.dart';
import '../../util/app_log.dart';
import '../../widgets/surface_card.dart';
import 'owner_profile_screen.dart';

/// Reached from the hamburger menu: the owner's own account. The driver roster
/// and invitation validity that used to sit here have their own tab now -
/// see OwnerDriversScreen.
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
