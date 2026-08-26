import 'package:flutter/material.dart';

import '../../state/auth_state.dart';
import '../../theme/app_colors.dart';
import '../../util/app_log.dart';

/// The driver's menu, reached from the hamburger in the app bar.
///
/// It exists mainly so a driver can sign out. Until now there was no way at
/// all: the driver shell had no drawer, so Scaffold added no hamburger, and
/// the only route back to the sign-in screen was uninstalling the app. That
/// matters more here than on the owner side - a driver may hand the phone
/// back, or be signed in on the wrong Google account, which is precisely the
/// mistake the invitation flow tells them to correct by signing in again.
///
/// Deliberately smaller than OwnerMenuDrawer: a driver has one job, and the
/// menu should not imply otherwise.
class DriverMenuDrawer extends StatelessWidget {
  const DriverMenuDrawer({super.key, required this.authState});

  final AuthState authState;

  @override
  Widget build(BuildContext context) {
    final user = authState.user;

    return Drawer(
      width: MediaQuery.of(context).size.width * 0.74,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(),
      child: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 12, 12, 12),
              child: Row(
                children: [
                  const Expanded(
                    child: Text(
                      'Menu',
                      style: TextStyle(fontSize: 15, fontWeight: FontWeight.w800, letterSpacing: -0.3),
                    ),
                  ),
                  IconButton(
                    onPressed: () => Navigator.of(context).pop(),
                    icon: const Icon(Icons.close_rounded, size: 18),
                    tooltip: 'Close menu',
                  ),
                ],
              ),
            ),
            const Divider(height: 1, color: AppColors.hairline),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 16),
              child: Row(
                children: [
                  const CircleAvatar(radius: 20, child: Icon(Icons.person_rounded)),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          user?.displayName ?? 'Driver',
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontWeight: FontWeight.w700),
                        ),
                        // The address, shown because signing in on the wrong
                        // Google account is the commonest thing to go wrong
                        // here and the hardest to notice from the inside.
                        Text(
                          user?.email ?? '',
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontSize: 12, color: AppColors.inkMuted),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const Divider(height: 1, color: AppColors.hairline),
            const Spacer(),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
              child: SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  onPressed: () {
                    AppLog.auth('driver menu -> sign out');
                    Navigator.of(context).pop();
                    authState.signOut();
                  },
                  icon: const Icon(Icons.logout_rounded, size: 18),
                  label: const Text('Sign out'),
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
