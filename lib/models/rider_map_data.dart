import 'package:latlong2/latlong.dart';

/// One rider's route and where they are on it.
///
/// The server sends an encoded polyline rather than a coordinate array - the
/// convention every production tracking API uses, because a few hundred points
/// compress to a short string. Decoding is the client's job, the same way a
/// map SDK decodes a route it's handed.
class RiderMapData {
  const RiderMapData({
    required this.riderKey,
    required this.driverName,
    required this.route,
    required this.position,
    required this.bearing,
    required this.stops,
    required this.isMock,
  });

  final String riderKey;
  final String driverName;
  final List<LatLng> route;
  final LatLng position;

  /// Compass degrees the vehicle is travelling, for orienting the marker.
  final double bearing;
  final List<RiderMapStop> stops;

  /// True while the route is the static file and the position is randomised.
  /// Surfaced in the UI rather than hidden - a demo position that looks live
  /// is the kind of thing that gets believed.
  final bool isMock;

  factory RiderMapData.fromJson(Map<String, dynamic> json) {
    final route = json['route'] as Map<String, dynamic>? ?? const {};
    final position = json['position'] as Map<String, dynamic>? ?? const {};
    final format = route['shape_format'] as String? ?? 'polyline6';

    return RiderMapData(
      riderKey: json['rider_key'] as String? ?? '',
      driverName: json['driver_name'] as String? ?? 'Driver',
      // Precision comes from the payload, never assumed: reading a
      // precision-6 shape as 5 doesn't fail, it silently lands the route ten
      // degrees away.
      route: decodePolyline(route['shape'] as String? ?? '', precision: format == 'polyline5' ? 5 : 6),
      position: LatLng(
        (position['lat'] as num?)?.toDouble() ?? 0,
        (position['lng'] as num?)?.toDouble() ?? 0,
      ),
      bearing: (position['bearing'] as num?)?.toDouble() ?? 0,
      stops: [
        for (final stop in (json['stops'] as List?) ?? const [])
          RiderMapStop.fromJson(stop as Map<String, dynamic>),
      ],
      isMock: route['source'] == 'static-mock' || position['source'] == 'randomised-mock',
    );
  }
}

class RiderMapStop {
  const RiderMapStop({required this.point, required this.address});

  final LatLng point;
  final String address;

  factory RiderMapStop.fromJson(Map<String, dynamic> json) => RiderMapStop(
    point: LatLng((json['lat'] as num).toDouble(), (json['lng'] as num).toDouble()),
    address: json['address'] as String? ?? '',
  );
}

/// Decodes a Valhalla/Google encoded polyline.
///
/// Valhalla emits precision 6, Google's own APIs emit 5 - hence the parameter
/// rather than a baked-in constant.
List<LatLng> decodePolyline(String shape, {int precision = 6}) {
  if (shape.isEmpty) return const [];

  final factor = <int, double>{5: 1e5, 6: 1e6}[precision] ?? 1e6;
  final points = <LatLng>[];
  var index = 0;
  var lat = 0;
  var lng = 0;

  while (index < shape.length) {
    for (var coordinate = 0; coordinate < 2; coordinate++) {
      var result = 0;
      var shift = 0;
      int byte;
      do {
        byte = shape.codeUnitAt(index++) - 63;
        result |= (byte & 0x1F) << shift;
        shift += 5;
      } while (byte >= 0x20);
      final delta = (result & 1) != 0 ? ~(result >> 1) : (result >> 1);
      if (coordinate == 0) {
        lat += delta;
      } else {
        lng += delta;
      }
    }
    points.add(LatLng(lat / factor, lng / factor));
  }

  return points;
}
