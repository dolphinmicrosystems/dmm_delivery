import 'package:dmm_delivery/config/map_config.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  // TileLayer writes a User-Agent into its provider's headers. Handing it the
  // const MapConfig map crashed every Google-style map on open; the provider
  // must get a copy it is allowed to change.
  test('Google tile headers can be handed to a TileLayer, which adds to them', () {
    final provider = NetworkTileProvider(headers: {...MapConfig.googleMapTilesHeaders});

    TileLayer(urlTemplate: 'https://example.com/{z}/{x}/{y}', userAgentPackageName: 'x', tileProvider: provider);

    expect(provider.headers['X-Android-Package'], 'com.delivery.dmm_delivery');
    expect(provider.headers.containsKey('User-Agent'), isTrue);
  });

  test('the const headers themselves are left untouched', () {
    expect(MapConfig.googleMapTilesHeaders.containsKey('User-Agent'), isFalse);
  });
}
