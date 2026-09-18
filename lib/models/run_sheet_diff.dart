/// The `diff` map on a `run_sheet_upload` document, as something the review
/// screen can ask questions of.
///
/// Written by the backend's process_run_sheet_upload.py at the end of a
/// parse. This used to be dug out of the raw map inline in the review
/// header's `build`, which put the one piece of logic worth testing - what
/// the owner is told changed - in the one place the tests cannot reach. It
/// lives here now for the reason the rest of this app's parsing does.
class RunSheetDiff {
  const RunSheetDiff({
    required this.added,
    required this.removed,
    required this.changed,
    required this.orderStrategy,
    required this.insertedCount,
    required this.roundMismatch,
    this.pdfRound,
  });

  final int added;
  final int removed;
  final int changed;

  /// How this upload's stop sequence was arrived at, straight from the
  /// backend: `optimized` (routed from scratch), `reused` (the confirmed
  /// order stood, same addresses), or `merged` (the confirmed order stood
  /// and new stops were slotted into it). Unknown values are treated as
  /// `optimized` - the conservative reading, since it is the one that does
  /// not promise the owner their order survived.
  final String orderStrategy;

  /// How many stops were slotted into an existing sequence. Only meaningful
  /// when [orderStrategy] is `merged`.
  final int insertedCount;

  /// The PDF's heading disagrees with the heading this route was built from
  /// - i.e. this may be the wrong sheet for the route, not merely a route
  /// that has been renamed.
  final bool roundMismatch;

  final String? pdfRound;

  static const empty = RunSheetDiff(
    added: 0,
    removed: 0,
    changed: 0,
    orderStrategy: 'optimized',
    insertedCount: 0,
    roundMismatch: false,
  );

  factory RunSheetDiff.fromMap(Map<String, dynamic>? map) {
    if (map == null) return empty;
    return RunSheetDiff(
      added: ((map['added'] as List?) ?? const []).length,
      removed: ((map['removed'] as List?) ?? const []).length,
      changed: ((map['content_changed'] as List?) ?? const []).length,
      orderStrategy: map['order_strategy'] as String? ?? 'optimized',
      insertedCount: (map['inserted_count'] as num?)?.toInt() ?? 0,
      roundMismatch: map['round_mismatch'] == true,
      pdfRound: map['pdf_round'] as String?,
    );
  }

  /// True when this upload left the owner's confirmed sequence intact. The
  /// backend decides this, not the client - see the three strategies in
  /// process_run_sheet_upload.py's docstring.
  bool get orderPreserved => orderStrategy == 'reused' || orderStrategy == 'merged' || orderStrategy == 'learned';

  /// What changed, as one line: "2 added · 1 updated".
  String get changeSummary {
    final parts = [
      if (added > 0) '$added added',
      if (removed > 0) '$removed removed',
      if (changed > 0) '$changed updated',
    ];
    return parts.isEmpty ? 'No changes since the last sheet' : parts.join(' · ');
  }

  /// What happened to the order the owner last approved, or null on a first
  /// upload where there was no such order to keep.
  ///
  /// Worth saying out loud on every re-upload: a sequence that quietly
  /// reverted to the optimizer's looks exactly like one that didn't, and the
  /// owner only finds out when a driver is halfway through the run.
  String? get orderNote => switch (orderStrategy) {
        'reused' => 'Your stop order is unchanged.',
        'merged' when insertedCount == 1 => 'Your stop order was kept — 1 new stop slotted in.',
        'merged' when insertedCount > 1 => 'Your stop order was kept — $insertedCount new stops slotted in.',
        // A merge with nothing inserted is a removal: stops left the sheet
        // and the rest held their places.
        'merged' => 'Your stop order was kept for the stops that remain.',
        // A new route (often one deleted and uploaded again) that drivers have
        // already run most of: their order, not a fresh optimisation.
        'learned' when insertedCount == 0 => 'Ordered the way your driver has run these stops before.',
        'learned' => 'Ordered the way your driver has run these stops before — '
            '$insertedCount new ${insertedCount == 1 ? 'stop' : 'stops'} slotted in.',
        _ => null,
      };
}
