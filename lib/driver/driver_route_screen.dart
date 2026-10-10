import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:latlong2/latlong.dart';

import '../models/run_stop.dart';
import '../models/run_time.dart';
import '../services/depot_locator.dart';
import '../theme/app_colors.dart';
import '../util/app_log.dart';
import '../widgets/route_preview_map.dart';
import '../widgets/surface_card.dart';

/// One of the driver's routes as planned: the stops in order on the map, when
/// it runs and in which vehicle.
///
/// Opens before the day's run sheet exists, which is the point: a driver given
/// a route can see where it goes the day they are given it. It is read from
/// the route card (`circuits.stops_summary` - name, address, order) and the
/// geocode cache (`addresses`, for each stop's pin), both of which a driver may
/// read. What to deliver at each stop is on the day's run (DriverRunScreen),
/// once the owner uploads its sheet.
class DriverRouteScreen extends StatefulWidget {
  const DriverRouteScreen({
    super.key,
    required this.roundKey,
    required this.routeName,
    this.startTime,
    this.endTime,
    this.vehicle,
  });

  final String roundKey;
  final String routeName;
  final String? startTime;
  final String? endTime;
  final String? vehicle;

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
          return ListView(
            padding: const EdgeInsets.only(bottom: 24),
            children: [
              SizedBox(
                height: MediaQuery.sizeOf(context).height * 0.34,
                child: RoutePreviewMap(stops: route.stops, depot: route.depot, highlight: _highlight),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
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
                        'The route as planned. What to deliver at each stop shows on the day\'s run, '
                        'under Runs, once your owner uploads its run sheet.',
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
                    if (pinned.isEmpty) return;
                    setState(() => _highlight = StopHighlight.after(_highlight, pinned.first.id));
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
