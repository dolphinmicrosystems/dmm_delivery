import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:latlong2/latlong.dart';

import '../models/delivery_estimate.dart';
import '../models/driver_stats.dart';
import '../models/road_legs.dart';
import '../models/run_listing.dart';
import '../models/run_stop.dart';
import '../models/run_time.dart';
import '../services/depot_locator.dart';
import '../state/auth_state.dart';
import '../theme/app_colors.dart';
import '../widgets/pill_badge.dart';
import '../widgets/route_preview_map.dart';
import '../widgets/surface_card.dart';
import 'driver_runs_screen.dart';
import 'driving/driving_screen.dart';

/// One of the driver's runs: the route on the map, what it involves, and -
/// once driven - its full history: when it started and finished, how long it
/// took against the estimate, and when each stop was delivered.
///
/// Read-only. Streams, so a run being driven updates as stops are delivered.
class DriverRunScreen extends StatefulWidget {
  const DriverRunScreen({
    super.key,
    required this.authState,
    required this.runId,
    required this.routeName,
    this.startTime,
    this.endTime,
    this.vehicle,
  });

  final AuthState authState;
  final String runId;
  final String routeName;
  final String? startTime;
  final String? endTime;

  /// The vehicle to drive, for a run still to come.
  final String? vehicle;

  @override
  State<DriverRunScreen> createState() => _DriverRunScreenState();
}

class _DriverRunScreenState extends State<DriverRunScreen> {
  StopHighlight? _highlight;
  Future<LatLng?>? _depotFuture;
  Object? _roadLegsSource;
  RoadLegs _roadLegs = const RoadLegs();

  RoadLegs _roadLegsFor(Map<String, dynamic>? run) {
    final raw = run?['road_legs'];
    if (!identical(raw, _roadLegsSource)) {
      _roadLegsSource = raw;
      _roadLegs = RoadLegs.fromRun(raw);
    }
    return _roadLegs;
  }

  Future<LatLng?> _depot(Map<String, dynamic>? run) {
    final lat = (run?['depot_lat'] as num?)?.toDouble();
    final lng = (run?['depot_lng'] as num?)?.toDouble();
    if (lat != null && lng != null) return Future.value(LatLng(lat, lng));
    return _depotFuture ??= DepotLocator().resolve(run?['depot_address'] as String?);
  }

  @override
  Widget build(BuildContext context) {
    final runRef = FirebaseFirestore.instance.collection('delivery_run').doc(widget.runId);
    return Scaffold(
      backgroundColor: AppColors.surfaceMuted,
      appBar: AppBar(title: Text(widget.routeName, overflow: TextOverflow.ellipsis)),
      body: StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
        stream: runRef.snapshots(),
        builder: (context, runSnap) {
          final run = runSnap.data?.data();
          return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
            stream: runRef.collection('delivery_stop').orderBy('seq_order').snapshots(),
            builder: (context, stopsSnap) {
              if (runSnap.hasError || stopsSnap.hasError) {
                return const Center(child: Text("This run isn't yours to open any more."));
              }
              if (!runSnap.hasData || !stopsSnap.hasData) {
                return const Center(child: CircularProgressIndicator());
              }
              final docs = [
                for (final doc in stopsSnap.data!.docs)
                  if (doc.data()['excluded'] != true) doc,
              ];
              final stops = [for (final doc in docs) ?RunStop.fromDoc(doc)];
              final listing = RunListing.fromMap(widget.runId, run ?? const {}, routeName: widget.routeName);
              final delivered = {
                for (final doc in docs)
                  if (doc.data()['status'] == 'delivered') doc.id,
              };

              return FutureBuilder<LatLng?>(
                future: _depot(run),
                builder: (context, depotSnap) => ListView(
                  padding: const EdgeInsets.only(bottom: 24),
                  children: [
                    SizedBox(
                      height: MediaQuery.sizeOf(context).height * 0.32,
                      child: RoutePreviewMap(
                        stops: stops,
                        depot: depotSnap.data,
                        highlight: _highlight,
                        roadLegs: _roadLegsFor(run),
                        deliveredIds: delivered,
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                      child: _Summary(
                        listing: listing,
                        startTime: widget.startTime,
                        endTime: widget.endTime,
                        vehicle: widget.vehicle,
                      ),
                    ),
                    // Today's run, not finished: drive it from here too.
                    if (listing.phase(DateTime.now()) == RunPhase.today && listing.finished == null)
                      Padding(
                        padding: const EdgeInsets.fromLTRB(16, 4, 16, 4),
                        child: FilledButton.icon(
                          onPressed: () => Navigator.of(context).pushReplacement(
                            MaterialPageRoute(
                              builder: (_) => DrivingScreen(
                                authState: widget.authState,
                                runId: widget.runId,
                                routeName: widget.routeName,
                                vehicle: widget.vehicle,
                              ),
                            ),
                          ),
                          icon: const Icon(Icons.navigation_rounded),
                          label: Text(listing.started == null ? 'Start run' : 'Drive this run'),
                          style: FilledButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 14)),
                        ),
                      ),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(20, 12, 20, 4),
                      child: Text(
                        '${docs.length} stops',
                        style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700),
                      ),
                    ),
                    for (final (index, doc) in docs.indexed)
                      _StopRow(
                        number: index + 1,
                        data: doc.data(),
                        onTap: () => setState(() => _highlight = StopHighlight.after(_highlight, doc.id)),
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
}

/// What the run is - or, once driven, how it went.
class _Summary extends StatelessWidget {
  const _Summary({required this.listing, required this.startTime, this.endTime, this.vehicle});

  final RunListing listing;
  final String? startTime;
  final String? endTime;
  final String? vehicle;

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final status = listing.status(now);
    final (tone, soft) = runStatusColors(status);
    final estimate = listing.estimatedTotal;
    final started = listing.started?.toLocal();
    final finished = listing.finished?.toLocal();
    final took = listing.totalTime;
    final firstDrop = listing.startedAt?.toLocal();
    final lastDrop = listing.lastDeliveredAt?.toLocal();

    final rows = <(String, String)>[
      ('Date', listing.date == null ? 'Not on the sheet' : relativeDayLabel(listing.date, now)),
      if (started == null) ...[
        if (startTime != null) ('Starts', formatStartTime(startTime!)),
        if (endTime != null)
          ('Finish by', formatStartTime(endTime!))
        else if (expectedFinish(startTime, estimate) case final back?)
          ('Back by about', back),
        if (estimate != null) ('Takes about', DeliveryEstimate.format(estimate)),
        if (vehicle != null) ('Vehicle', vehicle!),
      ] else ...[
        if (vehicle != null) ('Vehicle', vehicle!),
        ('Started', _clock(started)),
        if (finished != null) ('Finished', _clock(finished)),
        if (took != null) ('Total time', DeliveryEstimate.format(took)),
        if (endTime != null) ('Due to finish by', formatStartTime(endTime!)),
        if (estimate != null) ('Estimate', 'about ${DeliveryEstimate.format(estimate)}'),
        ('Delivered', '${listing.deliveredCount} of ${listing.stopCount}'),
        if (firstDrop != null) ('First delivery', _clock(firstDrop)),
        if (lastDrop != null) ('Last delivery', _clock(lastDrop)),
      ],
    ];

    return SurfaceCard(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  started != null && finished != null ? 'How it went' : 'Your run',
                  style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w800),
                ),
              ),
              PillBadge(label: status.label, background: soft, foreground: tone),
            ],
          ),
          if (started != null && finished == null) ...[
            const SizedBox(height: 10),
            ClipRRect(
              borderRadius: BorderRadius.circular(999),
              child: LinearProgressIndicator(
                value: listing.progress,
                minHeight: 6,
                backgroundColor: AppColors.hairline,
                color: tone,
              ),
            ),
          ],
          const SizedBox(height: 8),
          for (final (label, value) in rows)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Row(
                children: [
                  Expanded(
                    child: Text(label, style: const TextStyle(fontSize: 13, color: AppColors.inkMuted)),
                  ),
                  Text(value, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700)),
                ],
              ),
            ),
        ],
      ),
    );
  }

  static String _clock(DateTime at) => formatClock(at.hour, at.minute);
}

class _StopRow extends StatelessWidget {
  const _StopRow({required this.number, required this.data, required this.onTap});

  final int number;
  final Map<String, dynamic> data;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final isDone = data['status'] == 'delivered';
    final at = (data['delivered_at'] as Timestamp?)?.toDate().toLocal();
    final instructions = (data['instructions'] as String?)?.trim();
    return ListTile(
      onTap: onTap,
      leading: StopPin(number: number, compact: true, delivered: isDone),
      title: Text(
        data['customer_name'] as String? ?? '',
        style: TextStyle(fontWeight: FontWeight.w600, color: isDone ? AppColors.inkMuted : AppColors.ink),
      ),
      subtitle: Text(
        [
          data['address'] as String? ?? '',
          if (instructions != null && instructions.isNotEmpty) instructions,
        ].join('\n'),
        maxLines: 3,
        overflow: TextOverflow.ellipsis,
      ),
      trailing: isDone
          ? Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                const Icon(Icons.check_circle_rounded, color: AppColors.success, size: 20),
                if (at != null)
                  Text(
                    formatClock(at.hour, at.minute),
                    style: const TextStyle(fontSize: 11, color: AppColors.inkMuted),
                  ),
              ],
            )
          : null,
    );
  }
}
