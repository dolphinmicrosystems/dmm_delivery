import 'package:flutter/material.dart';

import '../../state/auth_state.dart';
import '../../util/app_log.dart';
import '../root_shell.dart';
import 'role_select_screen.dart';

/// Top-level widget deciding what the user sees based on AuthState: signed
/// out -> role picker -> sign-in, signed in -> the app (RootShell). A
/// `needsRole` state is a defensive fallback (the beforeSignIn blocking
/// function should always grant owner or reject with an error - see
/// dmm-delivery-app's application/handle_sign_in.py) rather than an
/// expected steady state.
class AuthGate extends StatelessWidget {
  const AuthGate({super.key, required this.authState});

  final AuthState authState;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: authState,
      builder: (context, _) {
        // What the gate decides to show for a given status is the crux of
        // any "it bounced me back to login" report - log the decision, not
        // just the status, so the rendered screen is visible in the trace.
        AppLog.auth('AuthGate rebuild', {
          'status': authState.status.name,
          'role': authState.role?.name,
          'uid': authState.user?.uid,
        });
        switch (authState.status) {
          case AuthStatus.loading:
            AppLog.auth('AuthGate -> loading spinner');
            return const Scaffold(body: Center(child: CircularProgressIndicator()));
          case AuthStatus.signedOut:
          case AuthStatus.error:
            AppLog.auth('AuthGate -> RoleSelectScreen', {'error': authState.errorMessage});
            return RoleSelectScreen(authState: authState);
          case AuthStatus.needsRole:
            AppLog.auth('AuthGate -> needsRole dead-end (no role claim on token)');
            return Scaffold(
              body: Center(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Text(
                        'Your account isn\'t set up yet. Ask your owner to invite you, then sign in again.',
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 16),
                      TextButton(onPressed: authState.signOut, child: const Text('Sign out')),
                    ],
                  ),
                ),
              ),
            );
          case AuthStatus.signedIn:
            AppLog.auth('AuthGate -> RootShell (signed in)', {'role': authState.role?.name});
            return RootShell(authState: authState);
        }
      },
    );
  }
}
