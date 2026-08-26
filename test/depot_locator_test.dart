import 'package:flutter_test/flutter_test.dart';

import 'package:dmm_delivery/services/depot_locator.dart';

void main() {
  group('stopInstructionsId', () {
    // Mirrors `firestore_paths.stop_instructions_id` in the backend repo.
    // The two are a contract: change one and the owner's saved instructions
    // stop being found by the pipeline, silently and only in production.
    test('scopes the address hash to one business', () {
      expect(DepotLocator.stopInstructionsId('owner-1', 'abc123'), 'owner-1__abc123');
    });

    test('two businesses at the same address get different documents', () {
      // The whole reason the prefix exists. Without it, one owner's
      // "leave at the side gate" appears on the other owner's run.
      final key = DepotLocator.addressKey('12 George St, Dunedin');

      expect(
        DepotLocator.stopInstructionsId('owner-1', key),
        isNot(DepotLocator.stopInstructionsId('owner-2', key)),
      );
    });

    test('leaves the address hash itself untouched', () {
      final key = DepotLocator.addressKey('12 George St, Dunedin');

      expect(DepotLocator.stopInstructionsId('owner-1', key), endsWith(key));
    });
  });

  group('addressKey', () {
    // Mirrors `firestore_paths.address_key`: sha256 of the trimmed,
    // lowercased address.
    test('is insensitive to case and surrounding space', () {
      expect(
        DepotLocator.addressKey('  12 George St, DUNEDIN '),
        DepotLocator.addressKey('12 george st, dunedin'),
      );
    });

    test('differs for different addresses', () {
      expect(
        DepotLocator.addressKey('12 George St'),
        isNot(DepotLocator.addressKey('13 George St')),
      );
    });
  });
}
