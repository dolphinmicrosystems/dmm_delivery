import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import '../../state/auth_state.dart';
import '../../theme/app_colors.dart';
import '../../util/app_log.dart';
import '../../widgets/primary_button.dart';
import '../../widgets/section_label.dart';
import '../../widgets/surface_card.dart';

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
          SurfaceCard(
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
                        authState.user?.displayName ?? authState.user?.email ?? 'Owner',
                        style: const TextStyle(fontWeight: FontWeight.w700),
                      ),
                      Text(authState.user?.email ?? '', style: const TextStyle(fontSize: 12, color: AppColors.inkMuted)),
                    ],
                  ),
                ),
                TextButton(onPressed: authState.signOut, child: const Text('Sign out')),
              ],
            ),
          ),
          const SizedBox(height: 24),
          const SectionLabel('Drivers'),
          const SizedBox(height: 8),
          PrimaryButton(
            label: 'Register driver',
            icon: Icons.person_add_alt_1_rounded,
            onPressed: () => showInviteDriverDialog(context, authState),
          ),
          const SizedBox(height: 16),
          _DriverList(authState: authState),
        ],
      ),
    );
  }
}

/// Shared by this screen's "Register driver" button and the Owner home
/// "Invite riders" quick action - the same invitation, reached from the two
/// places an owner looks for it.
///
/// Email + Google sign-in is the interim mechanism; the prototype's
/// phone + OTP flow replaces it (see plan.md, "Rider invitations by phone").
void showInviteDriverDialog(BuildContext context, AuthState authState) {
  final controller = TextEditingController();
  String? error;

  showDialog<void>(
    context: context,
    builder: (dialogContext) => StatefulBuilder(
        builder: (dialogContext, setState) => AlertDialog(
          title: const Text('Register driver'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              TextField(
                controller: controller,
                autofocus: true,
                keyboardType: TextInputType.emailAddress,
                decoration: const InputDecoration(labelText: 'Driver\'s Gmail address'),
              ),
              if (error != null) ...[
                const SizedBox(height: 8),
                Text(error!, style: const TextStyle(color: Colors.red, fontSize: 12)),
              ],
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(dialogContext), child: const Text('Cancel')),
            FilledButton(
              onPressed: () async {
                final email = controller.text.trim();
                if (!email.contains('@')) {
                  setState(() => error = 'Enter a valid email address.');
                  return;
                }
                try {
                  AppLog.owner('inviting driver', {'email': email});
                  await authState.inviteDriver(email);
                  AppLog.owner('driver invite written', {'email': email});
                  if (dialogContext.mounted) Navigator.pop(dialogContext);
                } catch (e, s) {
                  AppLog.owner.error('driver invite failed', e, s, {'email': email});
                  setState(() => error = 'Couldn\'t send the invite: $e');
                }
              },
              child: const Text('Send invite'),
            ),
          ],
        ),
    ),
  );
}

class _DriverList extends StatelessWidget {
  const _DriverList({required this.authState});

  final AuthState authState;

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: authState.acceptedDrivers(),
      builder: (context, snapshot) {
        // Same trap as the circuits stream: a rules rejection would
        // otherwise render as the benign "No drivers yet" empty state.
        if (snapshot.hasError) {
          AppLog.owner.error('acceptedDrivers stream failed', snapshot.error, snapshot.stackTrace);
        }
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: Padding(padding: EdgeInsets.all(24), child: CircularProgressIndicator()));
        }
        final docs = snapshot.data?.docs ?? [];
        AppLog.owner('acceptedDrivers snapshot', {'count': docs.length});
        if (docs.isEmpty) {
          return const SurfaceCard(
            padding: EdgeInsets.all(16),
            child: Text(
              'No drivers yet. Invited drivers appear here once they accept by signing in.',
              style: TextStyle(color: AppColors.inkMuted, fontSize: 13),
            ),
          );
        }
        return SurfaceCard(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: Column(
            children: [
              for (final doc in docs)
                ListTile(
                  leading: const Icon(Icons.local_shipping_rounded, color: AppColors.brand),
                  title: Text(doc.data()['driver_email'] as String? ?? doc.id),
                  subtitle: const Text('Active driver', style: TextStyle(fontSize: 12)),
                ),
            ],
          ),
        );
      },
    );
  }
}
