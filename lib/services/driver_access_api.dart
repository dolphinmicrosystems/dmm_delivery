import 'dart:convert';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:http/http.dart' as http;

import '../config/infra_config.dart';
import '../util/app_log.dart';

/// Thrown when removing or restoring a driver doesn't go through. Carries a
/// message already fit to show a person, the same contract as
/// `RiderBoardException` - the screen has no better idea than this class does
/// what went wrong, and a raw exception toString in a snackbar reads as a crash.
class DriverAccessException implements Exception {
  DriverAccessException(this.message);

  final String message;

  @override
  String toString() => message;
}

/// What actually happened, so the screen can say so rather than guess.
class DriverAccessResult {
  const DriverAccessResult({required this.removed, required this.accountChanged});

  final bool removed;

  /// False when the driver had never signed in. There is no Firebase account
  /// behind a pending invitation, so there was nothing to switch off - and
  /// "invitation withdrawn" is a different sentence from "signed out".
  final bool accountChanged;

  factory DriverAccessResult.fromJson(Map<String, dynamic> json) =>
      DriverAccessResult(removed: json['removed'] == true, accountChanged: json['account_changed'] == true);
}

/// Removing and restoring a driver, via the `driver-access` Cloud Function.
///
/// The one owner action that is not a Firestore write, and it has to be.
/// Removing somebody is two changes in two systems: a `removed_at` field,
/// which refuses their *next* sign-in, and disabling their Firebase account,
/// which ends the session they are already in. Only the second actually stops
/// a driver who is signed in right now - they are not signing in again, they
/// are quietly renewing a refresh token, and no Firestore field interrupts
/// that. Disabling an account needs the Admin SDK, which a mobile client
/// cannot and must never hold.
///
/// So this app asks a function to do both, and `firestore.rules` refuses a
/// client write that sets `removed_at` at all - along with refusing a
/// `driver_invitations` delete outright, because nothing here deletes a
/// driver. See `application/manage_driver_access.py`.
///
/// The endpoint is IAM-open (`allUsers`) but not public: it verifies the
/// caller's Firebase ID token, requires `role: owner`, and then requires that
/// the target driver was invited by *this* owner. That last check is what
/// stops one owner disabling another owner's drivers.
class DriverAccessApi {
  DriverAccessApi({http.Client? client}) : _client = client ?? http.Client();

  final http.Client _client;

  /// Switches a driver off: their account is disabled and their record is
  /// flagged. Nothing is deleted.
  Future<DriverAccessResult> remove(String email) => _post(email, 'remove');

  /// Switches a driver back on, and the only way back in - a removed driver
  /// cannot sign in to ask, so it has to be the owner.
  Future<DriverAccessResult> restore(String email) => _post(email, 'restore');

  Future<DriverAccessResult> _post(String email, String action) async {
    if (InfraConfig.driverAccessUrl.isEmpty) {
      // The generator leaves this empty when the function isn't deployed in
      // the target project. Saying so beats a Uri.parse('') failing later as
      // an unrelated-looking network error.
      throw DriverAccessException('Removing a driver isn\'t configured for this build.');
    }

    final user = FirebaseAuth.instance.currentUser;
    if (user == null) throw DriverAccessException('You are signed out.');

    // Fetched per request, never cached at sign-in: a Firebase ID token
    // expires after an hour, and getIdToken() returns the cached one while
    // it's still valid and refreshes it when it isn't.
    final token = await user.getIdToken();

    AppLog.owner('driver access request', {'action': action});

    final http.Response response;
    try {
      response = await _client
          .post(
            Uri.parse(InfraConfig.driverAccessUrl),
            headers: {'Authorization': 'Bearer $token', 'Content-Type': 'application/json'},
            body: jsonEncode({'email': email, 'action': action}),
          )
          // Shorter than the board's 60s: this is one document read, one
          // account update and one write, none of which grow with the size of
          // the business. A cold start is the only slow part.
          .timeout(const Duration(seconds: 30));
    } catch (e, s) {
      AppLog.owner.error('driver access request failed', e, s, {'action': action});
      throw DriverAccessException('Couldn\'t reach the server. Check your connection and try again.');
    }

    if (response.statusCode != 200) {
      AppLog.owner.error('driver access returned ${response.statusCode}', response.body, null, {
        'action': action,
      });
      throw DriverAccessException(switch (response.statusCode) {
        401 => 'Your session expired. Sign out and back in.',
        403 => 'This account isn\'t an owner.',
        // The function answers 404 both for an address nobody invited and for
        // another owner's driver, on purpose - so this sentence has to cover
        // both without implying which.
        404 => 'That driver isn\'t on your roster.',
        _ => 'The server returned an error (${response.statusCode}).',
      });
    }

    AppLog.owner('driver access done', {'action': action});
    return DriverAccessResult.fromJson(jsonDecode(response.body) as Map<String, dynamic>);
  }
}
