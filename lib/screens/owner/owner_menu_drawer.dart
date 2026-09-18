import 'package:flutter/material.dart';

import '../../state/auth_state.dart';
import '../../theme/app_colors.dart';
import '../../util/app_log.dart';
import 'owner_settings_screen.dart';

/// The right-hand hamburger menu from owner-menu.html. An end drawer rather
/// than a third nav tab: these are occasional destinations, and the bottom
/// bar is reserved for the two screens the owner moves between constantly.
class OwnerMenuDrawer extends StatelessWidget {
  const OwnerMenuDrawer({super.key, required this.authState});

  final AuthState authState;

  @override
  Widget build(BuildContext context) {
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
            const SizedBox(height: 8),
            _MenuItem(
              icon: Icons.settings_outlined,
              title: 'Settings',
              subtitle: 'Account, sign out',
              onTap: () {
                AppLog.owner('menu -> Settings');
                Navigator.of(context).pop();
                Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => OwnerSettingsScreen(authState: authState)),
                );
              },
            ),
            _MenuItem(
              icon: Icons.info_outline_rounded,
              title: 'About',
              subtitle: 'Blue Dot v1.0 · NZ',
              onTap: () {
                AppLog.owner('menu -> About');
                Navigator.of(context).pop();
                showAboutDialog(
                  context: context,
                  applicationName: 'Blue Dot',
                  applicationVersion: '1.0 · NZ',
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}

class _MenuItem extends StatelessWidget {
  const _MenuItem({required this.icon, required this.title, required this.subtitle, required this.onTap});

  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
        child: Row(
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(color: AppColors.brandSoft, borderRadius: BorderRadius.circular(12)),
              alignment: Alignment.center,
              child: Icon(icon, size: 18, color: AppColors.brand),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 12, color: AppColors.inkMuted),
                  ),
                ],
              ),
            ),
            const Icon(Icons.chevron_right_rounded, size: 18, color: AppColors.inkMuted),
          ],
        ),
      ),
    );
  }
}
