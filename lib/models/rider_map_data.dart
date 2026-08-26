import 'package:latlong2/latlong.dart';

/// One rider's round: the stops they are carrying, in the sequence the owner
/// approved.
///
/// The line is drawn straight between stops, because that is what the server
/// sends - a sequence, not a driven path. A road-following shape needs a
/// routing engine, and drawing one that merely looked plausible would be a
/// picture of a route nobody drives. `route.source` names which it is, and
/// [isSequenceOnly] is what the badge reads.
///
/// [position] is null until something observes a driver. A marker that moves
/// is believed, so there isn't one until GPS is real.
class RiderMapData {
  const RiderMapData({
    required this.riderKey,
    required this.driverName,
    required this.stops,
    this.round,
    this.runId,
    this.position,
    this.isSequenceOnly = true,
    this.stopsTotal = 0,
    this.stopsLocated = 0,
  });

  final String riderKey;
  final String driverName;

  /// The route's display name, and the run these stops belong to.
  final String? round;
  final String? runId;

  final List<RiderMapStop> stops;

  /// Null until a driver is actually observed.
  final LatLng? position;

  /// The line joins stops rather than following roads.
  final bool isSequenceOnly;

  /// Stops the run has, against stops that had coordinates. A map quietly
  /// missing three drops looks identical to a round with three fewer.
  final int stopsTotal;
  final int stopsLocated;

  /// The polyline to draw: the stops themselves, in order.
  List<LatLng> get route => [for (final stop in stops) stop.point];

  bool get hasStops => stops.isNotEmpty;

  /// Set when the run has stops the map cannot place.
  String? get missingStopsNotice {
    final missing = stopsTotal - stopsLocated;
    if (missing <= 0) return null;
    return missing == 1 ? '1 stop has no map location yet' : '$missing stops have no map location yet';
  }

  factory RiderMapData.fromJson(Map<String, dynamic> json) {
    final route = json['route'] as Map<String, dynamic>? ?? const {};
    final position = json['position'] as Map<String, dynamic>?;

    return RiderMapData(
      riderKey: json['rider_key'] as String? ?? '',
      driverName: json['driver_name'] as String? ?? 'Driver',
      round: json['round'] as String?,
      runId: json['run_id'] as String?,
      stops: [
        for (final stop in (json['stops'] as List?) ?? const [])
          RiderMapStop.fromJson(stop as Map<String, dynamic>),
      ],
      position: position == null
          ? null
          : LatLng((position['lat'] as num?)?.toDouble() ?? 0, (position['lng'] as num?)?.toDouble() ?? 0),
      // Anything other than a routed provenance means the line is a sequence.
      // Reading it this way rather than matching 'stops' exactly keeps the
      // badge honest if the server starts naming a different non-routed
      // source before this build knows about it.
      isSequenceOnly: route['source'] != 'valhalla',
      stopsTotal: (json['stops_total'] as num?)?.toInt() ?? 0,
      stopsLocated: (json['stops_located'] as num?)?.toInt() ?? 0,
    );
  }
}

class RiderMapStop {
  const RiderMapStop({
    required this.point,
    required this.address,
    this.customerName,
    this.seqOrder,
    this.status,
  });

  final LatLng point;
  final String address;
  final String? customerName;
  final int? seqOrder;
  final String? status;

  bool get isDelivered => status == 'delivered';

  factory RiderMapStop.fromJson(Map<String, dynamic> json) => RiderMapStop(
    point: LatLng((json['lat'] as num).toDouble(), (json['lng'] as num).toDouble()),
    address: json['address'] as String? ?? '',
    customerName: json['customer_name'] as String?,
    seqOrder: (json['seq_order'] as num?)?.toInt(),
    status: json['status'] as String?,
  );
}
