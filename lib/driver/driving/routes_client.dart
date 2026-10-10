import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:latlong2/latlong.dart';

import '../../config/map_config.dart';
import '../../util/app_log.dart';
import 'turn_by_turn.dart';

/// Asks Google's Routes API for the road from the van to a stop, with each
/// turn's instruction - in-app navigation, instead of handing off to another
/// app.
///
/// Uses the app's own key (`GOOGLE_MAP_TILES_KEY`, restricted to this
/// package and certificate, and since maps.tf allows it, to the Routes API
/// too) with the same `X-Android-*` headers as the map tiles.
///
/// TRAFFIC_UNAWARE: the cheaper Essentials SKU, and Dunedin at milk-run hours
/// has little traffic to be aware of. One request per stop, plus one per
/// re-route when the van leaves the line.
class RoutesClient {
  const RoutesClient();

  static bool get available => MapConfig.googleMapTilesKey.isNotEmpty;

  static const _fields = [
    'routes.distanceMeters',
    'routes.duration',
    'routes.polyline.encodedPolyline',
    'routes.legs.steps.polyline.encodedPolyline',
    'routes.legs.steps.navigationInstruction',
  ];

  /// The route, or [RoutesException] saying why there isn't one. [to] is the
  /// stop's pin; a stop the geocoder couldn't place goes by [address].
  Future<NavRoute> route(LatLng from, {LatLng? to, String? address, double? heading}) async {
    if (!available) throw const RoutesException('Directions need the map key in this build.');
    if (to == null && (address == null || address.isEmpty)) {
      throw const RoutesException('This stop has no location to drive to.');
    }
    final response = await http
        .post(
          Uri.parse('https://routes.googleapis.com/directions/v2:computeRoutes'),
          headers: {
            'Content-Type': 'application/json',
            'X-Goog-Api-Key': MapConfig.googleMapTilesKey,
            'X-Goog-FieldMask': _fields.join(','),
            ...MapConfig.googleMapTilesHeaders,
          },
          body: jsonEncode({
            'origin': {
              'location': {
                'latLng': {'latitude': from.latitude, 'longitude': from.longitude},
                // Which way the van faces, so the route doesn't start with a U-turn.
                if (heading != null && heading >= 0) 'heading': heading.round() % 360,
              },
            },
            'destination': to != null
                ? {
                    'location': {
                      'latLng': {'latitude': to.latitude, 'longitude': to.longitude},
                    },
                  }
                : {'address': '$address, New Zealand'},
            'travelMode': 'DRIVE',
            'routingPreference': 'TRAFFIC_UNAWARE',
            'languageCode': 'en-GB',
            'units': 'METRIC',
          }),
        )
        .timeout(const Duration(seconds: 12));
    if (response.statusCode != 200) {
      // The body names the problem (key, quota); no secrets in it.
      AppLog.auth.error('routes request refused', 'HTTP ${response.statusCode}', null, {
        'body': response.body.length > 300 ? response.body.substring(0, 300) : response.body,
      });
      throw RoutesException("Google refused the directions request (${response.statusCode}).");
    }
    final route = NavRoute.fromResponse(jsonDecode(response.body) as Map<String, dynamic>);
    if (route == null) throw const RoutesException('No road route to this stop.');
    return route;
  }
}

/// Why there are no directions, in words for the driver.
class RoutesException implements Exception {
  const RoutesException(this.message);

  final String message;

  @override
  String toString() => message;
}
