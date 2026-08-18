import 'package:flutter/material.dart';

import '../../state/auth_state.dart';
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
        switch (authState.status) {
          case AuthStatus.loading:
            return const Scaffold(body: Center(child: CircularProgressIndicator()));
          case AuthStatus.signedOut:
          case AuthStatus.error:
            return RoleSelectScreen(authState: authState);
          case AuthStatus.needsRole:
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
            return RootShell(authState: authState);
        }
      },
    );
  }
}
