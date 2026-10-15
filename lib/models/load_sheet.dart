import 'package:cloud_firestore/cloud_firestore.dart';

import 'run_stop.dart';

enum LoadChangeKind {
  /// The owner: extra of a product (delta > 0) or less (delta < 0).
  adjust,

  /// The driver: not enough on the truck; delta is how many are missing.
  short,
}

/// One change to a run's load: `delivery_run/{runId}/load_changes/{id}`.
/// Never edited - a correction is another change - so the list is the history.
class LoadChange {
  const LoadChange({
    required this.id,
    required this.kind,
    required this.code,
    required this.product,
    required this.delta,
    this.note,
    this.byName,
    this.at,
  });

  final String id;
  final LoadChangeKind kind;
  final String code;
  final String product;
  final int delta;
  final String? note;
  final String? byName;
  final DateTime? at;

  /// "+6 × 2 L Standard Milk", "−2 × …", "Short 4 × …".
  String get label => switch (kind) {
    LoadChangeKind.adjust => '${delta > 0 ? '+$delta' : '−${-delta}'} × $product',
    LoadChangeKind.short => 'Short $delta × $product',
  };

  static LoadChange? fromDoc(QueryDocumentSnapshot<Map<String, dynamic>> doc) => fromMap(doc.id, doc.data());

  static LoadChange? fromMap(String id, Map<String, dynamic> data) {
    final kind = switch (data['kind']) {
      'adjust' => LoadChangeKind.adjust,
      'short' => LoadChangeKind.short,
      _ => null,
    };
    final delta = (data['delta'] as num?)?.toInt();
    final code = data['code'] as String?;
    if (kind == null || delta == null || delta == 0 || code == null) return null;
    final at = data['created_at'];
    return LoadChange(
      id: id,
      kind: kind,
      code: code,
      product: data['product'] as String? ?? 'Product',
      delta: delta,
      note: (data['note'] as String?)?.trim().isEmpty ?? true ? null : (data['note'] as String).trim(),
      byName: data['by_name'] as String?,
      at: at is Timestamp ? at.toDate() : (at is DateTime ? at : null),
    );
  }

  /// The code for a product the run sheet doesn't carry, added by the owner
  /// by name: stable for the same name, so a second "Butter" adds to the first.
  static String codeFor(String product) =>
      'x-${product.trim().toLowerCase().replaceAll(RegExp(r'[^a-z0-9]+'), '-')}';
}

/// One product on the truck: what the run sheet says, the owner's changes on
/// top, and any shortage the driver reported.
class LoadLine {
  const LoadLine({
    required this.code,
    required this.product,
    required this.fromSheet,
    required this.extra,
    required this.short,
    required this.crates,
    required this.loose,
    required this.checked,
  });

  final String code;
  final String product;

  /// Units on the run sheet's stops.
  final int fromSheet;

  /// The owner's changes, summed: + more, − less.
  final int extra;

  /// How many the driver said are missing, summed.
  final int short;

  /// The sheet's own crates and loose split (before any change).
  final int crates;
  final int loose;

  /// Ticked by the driver at this [total]; a tick at another quantity (the
  /// owner changed it since) doesn't count.
  final bool checked;

  /// What to load. Never below zero, however much was taken off.
  int get total => fromSheet + extra < 0 ? 0 : fromSheet + extra;
}

/// A run's load sheet: every product to put on the truck and how many, the
/// changes made, and how far the driver has got ticking it off.
///
/// Pure (test/load_sheet_test.dart); the screens stream the stops, the
/// changes and the ticks, and hand them here.
class LoadSheet {
  const LoadSheet({required this.lines, required this.changes});

  /// Heaviest first, as the depot loads.
  final List<LoadLine> lines;

  /// Oldest first.
  final List<LoadChange> changes;

  int get units => lines.fold(0, (running, line) => running + line.total);
  int get checkedCount => lines.where((line) => line.checked).length;
  bool get allChecked => lines.isNotEmpty && checkedCount == lines.length;
  List<LoadChange> get shortages => [
    for (final c in changes)
      if (c.kind == LoadChangeKind.short) c,
  ];

  static LoadSheet build({
    required Iterable<StopItem> items,
    Iterable<LoadChange> changes = const [],
    Map<String, int> checked = const {},
  }) {
    final sheet = <String, ({String product, int units, int crates, int loose})>{};
    for (final item in items) {
      final had = sheet[item.code];
      sheet[item.code] = (
        product: had?.product ?? item.product,
        units: (had?.units ?? 0) + item.quantity,
        crates: (had?.crates ?? 0) + item.crates,
        loose: (had?.loose ?? 0) + item.loose,
      );
    }
    final ordered = [...changes]..sort((a, b) => (a.at ?? DateTime(9999)).compareTo(b.at ?? DateTime(9999)));
    final extra = <String, int>{}, short = <String, int>{}, names = <String, String>{};
    for (final change in ordered) {
      names.putIfAbsent(change.code, () => change.product);
      final into = change.kind == LoadChangeKind.adjust ? extra : short;
      into[change.code] = (into[change.code] ?? 0) + change.delta;
    }

    final codes = {...sheet.keys, ...extra.keys, ...short.keys};
    final lines =
        [
          for (final code in codes)
            if (LoadLine(
                  code: code,
                  product: sheet[code]?.product ?? names[code] ?? code,
                  fromSheet: sheet[code]?.units ?? 0,
                  extra: extra[code] ?? 0,
                  short: short[code] ?? 0,
                  crates: sheet[code]?.crates ?? 0,
                  loose: sheet[code]?.loose ?? 0,
                  checked: false,
                )
                case final line)
              // A product only ever added and then taken off again leaves nothing to show.
              if (line.total > 0 || line.fromSheet > 0 || line.short > 0)
                LoadLine(
                  code: line.code,
                  product: line.product,
                  fromSheet: line.fromSheet,
                  extra: line.extra,
                  short: line.short,
                  crates: line.crates,
                  loose: line.loose,
                  checked: checked[code] == line.total,
                ),
        ]..sort((a, b) {
          final byUnits = b.total.compareTo(a.total);
          return byUnits != 0 ? byUnits : a.product.compareTo(b.product);
        });
    return LoadSheet(lines: lines, changes: ordered);
  }
}
