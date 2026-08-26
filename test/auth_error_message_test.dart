import 'package:flutter_test/flutter_test.dart';

import 'package:dmm_delivery/models/auth_error_message.dart';

void main() {
  group('AuthErrorMessage.humanize', () {
    test('digs the sentence out of the envelope Identity Platform wraps it in', () {
      // Verbatim from a real rejection: handle_sign_in.py writes a sentence
      // for a person, and this is what reaches the client.
      const raw =
          '{"error":{"message":"jagdish.lal0665@gmail.com hasn\'t been invited '
          'to this app. Ask the owner to send an invitation to this address, '
          'then sign in again.","status":"PERMISSION_DENIED"}}';

      expect(
        AuthErrorMessage.humanize(raw),
        'jagdish.lal0665@gmail.com hasn\'t been invited to this app. Ask the '
        'owner to send an invitation to this address, then sign in again.',
      );
    });

    test('handles the expired-invitation rejection too', () {
      const raw =
          '{"error":{"message":"Your invitation expired on 01 Sep 2026. Ask the '
          'owner to invite you again.","status":"PERMISSION_DENIED"}}';

      expect(AuthErrorMessage.humanize(raw), startsWith('Your invitation expired on'));
    });

    test('strips the blocking-function prefix Firebase adds', () {
      const raw =
          'BLOCKING_FUNCTION_ERROR_RESPONSE : {"error":{"message":"Nope.","status":"PERMISSION_DENIED"}}';

      expect(AuthErrorMessage.humanize(raw), 'Nope.');
    });

    test('unwraps a message that was wrapped twice', () {
      // Seen when a blocking function rejects: the inner payload is itself a
      // JSON string that has to be decoded again.
      const inner = '{"error":{"message":"Really nope.","status":"PERMISSION_DENIED"}}';
      final raw = '{"error":{"message":${_quoted(inner)},"status":"PERMISSION_DENIED"}}';

      expect(AuthErrorMessage.humanize(raw), 'Really nope.');
    });

    test('leaves a plain sentence alone', () {
      // Every other FirebaseAuthException - a wrong password, a network
      // failure - already reads fine and must not be mangled.
      const raw = 'The email address is badly formatted.';

      expect(AuthErrorMessage.humanize(raw), raw);
    });

    test('leaves text that merely mentions a brace alone', () {
      const raw = 'Something failed near { here';

      expect(AuthErrorMessage.humanize(raw), raw);
    });

    test('falls back rather than showing an empty box', () {
      expect(AuthErrorMessage.humanize(null), 'Something went wrong.');
      expect(AuthErrorMessage.humanize('   '), 'Something went wrong.');
      expect(AuthErrorMessage.humanize(null, fallback: 'internal-error'), 'internal-error');
    });

    test('an envelope with no message falls back to the raw text', () {
      // Better than inventing a sentence: whatever the server said is still
      // more use to whoever has to debug it.
      const raw = '{"error":{"status":"PERMISSION_DENIED"}}';

      expect(AuthErrorMessage.humanize(raw), raw);
    });
  });
}

/// JSON-encodes [value] as a string literal, so the double-wrapped fixture
/// above is escaped the way a real payload would be.
String _quoted(String value) => '"${value.replaceAll(r'\', r'\\').replaceAll('"', r'\"')}"';
