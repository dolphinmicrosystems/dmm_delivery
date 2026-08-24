/// What an owner is allowed to call a route.
///
/// The route's name starts life as the PDF's own "Round:" heading - the
/// backend's pdf_run_sheet_parser reads `Round: Run 2` and the route is
/// called "Run 2" from then on. That is a filing code, not a name, and the
/// owner can replace it: on upload, on the review screen, or from the route
/// list afterwards.
///
/// The limits below are not decoration - they mirror `firestore.rules`
/// exactly (`round.size() > 0 && round.size() <= 80`). A name the rules
/// reject comes back as a bare `permission-denied`, which reads as a sign-in
/// problem rather than "that name is too long", so it is checked here first
/// and never sent.
class RouteName {
  const RouteName._();

  /// Matches `round.size() <= 80` in firestore.rules for `circuits`, and
  /// `route_name.size() <= 80` for `run_sheet_upload`. Firestore counts
  /// bytes, Dart's `String.length` counts UTF-16 units; for a route label
  /// they only diverge on non-ASCII, so the field also enforces this as a
  /// `maxLength` and the check below stays the honest one.
  static const maxLength = 80;

  /// The form that gets written: surrounding whitespace gone, internal runs
  /// collapsed. "Mosgiel  morning " and "Mosgiel morning" are the same name,
  /// and a route list that shows both is a list with a duplicate in it.
  static String normalize(String value) => value.trim().replaceAll(RegExp(r'\s+'), ' ');

  /// Null when the name is fine, otherwise the sentence to put under the
  /// field. An empty name is valid input here and means "no opinion" - the
  /// caller falls back to the sheet's own heading rather than writing a
  /// blank - so emptiness is not an error, only over-length is.
  static String? validationError(String value) {
    if (normalize(value).length > maxLength) {
      return 'Keep the name to $maxLength characters or fewer.';
    }
    return null;
  }

  /// The name to send, or null for "leave it to the run sheet". Callers pass
  /// this straight to Storage metadata or to the confirm write, both of
  /// which treat null as absent rather than as a name of "".
  static String? toSubmit(String value) {
    final normalized = normalize(value);
    return normalized.isEmpty ? null : normalized;
  }

  /// Whether the owner actually changed anything, which is what decides
  /// between `route_name_source: 'owner'` and leaving the file in charge.
  /// Typing the sheet's own heading back into the field is not a rename -
  /// the route keeps following the sheet, which is what an owner who has
  /// not expressed a preference should get.
  static bool isRenameOf(String value, String? current) {
    final normalized = normalize(value);
    return normalized.isNotEmpty && normalized != (current == null ? null : normalize(current));
  }
}
