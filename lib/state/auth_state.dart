import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:google_sign_in/google_sign_in.dart';

import '../config/infra_config.dart';
import '../util/app_log.dart';

/// Who the signed-in Firebase user is, per the `role` custom claim the
/// backend's beforeSignIn blocking function sets (see dmm-delivery-app's
/// application/handle_sign_in.py). `rider` is the backend's/Firestore rules'
/// term for what this app calls a driver.
enum AuthRole { owner, driver }

enum AuthStatus { loading, signedOut, needsRole, signedIn, error }

/// Wraps Firebase Auth + Google Sign-In. A single instance lives for the
/// app's lifetime (created in main.dart), separate from AppState - that
/// class owns the existing mock prototype data/navigation, this one owns
/// real identity.
class AuthState extends ChangeNotifier {
  AuthState() {
    AppLog.auth('AuthState created, subscribing to idTokenChanges');
    FirebaseAuth.instance.idTokenChanges().listen(_onIdTokenChanged);
  }

  final GoogleSignIn _googleSignIn = GoogleSignIn.instance;
  bool _googleSignInReady = false;

  AuthStatus status = AuthStatus.loading;
  User? user;
  AuthRole? role;
  String? errorMessage;

  Future<void> _onIdTokenChanged(User? user) async {
    AppLog.auth('idTokenChanged fired', {'uid': user?.uid, 'email': user?.email, 'statusBefore': status.name});
    this.user = user;
    if (user == null) {
      status = AuthStatus.signedOut;
      role = null;
      AppLog.auth('no user -> signedOut');
      notifyListeners();
      return;
    }

    final tokenResult = await user.getIdTokenResult();
    final claim = tokenResult.claims?['role'] as String?;
    // The full claim set matters here, not just `role`: a missing role claim
    // is the difference between "signed in" and the needsRole dead-end, and
    // it's worth seeing exactly what the backend actually returned.
    AppLog.auth('token claims read', {
      'roleClaim': claim,
      'allClaims': tokenResult.claims?.keys.toList(),
      'authTime': tokenResult.authTime,
    });
    role = switch (claim) {
      'owner' => AuthRole.owner,
      'rider' => AuthRole.driver,
      _ => null,
    };
    status = role == null ? AuthStatus.needsRole : AuthStatus.signedIn;
    AppLog.auth('status resolved', {'role': role?.name, 'status': status.name});
    notifyListeners();
  }

  Future<void> signInWithGoogle() async {
    AppLog.auth('signInWithGoogle start', {'statusBefore': status.name});
    errorMessage = null;
    status = AuthStatus.loading;
    notifyListeners();

    try {
      if (!_googleSignInReady) {
        AppLog.auth('initializing GoogleSignIn', {'serverClientId': InfraConfig.googleSignInServerClientId});
        await _googleSignIn.initialize(serverClientId: InfraConfig.googleSignInServerClientId);
        _googleSignInReady = true;
        AppLog.auth('GoogleSignIn initialized');
      }
      final googleUser = await _googleSignIn.authenticate();
      AppLog.auth('google account authenticated', {'email': googleUser.email, 'id': googleUser.id});
      final googleAuth = googleUser.authentication;
      // A null idToken here yields a credential Firebase silently refuses,
      // which reads downstream as "signed in but nothing happened" - so log
      // its presence explicitly rather than the token itself.
      AppLog.auth('google auth tokens', {'hasIdToken': googleAuth.idToken != null});
      final credential = GoogleAuthProvider.credential(idToken: googleAuth.idToken);
      final userCredential = await FirebaseAuth.instance.signInWithCredential(credential);
      AppLog.auth('firebase signInWithCredential ok', {
        'uid': userCredential.user?.uid,
        'isNewUser': userCredential.additionalUserInfo?.isNewUser,
      });
      // Force a fresh token fetch rather than trusting whatever claims are
      // already cached locally - the beforeSignIn blocking function sets the
      // role claim server-side as part of *this* sign-in, and a stale local
      // token snapshot here would otherwise read back as "no role yet".
      final refreshed = await userCredential.user?.getIdTokenResult(true);
      AppLog.auth('forced token refresh done', {'roleClaim': refreshed?.claims?['role']});
      // _onIdTokenChanged fires from the listener above (forceRefresh above
      // triggers it again with the up-to-date claims) and sets status.
    } on FirebaseAuthException catch (e, s) {
      AppLog.auth.error('FirebaseAuthException during sign-in', e, s, {'code': e.code});
      errorMessage = e.message ?? e.code;
      status = AuthStatus.error;
      notifyListeners();
    } on GoogleSignInException catch (e, s) {
      if (e.code != GoogleSignInExceptionCode.canceled) {
        AppLog.auth.error('GoogleSignInException during sign-in', e, s, {'code': e.code.name});
        errorMessage = e.description ?? e.code.name;
        status = AuthStatus.error;
        notifyListeners();
      } else {
        AppLog.auth('sign-in canceled by user -> signedOut');
        status = AuthStatus.signedOut;
        notifyListeners();
      }
    }
  }

  Future<void> signOut() async {
    AppLog.auth('signOut requested', {'uid': user?.uid});
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

  /// Drivers who have accepted - the roster behind the Owner's Maps board
  /// and the Settings driver list.
  Stream<QuerySnapshot<Map<String, dynamic>>> acceptedDrivers() {
    return FirebaseFirestore.instance
        .collection('driver_invitations')
        .where('accepted_at', isNotEqualTo: null)
        .snapshots();
  }

  /// Invitations sent but not yet accepted, for the Owner home "Invite
  /// riders" count. `accepted_at` is null until before_sign_in_fn.py sets
  /// it, so this and [acceptedDrivers] partition the collection.
  Stream<QuerySnapshot<Map<String, dynamic>>> pendingInvites() {
    return FirebaseFirestore.instance
        .collection('driver_invitations')
        .where('accepted_at', isNull: true)
        .snapshots();
  }
}
