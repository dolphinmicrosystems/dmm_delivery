import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:latlong2/latlong.dart';

import '../../models/delivery_estimate.dart';
import '../../models/road_legs.dart';
import '../../models/run_stop.dart';
import '../../services/depot_locator.dart';
import '../../services/route_editor.dart';
import '../../state/auth_state.dart';
import '../../theme/app_colors.dart';
import '../../widgets/delivery_time_card.dart';
import '../../widgets/route_preview_map.dart';
import '../../widgets/stop_instructions_sheet.dart';
import '../../widgets/stop_search_delegate.dart';

/// FR3 (DMM-08-10): the confirmed route for one circuit - and where it is
/// edited after it has been confirmed.
///
/// The map itself is RoutePreviewMap, shared with the pre-confirm review
/// screen - the sequence an owner approves and the sequence they later look
/// up have to be the same picture, including the depot legs at each end.
/// Before that was shared, this screen drew the polyline through the stops
/// only and parked the location dot on stop 1, which read as "the run starts
/// at the first customer" - it starts at the depot, and comes back to it.
///
/// The stop list edits the route the way the review screen does before
/// confirming: long-press a stop (or grab its handle) to drag it, ✕ to take
/// it off, with Undo. Each edit is saved at once through RouteEditor, and the
/// backend's refresh-run function then redraws the road path and re-times
/// the route - which arrives here through the run document's stream.
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

  /// The road path, decoded once per run-document snapshot rather than on
  /// every rebuild the stop stream triggers - sixty legs of geometry is too
  /// much to re-decode each time.
  Object? _roadLegsSource;
  RoadLegs _roadLegs = const RoadLegs();

  /// The order just saved, shown until the stop stream catches up with it -
  /// without this a dragged stop jumps back for a moment before settling.
  List<String>? _pendingOrder;

  /// The revision last written by this screen. A second edit made before the
  /// first has come back through the stream must still bump from the newest
  /// value, or the rules (exactly +1) refuse it.
  int _writtenRevision = 0;

  bool _saving = false;

  RoadLegs _roadLegsFor(Map<String, dynamic>? run) {
    final raw = run?['road_legs'];
    if (!identical(raw, _roadLegsSource)) {
      _roadLegsSource = raw;
      _roadLegs = RoadLegs.fromRun(raw);
    }
    return _roadLegs;
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

        // Streamed, not read once: after an edit the backend writes the new
        // road path and times here, and they should appear without reopening.
        return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
          stream: FirebaseFirestore.instance.collection('delivery_run').doc(runId).snapshots(),
          builder: (context, runSnap) {
            final run = runSnap.data?.data();
            return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
              stream: FirebaseFirestore.instance
                  .collection('delivery_run')
                  .doc(runId)
                  .collection('delivery_stop')
                  .orderBy('seq_order')
                  .snapshots(),
              builder: (context, stopsSnap) {
                if (!stopsSnap.hasData) {
                  return Scaffold(
                    appBar: AppBar(title: Text(title)),
                    body: const Center(child: CircularProgressIndicator()),
                  );
                }
                // Stops taken off the route - on the review screen or here -
                // are kept as records but are not part of the route.
                final live = [for (final doc in stopsSnap.data!.docs) if (doc.data()['excluded'] != true) doc];
                final stopDocsById = {for (final doc in live) doc.id: doc};
                final located = [for (final doc in live) ?RunStop.fromDoc(doc)];
                // Stops the map cannot place stay at the end of the run and
                // are carried along untouched by every edit.
                final unlocatedIds = [
                  for (final doc in live)
                    if (!located.any((s) => s.id == doc.id)) doc.id,
                ];
                final stops = _inPendingOrder(located);
                return _scaffold(context, title, runId, run, circuit, stops, unlocatedIds, stopDocsById);
              },
            );
          },
        );
      },
    );
  }

  /// [stops] in the order just saved, while the stream still has the old one.
  List<RunStop> _inPendingOrder(List<RunStop> stops) {
    final pending = _pendingOrder;
    if (pending == null) return stops;
    final streamed = [for (final stop in stops) stop.id];
    if (_sameOrder(streamed, pending)) {
      _pendingOrder = null; // caught up
      return stops;
    }
    final byId = {for (final stop in stops) stop.id: stop};
    // A stop that vanished meanwhile (removed elsewhere) is simply skipped.
    return [for (final id in pending) ?byId[id]];
  }

  static bool _sameOrder(List<String> a, List<String> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }

  Widget _scaffold(
    BuildContext context,
    String title,
    String runId,
    Map<String, dynamic>? run,
    Map<String, dynamic>? circuit,
    List<RunStop> stops,
    List<String> unlocatedIds,
    Map<String, QueryDocumentSnapshot<Map<String, dynamic>>> stopDocsById,
  ) {
    final streamedRevision = (run?['order_revision'] as num?)?.toInt() ?? 0;
    final revision = streamedRevision > _writtenRevision ? streamedRevision : _writtenRevision;

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
          final inputs = EstimateInputs.fromRun(run, roadSeconds: roadSecondsFromRun(run?['road_legs']));
          // Re-estimated here rather than read off the run, so a drag moves
          // the total at once instead of when the backend has caught up.
          final estimate = inputs.estimate(depot: depotSnap.data, stops: stops);
          return Stack(
            children: [
              Positioned.fill(
                child: RoutePreviewMap(
                  stops: stops,
                  depot: depotSnap.data,
                  highlight: _highlight,
                  roadLegs: _roadLegsFor(run),
                  // The stop sheet covers the map's lower edge.
                  attributionAtTop: true,
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
                  child: ReorderableListView.builder(
                    scrollController: scrollController,
                    padding: const EdgeInsets.only(top: 12, bottom: 12),
                    // Explicit handles and a long-press listener per row
                    // instead of the platform default, as on the review
                    // screen: a plain tap must still open the stop's sheet.
                    buildDefaultDragHandles: false,
                    header: _SheetHeader(
                      estimate: estimate,
                      inputs: inputs,
                      depotResolved: depotSnap.data != null,
                      orderFromDriver: run?['order_source'] == 'driver',
                      saving: _saving,
                    ),
                    itemCount: stops.length,
                    onReorderItem: (oldIndex, newIndex) =>
                        _move(runId, stops, unlocatedIds, revision, oldIndex, newIndex),
                    itemBuilder: (context, index) {
                      final stop = stops[index];
                      return ReorderableDelayedDragStartListener(
                        key: ValueKey(stop.id),
                        index: index,
                        child: _StopRow(
                          stop: stop,
                          position: index + 1,
                          // Two answers to one tap, because the row raises two
                          // questions at once: the sheet says what to drop
                          // here, and the pulse says where "here" is.
                          onTap: () {
                            setState(() => _highlight = StopHighlight.after(_highlight, stop.id));
                            _showStop(context, stopDocsById[stop.id]);
                          },
                          trailing: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              IconButton(
                                onPressed: _saving
                                    ? null
                                    : () => _remove(context, runId, stops, unlocatedIds, revision, index),
                                icon: const Icon(Icons.close_rounded, size: 18),
                                color: AppColors.inkMuted,
                                tooltip: 'Remove this stop',
                                visualDensity: VisualDensity.compact,
                              ),
                              ReorderableDragStartListener(
                                index: index,
                                child: const Padding(
                                  padding: EdgeInsets.all(8),
                                  child: Icon(Icons.drag_indicator_rounded, color: AppColors.inkMuted),
                                ),
                              ),
                            ],
                          ),
                        ),
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
  }

  /// `onReorderItem` already accounts for the lifted row, so the classic
  /// `if (newIndex > oldIndex) newIndex -= 1` fixup must NOT be repeated.
  Future<void> _move(
    String runId,
    List<RunStop> stops,
    List<String> unlocatedIds,
    int revision,
    int oldIndex,
    int newIndex,
  ) async {
    if (oldIndex == newIndex) return;
    final order = [for (final stop in stops) stop.id];
    order.insert(newIndex, order.removeAt(oldIndex));
    setState(() => _pendingOrder = order);
    await _save(() => RouteEditor.reorder(
          runId: runId,
          orderedStopIds: [...order, ...unlocatedIds],
          currentRevision: revision,
        ), revision);
  }

  Future<void> _remove(
    BuildContext context,
    String runId,
    List<RunStop> stops,
    List<String> unlocatedIds,
    int revision,
    int index,
  ) async {
    final messenger = ScaffoldMessenger.of(context);
    final removed = stops[index];
    final remaining = [for (final stop in stops) if (stop.id != removed.id) stop.id];
    setState(() => _pendingOrder = remaining);
    final saved = await _save(() => RouteEditor.remove(
          runId: runId,
          stopId: removed.id,
          remainingStopIds: [...remaining, ...unlocatedIds],
          currentRevision: revision,
        ), revision);
    if (!saved || !mounted) return;

    // Undo on the snackbar: removing the wrong row of sixty similar
    // addresses is easy, and the moment someone notices is while it is up.
    messenger.hideCurrentSnackBar();
    messenger.showSnackBar(
      SnackBar(
        content: Text('${removed.customerName} removed from this route'),
        // Flutter keeps a snackbar with an action up until it is tapped
        // (`persist` defaults to true then); Undo is a few seconds' offer.
        persist: false,
        duration: const Duration(seconds: 5),
        action: SnackBarAction(
          label: 'Undo',
          onPressed: () {
            final restored = [...remaining]..insert(index.clamp(0, remaining.length), removed.id);
            setState(() => _pendingOrder = restored);
            _save(() => RouteEditor.restore(
                  runId: runId,
                  stopId: removed.id,
                  orderedStopIds: [...restored, ...unlocatedIds],
                  currentRevision: _writtenRevision,
                ), _writtenRevision);
          },
        ),
      ),
    );
  }

  /// Runs one edit. On failure the list goes back to what is saved and the
  /// reason is shown; true when it was saved.
  Future<bool> _save(Future<void> Function() write, int revision) async {
    final messenger = ScaffoldMessenger.of(context);
    setState(() => _saving = true);
    try {
      await write();
      _writtenRevision = revision + 1;
      return true;
    } on FirebaseException catch (error) {
      if (mounted) setState(() => _pendingOrder = null);
      messenger.showSnackBar(SnackBar(content: Text(RouteEditor.errorMessage(error))));
      return false;
    } finally {
      if (mounted) setState(() => _saving = false);
    }
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

/// The grip, the route's time, and how to edit it - above the stop list.
class _SheetHeader extends StatelessWidget {
  const _SheetHeader({
    required this.estimate,
    required this.inputs,
    required this.depotResolved,
    required this.orderFromDriver,
    required this.saving,
  });

  final DeliveryEstimate estimate;
  final EstimateInputs inputs;
  final bool depotResolved;
  final bool orderFromDriver;
  final bool saving;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Center(
            child: Container(
              width: 36,
              height: 4,
              margin: const EdgeInsets.only(bottom: 12),
              decoration: BoxDecoration(color: AppColors.hairline, borderRadius: BorderRadius.circular(2)),
            ),
          ),
          DeliveryTimeCard(estimate: estimate, depotResolved: depotResolved, inputs: inputs),
          // Set by learn_from_run.py when the driver ran this route the same
          // different way twice in a row; cleared by the owner's own edit.
          if (orderFromDriver) ...[
            const SizedBox(height: 8),
            const Text(
              'Stop order updated to match how the driver runs this route.',
              style: TextStyle(fontSize: 12, color: AppColors.inkMuted),
            ),
          ],
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: Text(
                  saving
                      ? 'Saving…'
                      : 'Long-press a stop to move it, or ✕ to remove it. Changes are saved straight away.',
                  style: const TextStyle(fontSize: 11.5, color: AppColors.inkMuted),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// A stop in the bottom sheet. Not a ListTile: the run sheet's product lines
/// are the point of the row, and ListTile's fixed title/subtitle slots have
/// nowhere to put them.
class _StopRow extends StatelessWidget {
  const _StopRow({required this.stop, required this.position, required this.onTap, this.trailing});

  final RunStop stop;
  final int position;
  final VoidCallback onTap;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 10, 4, 10),
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
              ?trailing,
            ],
          ),
        ),
      ),
    );
  }
}
