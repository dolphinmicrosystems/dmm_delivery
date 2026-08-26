import 'dart:convert';

/// Turns whatever Firebase Auth hands back into a sentence worth showing.
///
/// A rejection from the `beforeSignIn` blocking function is the case that
/// matters. `handle_sign_in.py` raises an `HttpsError` with a message written
/// for a person - "hasn't been invited to this app" - but by the time it
/// reaches `FirebaseAuthException.message` it has been wrapped in Identity
/// Platform's JSON envelope:
///
///     {"error":{"message":"jagdish...@gmail.com hasn't been invited to this
///      app. Ask the owner...","status":"PERMISSION_DENIED"}}
///
/// Rendered raw, that reads as a crash rather than as an answer, and the
/// sentence someone actually needs is buried in the middle of it.
///
/// Pure and string-in/string-out, so every shape below is testable without
/// signing anything in.
class AuthErrorMessage {
  const AuthErrorMessage._();

  /// Firebase prefixes some blocking-function errors with this before the
  /// JSON, and Identity Platform occasionally repeats it inside the message.
  static final RegExp _blockingPrefix = RegExp(
    r'^\s*(BLOCKING_FUNCTION_ERROR_RESPONSE\s*:?\s*)+',
    caseSensitive: false,
  );

  /// The sentence to show. Falls back to the input unchanged rather than to
  /// anything invented - an unrecognised shape is still more useful to a
  /// person than "Something went wrong".
  static String humanize(String? raw, {String fallback = 'Something went wrong.'}) {
    final text = raw?.trim();
    if (text == null || text.isEmpty) return fallback;

    final unwrapped = _unwrapJson(text) ?? text;
    final cleaned = unwrapped.replaceFirst(_blockingPrefix, '').trim();
    return cleaned.isEmpty ? fallback : cleaned;
  }

  /// Digs `error.message` out of the envelope, tolerating the prefix, a
  /// bare message string, and nesting - Identity Platform has been seen to
  /// wrap an already-wrapped message when a blocking function rejects.
  static String? _unwrapJson(String text) {
    final start = text.indexOf('{');
    if (start < 0) return null;

    Object? decoded;
    try {
      decoded = jsonDecode(text.substring(start));
    } on FormatException {
      return null;
    }

    String? message;
    // Bounded rather than `while (true)`: a self-referential payload would
    // otherwise spin forever on the sign-in screen.
    for (var depth = 0; depth < 5; depth++) {
      if (decoded is! Map) break;
      final error = decoded['error'];
      final candidate = error is Map ? error['message'] : decoded['message'];
      if (candidate is! String) break;
      message = candidate;
      final nested = _unwrapJson(candidate);
      if (nested == null || nested == candidate) break;
      decoded = jsonDecode(candidate.substring(candidate.indexOf('{')));
    }

    return message;
  }
}
