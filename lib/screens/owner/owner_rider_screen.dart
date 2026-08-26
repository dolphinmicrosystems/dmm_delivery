import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

import '../../models/rider_board_entry.dart';
import '../../models/rider_map_data.dart';
import '../../services/rider_board_api.dart';
import '../../theme/app_colors.dart';
import '../../util/app_log.dart';
import '../../widgets/pill_badge.dart';

/// owner-rider.html: one driver's route on the map, with a pulsing marker at
/// their position and a detail sheet over the bottom of the screen.
///
/// The map is rendered here from data the backend returns - an encoded
/// polyline and a position - not from a server-rendered image. The viewport is
/// client state (the owner can pan and zoom), so only the client can project
/// coordinates to pixels; that's the same split production tracking uses.
class OwnerRiderScreen extends StatefulWidget {
  const OwnerRiderScreen({super.key, required this.entry});

  final RiderBoardEntry entry;

  @override
  State<OwnerRiderScreen> createState() => _OwnerRiderScreenState();
}

class _OwnerRiderScreenState extends State<OwnerRiderScreen> {
  final RiderBoardApi _api = RiderBoardApi();
  late Future<RiderMapData> _map;

  @override
  void initState() {
    super.initState();
    AppLog.owner('OwnerRiderScreen open', {'riderKey': widget.entry.riderKey});
    _map = _api.fetchRiderMap(widget.entry.riderKey);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.surfaceMuted,
      body: FutureBuilder<RiderMapData>(
        future: _map,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) {
            AppLog.owner.error('rider map load failed', snapshot.error, snapshot.stackTrace);
            return _ErrorState(message: '${snapshot.error}', onBack: () => Navigator.of(context).pop());
          }

          final data = snapshot.data!;
          AppLog.owner('rider map loaded', {
            'riderKey': data.riderKey,
            'points': data.route.length,
            'stops': data.stops.length,
            'sequenceOnly': data.isSequenceOnly,
            'hasPosition': data.position != null,
          });

          return Stack(
            children: [
              _RiderMap(data: data),
              // Back control floats over the map rather than sitting in an
              // app bar: the prototype gives the map the full canvas, and a
              // bar would cut the route off at the top.
              Positioned(
                left: 16,
                top: MediaQuery.of(context).padding.top + 12,
                child: _MapButton(
                  icon: Icons.arrow_back_rounded,
                  onPressed: () => Navigator.of(context).pop(),
                  tooltip: 'Back',
                ),
              ),
              // The stops and their order are real; the line between them is
              // not a driven path, and nothing is watching the driver. Said
              // plainly, because a line on a map reads as a route and a
              // marker reads as a person.
              if (data.isSequenceOnly)
                Positioned(
                  right: 16,
                  top: MediaQuery.of(context).padding.top + 12,
                  child: const PillBadge(
                    label: 'Stop order · not live',
                    background: Colors.white,
                    foreground: AppColors.inkMuted,
                  ),
                ),
              if (data.missingStopsNotice != null)
                Positioned(
                  left: 16,
                  right: 16,
                  top: MediaQuery.of(context).padding.top + 60,
                  child: Center(
                    child: PillBadge(
                      label: data.missingStopsNotice!,
                      background: const Color(0xFFFDF3E2),
                      foreground: AppColors.warning,
                    ),
                  ),
                ),
              Align(
                alignment: Alignment.bottomCenter,
                child: _RiderSheet(entry: widget.entry, data: data),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _RiderMap extends StatelessWidget {
  const _RiderMap({required this.data});

  final RiderMapData data;

  @override
  Widget build(BuildContext context) {
    return FlutterMap(
      options: MapOptions(
        // Framed to the route rather than a fixed centre/zoom, so the whole
        // run is visible on any screen size without hand-tuning a zoom level.
        initialCameraFit: CameraFit.coordinates(
          // Dunedin, when there is nothing to frame: a driver with no run
          // assigned still opens a map rather than a crash.
          coordinates: data.route.isEmpty ? const [LatLng(-45.8788, 170.5028)] : data.route,
          padding: const EdgeInsets.fromLTRB(48, 96, 48, 260),
        ),
        interactionOptions: const InteractionOptions(flags: InteractiveFlag.all & ~InteractiveFlag.rotate),
      ),
      children: [
        TileLayer(
          // Same muted basemap RouteMapScreen uses - no API key, nothing
          // billed per view, and it keeps the route line the only saturated
          // thing on screen.
          urlTemplate: 'https://basemaps.cartocdn.com/light_all/{z}/{x}/{y}{r}.png',
          userAgentPackageName: 'com.delivery.dmm_delivery',
          retinaMode: RetinaMode.isHighDensity(context),
        ),
        if (data.route.length > 1)
          PolylineLayer(
            polylines: [
              // Matches RouteMapScreen exactly: brand blue at width 5.
              Polyline(points: data.route, color: AppColors.brand, strokeWidth: 5),
            ],
          ),
        MarkerLayer(
          markers: [
            for (final stop in data.stops)
              Marker(
                point: stop.point,
                width: 12,
                height: 12,
                child: Container(
                  decoration: BoxDecoration(
                    // A delivered stop is filled in, so the owner can read
                    // progress off the map without opening the list.
                    color: stop.isDelivered ? AppColors.success : Colors.white,
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: stop.isDelivered ? AppColors.success : AppColors.brand,
                      width: 2.5,
                    ),
                  ),
                ),
              ),
            // Only when something has actually reported a position. There is
            // no such thing yet, so this draws nothing rather than pulsing
            // somewhere plausible.
            if (data.position != null)
              Marker(
                point: data.position!,
                // Sized for the halo at its widest, or the ping gets clipped
                // to the marker box and pulses into a square.
                width: 72,
                height: 72,
                child: const _PulsingRider(bearing: 0),
              ),
          ],
        ),
      ],
    );
  }
}

/// The rider's position: a solid brand dot under an expanding, fading ring -
/// the prototype's `animate-ping`. The pulse is what separates "this is where
/// they are now" from the static stop pins around it.
class _PulsingRider extends StatefulWidget {
  const _PulsingRider({required this.bearing});

  final double bearing;

  @override
  State<_PulsingRider> createState() => _PulsingRiderState();
}

class _PulsingRiderState extends State<_PulsingRider> with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1800),
  )..repeat();

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
        final t = _controller.value;
        return Stack(
          alignment: Alignment.center,
          children: [
            // Grows outward while fading, then restarts - a ring that faded
            // without growing would read as a blink, not a heartbeat.
            Opacity(
              opacity: (1 - t) * 0.35,
              child: Container(
                width: 28 + 44 * t,
                height: 28 + 44 * t,
                decoration: const BoxDecoration(color: AppColors.brand, shape: BoxShape.circle),
              ),
            ),
            child!,
          ],
        );
      },
      child: Container(
        width: 34,
        height: 34,
        decoration: BoxDecoration(
          color: AppColors.brand,
          shape: BoxShape.circle,
          border: Border.all(color: Colors.white, width: 2.5),
          boxShadow: [
            BoxShadow(color: AppColors.ink.withValues(alpha: 0.3), blurRadius: 8, offset: const Offset(0, 2)),
          ],
        ),
        child: Transform.rotate(
          // The icon points the way of travel, which is the only thing the
          // bearing is good for while the position itself is mocked.
          angle: widget.bearing * 3.1415926535 / 180,
          child: const Icon(Icons.navigation_rounded, color: Colors.white, size: 18),
        ),
      ),
    );
  }
}

class _RiderSheet extends StatelessWidget {
  const _RiderSheet({required this.entry, required this.data});

  final RiderBoardEntry entry;
  final RiderMapData data;

  @override
  Widget build(BuildContext context) {
    final isLive = entry.presence == RiderPresence.onRoute;

    return Container(
      width: double.infinity,
      padding: EdgeInsets.fromLTRB(20, 18, 20, MediaQuery.of(context).padding.bottom + 20),
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        boxShadow: [BoxShadow(color: Color(0x1A0B1220), blurRadius: 28, offset: Offset(0, -8))],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  data.driverName,
                  style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800, letterSpacing: -0.4),
                ),
              ),
              StatusDot(label: entry.presence.label, color: isLive ? AppColors.success : AppColors.inkMuted),
            ],
          ),
          const SizedBox(height: 4),
          Text(entry.subtitle, style: const TextStyle(fontSize: 13, color: AppColors.inkMuted, height: 1.35)),
          const SizedBox(height: 16),
          Row(
            children: [
              _Stat(label: 'ETA', value: entry.etaLabel),
              _Stat(
                label: 'Queue',
                value: entry.dropsLeft == 0 ? 'Awaiting run' : '${entry.dropsLeft} drops',
              ),
              _Stat(label: 'Stops', value: '${data.stops.length}'),
            ],
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: FilledButton.icon(
                  // Disabled rather than hidden: following a mocked position
                  // would show motion that means nothing, but the control is
                  // real and belongs in the design.
                  onPressed: null,
                  icon: const Icon(Icons.my_location_rounded, size: 18),
                  label: const Text('Follow live'),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: null,
                  icon: const Icon(Icons.call_rounded, size: 18),
                  label: const Text('Call'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _Stat extends StatelessWidget {
  const _Stat({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label.toUpperCase(),
            style: const TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.w700,
              letterSpacing: 1,
              color: AppColors.inkMuted,
            ),
          ),
          const SizedBox(height: 3),
          Text(value, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
        ],
      ),
    );
  }
}

class _MapButton extends StatelessWidget {
  const _MapButton({required this.icon, required this.onPressed, required this.tooltip});

  final IconData icon;
  final VoidCallback onPressed;
  final String tooltip;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white,
      shape: const CircleBorder(),
      elevation: 3,
      child: IconButton(onPressed: onPressed, icon: Icon(icon, size: 20), tooltip: tooltip),
    );
  }
}

class _ErrorState extends StatelessWidget {
  const _ErrorState({required this.message, required this.onBack});

  final String message;
  final VoidCallback onBack;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.map_outlined, size: 36, color: AppColors.inkMuted),
            const SizedBox(height: 12),
            const Text(
              "Couldn't load this driver",
              style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 6),
            Text(
              message,
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 13, color: AppColors.inkMuted, height: 1.4),
            ),
            const SizedBox(height: 16),
            TextButton(onPressed: onBack, child: const Text('Back')),
          ],
        ),
      ),
    );
  }
}
