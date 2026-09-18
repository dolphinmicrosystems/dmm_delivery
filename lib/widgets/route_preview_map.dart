import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

import '../models/delivery_estimate.dart';
import '../models/road_legs.dart';
import '../models/run_stop.dart';
import '../theme/app_colors.dart';
import 'basemap.dart';
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
/// The line follows the roads wherever the run has a road shape for a leg
/// ([roadLegs], from the backend's Routes API call), and is a straight segment
/// only where it does not: a run from before road paths existed, a Routes API
/// outage, or a leg the owner has just created by dragging a stop, which the
/// backend redraws once the order is confirmed.
class RoutePreviewMap extends StatefulWidget {
  const RoutePreviewMap({
    super.key,
    required this.stops,
    this.depot,
    this.onStopTap,
    this.highlight,
    this.roadLegs = const RoadLegs(),
    this.expanded = false,
    this.onToggleExpanded,
    this.attributionAtTop = false,
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

  /// Road shapes per leg, keyed by address pair. Legs missing from it are
  /// drawn straight.
  final RoadLegs roadLegs;

  /// Whether the host is currently showing this map at its larger size. Only
  /// read to pick the expand/collapse icon - the host owns the size.
  final bool expanded;

  /// Shows an expand/collapse button among the map controls when set. The
  /// review screen docks the map in a 240px strip above a long list, which is
  /// too small to check a pin against its street; the full-screen route map
  /// has nothing to expand into and leaves this null.
  final VoidCallback? onToggleExpanded;

  /// Moves the map credits to the top, for a host that pulls a sheet up over
  /// the map's lower edge - see [BasemapAttribution.atTop].
  final bool attributionAtTop;

  @override
  State<RoutePreviewMap> createState() => _RoutePreviewMapState();
}

/// How much of a stop pin to draw at the current zoom.
///
/// A whole Dunedin round fitted onto a phone lands around zoom 12, where the
/// full numbered pins are bigger than the streets between them: a dozen stops
/// on Orari and Strathallan Streets pile into one unreadable stack. So the
/// pins shrink with the map and only earn their numbers once there is room to
/// read them - the list beside the map carries the numbers in the meantime.
enum _PinTier {
  dot,
  compact,
  full;

  static _PinTier forZoom(double zoom) => zoom < 13 ? dot : (zoom < 14.5 ? compact : full);
}

class _RoutePreviewMapState extends State<RoutePreviewMap> {
  static const _minZoom = 5.0;
  static const _maxZoom = 19.0;

  final _controller = MapController();

  /// Only the tier is state, not the zoom: `onPositionChanged` fires on every
  /// frame of a pinch, and rebuilding every marker 60 times a second to draw
  /// the same pins would make the gesture stutter.
  _PinTier _tier = _PinTier.full;

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

  void _syncTier(double zoom) {
    final tier = _PinTier.forZoom(zoom);
    if (tier != _tier) setState(() => _tier = tier);
  }

  CameraFit get _fitAll => CameraFit.bounds(
    bounds: LatLngBounds.fromPoints(_linePoints),
    // Wider on the right, where the zoom controls sit over the map.
    padding: const EdgeInsets.fromLTRB(40, 40, 64, 40),
    // A run whose stops all share one address would otherwise fit to the
    // deepest zoom the map allows, which reads as a blank map.
    maxZoom: 17,
  );

  void _zoomBy(double delta) {
    final camera = _controller.camera;
    _controller.move(camera.center, (camera.zoom + delta).clamp(_minZoom, _maxZoom));
  }

  List<LatLng> get _linePoints {
    final depot = widget.depot;
    final nodes = <(String?, LatLng)>[
      if (depot != null) (DeliveryEstimate.depotKey, depot),
      for (final stop in widget.stops) (stop.addressKey, stop.location),
      // Closes the loop. The van goes home; a route drawn as an open path
      // ending at the last customer understates the run by a leg, which is
      // exactly the leg the depot address is configured to account for.
      if (depot != null) (DeliveryEstimate.depotKey, depot),
    ];
    if (nodes.isEmpty) return const [];

    final line = <LatLng>[nodes.first.$2];
    for (var i = 0; i + 1 < nodes.length; i++) {
      final (fromKey, _) = nodes[i];
      final (toKey, to) = nodes[i + 1];
      final shape = fromKey == null || toKey == null
          ? null
          : widget.roadLegs.shapes[DeliveryEstimate.legKey(fromKey, toKey)];
      // The road shape starts and ends where the road passes the stop, a few
      // metres from its pin - close enough that joining them reads as the
      // van pulling in, not as a gap.
      if (shape != null) {
        line.addAll(shape);
      } else {
        line.add(to);
      }
    }
    return line;
  }

  Marker _stopMarker(int index) {
    final stop = widget.stops[index];
    final highlight = widget.highlight;
    final isHighlighted = highlight != null && highlight.stopId == stop.id;
    final onTap = widget.onStopTap == null ? null : () => widget.onStopTap!(index);
    // The stop the owner asked about is drawn in full whatever the zoom - a
    // pulsing dot is not an answer to "which one is this?".
    if (isHighlighted || _tier == _PinTier.full) {
      return Marker(
        point: stop.location,
        width: 36,
        height: 44,
        alignment: Alignment.topCenter,
        child: GestureDetector(
          onTap: onTap,
          child: isHighlighted
              ? _PulsingPin(number: index + 1, tick: highlight.tick)
              : StopPin(number: index + 1),
        ),
      );
    }
    // Compact pins and dots sit centred on the stop: without the full pin's
    // tail there is no tip to stand on it.
    final compact = _tier == _PinTier.compact;
    return Marker(
      point: stop.location,
      width: compact ? 28 : 22,
      height: compact ? 28 : 22,
      child: GestureDetector(
        onTap: onTap,
        // The hit box is the whole marker rather than the 12px dot inside it,
        // so a tap on a zoomed-out map does not need a fingertip placed to the
        // pixel.
        behavior: HitTestBehavior.opaque,
        child: Center(child: compact ? StopPin(number: index + 1, compact: true) : const _StopDot()),
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
        // an owner who has zoomed in to check one cluster of stops. The
        // "Show whole route" control is how they ask for it back.
        initialCameraFit: _fitAll,
        minZoom: _minZoom,
        maxZoom: _maxZoom,
        // Rotation is off: a map knocked a few degrees askew by a two-finger
        // pinch has no compass to put it right, and north-up is how every
        // owner reads Dunedin.
        interactionOptions: const InteractionOptions(flags: InteractiveFlag.all & ~InteractiveFlag.rotate),
        // The initial fit does not reliably report itself through
        // onPositionChanged, and a round fitted at zoom 12 must not open on
        // full-size pins just because that is the tier's starting value.
        onMapReady: () => _syncTier(_controller.camera.zoom),
        onPositionChanged: (camera, _) => _syncTier(camera.zoom),
      ),
      children: [
        const BasemapLayer(),
        PolylineLayer(
          polylines: [
            Polyline(
              points: points,
              color: AppColors.brand,
              strokeWidth: 4,
              // A white casing lifts the line off the basemap's own roads,
              // the same pale grey a thin blue line otherwise sinks into.
              borderColor: Colors.white,
              borderStrokeWidth: 2,
              strokeCap: StrokeCap.round,
              strokeJoin: StrokeJoin.round,
            ),
          ],
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
        _MapControls(
          onZoomIn: () => _zoomBy(1),
          onZoomOut: () => _zoomBy(-1),
          onFitAll: () => _controller.fitCamera(_fitAll),
          expanded: widget.expanded,
          onToggleExpanded: widget.onToggleExpanded,
        ),
        BasemapAttribution(atTop: widget.attributionAtTop),
      ],
    );
  }
}

/// Zoom in, zoom out, back to the whole run - and enlarge, where the host
/// allows it.
///
/// Pinch and double-tap already zoom, but neither is discoverable, and on an
/// emulator a pinch is a Ctrl-drag nobody guesses. Buttons are the part of a
/// map everyone already knows how to use.
class _MapControls extends StatelessWidget {
  const _MapControls({
    required this.onZoomIn,
    required this.onZoomOut,
    required this.onFitAll,
    required this.expanded,
    this.onToggleExpanded,
  });

  final VoidCallback onZoomIn;
  final VoidCallback onZoomOut;
  final VoidCallback onFitAll;
  final bool expanded;
  final VoidCallback? onToggleExpanded;

  @override
  Widget build(BuildContext context) {
    final onToggleExpanded = this.onToggleExpanded;
    return Align(
      alignment: Alignment.topRight,
      child: Padding(
        padding: const EdgeInsets.all(10),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (onToggleExpanded != null) ...[
              _ControlGroup(
                children: [
                  _ControlButton(
                    icon: expanded ? Icons.close_fullscreen_rounded : Icons.open_in_full_rounded,
                    tooltip: expanded ? 'Shrink map' : 'Enlarge map',
                    onPressed: onToggleExpanded,
                  ),
                ],
              ),
              const SizedBox(height: 8),
            ],
            _ControlGroup(
              children: [
                _ControlButton(icon: Icons.add_rounded, tooltip: 'Zoom in', onPressed: onZoomIn),
                const Divider(height: 1, thickness: 1, color: AppColors.hairline),
                _ControlButton(icon: Icons.remove_rounded, tooltip: 'Zoom out', onPressed: onZoomOut),
              ],
            ),
            const SizedBox(height: 8),
            _ControlGroup(
              children: [
                _ControlButton(icon: Icons.fit_screen_rounded, tooltip: 'Show whole route', onPressed: onFitAll),
              ],
            ),
            const SizedBox(height: 8),
            const MapStyleButton(),
          ],
        ),
      ),
    );
  }
}

class _ControlGroup extends StatelessWidget {
  const _ControlGroup({required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white,
      elevation: 3,
      shadowColor: Colors.black26,
      borderRadius: BorderRadius.circular(10),
      clipBehavior: Clip.antiAlias,
      child: SizedBox(width: 38, child: Column(mainAxisSize: MainAxisSize.min, children: children)),
    );
  }
}

class _ControlButton extends StatelessWidget {
  const _ControlButton({required this.icon, required this.tooltip, required this.onPressed});

  final IconData icon;
  final String tooltip;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: InkWell(
        onTap: onPressed,
        child: SizedBox(width: 38, height: 38, child: Icon(icon, size: 20, color: AppColors.ink)),
      ),
    );
  }
}

/// A stop on a zoomed-out map: position only. The number comes back once the
/// map is close enough for numbers to be told apart - see [_PinTier].
class _StopDot extends StatelessWidget {
  const _StopDot();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 12,
      height: 12,
      decoration: BoxDecoration(
        color: AppColors.brand,
        shape: BoxShape.circle,
        border: Border.all(color: Colors.white, width: 2),
        boxShadow: const [BoxShadow(color: Colors.black26, blurRadius: 3, offset: Offset(0, 1))],
      ),
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
