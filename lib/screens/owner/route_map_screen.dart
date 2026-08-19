import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

import '../../state/auth_state.dart';
import '../../theme/app_colors.dart';
import '../../widgets/stop_instructions_sheet.dart';

/// FR3 (DMM-08-10) structure pass - see this repo's plan doc for why the
/// exact visual match to Spoke (Circuit) Route Planner is a separate,
/// unscheduled follow-up. This screen already applies what a real
/// screenshot showed: a light/muted basemap (CartoDB Positron - no API key
/// needed, unlike Google Maps, and closer to that look than stock OSM
/// tiles), a bold blue route line, white rounded-square numbered pins with
/// a blue border, and a solid-with-halo current-location dot.
class RouteMapScreen extends StatelessWidget {
  const RouteMapScreen({super.key, required this.authState, required this.roundKey});

  final AuthState authState;
  final String roundKey;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
        stream: FirebaseFirestore.instance.collection('circuits').doc(roundKey).snapshots(),
        builder: (context, circuitSnap) {
          final circuit = circuitSnap.data?.data();
          final runId = circuit?['latest_run_id'] as String?;
          if (runId == null) {
            return Scaffold(
              appBar: AppBar(title: const Text('Route')),
              body: const Center(child: Text('No confirmed run yet for this route.')),
            );
          }
          return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
            stream: FirebaseFirestore.instance
                .collection('delivery_run')
                .doc(runId)
                .collection('delivery_stop')
                .orderBy('seq_order')
                .snapshots(),
            builder: (context, stopsSnap) {
              final stops = stopsSnap.data?.docs ?? [];
              if (stops.isEmpty) {
                return Scaffold(
                  appBar: AppBar(title: Text(circuit?['round'] as String? ?? 'Route')),
                  body: const Center(child: CircularProgressIndicator()),
                );
              }
              final points = [
                for (final s in stops) LatLng((s['lat'] as num).toDouble(), (s['lng'] as num).toDouble()),
              ];

              return Scaffold(
                appBar: AppBar(title: Text(circuit?['round'] as String? ?? 'Route')),
                body: Stack(
                  children: [
                    FlutterMap(
                      options: MapOptions(initialCenter: points.first, initialZoom: 13),
                      children: [
                        TileLayer(
                          urlTemplate: 'https://{s}.basemaps.cartocdn.com/light_all/{z}/{x}/{y}{r}.png',
                          subdomains: const ['a', 'b', 'c', 'd'],
                          userAgentPackageName: 'com.delivery.dmm_delivery',
                        ),
                        PolylineLayer(
                          polylines: [Polyline(points: points, color: AppColors.brand, strokeWidth: 5)],
                        ),
                        MarkerLayer(
                          markers: [
                            Marker(point: points.first, width: 24, height: 24, child: const _CurrentLocationDot()),
                            for (var i = 0; i < stops.length; i++)
                              Marker(
                                point: points[i],
                                width: 36,
                                height: 44,
                                child: GestureDetector(
                                  onTap: () => _showStop(context, stops[i]),
                                  child: _StopPin(number: i + 1),
                                ),
                              ),
                          ],
                        ),
                      ],
                    ),
                    DraggableScrollableSheet(
                      initialChildSize: 0.22,
                      minChildSize: 0.12,
                      maxChildSize: 0.7,
                      builder: (context, scrollController) => Container(
                        decoration: const BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
                        ),
                        child: ListView.builder(
                          controller: scrollController,
                          padding: const EdgeInsets.symmetric(vertical: 12),
                          itemCount: stops.length + 1,
                          itemBuilder: (context, index) {
                            if (index == 0) {
                              return Center(
                                child: Container(
                                  width: 36,
                                  height: 4,
                                  margin: const EdgeInsets.only(bottom: 12),
                                  decoration: BoxDecoration(color: AppColors.hairline, borderRadius: BorderRadius.circular(2)),
                                ),
                              );
                            }
                            final stop = stops[index - 1].data();
                            return ListTile(
                              leading: _StopPin(number: index, compact: true),
                              title: Text(stop['customer_name'] as String? ?? '', style: const TextStyle(fontWeight: FontWeight.w600)),
                              subtitle: Text(stop['address'] as String? ?? ''),
                              onTap: () => _showStop(context, stops[index - 1]),
                            );
                          },
                        ),
                      ),
                    ),
                  ],
                ),
              );
            },
          );
        },
      ),
    );
  }

  void _showStop(BuildContext context, QueryDocumentSnapshot<Map<String, dynamic>> stop) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (_) => StopInstructionsSheet(authState: authState, stopDoc: stop),
    );
  }
}

class _CurrentLocationDot extends StatelessWidget {
  const _CurrentLocationDot();

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(color: AppColors.brand.withValues(alpha: 0.2), shape: BoxShape.circle),
      alignment: Alignment.center,
      child: Container(
        width: 12,
        height: 12,
        decoration: const BoxDecoration(color: AppColors.brand, shape: BoxShape.circle),
      ),
    );
  }
}

class _StopPin extends StatelessWidget {
  const _StopPin({required this.number, this.compact = false});

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
                decoration: BoxDecoration(color: Colors.white, border: Border.all(color: AppColors.brand, width: 2)),
              ),
            ),
          ),
          badge,
        ],
      ),
    );
  }
}
