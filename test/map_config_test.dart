import 'package:dmm_delivery/config/map_config.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('MapConfig basemap URL', () {
    test('carries the key as a query parameter when there is one', () {
      final url = MapConfig.basemapUrlFor('abc123');

      expect(url, contains('?key=abc123'));
      // The placeholders have to survive: flutter_map substitutes them, and a
      // template that lost {s} or {r} fetches tiles from a host that is not
      // there rather than failing loudly.
      expect(url, startsWith('https://{s}.basemaps.cartocdn.com/light_all/{z}/{x}/{y}{r}.png'));
    });

    test('omits the parameter entirely when there is no key', () {
      // Not `?key=`. CARTO answers an unkeyed request with a watermarked tile
      // either way, but an empty parameter is a malformed request where no
      // parameter is merely an anonymous one - and it is the shape somebody
      // will later read as "the key is set to nothing".
      final url = MapConfig.basemapUrlFor('');

      expect(url, isNot(contains('key=')));
      expect(url, isNot(contains('?')));
      expect(url, endsWith('.png'));
    });

    test('credits both CARTO and OpenStreetMap', () {
      // Both licences require it, and dropping either is the kind of thing
      // that only surfaces as a letter.
      expect(MapConfig.basemapAttribution, contains('CARTO'));
      expect(MapConfig.basemapAttribution, contains('OpenStreetMap'));
    });
  });
}
