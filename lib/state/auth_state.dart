import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:google_sign_in/google_sign_in.dart';

import '../config/infra_config.dart';
import '../models/auth_error_message.dart';
import '../models/driver_invitation.dart';
import '../models/owner_profile.dart';
import '../util/app_log.dart';

/// Who the signed-in Firebase user is, per the `role` custom claim the
/// backend's beforeSignIn blocking function sets (see dmm-delivery-app's
/// application/handle_sign_in.py). `rider` is the backend's/Firestore rules'
/// term for what this app calls a driver.
enum AuthRole { owner, driver }

enum AuthStatus {
  loading,
  signedOut,
  needsRole,

  /// Signed in with a role, but on a token minted before `owner_uid`
  /// existed - so it belongs to no business and every scoped query returns
  /// nothing.
  ///
  /// Worth its own state rather than letting it through as `signedIn`: the
  /// app would render perfectly and be completely empty, which reads as data
  /// loss. The fix is one sign-out away, and nothing but a screen saying so
  /// will lead anyone to it.
  staleSession,

  signedIn,
  error,
}

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

  /// The business this session belongs to - an owner's own uid, or for a
  /// driver the uid of the owner who invited them. Null until the token is
  /// read, and on any token minted before this claim existed.
  String? ownerUid;

  String? errorMessage;

  Future<void> _onIdTokenChanged(User? user) async {
    AppLog.auth('idTokenChanged fired', {
      'uid': user?.uid,
      'email': user?.email,
      'statusBefore': status.name,
    });
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
    // The tenant key, minted alongside `role` by before_sign_in_fn.py. For an
    // owner it is their own uid; for a driver it is the uid of the owner who
    // invited them. Every owner-scoped query filters on it, and
    // firestore.rules compares it - so a session without it can read nothing,
    // which is the correct outcome for a token that predates this claim.
    ownerUid = tokenResult.claims?['owner_uid'] as String?;
    // The full claim set matters here, not just `role`: a missing role claim
    // is the difference between "signed in" and the needsRole dead-end, and
    // it's worth seeing exactly what the backend actually returned.
    AppLog.auth('token claims read', {
      'roleClaim': claim,
      'hasOwnerUid': ownerUid != null,
      'allClaims': tokenResult.claims?.keys.toList(),
      'authTime': tokenResult.authTime,
    });
    role = switch (claim) {
      'owner' => AuthRole.owner,
      'rider' => AuthRole.driver,
      _ => null,
    };
    status = switch ((role, ownerUid)) {
      (null, _) => AuthStatus.needsRole,
      (_, null) => AuthStatus.staleSession,
      _ => AuthStatus.signedIn,
    };
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
      // A blocking-function rejection arrives wrapped in Identity Platform's
      // JSON envelope, so the sentence handle_sign_in.py wrote for a person
      // has to be dug back out - see AuthErrorMessage.
      errorMessage = AuthErrorMessage.humanize(e.message, fallback: e.code);
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

  /// The signed-in account's own details.
  ///
  /// Placeholder data - nothing in the delivery pipeline reads it. A missing
  /// document is [OwnerProfile.empty] rather than an error: an account that
  /// has never opened the profile screen has no document, and that is the
  /// normal state, not a failure.
  Stream<OwnerProfile> profile() {
    final uid = user?.uid;
    if (uid == null) return Stream.value(OwnerProfile.empty);
    return FirebaseFirestore.instance
        .collection('user_profiles')
        .doc(uid)
        .snapshots()
        .map((snap) => OwnerProfile.fromMap(snap.data()));
  }

  /// Writes the profile as a whole-document replace.
  ///
  /// Not a merge, deliberately: `toMap()` omits fields the owner cleared, and
  /// a replace is what removes their keys. A merge would leave a cleared age
  /// sitting in the document for ever, with no way to take it back out.
  Future<void> saveProfile(OwnerProfile profile) async {
    AppLog.owner('saving profile', {'fields': profile.toMap().keys.toList()});
    await FirebaseFirestore.instance.collection('user_profiles').doc(user!.uid).set({
      ...profile.toMap(),
      'updated_at': FieldValue.serverTimestamp(),
    });
    AppLog.owner('profile saved', {});
  }

  /// Every driver the owner has ever invited, in one stream.
  ///
  /// Deliberately unfiltered, where this used to be two queries partitioning
  /// the collection on `accepted_at`. That split could only ever describe two
  /// states, and there are three: an invitation past its `expires_at` is not
  /// pending - the driver's next sign-in will be rejected outright by
  /// `handle_sign_in.py` - but it has not been accepted either, so it fell
  /// into the pending bucket and reported itself as still waiting. The one
  /// row needing the owner's attention was the one row they could not see.
  ///
  /// Expiry is a comparison against the clock, and Firestore cannot express
  /// "expired" as a query that stays true as time passes, so the sorting and
  /// the state live in [DriverInvitation] instead. The collection is one row
  /// per driver; reading it whole costs nothing worth optimising.
  Stream<QuerySnapshot<Map<String, dynamic>>> invitations() {
    // Scoped on `invited_by` rather than a separate tenant field: for a
    // driver invitation the inviting owner *is* the business, and
    // handle_sign_in already reads this exact field to decide which business
    // the driver joins. A second field meaning the same thing is a second
    // field that can disagree.
    return FirebaseFirestore.instance
        .collection('driver_invitations')
        .where('invited_by', isEqualTo: ownerUid)
        .snapshots();
  }

  /// Every route assignment this business has ever made.
  ///
  /// Streamed whole and grouped client-side rather than queried per route:
  /// which row is in force is a comparison against the clock, and Firestore
  /// cannot express that as a query that stays true as time passes. One
  /// query feeds every card on the routes list; one query per card would be
  /// N reads to answer a question about a handful of rows.
  Stream<QuerySnapshot<Map<String, dynamic>>> routeAssignments() {
    return FirebaseFirestore.instance
        .collection('route_assignments')
        .where('owner_uid', isEqualTo: ownerUid)
        .snapshots();
  }

  /// How long a newly sent invitation stays valid, in days.
  ///
  /// A stream rather than a one-off read because the invite dialog and the
  /// settings control are on screen at the same time - the dialog has to
  /// quote the deadline the owner just changed, not the one it opened with.
  ///
  /// A missing document is not an error: it is a project that has never
  /// changed the setting, and [InvitationTtl.fallback] is what the client
  /// hardcoded before this was configurable.
  Stream<int> invitationTtlDays() {
    return FirebaseFirestore.instance
        .collection('app_settings')
        .doc(ownerUid ?? '-')
        .snapshots()
        .map((snap) => InvitationTtl.sanitize(snap.data()?['invitation_ttl_days']));
  }

  /// Writes the invitation validity period.
  ///
  /// Applies to invitations sent *after* it, and to nothing already out
  /// there: `expires_at` is stamped onto each document when it is written, so
  /// shortening the window cannot retroactively expire an invitation somebody
  /// is already holding. Resending is what moves an existing deadline.
  Future<void> setInvitationTtlDays(int days) async {
    AppLog.owner('setting invitation ttl', {'days': days});
    // One settings document per business - the invite window is a property
    // of this owner's operation, not of the app.
    await FirebaseFirestore.instance.collection('app_settings').doc(ownerUid!).set({
      'invitation_ttl_days': days,
    });
  }
}
