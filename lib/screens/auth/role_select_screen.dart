import 'package:flutter/material.dart';

import '../../state/auth_state.dart';
import '../../theme/app_colors.dart';
import '../../util/app_log.dart';
import '../../widgets/surface_card.dart';
import 'sign_in_screen.dart';

/// First screen shown to a signed-out user. Purely a copy/navigation
/// router - the actual role is decided server-side by the `role` custom
/// claim (see AuthState), not by which card is tapped here.
class RoleSelectScreen extends StatelessWidget {
  const RoleSelectScreen({super.key, required this.authState});

  final AuthState authState;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.surfaceMuted,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                width: 56,
                height: 56,
                decoration: BoxDecoration(color: AppColors.brand, borderRadius: BorderRadius.circular(16)),
                alignment: Alignment.center,
                child: const Text('B', style: TextStyle(color: Colors.white, fontSize: 24, fontWeight: FontWeight.w800)),
              ),
              const SizedBox(height: 16),
              const Text('Blue Dot', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800)),
              const SizedBox(height: 4),
              const Text(
                'Who are you signing in as?',
                style: TextStyle(fontSize: 14, color: AppColors.inkMuted),
              ),
              const SizedBox(height: 32),
              _RoleCard(
                icon: Icons.storefront_rounded,
                title: 'Owner',
                subtitle: 'Manage drivers and runs',
                onTap: () => _continue(context, isOwnerPath: true),
              ),
              const SizedBox(height: 16),
              _RoleCard(
                icon: Icons.local_shipping_rounded,
                title: 'Driver',
                subtitle: 'You’ll need an invite from an owner first',
                onTap: () => _continue(context, isOwnerPath: false),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _continue(BuildContext context, {required bool isOwnerPath}) {
    // SignInScreen is *pushed* on top of AuthGate rather than swapped in by
    // it, so it outlives any status change AuthGate reacts to - worth
    // logging, since a route left on the stack looks identical to "signed
    // in but bounced back to login" from the outside.
    AppLog.auth('RoleSelect -> pushing SignInScreen', {'isOwnerPath': isOwnerPath});
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => SignInScreen(authState: authState, isOwnerPath: isOwnerPath),
      ),
    );
  }
}

class _RoleCard extends StatelessWidget {
  const _RoleCard({required this.icon, required this.title, required this.subtitle, required this.onTap});

  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(20),
      child: SurfaceCard(
        padding: const EdgeInsets.all(20),
        child: Row(
          children: [
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(color: AppColors.brandSoft, borderRadius: BorderRadius.circular(12)),
              alignment: Alignment.center,
              child: Icon(icon, color: AppColors.brand),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
                  const SizedBox(height: 2),
                  Text(subtitle, style: const TextStyle(fontSize: 12, color: AppColors.inkMuted)),
                ],
              ),
            ),
            const Icon(Icons.chevron_right_rounded, color: AppColors.inkMuted),
          ],
        ),
      ),
    );
  }
}
