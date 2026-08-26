import 'dart:convert';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:http/http.dart' as http;

import '../config/infra_config.dart';
import '../models/rider_board_entry.dart';
import '../models/rider_map_data.dart';
import '../util/app_log.dart';

/// Thrown when the board can't be loaded. Carries a message already fit to
/// show a person - the screen has no better idea than this class does what
/// went wrong, and a raw exception toString on a card reads as a crash.
class RiderBoardException implements Exception {
  RiderBoardException(this.message);

  final String message;

  @override
  String toString() => message;
}

/// Reads the Owner's rider board from the `rider-board` Cloud Function.
///
/// The endpoint is IAM-open (`allUsers`) but not public: it verifies the
/// caller's Firebase ID token and requires a `role: owner` claim before it
/// reads anything. That's why this sends a bearer token rather than relying
/// on the Cloud Run IAM layer, which cannot evaluate a Firebase token at all.
class RiderBoardApi {
  RiderBoardApi({http.Client? client}) : _client = client ?? http.Client();

  final http.Client _client;

  /// One rider's route shape and current position, for the rider detail map.
  Future<RiderMapData> fetchRiderMap(String riderKey) async {
    final body = await _get('/rider/$riderKey');
    return RiderMapData.fromJson(body);
  }

  /// Shared request path: auth, timeout and status handling are identical for
  /// every endpoint on this function, and duplicating them per call is how
  /// they drift apart.
  Future<Map<String, dynamic>> _get(String path) async {
    if (InfraConfig.riderBoardUrl.isEmpty) {
      // The generator leaves this empty when the function isn't deployed in
      // the target project. Saying so beats a Uri.parse('') that fails as an
      // unrelated-looking network error.
      throw RiderBoardException('The rider-board endpoint isn\'t configured for this build.');
    }

    final user = FirebaseAuth.instance.currentUser;
    if (user == null) throw RiderBoardException('You are signed out.');

    // Fetched per request, never cached at sign-in: a Firebase ID token
    // expires after an hour, and getIdToken() returns the cached one while
    // it's still valid and silently refreshes it when it isn't. Holding the
    // token from login would start returning 401s an hour into a session.
    final token = await user.getIdToken();

    final uri = Uri.parse('${InfraConfig.riderBoardUrl}$path');
    AppLog.owner('api request', {'path': path.isEmpty ? '/' : path});

    final http.Response response;
    try {
      response = await _client
          .get(uri, headers: {'Authorization': 'Bearer $token'})
          // The board endpoint parses every PDF in the bucket, so a cold start
          // on a large bucket is genuinely slow - but an unbounded wait leaves
          // the screen spinning forever with no way to tell it from a hang.
          .timeout(const Duration(seconds: 60));
    } catch (e, s) {
      AppLog.owner.error('api request failed', e, s, {'path': path});
      throw RiderBoardException('Couldn\'t reach the server. Check your connection and try again.');
    }

    if (response.statusCode != 200) {
      AppLog.owner.error('api returned ${response.statusCode}', response.body, null, {'path': path});
      throw RiderBoardException(switch (response.statusCode) {
        401 => 'Your session expired. Sign out and back in.',
        403 => 'This account isn\'t an owner.',
        404 => 'That driver isn\'t on the board any more.',
        _ => 'The server returned an error (${response.statusCode}).',
      });
    }

    return jsonDecode(response.body) as Map<String, dynamic>;
  }

  /// This owner's drivers and their assigned runs.
  ///
  /// The endpoint reads Firestore scoped to the caller's `owner_uid` claim.
  /// It used to walk the whole run_sheets bucket and re-parse every PDF,
  /// which is why the timeout above is 60 seconds - that can come down once
  /// this has run in anger for a while.
  Future<RiderBoard> fetchBoard() async {
    final body = await _get('');
    final board = RiderBoard.fromJson(body);

    AppLog.owner('rider board loaded', {
      'riders': board.riders.length,
      'unassignedRuns': board.unassignedRuns.length,
    });

    return board;
  }
}
