import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

import '../models/run_stop.dart';
import '../theme/app_colors.dart';

/// The route as a shape: depot -> every stop in the current order -> depot.
///
/// Shared by the pre-confirm review screen and the confirmed-route screen so
/// the owner is never shown two different pictures of the same run. It is a
/// pure function of `stops` and `depot`, which is what makes the review
/// screen's drag-to-reorder redraw for free - reordering the list rebuilds
/// this widget with a new order and the polyline follows.
///
/// The line is straight segments between stops, not road geometry: the
/// backend's Routes API call requests `optimizedIntermediateWaypointIndex`
/// only, so an order is all that comes back. That is honest for a sequence
/// review (the question here is "which stop next?", not "which street?"),
/// and turns into real geometry the moment the backend also returns a
/// polyline - only this file changes.
class RoutePreviewMap extends StatelessWidget {
  const RoutePreviewMap({super.key, required this.stops, this.depot, this.onStopTap});

  final List<RunStop> stops;

  /// Start and end of the run. Null when the depot address has never been
  /// geocoded - the route then simply runs stop-to-stop, rather than
  /// inventing an origin.
  final LatLng? depot;

  final void Function(int index)? onStopTap;

  List<LatLng> get _linePoints => [
    ?depot,
    for (final stop in stops) stop.location,
    // Closes the loop. The van goes home; a route drawn as an open path
    // ending at the last customer understates the run by a leg, which is
    // exactly the leg the depot address is configured to account for.
    ?depot,
  ];

  @override
  Widget build(BuildContext context) {
    final points = _linePoints;
    if (points.isEmpty) {
      return const ColoredBox(
        color: AppColors.surfaceMuted,
        child: Center(
          child: Text('No mappable stops', style: TextStyle(color: AppColors.inkMuted, fontSize: 13)),
        ),
      );
    }

    return FlutterMap(
      options: MapOptions(
        // Fits the whole run on first paint. Deliberately `initial` only:
        // re-fitting on every reorder would yank the viewport out from under
        // an owner who has zoomed in to check one cluster of stops.
        initialCameraFit: CameraFit.bounds(
          bounds: LatLngBounds.fromPoints(points),
          padding: const EdgeInsets.all(48),
        ),
      ),
      children: [
        TileLayer(
          urlTemplate: 'https://{s}.basemaps.cartocdn.com/light_all/{z}/{x}/{y}{r}.png',
          subdomains: const ['a', 'b', 'c', 'd'],
          userAgentPackageName: 'com.delivery.dmm_delivery',
        ),
        PolylineLayer(
          polylines: [Polyline(points: points, color: AppColors.brand, strokeWidth: 4)],
        ),
        MarkerLayer(
          markers: [
            for (var i = 0; i < stops.length; i++)
              Marker(
                point: stops[i].location,
                width: 36,
                height: 44,
                alignment: Alignment.topCenter,
                child: GestureDetector(
                  onTap: onStopTap == null ? null : () => onStopTap!(i),
                  child: StopPin(number: i + 1),
                ),
              ),
            // Drawn last so it sits above the stop pins. At DMM the depot is
            // itself a delivery address (24 Donald Street has stops on it),
            // so the two can land on the same coordinate - and when they do,
            // the start/end marker is the one that has to stay legible.
            if (depot != null) Marker(point: depot!, width: 44, height: 44, child: const _DepotPin()),
          ],
        ),
      ],
    );
  }
}

/// White rounded square with a blue border and the stop's position in it -
/// the numbered pin the prototype's map uses.
class StopPin extends StatelessWidget {
  const StopPin({super.key, required this.number, this.compact = false});

  final int number;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final size = compact ? 28.0 : 32.0;
    final badge = Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(size * 0.3),
        border: Border.all(color: AppColors.brand, width: 2),
        boxShadow: const [BoxShadow(color: Colors.black26, blurRadius: 4, offset: Offset(0, 2))],
      ),
      alignment: Alignment.center,
      child: Text(
        '$number',
        style: TextStyle(fontWeight: FontWeight.w800, fontSize: compact ? 12 : 13, color: AppColors.brand),
      ),
    );
    if (compact) return badge;

    return SizedBox(
      width: 36,
      height: 44,
      child: Stack(
        alignment: Alignment.topCenter,
        children: [
          Positioned(
            bottom: 6,
            child: Transform.rotate(
              angle: 0.785398,
              child: Container(
                width: 12,
                height: 12,
                decoration: BoxDecoration(
                  color: Colors.white,
                  border: Border.all(color: AppColors.brand, width: 2),
                ),
              ),
            ),
          ),
          badge,
        ],
      ),
    );
  }
}

/// Solid brand-filled disc with a halo, distinct in shape from the numbered
/// stop pins so "where the run begins and ends" reads at a glance.
class _DepotPin extends StatelessWidget {
  const _DepotPin();

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(color: AppColors.brand.withValues(alpha: 0.22), shape: BoxShape.circle),
      alignment: Alignment.center,
      child: Container(
        width: 26,
        height: 26,
        decoration: BoxDecoration(
          color: AppColors.brand,
          shape: BoxShape.circle,
          border: Border.all(color: Colors.white, width: 2.5),
        ),
        alignment: Alignment.center,
        child: const Icon(Icons.home_rounded, size: 13, color: Colors.white),
      ),
    );
  }
}
