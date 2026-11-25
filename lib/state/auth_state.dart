import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:google_sign_in/google_sign_in.dart';

import '../config/infra_config.dart';
import '../driver/driver_presence.dart';
import '../models/auth_error_message.dart';
import '../models/driver_invitation.dart';
import '../models/owner_profile.dart';
import '../notifications/push_notifications.dart';
import '../observability/crash_reporting.dart';
import '../util/app_log.dart';

/// Who the signed-in Firebase user is, per the `role` custom claim the
/// backend's beforeSignIn blocking function sets (see dmm-delivery-app's
/// application/handle_sign_in.py). `rider` is the backend's/Firestore rules'
/// term for what this app calls a driver.
enum AuthRole { owner, driver }

/// The backend's spelling of a role (`rider` for a driver) to the app's.
extension AuthRoleClaim on AuthRole {
  static AuthRole? parse(String? claim) => switch (claim) {
    'owner' => AuthRole.owner,
    'rider' => AuthRole.driver,
    _ => null,
  };
}

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

  /// The raw code behind [errorMessage], shown small under it, for support.
  /// Null when the message already says everything (a refusal from the backend).
  String? errorDetail;

  /// True from tapping "Continue with Google" until that sign-in has been
  /// checked against the role the person chose. While it is set the token
  /// listener holds back: publishing `signedIn` early would show the wrong
  /// home screen for a moment before [signInWithGoogle] throws them out.
  bool _signingIn = false;

  Future<void> _onIdTokenChanged(User? user) async {
    AppLog.auth('idTokenChanged fired', {
      'uid': user?.uid,
      'email': user?.email,
      'statusBefore': status.name,
    });
    if (user == null) {
      this.user = null;
      role = null;
      ownerUid = null;
      // A refused sign-in signs out on purpose; keep its message on screen.
      // AuthGate shows the same screen for `error` as for `signedOut`.
      if (status != AuthStatus.error) status = AuthStatus.signedOut;
      AppLog.auth('no user -> ${status.name}');
      notifyListeners();
      return;
    }
    if (_signingIn) {
      AppLog.auth('token change held until sign-in has checked the role');
      return;
    }
    // A late event for an account already signed out again (a refused
    // sign-in) must not resurrect it.
    if (FirebaseAuth.instance.currentUser?.uid != user.uid) {
      AppLog.auth('stale token change ignored');
      return;
    }
    _apply(user, await user.getIdTokenResult());
  }

  /// Reads the backend's claims off [token] and decides the status.
  void _apply(User user, IdTokenResult token) {
    this.user = user;
    final claim = token.claims?['role'] as String?;
    // The tenant key, minted alongside `role` by before_sign_in_fn.py. For an
    // owner it is their own uid; for a driver it is the uid of the owner who
    // invited them. Every owner-scoped query filters on it, and
    // firestore.rules compares it - so a session without it can read nothing,
    // which is the correct outcome for a token that predates this claim.
    ownerUid = token.claims?['owner_uid'] as String?;
    // The full claim set matters here, not just `role`: a missing role claim
    // is the difference between "signed in" and the needsRole dead-end, and
    // it's worth seeing exactly what the backend actually returned.
    AppLog.auth('token claims read', {
      'roleClaim': claim,
      'hasOwnerUid': ownerUid != null,
      'allClaims': token.claims?.keys.toList(),
      'authTime': token.authTime,
    });
    role = AuthRoleClaim.parse(claim);
    status = switch ((role, ownerUid)) {
      (null, _) => AuthStatus.needsRole,
      (_, null) => AuthStatus.staleSession,
      _ => AuthStatus.signedIn,
    };
    AppLog.auth('status resolved', {'role': role?.name, 'status': status.name});
    notifyListeners();
  }

  /// Signs in with Google as the role the person chose on the first screen.
  ///
  /// The role itself is the backend's decision (the `role` claim), not the
  /// button's. The button is checked against it: an owner who tapped
  /// "Driver", or a driver who tapped "Owner", is signed straight back out
  /// and told which one to pick. Letting it through quietly lands them in a
  /// different app from the one they asked for, which reads as a bug.
  Future<void> signInWithGoogle({required AuthRole chosen}) async {
    AppLog.auth('signInWithGoogle start', {'statusBefore': status.name, 'chosen': chosen.name});
    _signingIn = true;
    errorMessage = null;
    errorDetail = null;
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
      final signedIn = userCredential.user;
      final refreshed = await signedIn?.getIdTokenResult(true);
      AppLog.auth('forced token refresh done', {'roleClaim': refreshed?.claims?['role']});
      // Never leave the spinner up: the catch-all below turns this into a message.
      if (signedIn == null || refreshed == null) throw StateError('signed in, but no user or token');

      final actual = AuthRoleClaim.parse(refreshed.claims?['role'] as String?);
      if (actual != null && actual != chosen) {
        AppLog.auth('role does not match the button chosen; signing out', {
          'chosen': chosen.name,
          'actual': actual.name,
        });
        errorMessage =
            SignInFailure.wrongRole(chosen: chosen.name, actual: actual.name, email: signedIn.email);
        errorDetail = null;
        status = AuthStatus.error;
        _signingIn = false;
        await FirebaseAuth.instance.signOut();
        await _googleSignIn.signOut();
        notifyListeners();
        return;
      }
      _signingIn = false;
      _apply(signedIn, refreshed);
    } on FirebaseAuthException catch (e, s) {
      AppLog.auth.error('FirebaseAuthException during sign-in', e, s, {'code': e.code});
      // A blocking-function rejection arrives wrapped in Identity Platform's
      // JSON envelope, so the sentence handle_sign_in.py wrote for a person
      // has to be dug back out - see AuthErrorMessage.
      errorMessage = AuthErrorMessage.humanize(e.message, fallback: e.code);
      status = AuthStatus.error;
      notifyListeners();
    } on GoogleSignInException catch (e, s) {
      // Reported and shown for every code, `canceled` included. Android's
      // Credential Manager reports more than the Back button as "canceled":
      // no usable Google account on the phone, an out-of-date Play services
      // and a sign-in setup problem can all arrive that way. Treating it as
      // a quiet sign-out is how an owner once watched sign-in "do nothing"
      // while nothing reached Firebase and nobody could see why.
      AppLog.auth.error('GoogleSignInException during sign-in', e, s, {'code': e.code.name});
      final failure = SignInFailure.google(e.code.name, e.description);
      errorMessage = failure.message;
      errorDetail = failure.detail;
      status = AuthStatus.error;
      notifyListeners();
    } catch (e, s) {
      // Anything else (a platform error from a plugin) must not escape and
      // leave the screen spinning or silently reset.
      AppLog.auth.error('unexpected error during sign-in', e, s, {'type': e.runtimeType.toString()});
      final failure = SignInFailure.unexpected(e);
      errorMessage = failure.message;
      errorDetail = failure.detail;
      status = AuthStatus.error;
      notifyListeners();
    } finally {
      _signingIn = false;
    }
  }

  Future<void> signOut() async {
    AppLog.auth('signOut requested', {'uid': user?.uid});
    // Before signing out, while the rules still know who is asking: a driver
    // goes offline (their owners are told), and this phone stops receiving
    // this person's notifications.
    final uid = user?.uid;
    if (role == AuthRole.driver && uid != null) {
      await DriverPresence.goOfflineOnSignOut(uid: uid, ownerUid: ownerUid);
    }
    await PushNotifications.instance.unregister();
    await CrashReporting.identify(uid: null, role: null);
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
}
