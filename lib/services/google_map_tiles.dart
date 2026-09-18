import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:latlong2/latlong.dart';

import '../config/map_config.dart';
import '../models/map_style.dart';
import '../util/app_log.dart';

/// A Map Tiles API session: the token every 2D tile request has to carry.
class GoogleTileSession {
  const GoogleTileSession({required this.token, required this.expiresAt});

  final String token;
  final DateTime expiresAt;

  String get urlTemplate =>
      'https://tile.googleapis.com/v1/2dtiles/{z}/{x}/{y}?session=$token&key=${MapConfig.googleMapTilesKey}';
}

/// Google's Map Tiles API, for the Detailed and Satellite map styles.
///
/// Sessions are created once per style and reused until shortly before they
/// expire (Google issues them for about two weeks), so switching styles back
/// and forth costs nothing. Tile requests are billed per tile; sessions and
/// viewport look-ups are not.
class GoogleMapTiles {
  GoogleMapTiles._();

  static final Map<MapStyle, Future<GoogleTileSession>> _sessions = {};

  /// The session for [style], created on first use. A failed attempt is
  /// forgotten so the next map to ask tries again rather than inheriting it.
  static Future<GoogleTileSession> session(MapStyle style, {http.Client? client}) {
    final cached = _sessions[style];
    if (cached != null) return cached;
    final created = _create(style, client ?? http.Client());
    _sessions[style] = created;
    created.then(
      (session) {
        // Renewed an hour early, so a map open across the boundary never
        // requests tiles with a token that has just lapsed.
        final renewIn = session.expiresAt.difference(DateTime.now()) - const Duration(hours: 1);
        Future<void>.delayed(renewIn.isNegative ? Duration.zero : renewIn, () {
          _sessions.remove(style);
        });
      },
      onError: (Object _) {
        _sessions.remove(style);
      },
    );
    return created;
  }

  static Future<GoogleTileSession> _create(MapStyle style, http.Client client) async {
    final body = {
      'mapType': style == MapStyle.satellite ? 'satellite' : 'roadmap',
      'language': 'en-NZ',
      'region': 'NZ',
      // 512px tiles drawn at 256 logical px: sharp on a phone's dense screen.
      'scale': 'scaleFactor2x',
      'highDpi': true,
      // Road names drawn over the imagery - bare satellite has no way to
      // tell Wharf Street from the rail yard beside it.
      if (style == MapStyle.satellite) 'layerTypes': ['layerRoadmap'],
    };
    final response = await client.post(
      Uri.parse('https://tile.googleapis.com/v1/createSession?key=${MapConfig.googleMapTilesKey}'),
      headers: {'Content-Type': 'application/json', ...MapConfig.googleMapTilesHeaders},
      body: jsonEncode(body),
    );
    if (response.statusCode != 200) {
      AppLog.owner('map tiles session failed', {'style': style.name, 'status': response.statusCode});
      throw GoogleMapTilesException(response.statusCode, response.body);
    }
    final json = jsonDecode(response.body) as Map<String, dynamic>;
    final expiry = int.tryParse('${json['expiry']}');
    return GoogleTileSession(
      token: json['session'] as String,
      expiresAt: expiry == null
          ? DateTime.now().add(const Duration(days: 1))
          : DateTime.fromMillisecondsSinceEpoch(expiry * 1000),
    );
  }

  /// The copyright line Google requires under its tiles for this view, e.g.
  /// "Map data ©2026 Google". Changes with what is on screen (imagery comes
  /// from different providers), which is why it is asked per viewport.
  static Future<String?> copyright(
    GoogleTileSession session, {
    required int zoom,
    required LatLng northEast,
    required LatLng southWest,
    http.Client? client,
  }) async {
    final uri = Uri.https('tile.googleapis.com', '/tile/v1/viewport', {
      'session': session.token,
      'key': MapConfig.googleMapTilesKey,
      'zoom': '$zoom',
      'north': '${northEast.latitude}',
      'south': '${southWest.latitude}',
      'east': '${northEast.longitude}',
      'west': '${southWest.longitude}',
    });
    try {
      final response = await (client ?? http.Client()).get(uri, headers: MapConfig.googleMapTilesHeaders);
      if (response.statusCode != 200) return null;
      return (jsonDecode(response.body) as Map<String, dynamic>)['copyright'] as String?;
    } on Exception {
      return null;
    }
  }
}

class GoogleMapTilesException implements Exception {
  const GoogleMapTilesException(this.statusCode, this.body);

  final int statusCode;
  final String body;

  @override
  String toString() => 'GoogleMapTilesException($statusCode): $body';
}
