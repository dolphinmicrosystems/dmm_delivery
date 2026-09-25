import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:latlong2/latlong.dart';

import '../../models/delivery_estimate.dart';
import '../../models/driver_stats.dart';
import '../../models/road_legs.dart';
import '../../models/run_listing.dart';
import '../../models/run_stop.dart';
import '../../models/run_time.dart';
import '../../services/depot_locator.dart';
import '../../state/auth_state.dart';
import '../../theme/app_colors.dart';
import '../../widgets/route_preview_map.dart';
import '../../widgets/stop_instructions_sheet.dart';

/// One run, live: the route on the map with delivered stops ticked off, how
/// far along it is, and each stop's status.
///
/// Everything streams, so a run being driven updates as the driver marks
/// stops delivered - the stops' own statuses for the list and the pins, and
/// the progress the backend writes onto the run (domain/run_progress.py) for
/// the header.
///
/// There is no live van position yet: nothing reports the driver's GPS until
/// the driver app does. The header says so rather than drawing a guess - the
/// old board drew a randomised one.
class RunDetailScreen extends StatefulWidget {
  const RunDetailScreen({
    super.key,
    required this.authState,
    required this.runId,
    required this.routeName,
    this.driver,
    this.startTime,
  });

  final AuthState authState;
  final String runId;
  final String routeName;
  final String? driver;
  final String? startTime;

  @override
  State<RunDetailScreen> createState() => _RunDetailScreenState();
}

class _RunDetailScreenState extends State<RunDetailScreen> {
  StopHighlight? _highlight;
  Future<LatLng?>? _depotFuture;
  String? _depotAddress;

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

  /// The run's stored depot when it has one; runs from before that was
  /// stored look the depot up by address, as the route screen does.
  Future<LatLng?> _depot(Map<String, dynamic>? run) {
    final lat = (run?['depot_lat'] as num?)?.toDouble();
    final lng = (run?['depot_lng'] as num?)?.toDouble();
    if (lat != null && lng != null) return Future.value(LatLng(lat, lng));
    final address = run?['depot_address'] as String?;
    if (address != _depotAddress || _depotFuture == null) {
      _depotAddress = address;
      _depotFuture = DepotLocator().resolve(address);
    }
    return _depotFuture!;
  }

  @override
  Widget build(BuildContext context) {
    final runRef = FirebaseFirestore.instance.collection('delivery_run').doc(widget.runId);
    return Scaffold(
      appBar: AppBar(title: Text(widget.routeName, overflow: TextOverflow.ellipsis)),
      body: StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
        stream: runRef.snapshots(),
        builder: (context, runSnap) {
          final run = runSnap.data?.data();
          return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
            stream: runRef.collection('delivery_stop').orderBy('seq_order').snapshots(),
            builder: (context, stopsSnap) {
              if (!runSnap.hasData || !stopsSnap.hasData) {
                return const Center(child: CircularProgressIndicator());
              }
              final docs = [
                for (final doc in stopsSnap.data!.docs)
                  if (doc.data()['excluded'] != true) doc,
              ];
              final stops = [for (final doc in docs) ?RunStop.fromDoc(doc)];
              final byId = {for (final doc in docs) doc.id: doc};
              final delivered = {
                for (final doc in docs)
                  if (doc.data()['status'] == 'delivered') doc.id,
              };
              final listing = RunListing.fromMap(widget.runId, run ?? const {}, routeName: widget.routeName);

              return FutureBuilder<LatLng?>(
                future: _depot(run),
                builder: (context, depotSnap) => Column(
                  children: [
                    SizedBox(
                      height: MediaQuery.sizeOf(context).height * 0.38,
                      child: RoutePreviewMap(
                        stops: stops,
                        depot: depotSnap.data,
                        highlight: _highlight,
                        roadLegs: _roadLegsFor(run),
                        deliveredIds: delivered,
                        onStopTap: (index) => _openStop(byId[stops[index].id]),
                      ),
                    ),
                    Expanded(
                      child: ListView.builder(
                        padding: const EdgeInsets.only(bottom: 24),
                        itemCount: docs.length + 1,
                        itemBuilder: (context, index) {
                          if (index == 0) {
                            return _Header(
                              listing: listing,
                              driver: widget.driver,
                              startTime: widget.startTime,
                            );
                          }
                          final doc = docs[index - 1];
                          final data = doc.data();
                          final isDone = data['status'] == 'delivered';
                          final at = (data['delivered_at'] as Timestamp?)?.toDate().toLocal();
                          return ListTile(
                            onTap: () {
                              setState(() => _highlight = StopHighlight.after(_highlight, doc.id));
                              _openStop(doc);
                            },
                            leading: StopPin(number: index, compact: true, delivered: isDone),
                            title: Text(
                              data['customer_name'] as String? ?? '',
                              style: TextStyle(
                                fontWeight: FontWeight.w600,
                                color: isDone ? AppColors.inkMuted : AppColors.ink,
                              ),
                            ),
                            subtitle: Text(
                              data['address'] as String? ?? '',
                              maxLines: 2,
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
                        },
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

  void _openStop(QueryDocumentSnapshot<Map<String, dynamic>>? stop) {
    if (stop == null) return;
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (_) => StopInstructionsSheet(authState: widget.authState, stopDoc: stop),
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({required this.listing, required this.driver, required this.startTime});

  final RunListing listing;
  final String? driver;
  final String? startTime;

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final status = listing.status(now);
    final lastDrop = listing.lastDeliveredAt?.toLocal();
    final took = listing.actualDuration;
    final estimate = listing.estimatedTotal;
    final finish = expectedFinish(startTime, estimate);

    final lines = <String>[
      [
        if (listing.date != null) formatShortDate(listing.date!, thisYear: now.year),
        if (startTime != null) 'starts ${formatStartTime(startTime!)}',
        driver ?? 'No driver assigned',
      ].join(' · '),
      switch (status) {
        RunStatus.done => 'All ${listing.stopCount} delivered${took == null ? '' : ' in ${DeliveryEstimate.format(took)}'}',
        RunStatus.onTheRoad =>
          '${listing.deliveredCount} of ${listing.stopCount} delivered'
              '${lastDrop == null ? '' : ' · last drop ${formatClock(lastDrop.hour, lastDrop.minute)}'}',
        RunStatus.unfinished => '${listing.deliveredCount} of ${listing.stopCount} delivered - not finished',
        RunStatus.notRun => 'Nothing was marked delivered on this run',
        RunStatus.notStarted =>
          '${listing.stopCount} stops'
              '${estimate == null ? '' : ' · about ${DeliveryEstimate.format(estimate)}'}'
              '${finish == null ? '' : ', back ~$finish'}',
      },
      if (listing.nextStopName != null && status == RunStatus.onTheRoad) 'Next: ${listing.nextStopName}',
    ];

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(status.label, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800)),
          const SizedBox(height: 4),
          for (final line in lines)
            Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Text(line, style: const TextStyle(fontSize: 12.5, color: AppColors.inkMuted)),
            ),
          if (listing.startedAt != null) ...[
            const SizedBox(height: 10),
            ClipRRect(
              borderRadius: BorderRadius.circular(999),
              child: LinearProgressIndicator(
                value: listing.progress,
                minHeight: 6,
                backgroundColor: AppColors.hairline,
                color: status == RunStatus.done ? AppColors.success : AppColors.brand,
              ),
            ),
          ],
          const SizedBox(height: 8),
          // Said plainly rather than drawn: the old board placed a made-up
          // van on a made-up route.
          const Text(
            'Progress updates as the driver marks stops delivered. The van\'s live position will show '
            'here once the driver app reports it.',
            style: TextStyle(fontSize: 11.5, color: AppColors.inkMuted, height: 1.4),
          ),
          const Divider(height: 24, color: AppColors.hairline),
        ],
      ),
    );
  }
}
