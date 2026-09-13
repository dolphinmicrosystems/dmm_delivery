import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

import '../config/map_config.dart';
import '../models/run_stop.dart';
import '../theme/app_colors.dart';
import 'basemap_attribution.dart';

/// Which stop the map is calling out, and how many times it has been asked to.
///
/// The tick is the whole reason this is not simply a `String?`. Tapping the
/// same card twice has to blink twice - somebody who glanced away and missed
/// the first pulse taps it again - and an animation driven by identity alone
/// sits perfectly still the second time, which reads as the tap not landing.
@immutable
class StopHighlight {
  const StopHighlight._(this.stopId, this.tick);

  /// The highlight that follows [previous] when the owner taps [stopId].
  /// Centralised here so both screens bump the tick the same way rather than
  /// each keeping their own counter.
  factory StopHighlight.after(StopHighlight? previous, String stopId) =>
      StopHighlight._(stopId, (previous?.tick ?? 0) + 1);

  /// A `RunStop.id`, never a list index: the review screen's list is dragged
  /// about, and an index would leave the highlight sitting on whatever stop
  /// slid into that position.
  final String stopId;

  final int tick;
}

/// The route as a shape: depot -> every stop in the current order -> depot.
///
/// Shared by the pre-confirm review screen and the confirmed-route screen so
/// the owner is never shown two different pictures of the same run. It is a
/// pure function of `stops`, `depot` and `highlight`, which is what makes the
/// review screen's drag-to-reorder redraw for free - reordering the list
/// rebuilds this widget with a new order and the polyline follows.
///
/// The line is straight segments between stops, not road geometry: the
/// backend's Routes API call requests `optimizedIntermediateWaypointIndex`
/// only, so an order is all that comes back. That is honest for a sequence
/// review (the question here is "which stop next?", not "which street?"),
/// and turns into real geometry the moment the backend also returns a
/// polyline - only this file changes.
class RoutePreviewMap extends StatefulWidget {
  const RoutePreviewMap({
    super.key,
    required this.stops,
    this.depot,
    this.onStopTap,
    this.highlight,
  });

  final List<RunStop> stops;

  /// Start and end of the run. Null when the depot address has never been
  /// geocoded - the route then simply runs stop-to-stop, rather than
  /// inventing an origin.
  final LatLng? depot;

  final void Function(int index)? onStopTap;

  /// The stop the owner picked out of the list beside this map. Drives the
  /// pulse, the filled pin that stays behind afterwards, and the pan that
  /// brings an off-screen pin into view.
  final StopHighlight? highlight;

  @override
  State<RoutePreviewMap> createState() => _RoutePreviewMapState();
}

class _RoutePreviewMapState extends State<RoutePreviewMap> {
  final _controller = MapController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  void didUpdateWidget(RoutePreviewMap oldWidget) {
    super.didUpdateWidget(oldWidget);
    final highlight = widget.highlight;
    if (highlight == null || highlight.tick == oldWidget.highlight?.tick) return;
    // After the frame, because the camera only exists once FlutterMap has
    // laid itself out - and on the first highlight of a freshly built screen
    // this can run before that has happened.
    WidgetsBinding.instance.addPostFrameCallback((_) => _reveal(highlight.stopId));
  }

  /// Pans to a highlighted pin only when it is off screen.
  ///
  /// Both halves matter. A blink nobody can see is not an answer to "which
  /// one is this?", and on a run the size of a Dunedin round the tapped stop
  /// is often outside the fitted viewport. But re-centring a pin the owner is
  /// already looking at moves the map for no reason, which is the same
  /// complaint that keeps `initialCameraFit` from re-fitting on reorder: the
  /// viewport is theirs once they have touched it.
  void _reveal(String stopId) {
    if (!mounted) return;
    for (final stop in widget.stops) {
      if (stop.id != stopId) continue;
      final camera = _controller.camera;
      if (!camera.visibleBounds.contains(stop.location)) {
        _controller.move(stop.location, camera.zoom);
      }
      return;
    }
  }

  List<LatLng> get _linePoints => [
    ?widget.depot,
    for (final stop in widget.stops) stop.location,
    // Closes the loop. The van goes home; a route drawn as an open path
    // ending at the last customer understates the run by a leg, which is
    // exactly the leg the depot address is configured to account for.
    ?widget.depot,
  ];

  Marker _stopMarker(int index) {
    final stop = widget.stops[index];
    final highlight = widget.highlight;
    final isHighlighted = highlight != null && highlight.stopId == stop.id;
    return Marker(
      point: stop.location,
      width: 36,
      height: 44,
      alignment: Alignment.topCenter,
      child: GestureDetector(
        onTap: widget.onStopTap == null ? null : () => widget.onStopTap!(index),
        child: isHighlighted
            ? _PulsingPin(number: index + 1, tick: highlight.tick)
            : StopPin(number: index + 1),
      ),
    );
  }

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

    final highlightedId = widget.highlight?.stopId;

    return FlutterMap(
      mapController: _controller,
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
          // Template and key both come from MapConfig - an unkeyed CARTO tile
          // still returns a perfectly valid PNG with "API KEY REQUIRED"
          // printed across it, so there is no failure here to notice.
          urlTemplate: MapConfig.basemapUrlTemplate,
          subdomains: MapConfig.basemapSubdomains,
          userAgentPackageName: 'com.delivery.dmm_delivery',
        ),
        PolylineLayer(
          polylines: [Polyline(points: points, color: AppColors.brand, strokeWidth: 4)],
        ),
        MarkerLayer(
          markers: [
            for (var i = 0; i < widget.stops.length; i++)
              if (widget.stops[i].id != highlightedId) _stopMarker(i),
            // Drawn last so it sits above the stop pins. At DMM the depot is
            // itself a delivery address (24 Donald Street has stops on it),
            // so the two can land on the same coordinate - and when they do,
            // the start/end marker is the one that has to stay legible.
            if (widget.depot != null)
              Marker(point: widget.depot!, width: 44, height: 44, child: const _DepotPin()),
            // Above even the depot, and the one place that rule bends. The
            // pins pile up on the tight parts of a run - the depot end most
            // of all - and a pulse underneath three other markers answers
            // nobody. Whichever marker the owner just asked about is the one
            // that has to be legible, for as long as they are asking.
            for (var i = 0; i < widget.stops.length; i++)
              if (widget.stops[i].id == highlightedId) _stopMarker(i),
          ],
        ),
        const BasemapAttribution(),
      ],
    );
  }
}

/// A [StopPin] that pulses when the owner taps its card, then stays filled.
///
/// Three beats and done, rather than a pin that throbs for as long as it is
/// selected: this is the answer to a question, and once it has been read the
/// motion is just something moving on a map somebody is trying to study. What
/// persists is the filled pin, which goes on saying "this is the one you
/// picked" without moving.
class _PulsingPin extends StatefulWidget {
  const _PulsingPin({required this.number, required this.tick});

  final int number;

  /// Bumped by every tap, including a repeat tap on the stop that is already
  /// highlighted - see [StopHighlight].
  final int tick;

  @override
  State<_PulsingPin> createState() => _PulsingPinState();
}

class _PulsingPinState extends State<_PulsingPin> with SingleTickerProviderStateMixin {
  static const _beats = 3;

  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 380),
  );

  @override
  void initState() {
    super.initState();
    _blink();
  }

  @override
  void didUpdateWidget(_PulsingPin oldWidget) {
    super.didUpdateWidget(oldWidget);
    // The controller has already run to completion by now, so nothing
    // restarts it on its own - a second tap would otherwise do nothing at all.
    if (widget.tick != oldWidget.tick) _blink();
  }

  void _blink() {
    _controller
      ..reset()
      // `reverse` with an even count lands back on 0, which is what leaves
      // the pin at rest rather than stranded mid-pulse.
      ..repeat(reverse: true, count: _beats * 2);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        final t = Curves.easeOut.transform(_controller.value);
        return Stack(
          // The halo and the grown pin both paint outside the 36x44 marker
          // box on purpose. Markers are `Positioned` in a Stack, so nothing
          // clips them to their own bounds - only to the map itself.
          clipBehavior: Clip.none,
          alignment: Alignment.topCenter,
          children: [
            Positioned(
              top: -14,
              child: Container(
                width: 32 + 36 * t,
                height: 32 + 36 * t,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: AppColors.brand.withValues(alpha: 0.28 * (1 - t)),
                ),
              ),
            ),
            Transform.scale(scale: 1 + 0.22 * t, alignment: Alignment.topCenter, child: child),
          ],
        );
      },
      child: StopPin(number: widget.number, selected: true),
    );
  }
}

/// White rounded square with a blue border and the stop's position in it -
/// the numbered pin the prototype's map uses. Inverted when [selected], so
/// the stop the owner picked out of the list still reads as picked once the
/// pulse has finished.
class StopPin extends StatelessWidget {
  const StopPin({super.key, required this.number, this.compact = false, this.selected = false});

  final int number;
  final bool compact;
  final bool selected;

  @override
  Widget build(BuildContext context) {
    final size = compact ? 28.0 : 32.0;
    final fill = selected ? AppColors.brand : Colors.white;
    final ink = selected ? Colors.white : AppColors.brand;
    final badge = Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: fill,
        borderRadius: BorderRadius.circular(size * 0.3),
        border: Border.all(color: selected ? Colors.white : AppColors.brand, width: 2),
        boxShadow: const [BoxShadow(color: Colors.black26, blurRadius: 4, offset: Offset(0, 2))],
      ),
      alignment: Alignment.center,
      child: Text(
        '$number',
        style: TextStyle(fontWeight: FontWeight.w800, fontSize: compact ? 12 : 13, color: ink),
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
                  color: fill,
                  border: Border.all(color: selected ? Colors.white : AppColors.brand, width: 2),
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
