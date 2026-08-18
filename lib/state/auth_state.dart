import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:google_sign_in/google_sign_in.dart';

/// Who the signed-in Firebase user is, per the `role` custom claim the
/// backend's beforeSignIn blocking function sets (see dmm-delivery-app's
/// application/handle_sign_in.py). `rider` is the backend's/Firestore rules'
/// term for what this app calls a driver.
enum AuthRole { owner, driver }

enum AuthStatus { loading, signedOut, needsRole, signedIn, error }

/// The OAuth web client ID backing Firebase's Google sign-in provider - the
/// same value as infrastructure/terraform/terraform.tfvars'
/// google_signin_client_id in dmm-delivery-app. Not a secret (it's a public
/// identifier apps embed directly), but Android's GoogleSignIn needs it
/// explicitly as `serverClientId` to request an ID token Firebase can verify
/// - without it, GoogleSignIn.instance.initialize() throws on Android.
const _googleSignInServerClientId =
    '146112277848-k549kfqtmg1vsbvd0st2qmpsjtlmq06k.apps.googleusercontent.com';

/// Wraps Firebase Auth + Google Sign-In. A single instance lives for the
/// app's lifetime (created in main.dart), separate from AppState - that
/// class owns the existing mock prototype data/navigation, this one owns
/// real identity.
class AuthState extends ChangeNotifier {
  AuthState() {
    FirebaseAuth.instance.idTokenChanges().listen(_onIdTokenChanged);
  }

  final GoogleSignIn _googleSignIn = GoogleSignIn.instance;
  bool _googleSignInReady = false;

  AuthStatus status = AuthStatus.loading;
  User? user;
  AuthRole? role;
  String? errorMessage;

  Future<void> _onIdTokenChanged(User? user) async {
    this.user = user;
    if (user == null) {
      status = AuthStatus.signedOut;
      role = null;
      notifyListeners();
      return;
    }

    final tokenResult = await user.getIdTokenResult();
    final claim = tokenResult.claims?['role'] as String?;
    role = switch (claim) {
      'owner' => AuthRole.owner,
      'rider' => AuthRole.driver,
      _ => null,
    };
    status = role == null ? AuthStatus.needsRole : AuthStatus.signedIn;
    notifyListeners();
  }

  Future<void> signInWithGoogle() async {
    errorMessage = null;
    status = AuthStatus.loading;
    notifyListeners();

    try {
      if (!_googleSignInReady) {
        await _googleSignIn.initialize(serverClientId: _googleSignInServerClientId);
        _googleSignInReady = true;
      }
      final googleUser = await _googleSignIn.authenticate();
      final googleAuth = googleUser.authentication;
      final credential = GoogleAuthProvider.credential(idToken: googleAuth.idToken);
      final userCredential = await FirebaseAuth.instance.signInWithCredential(credential);
      // Force a fresh token fetch rather than trusting whatever claims are
      // already cached locally - the beforeSignIn blocking function sets the
      // role claim server-side as part of *this* sign-in, and a stale local
      // token snapshot here would otherwise read back as "no role yet".
      await userCredential.user?.getIdTokenResult(true);
      // _onIdTokenChanged fires from the listener above (forceRefresh above
      // triggers it again with the up-to-date claims) and sets status.
    } on FirebaseAuthException catch (e) {
      errorMessage = e.message ?? e.code;
      status = AuthStatus.error;
      notifyListeners();
    } on GoogleSignInException catch (e) {
      if (e.code != GoogleSignInExceptionCode.canceled) {
        errorMessage = e.description ?? e.code.name;
        status = AuthStatus.error;
        notifyListeners();
      } else {
        status = AuthStatus.signedOut;
        notifyListeners();
      }
    }
  }

  Future<void> signOut() async {
    await FirebaseAuth.instance.signOut();
  }

  /// DMM-01/02: writes the invitation Firestore write-then-trigger flow
  /// documented in dmm-delivery-app's README ("Driver invitations") relies
  /// on. Only reachable from the Owner Settings screen, and only succeeds
  /// against firestore.rules if the caller currently holds role: owner.
  Future<void> inviteDriver(String email) async {
    final normalized = email.trim().toLowerCase();
    await FirebaseFirestore.instance.collection('driver_invitations').doc(normalized).set({
      'driver_email': normalized,
      'invited_by': user!.uid,
      'invited_at': FieldValue.serverTimestamp(),
      'expires_at': Timestamp.fromDate(DateTime.now().add(const Duration(days: 7))),
      'accepted_at': null,
    });
  }

  Stream<QuerySnapshot<Map<String, dynamic>>> acceptedDrivers() {
    return FirebaseFirestore.instance
        .collection('driver_invitations')
        .where('accepted_at', isNotEqualTo: null)
        .snapshots();
  }
}
