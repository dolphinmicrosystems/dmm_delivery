// ---------------------------------------------------------------------------
// REGRESSION GUARD - read before changing this file.
//
// This screen already caused one hard-to-diagnose bug: sign-in succeeded, the
// app was fully running underneath, and the user still saw the login screen.
// It reads as "login loops back to login", and tapping the button again starts
// a second sign-in while already signed in. Proof it was happening, from the
// device log:
//
//     AuthGate -> RootShell (signed in) role=owner        <- signed in
//     OwnerHomeScreen build ... rider board rendered      <- app running
//     SignInScreen rebuild status=signedIn isCurrentRoute=true   <- covering it
//
// The cause: RoleSelectScreen *pushes* this screen with Navigator.push, so it
// sits ABOVE AuthGate in the navigator. AuthGate reacts to sign-in by swapping
// its own child to RootShell - which does nothing to a route stacked on top of
// it. This screen therefore has to dismiss itself.
//
// DO NOT:
//
//   * Do not turn this back into a StatelessWidget, and do not drop the
//     addListener/removeListener pair. Without them nothing dismisses the
//     route and the bug returns exactly as described above.
//
//   * Do not "simplify" by assuming AuthGate will take this screen away. It
//     cannot. A parent cannot remove a route pushed above itself.
//
//   * Do not pop without checking BOTH `mounted` and `route.isCurrent`.
//     Popping a route that is already gone, or popping mid-transition, closes
//     the screen underneath instead - which looks like the app randomly
//     exiting to a blank page.
//
//   * Do not replace the pop with Navigator.popUntil((r) => r.isFirst) or
//     pushReplacement to RootShell. The first tears down routes this screen
//     does not own; the second creates a second RootShell above AuthGate's
//     own, so the app runs twice and the back button reveals the stale copy.
//
//   * Do not delete the post-frame callback in initState. A session can
//     already be signedIn before this screen's first frame (restored session,
//     or sign-in completing between the push and initState). In that case no
//     further notification ever arrives, so the listener alone never fires.
//
//   * Do not remove `isCurrentRoute` from the rebuild log. That single field
//     is what distinguishes "sign-in failed" from "sign-in worked and this
//     screen is stale" - the two look identical on the device, and without it
//     this bug was mis-diagnosed as an auth failure for a long time.
//
// If you change the navigation model so AuthGate swaps this screen in rather
// than RoleSelectScreen pushing it, remove the push in role_select_screen.dart
// in the same change - and then all of the above becomes unnecessary.
// ---------------------------------------------------------------------------

import 'package:flutter/material.dart';

import '../../state/auth_state.dart';
import '../../theme/app_colors.dart';
import '../../util/app_log.dart';
import '../../widgets/primary_button.dart';

/// The Google sign-in step, *pushed* on top of AuthGate by RoleSelectScreen
/// rather than swapped in by AuthGate itself.
///
/// That distinction is the whole reason this is a StatefulWidget. AuthGate
/// swaps its own child to RootShell the moment the status becomes signedIn,
/// but a pushed route sits above AuthGate in the navigator and survives that
/// swap - so without the listener below, a successful sign-in leaves this
/// screen covering a perfectly functional app. From the outside that is
/// indistinguishable from "login bounced me back to login", and tapping the
/// button again starts a second sign-in while already signed in.
class SignInScreen extends StatefulWidget {
  const SignInScreen({super.key, required this.authState, required this.isOwnerPath});

  final AuthState authState;
  final bool isOwnerPath;

  @override
  State<SignInScreen> createState() => _SignInScreenState();
}

class _SignInScreenState extends State<SignInScreen> {
  @override
  void initState() {
    super.initState();
    widget.authState.addListener(_popWhenSignedIn);
    // A session can already be live before this frame - a restored session, or
    // a race where sign-in completed between the push and this initState - and
    // no further notification would ever arrive to trigger the listener.
    WidgetsBinding.instance.addPostFrameCallback((_) => _popWhenSignedIn());
  }

  @override
  void dispose() {
    widget.authState.removeListener(_popWhenSignedIn);
    super.dispose();
  }

  void _popWhenSignedIn() {
    if (!mounted || widget.authState.status != AuthStatus.signedIn) return;
    final route = ModalRoute.of(context);
    // Only pop a route that's still on the stack. Popping one that has already
    // been removed - or popping while the navigator is mid-transition - takes
    // the screen *below* this one with it.
    if (route == null || !route.isCurrent) return;
    AppLog.auth('SignInScreen popping itself, sign-in complete');
    Navigator.of(context).pop();
  }

  AuthState get authState => widget.authState;
  bool get isOwnerPath => widget.isOwnerPath;

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
