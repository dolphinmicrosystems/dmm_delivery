import 'package:flutter/material.dart';

import '../../state/auth_state.dart';
import '../../theme/app_colors.dart';
import '../../util/app_log.dart';
import '../../widgets/primary_button.dart';

class SignInScreen extends StatelessWidget {
  const SignInScreen({super.key, required this.authState, required this.isOwnerPath});

  final AuthState authState;
  final bool isOwnerPath;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.surfaceMuted,
      appBar: AppBar(backgroundColor: Colors.transparent, elevation: 0),
      body: ListenableBuilder(
        listenable: authState,
        builder: (context, _) {
          final isLoading = authState.status == AuthStatus.loading;
          // `isCurrent` is the tell: if this logs false while the status is
          // signedIn, the app really did sign in and this screen is simply
          // a stale route still covering it.
          AppLog.auth('SignInScreen rebuild', {
            'status': authState.status.name,
            'isOwnerPath': isOwnerPath,
            'isCurrentRoute': ModalRoute.of(context)?.isCurrent,
          });
          return Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  isOwnerPath ? 'Sign in as Owner' : 'Sign in as Driver',
                  textAlign: TextAlign.center,
                  style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800),
                ),
                const SizedBox(height: 8),
                Text(
                  isOwnerPath
                      ? 'New here? Signing in creates your owner account automatically.'
                      : 'Sign in with the Google account your owner invited.',
                  textAlign: TextAlign.center,
                  style: const TextStyle(fontSize: 13, color: AppColors.inkMuted),
                ),
                const SizedBox(height: 32),
                if (authState.status == AuthStatus.error) ...[
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: const Color(0xFFFCEAEA),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(
                      authState.errorMessage ?? 'Something went wrong.',
                      textAlign: TextAlign.center,
                      style: const TextStyle(fontSize: 13, color: Color(0xFFB42318)),
                    ),
                  ),
                  const SizedBox(height: 16),
                ],
                isLoading
                    ? const Center(child: CircularProgressIndicator())
                    : PrimaryButton(
                        label: 'Continue with Google',
                        icon: Icons.g_mobiledata_rounded,
                        onPressed: () {
                          AppLog.auth('Continue with Google tapped', {'isOwnerPath': isOwnerPath});
                          authState.signInWithGoogle();
                        },
                      ),
              ],
            ),
          );
        },
      ),
    );
  }
}
