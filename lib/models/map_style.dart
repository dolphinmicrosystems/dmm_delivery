import 'package:flutter/foundation.dart';

import '../config/map_config.dart';

/// Which basemap every map in the app draws under its route.
///
/// One app-wide setting rather than one per map: an owner who switches to
/// Satellite on the review screen expects the route screen and the rider map
/// to follow, not to reset to their own defaults.
enum MapStyle {
  /// CARTO Positron: pale and sparse, so the route line is the only strong
  /// colour on screen. Needs no Google key.
  simple('Simple', 'Pale map, route stands out'),

  /// Google's road map: business names, points of interest, building
  /// outlines and house numbers as you zoom in.
  detailed('Detailed', 'Streets, businesses and buildings'),

  /// Google satellite imagery with road names over it.
  satellite('Satellite', 'Aerial photos with road names');

  const MapStyle(this.label, this.description);

  final String label;
  final String description;

  bool get isGoogle => this != simple;

  /// The styles this build can draw: Google's need a Map Tiles key.
  static List<MapStyle> get available =>
      MapConfig.googleMapTilesKey.isEmpty ? const [simple] : MapStyle.values;

  /// The style in force, shared by every map. Starts on Detailed when the
  /// build can draw it - the Simple map's lack of detail is what prompted
  /// the others.
  static final ValueNotifier<MapStyle> current = ValueNotifier(
    MapConfig.googleMapTilesKey.isEmpty ? simple : detailed,
  );
}
