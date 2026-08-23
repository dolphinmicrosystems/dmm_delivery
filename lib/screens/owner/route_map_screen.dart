import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:latlong2/latlong.dart';

import '../../models/run_stop.dart';
import '../../services/depot_locator.dart';
import '../../state/auth_state.dart';
import '../../theme/app_colors.dart';
import '../../widgets/route_preview_map.dart';
import '../../widgets/stop_instructions_sheet.dart';

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
              appBar: AppBar(title: Text(title)),
              body: FutureBuilder<LatLng?>(
                future: _depot(circuit?['depot_address'] as String?),
                builder: (context, depotSnap) {
                  return Stack(
                    children: [
                      Positioned.fill(
                        child: RoutePreviewMap(
                          stops: stops,
                          depot: depotSnap.data,
                          onStopTap: (index) => _showStop(context, stopDocsById[stops[index].id]),
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
                              if (index == 0) return const _SheetGrip();
                              final stop = stops[index - 1];
                              return _StopRow(
                                stop: stop,
                                position: index,
                                onTap: () => _showStop(context, stopDocsById[stop.id]),
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
