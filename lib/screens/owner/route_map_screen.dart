import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:latlong2/latlong.dart';

import '../../models/delivery_estimate.dart';
import '../../models/road_legs.dart';
import '../../models/run_stop.dart';
import '../../services/depot_locator.dart';
import '../../state/auth_state.dart';
import '../../theme/app_colors.dart';
import '../../widgets/delivery_time_card.dart';
import '../../widgets/route_preview_map.dart';
import '../../widgets/stop_instructions_sheet.dart';
import '../../widgets/stop_search_delegate.dart';

/// FR3 (DMM-08-10): the confirmed route for one circuit.
///
/// The map itself is RoutePreviewMap, shared with the pre-confirm review
/// screen - the sequence an owner approves and the sequence they later look
/// up have to be the same picture, including the depot legs at each end.
/// Before that was shared, this screen drew the polyline through the stops
/// only and parked the location dot on stop 1, which read as "the run starts
/// at the first customer" - it starts at the depot, and comes back to it.
class RouteMapScreen extends StatefulWidget {
  const RouteMapScreen({super.key, required this.authState, required this.roundKey});

  final AuthState authState;
  final String roundKey;

  @override
  State<RouteMapScreen> createState() => _RouteMapScreenState();
}

class _RouteMapScreenState extends State<RouteMapScreen> {
  /// Memoised per address so the depot lookup doesn't re-issue a read on
  /// every snapshot the circuit stream delivers.
  String? _depotAddress;
  Future<LatLng?>? _depotFuture;

  /// Which stop the map is calling out, set by tapping its row in the sheet.
  StopHighlight? _highlight;

  /// Memoised per run for the same reason: the run document only supplies
  /// the learned leg times and whether its order came from the driver, and
  /// neither changes while this screen is open often enough to stream.
  String? _runId;
  Future<Map<String, dynamic>?>? _runFuture;

  Future<RoadLegs>? _roadLegsFuture;

  Future<Map<String, dynamic>?> _run(String runId) {
    if (runId != _runId || _runFuture == null) {
      _runId = runId;
      _runFuture = FirebaseFirestore.instance
          .collection('delivery_run')
          .doc(runId)
          .get()
          .then((snap) => snap.data());
      // Decoded once per run: sixty legs of road geometry is too much to
      // re-decode on every rebuild the stop stream triggers.
      _roadLegsFuture = _runFuture!.then((run) => RoadLegs.fromRun(run?['road_legs']));
    }
    return _runFuture!;
  }

  Future<RoadLegs> _roadLegs(String runId) {
    _run(runId);
    return _roadLegsFuture!;
  }

  Future<LatLng?> _depot(String? address) {
    if (address != _depotAddress || _depotFuture == null) {
      _depotAddress = address;
      _depotFuture = DepotLocator().resolve(address);
    }
    return _depotFuture!;
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      stream: FirebaseFirestore.instance.collection('circuits').doc(widget.roundKey).snapshots(),
      builder: (context, circuitSnap) {
        final circuit = circuitSnap.data?.data();
        final title = circuit?['round'] as String? ?? 'Route';
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
            final docs = stopsSnap.data?.docs ?? [];
            if (docs.isEmpty) {
              return Scaffold(
                appBar: AppBar(title: Text(title)),
                body: const Center(child: CircularProgressIndicator()),
              );
            }

            final stops = [for (final doc in docs) ?RunStop.fromDoc(doc)];
            final stopDocsById = {for (final doc in docs) doc.id: doc};

            return Scaffold(
              appBar: AppBar(
                title: Text(title),
                actions: [
                  IconButton(
                    tooltip: 'Find a stop',
                    icon: const Icon(Icons.search_rounded),
                    onPressed: () => _findStop(context, stops, stopDocsById),
                  ),
                ],
              ),
              body: FutureBuilder<LatLng?>(
                future: _depot(circuit?['depot_address'] as String?),
                builder: (context, depotSnap) {
                  return Stack(
                    children: [
                      Positioned.fill(
                        child: FutureBuilder<RoadLegs>(
                          future: _roadLegs(runId),
                          builder: (context, roadSnap) => RoutePreviewMap(
                            stops: stops,
                            depot: depotSnap.data,
                            highlight: _highlight,
                            roadLegs: roadSnap.data ?? const RoadLegs(),
                            onStopTap: (index) => _showStop(context, stopDocsById[stops[index].id]),
                          ),
                        ),
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
                                return Column(
                                  children: [
                                    const _SheetGrip(),
                                    FutureBuilder<Map<String, dynamic>?>(
                                      future: _run(runId),
                                      builder: (context, runSnap) {
                                        final run = runSnap.data;
                                        // Same precedence as the backend:
                                        // road times, then learned over them.
                                        final estimate = DeliveryEstimate.forRun(
                                          depot: depotSnap.data,
                                          stops: stops,
                                          learnedLegs: {
                                            ...roadSecondsFromRun(run?['road_legs']),
                                            ...DeliveryEstimate.learnedLegsFrom(run?['learned_legs']),
                                          },
                                        );
                                        return Padding(
                                          padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                                          child: Column(
                                            crossAxisAlignment: CrossAxisAlignment.stretch,
                                            children: [
                                              DeliveryTimeCard(
                                                estimate: estimate,
                                                depotResolved: depotSnap.data != null,
                                              ),
                                              // Set by learn_from_run.py when the
                                              // driver ran this route the same
                                              // different way twice in a row.
                                              if (run?['order_source'] == 'driver') ...[
                                                const SizedBox(height: 8),
                                                const Text(
                                                  'Stop order updated to match how the driver runs this route.',
                                                  style: TextStyle(fontSize: 12, color: AppColors.inkMuted),
                                                ),
                                              ],
                                            ],
                                          ),
                                        );
                                      },
                                    ),
                                  ],
                                );
                              }
                              final stop = stops[index - 1];
                              return _StopRow(
                                stop: stop,
                                position: index,
                                // Two answers to one tap, because the row
                                // raises two questions at once: the sheet
                                // says what to drop here, and the pulse says
                                // where "here" is. The sheet covers most of
                                // the map while it is open, which is why the
                                // pin stays filled once the pulse is over -
                                // the answer has to survive the dismissal.
                                onTap: () {
                                  setState(() => _highlight = StopHighlight.after(_highlight, stop.id));
                                  _showStop(context, stopDocsById[stop.id]);
                                },
                              );
                            },
                          ),
                        ),
                      ),
                    ],
                  );
                },
              ),
            );
          },
        );
      },
    );
  }

  /// Search, then answer both questions at once, as tapping a row does: the
  /// pin pulses (and the map pans to it) for where, and the stop's sheet
  /// opens for what to drop there.
  Future<void> _findStop(
    BuildContext context,
    List<RunStop> stops,
    Map<String, QueryDocumentSnapshot<Map<String, dynamic>>> stopDocsById,
  ) async {
    final index = await searchForStop(context, stops);
    if (index == null || !context.mounted || index >= stops.length) return;
    final stop = stops[index];
    setState(() => _highlight = StopHighlight.after(_highlight, stop.id));
    _showStop(context, stopDocsById[stop.id]);
  }

  void _showStop(BuildContext context, QueryDocumentSnapshot<Map<String, dynamic>>? stop) {
    if (stop == null) return;
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (_) => StopInstructionsSheet(authState: widget.authState, stopDoc: stop),
    );
  }
}

class _SheetGrip extends StatelessWidget {
  const _SheetGrip();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Container(
        width: 36,
        height: 4,
        margin: const EdgeInsets.only(bottom: 12),
        decoration: BoxDecoration(color: AppColors.hairline, borderRadius: BorderRadius.circular(2)),
      ),
    );
  }
}

/// A stop in the bottom sheet. Not a ListTile: the run sheet's product lines
/// are the point of the row, and ListTile's fixed title/subtitle slots have
/// nowhere to put them.
class _StopRow extends StatelessWidget {
  const _StopRow({required this.stop, required this.position, required this.onTap});

  final RunStop stop;
  final int position;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            StopPin(number: position, compact: true),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(stop.customerName, style: const TextStyle(fontWeight: FontWeight.w600)),
                  const SizedBox(height: 2),
                  Text(stop.address, style: const TextStyle(fontSize: 12, color: AppColors.inkMuted)),
                  if (stop.items.isNotEmpty) ...[
                    const SizedBox(height: 6),
                    Text(
                      stop.itemsSummary,
                      style: const TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        color: AppColors.brandDark,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
