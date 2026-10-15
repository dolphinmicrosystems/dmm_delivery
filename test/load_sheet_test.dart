import 'package:dmm_delivery/models/load_sheet.dart';
import 'package:dmm_delivery/models/run_stop.dart';
import 'package:flutter_test/flutter_test.dart';

StopItem item(String code, String product, int quantity) =>
    StopItem(code: code, product: product, quantity: quantity, crates: quantity ~/ 12, loose: quantity % 12);

LoadChange change(String id, LoadChangeKind kind, String code, String product, int delta, int minute) =>
    LoadChange(
      id: id,
      kind: kind,
      code: code,
      product: product,
      delta: delta,
      at: DateTime(2026, 10, 12, 4, minute),
    );

void main() {
  // Two stops' worth of a South Runsheet.
  final items = [
    item('20', '2 L Standard Milk', 24),
    item('10', '1 L Standard Milk', 6),
    item('20', '2 L Standard Milk', 18),
    item('90', '1 L Oat Milk', 4),
  ];

  test('totals by product code, heaviest first', () {
    final sheet = LoadSheet.build(items: items);
    expect(
      [for (final l in sheet.lines) (l.product, l.total)],
      [('2 L Standard Milk', 42), ('1 L Standard Milk', 6), ('1 L Oat Milk', 4)],
    );
    expect(sheet.units, 52);
  });

  test("the owner's extra and less change what to load; a shortage doesn't", () {
    final sheet = LoadSheet.build(
      items: items,
      changes: [
        change('a', LoadChangeKind.adjust, '20', '2 L Standard Milk', 6, 1),
        change('b', LoadChangeKind.adjust, '90', '1 L Oat Milk', -4, 2),
        change('c', LoadChangeKind.short, '10', '1 L Standard Milk', 2, 3),
        change('d', LoadChangeKind.adjust, LoadChange.codeFor('Butter 500g'), 'Butter 500g', 3, 4),
      ],
    );
    final byCode = {for (final l in sheet.lines) l.code: l};
    expect((byCode['20']!.fromSheet, byCode['20']!.extra, byCode['20']!.total), (42, 6, 48));
    expect(byCode['90']!.total, 0, reason: 'all taken off, still listed: it was on the sheet');
    expect((byCode['10']!.total, byCode['10']!.short), (6, 2));
    expect(byCode['x-butter-500g']!.total, 3, reason: 'a product the sheet never had');
    expect(sheet.shortages.single.label, 'Short 2 × 1 L Standard Milk');
  });

  test('a tick holds only at the quantity it was ticked at', () {
    final before = LoadSheet.build(items: items, checked: {'20': 42, '10': 6});
    expect(before.checkedCount, 2);
    final after = LoadSheet.build(
      items: items,
      changes: [change('a', LoadChangeKind.adjust, '20', '2 L Standard Milk', 6, 1)],
      checked: {'20': 42, '10': 6},
    );
    expect(after.checkedCount, 1, reason: 'the owner added 6 after the driver ticked 42');
  });

  test('labels', () {
    expect(change('a', LoadChangeKind.adjust, '20', '2 L Milk', 6, 0).label, '+6 × 2 L Milk');
    expect(change('a', LoadChangeKind.adjust, '20', '2 L Milk', -2, 0).label, '−2 × 2 L Milk');
  });
}
