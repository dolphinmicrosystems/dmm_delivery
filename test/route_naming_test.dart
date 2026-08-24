import 'package:flutter_test/flutter_test.dart';

import 'package:dmm_delivery/models/pending_changes.dart';
import 'package:dmm_delivery/models/route_name.dart';
import 'package:dmm_delivery/models/run_sheet_diff.dart';

void main() {
  group('RouteName', () {
    test('collapses whitespace so two spellings of one name are one name', () {
      expect(RouteName.normalize('  Mosgiel   morning '), 'Mosgiel morning');
    });

    test('accepts a name at the limit firestore.rules enforces', () {
      final atLimit = 'x' * RouteName.maxLength;

      expect(RouteName.validationError(atLimit), isNull);
    });

    test('rejects a name one character past it, rather than letting the rules '
        'reject it as a bare permission-denied', () {
      final overLimit = 'x' * (RouteName.maxLength + 1);

      expect(RouteName.validationError(overLimit), isNotNull);
    });

    test('measures the trimmed name, not what was typed', () {
      final padded = '  ${'x' * RouteName.maxLength}  ';

      expect(RouteName.validationError(padded), isNull);
    });

    test('an empty name is not an error - it means "use the sheet\'s heading"', () {
      expect(RouteName.validationError(''), isNull);
      expect(RouteName.validationError('   '), isNull);
      expect(RouteName.toSubmit('   '), isNull);
    });

    test('submits the normalized form', () {
      expect(RouteName.toSubmit('  Mosgiel   morning '), 'Mosgiel morning');
    });

    group('isRenameOf', () {
      test('typing a different name is a rename', () {
        expect(RouteName.isRenameOf('Mosgiel morning', 'Run 2'), isTrue);
      });

      test('typing the same name back is not', () {
        // Otherwise opening the review screen and confirming would pin the
        // route to "Run 2" forever, and a sheet whose heading later changed
        // would stop being able to update it.
        expect(RouteName.isRenameOf('Run 2', 'Run 2'), isFalse);
      });

      test('re-spacing the same name is not', () {
        expect(RouteName.isRenameOf(' Run  2 ', 'Run 2'), isFalse);
      });

      test('clearing the field is not a rename', () {
        expect(RouteName.isRenameOf('', 'Run 2'), isFalse);
      });

      test('naming a route that had no name is a rename', () {
        expect(RouteName.isRenameOf('Mosgiel morning', null), isTrue);
      });
    });
  });

  group('PendingChanges', () {
    test('nothing touched is nothing to warn about', () {
      expect(const PendingChanges(renamed: false, reordered: false).isEmpty, isTrue);
      expect(PendingChanges.none.isNotEmpty, isFalse);
    });

    test('names the new name when only the name changed', () {
      const pending = PendingChanges(renamed: true, reordered: false);

      expect(pending.isNotEmpty, isTrue);
      expect(pending.summary, 'The new name');
    });

    test('names the order when only stops moved', () {
      const pending = PendingChanges(renamed: false, reordered: true);

      expect(pending.summary, 'The order you dragged');
    });

    test('names both when both changed, rather than saying "changes"', () {
      // The generic version of this dialog is the one people dismiss without
      // reading, because it tells them nothing they didn't already know.
      const pending = PendingChanges(renamed: true, reordered: true);

      expect(pending.summary, 'The new name and the order you dragged');
    });

    test('summary reads as the subject of the warning sentence', () {
      const pending = PendingChanges(renamed: true, reordered: true);

      expect('${pending.summary} won\u2019t be applied.',
          'The new name and the order you dragged won\u2019t be applied.');
    });
  });

  group('RunSheetDiff', () {
    // Shapes taken from what process_run_sheet_upload.py actually writes.
    Map<String, dynamic> diffMap({
      int added = 0,
      int removed = 0,
      int changed = 0,
      String strategy = 'optimized',
      int inserted = 0,
    }) =>
        {
          'added': List.generate(added, (i) => {'address_key': 'a$i'}),
          'removed': List.generate(removed, (i) => {'address_key': 'r$i'}),
          'content_changed': List.generate(changed, (i) => {'address_key': 'c$i'}),
          'order_strategy': strategy,
          'inserted_count': inserted,
          'round_mismatch': false,
          'pdf_round': 'Run 2',
        };

    test('counts each kind of change', () {
      final diff = RunSheetDiff.fromMap(diffMap(added: 2, removed: 1, changed: 3));

      expect(diff.added, 2);
      expect(diff.removed, 1);
      expect(diff.changed, 3);
      expect(diff.changeSummary, '2 added · 1 removed · 3 updated');
    });

    test('says so plainly when nothing changed', () {
      expect(RunSheetDiff.fromMap(diffMap()).changeSummary, 'No changes since the last sheet');
    });

    test('a missing diff map is an empty diff, not a crash', () {
      expect(RunSheetDiff.fromMap(null).added, 0);
      expect(RunSheetDiff.fromMap(null).orderPreserved, isFalse);
    });

    group('orderNote', () {
      test('a reused order says the sequence is untouched', () {
        final diff = RunSheetDiff.fromMap(diffMap(changed: 1, strategy: 'reused'));

        expect(diff.orderPreserved, isTrue);
        expect(diff.orderNote, 'Your stop order is unchanged.');
      });

      test('one inserted stop reads in the singular', () {
        final diff = RunSheetDiff.fromMap(diffMap(added: 1, strategy: 'merged', inserted: 1));

        expect(diff.orderNote, 'Your stop order was kept — 1 new stop slotted in.');
      });

      test('several inserted stops read in the plural', () {
        final diff = RunSheetDiff.fromMap(diffMap(added: 3, strategy: 'merged', inserted: 3));

        expect(diff.orderNote, 'Your stop order was kept — 3 new stops slotted in.');
      });

      test('a merge that only removed stops still reassures', () {
        final diff = RunSheetDiff.fromMap(diffMap(removed: 2, strategy: 'merged'));

        expect(diff.orderNote, 'Your stop order was kept for the stops that remain.');
      });

      test('a first upload promises nothing, because there was no order to keep', () {
        final diff = RunSheetDiff.fromMap(diffMap(added: 5, strategy: 'optimized'));

        expect(diff.orderPreserved, isFalse);
        expect(diff.orderNote, isNull);
      });

      test('an unrecognised strategy is read as optimized, never as preserved', () {
        // The conservative direction: a backend that starts sending a
        // strategy this build has never heard of must not have it rendered
        // as a promise that the owner's order survived.
        final diff = RunSheetDiff.fromMap(diffMap(strategy: 'something-new'));

        expect(diff.orderPreserved, isFalse);
        expect(diff.orderNote, isNull);
      });
    });
  });
}
