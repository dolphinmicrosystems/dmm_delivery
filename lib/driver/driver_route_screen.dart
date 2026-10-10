import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:latlong2/latlong.dart';

import '../models/run_stop.dart';
import '../models/run_time.dart';
import '../services/depot_locator.dart';
import '../state/auth_state.dart';
import '../theme/app_colors.dart';
import '../util/app_log.dart';
import '../widgets/map_with_sheet.dart';
import '../widgets/route_preview_map.dart';
import '../widgets/stop_details_sheet.dart';
import '../widgets/surface_card.dart';
import 'route_starter.dart';

/// One of the driver's routes as planned: the stops in order on the map, when
/// it runs and in which vehicle.
///
/// Opens before the day's run sheet exists, which is the point: a driver given
/// a route can see where it goes the day they are given it. It is read from
/// the route card (`circuits.stops_summary` - name, address, order) and the
/// geocode cache (`addresses`, for each stop's pin), both of which a driver may
/// read. The card also carries what to deliver and the instructions (from the
/// latest sheet), shown when a stop is tapped.
///
/// When the driver is scheduled on the route today, "Start this route today"
/// gets today's run from the backend and opens the driving screen
/// (startRouteToday) - with no run sheet uploaded, the run is the last one's.
class DriverRouteScreen extends StatefulWidget {
  const DriverRouteScreen({
    super.key,
    required this.roundKey,
    required this.routeName,
    this.startTime,
    this.endTime,
    this.vehicle,
    this.authState,
    this.canStartToday = false,
  });

  final String roundKey;
  final String routeName;
  final String? startTime;
  final String? endTime;
  final String? vehicle;

  /// For "Start this route today"; shown only when [canStartToday] - the
  /// driver is the one scheduled on the route today.
  final AuthState? authState;
  final bool canStartToday;

  @override
  State<DriverRouteScreen> createState() => _DriverRouteScreenState();
}

class _DriverRouteScreenState extends State<DriverRouteScreen> {
  late final Future<_Route?> _route = _load();
  StopHighlight? _highlight;

  Future<_Route?> _load() async {
    final db = FirebaseFirestore.instance;
    final circuit = (await db.collection('circuits').doc(widget.roundKey).get()).data();
    if (circuit == null) return null;
    final summary = [
      for (final raw in (circuit['stops_summary'] as List?) ?? const [])
        if (raw is Map) Map<String, dynamic>.from(raw),
    ]..sort((a, b) => ((a['seq_order'] as num?) ?? 0).compareTo((b['seq_order'] as num?) ?? 0));

    // Pins from the geocode cache, 30 keys a query (Firestore's `in` limit).
    final keys = {for (final stop in summary) ?stop['address_key'] as String?}.toList();
    final pins = <String, LatLng>{};
    for (var i = 0; i < keys.length; i += 30) {
      final chunk = keys.sublist(i, i + 30 > keys.length ? keys.length : i + 30);
      final snap = await db.collection('addresses').where(FieldPath.documentId, whereIn: chunk).get();
      for (final doc in snap.docs) {
        final lat = (doc.data()['lat'] as num?)?.toDouble(), lng = (doc.data()['lng'] as num?)?.toDouble();
        if (lat != null && lng != null) pins[doc.id] = LatLng(lat, lng);
      }
    }

    return _Route(
      summary: summary,
      stops: [
        for (final (index, stop) in summary.indexed)
          if (pins[stop['address_key']] case final pin?)
            RunStop(
              id: '${stop['address_key']}-$index',
              seqOrder: index,
              customerName: stop['customer_name'] as String? ?? '',
              address: stop['address'] as String? ?? '',
              location: pin,
              items: const [],
              addressKey: stop['address_key'] as String?,
            ),
      ],
      depot: await DepotLocator().resolve(circuit['depot_address'] as String?),
    );
  }

  /// A stop from the route card. Cards written before items and instructions
  /// were added to it have neither; the note says where to find them.
  void _showStop(int number, Map<String, dynamic> stop) {
    final hasItems = stop.containsKey('items');
    showStopDetails(
      context,
      number: number,
      customerName: stop['customer_name'] as String? ?? '',
      address: stop['address'] as String? ?? '',
      items: [
        for (final raw in (stop['items'] as List?) ?? const [])
          if (raw is Map) StopItem.fromMap(Map<String, dynamic>.from(raw)),
      ],
      instructions: stop['instructions'] as String?,
      missingItemsNote: hasItems ? null : "Shows here once the route's next run sheet is confirmed.",
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.surfaceMuted,
      appBar: AppBar(title: Text(widget.routeName, overflow: TextOverflow.ellipsis)),
      body: FutureBuilder<_Route?>(
        future: _route,
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            AppLog.auth.error('driver route load failed', snapshot.error, snapshot.stackTrace);
            return const Center(child: Text("Couldn't load this route. Check your connection."));
          }
          if (snapshot.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator());
          }
          final route = snapshot.data;
          if (route == null) return const Center(child: Text('This route has been removed.'));
          return MapWithSheet(
            // Swipe the list down for the whole map; tap a stop for its details.
            // This map is the plan; "Start" opens the live one.
            overlay: widget.canStartToday && widget.authState != null
                ? FloatingActionButton.extended(
                    heroTag: 'start',
                    onPressed: () => startRouteToday(
                      context,
                      authState: widget.authState!,
                      roundKey: widget.roundKey,
                      routeName: widget.routeName,
                      vehicle: widget.vehicle,
                    ),
                    icon: const Icon(Icons.play_arrow_rounded),
                    label: const Text('Start'),
                  )
                : null,
            map: RoutePreviewMap(
              stops: route.stops,
              depot: route.depot,
              highlight: _highlight,
              attributionAtTop: true,
              onStopTap: (index) {
                final key = route.stops[index].addressKey;
                final at = route.summary.indexWhere((stop) => stop['address_key'] == key);
                if (at >= 0) _showStop(at + 1, route.summary[at]);
              },
            ),
            children: [
              if (widget.canStartToday && widget.authState != null)
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                  child: FilledButton.icon(
                    onPressed: () => startRouteToday(
                      context,
                      authState: widget.authState!,
                      roundKey: widget.roundKey,
                      routeName: widget.routeName,
                      vehicle: widget.vehicle,
                    ),
                    icon: const Icon(Icons.play_arrow_rounded),
                    label: const Text('Start this route today'),
                    style: FilledButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 14)),
                  ),
                ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                child: SurfaceCard(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('Your route', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w800)),
                      const SizedBox(height: 8),
                      for (final (label, value) in [
                        ('Stops', '${route.summary.length}'),
                        if (formatWindow(widget.startTime, widget.endTime) case final window?)
                          ('Times', window),
                        if (widget.vehicle case final vehicle?) ('Vehicle', vehicle),
                      ])
                        Padding(
                          padding: const EdgeInsets.symmetric(vertical: 4),
                          child: Row(
                            children: [
                              Expanded(
                                child: Text(
                                  label,
                                  style: const TextStyle(fontSize: 13, color: AppColors.inkMuted),
                                ),
                              ),
                              Text(value, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700)),
                            ],
                          ),
                        ),
                      const SizedBox(height: 6),
                      const Text(
                        'Tap a stop for what to deliver and the instructions (from the latest run sheet).',
                        style: TextStyle(fontSize: 12, color: AppColors.inkMuted, height: 1.4),
                      ),
                    ],
                  ),
                ),
              ),
              for (final (index, stop) in route.summary.indexed)
                ListTile(
                  onTap: () {
                    final pinned = route.stops.where((s) => s.addressKey == stop['address_key']);
                    if (pinned.isNotEmpty) {
                      setState(() => _highlight = StopHighlight.after(_highlight, pinned.first.id));
                    }
                    _showStop(index + 1, stop);
                  },
                  leading: StopPin(number: index + 1, compact: true),
                  title: Text(
                    stop['customer_name'] as String? ?? '',
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                  subtitle: Text(
                    stop['address'] as String? ?? '',
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
            ],
          );
        },
      ),
    );
  }
}

class _Route {
  const _Route({required this.summary, required this.stops, required this.depot});

  /// Every stop in order, as the route card lists them.
  final List<Map<String, dynamic>> summary;

  /// The stops with a pin, for the map.
  final List<RunStop> stops;
  final LatLng? depot;
}
