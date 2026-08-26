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
  /// The message currently on screen in the dialog, so a rebuild does not
  /// stack a second copy of it. Cleared when the status leaves `error`, which
  /// is what lets a *new* failed attempt raise the dialog again.
  String? _shownError;

  @override
  void initState() {
    super.initState();
    widget.authState.addListener(_onAuthChanged);
    // A session can already be live before this frame - a restored session, or
    // a race where sign-in completed between the push and this initState - and
    // no further notification would ever arrive to trigger the listener.
    WidgetsBinding.instance.addPostFrameCallback((_) => _popWhenSignedIn());
  }

  @override
  void dispose() {
    widget.authState.removeListener(_onAuthChanged);
    super.dispose();
  }

  /// The registered listener. `_popWhenSignedIn` is left exactly as it was -
  /// see the regression guard at the top of this file - and the error dialog
  /// is a second, independent reaction to the same notification.
  void _onAuthChanged() {
    _popWhenSignedIn();
    _showErrorDialog();
  }

  void _showErrorDialog() {
    if (!mounted) return;

    if (widget.authState.status != AuthStatus.error) {
      // Leaving the error state re-arms the dialog for the next attempt.
      _shownError = null;
      return;
    }

    final message = widget.authState.errorMessage ?? 'Something went wrong.';
    if (message == _shownError) return;

    final route = ModalRoute.of(context);
    if (route == null || !route.isCurrent) return;

    _shownError = message;
    // Deferred to after the frame: notifyListeners can land mid-build, and
    // showDialog during build throws.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      AppLog.auth('SignInScreen showing error dialog');
      showDialog<void>(
        context: context,
        builder: (dialogContext) => _SignInErrorDialog(message: message),
      );
    });
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
                // No inline error panel: a refusal is a conversation, not a
                // footnote under a button, and a box that appears above the
                // button shifts the thing someone is reaching for. It is a
                // dialog now - see _showErrorDialog.
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

/// The refusal, as a dialog rather than a panel wedged above the button.
///
/// Sized and worded for the commonest case by far: someone signed in with the
/// wrong Google account, or with one nobody has invited. That is not an error
/// in the crash sense - the system worked - so it is styled as an answer, not
/// as a failure. The icon is a closed envelope rather than a red warning
/// triangle for the same reason.
class _SignInErrorDialog extends StatelessWidget {
  const _SignInErrorDialog({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: Colors.white,
      insetPadding: const EdgeInsets.symmetric(horizontal: 32),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(24, 28, 24, 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 56,
              height: 56,
              decoration: const BoxDecoration(color: Color(0xFFFCEAEA), shape: BoxShape.circle),
              alignment: Alignment.center,
              child: const Icon(Icons.mark_email_unread_outlined, size: 26, color: Color(0xFFB42318)),
            ),
            const SizedBox(height: 18),
            const Text(
              'Can\'t sign you in',
              style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800, letterSpacing: -0.2),
            ),
            const SizedBox(height: 10),
            Text(
              message,
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 13.5, color: AppColors.inkMuted, height: 1.45),
            ),
            const SizedBox(height: 22),
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: () => Navigator.of(context).pop(),
                style: FilledButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                ),
                // Not "OK": the dialog is telling someone what to do next, and
                // this is them acknowledging it rather than dismissing a fault.
                child: const Text('Got it'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
