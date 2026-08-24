/// What an owner would lose by leaving a screen, named so the warning can say
/// it rather than saying "changes".
///
/// "You have unsaved changes" is the version of this dialog that gets
/// dismissed without reading, because it doesn't tell you anything you didn't
/// know. Naming the actual thing - the new name, the order you dragged, or
/// both - is what makes the choice between Discard and Keep editing an
/// informed one.
///
/// Pure, so the branching is testable without pumping a screen that needs
/// Firebase to build.
class PendingChanges {
  const PendingChanges({required this.renamed, required this.reordered});

  static const none = PendingChanges(renamed: false, reordered: false);

  /// The route's name differs from what it was called on arrival. This is
  /// `RouteName.isRenameOf`, not raw text inequality - re-spacing a name or
  /// typing it back exactly is not a change worth stopping someone over.
  final bool renamed;

  /// At least one stop was dragged to a new position.
  final bool reordered;

  bool get isEmpty => !renamed && !reordered;
  bool get isNotEmpty => !isEmpty;

  /// The subject of the warning, as a noun phrase that reads inside a
  /// sentence: "... won't be kept."
  String get summary {
    if (renamed && reordered) return 'The new name and the order you dragged';
    if (reordered) return 'The order you dragged';
    return 'The new name';
  }
}
