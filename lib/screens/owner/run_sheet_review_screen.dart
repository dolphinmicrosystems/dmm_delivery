import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:latlong2/latlong.dart';

import '../../models/delivery_estimate.dart';
import '../../models/pending_changes.dart';
import '../../models/road_legs.dart';
import '../../models/route_name.dart';
import '../../models/run_sheet_diff.dart';
import '../../models/run_stop.dart';
import '../../services/depot_locator.dart';
import '../../state/auth_state.dart';
import '../../theme/app_colors.dart';
import '../../util/app_log.dart';
import '../../widgets/delivery_time_card.dart';
import '../../widgets/primary_button.dart';
import '../../widgets/route_preview_map.dart';
import '../../widgets/stop_card.dart';
import '../../widgets/stop_search_delegate.dart';
import '../../widgets/section_label.dart';
import '../../widgets/surface_card.dart';

/// FR2/FR3: the owner's review of an uploaded run sheet, before it becomes
/// the live route.
///
/// Replaces the diff-only screen this used to show. That screen answered
/// "what changed since last time?" and nothing else - it never showed the
/// sequence being confirmed, the load being sent out, or where any of it
/// was. The owner was asked to approve a route they could not see.
///
/// Three things happen here now:
///
///   * the sequence is shown on a map, depot to depot, and is editable by
///     dragging. The optimizer's order is a proposal; the person who knows
///     the run gets the last word on it.
///   * every stop carries its product lines, because "what am I dropping
///     here" is the actual content of a run sheet.
///   * the load-out total by product sits above the list, so the van is
///     packed from the same screen the route is approved on.
///   * the route's name is editable here, because this is the screen where
///     the owner is already deciding what this route *is*. Left alone it
///     stays whatever the sheet's "Round:" heading said - "Run 2" and the
///     like, which is a filing code rather than a name.
class RunSheetReviewScreen extends StatefulWidget {
  const RunSheetReviewScreen({
    super.key,
    required this.authState,
    required this.uploadId,
    required this.data,
  });

  final AuthState authState;
  final String uploadId;

  /// The run_sheet_upload document as of the moment it became reviewable.
  final Map<String, dynamic> data;

  @override
  State<RunSheetReviewScreen> createState() => _RunSheetReviewScreenState();
}

class _RunSheetReviewScreenState extends State<RunSheetReviewScreen> {
  late Future<_ReviewData> _future;

  List<RunStop> _stops = const [];

  /// Which stop the map is calling out, set by tapping its card in the list.
  /// Null until the owner asks - the map opens showing the whole run, not one
  /// stop out of it.
  StopHighlight? _highlight;

  /// The order the backend sequenced, kept so the owner can back out of
  /// their edits without re-uploading the sheet.
  List<RunStop> _optimizedOrder = const [];

  /// Whether the owner has enlarged the map above the list - see
  /// [RoutePreviewMap.onToggleExpanded].
  bool _mapExpanded = false;

  /// For scrolling the list to a stop picked from search. One key per stop
  /// id, kept across drags, so a card can be found wherever it has moved to.
  final _listController = ScrollController();
  final Map<String, GlobalKey> _cardKeys = {};

  LatLng? _depot;
  int _skipped = 0;

  /// Stops the backend kept on the run but could not place on a map. Not in
  /// `_stops`, so they are appended to `manual_order` explicitly - leaving
  /// them out would read to confirm_run_sheet_upload as "remove these".
  List<String> _unlocatedIds = const [];

  /// What the backend estimated this run with: learned leg times, each
  /// address's stop time, the driver's pace. Re-used here so a dragged order
  /// re-estimates to the same figures.
  EstimateInputs _estimateInputs = const EstimateInputs();

  /// The run's road path for the order the backend proposed.
  RoadLegs _roadLegs = const RoadLegs();

  late final TextEditingController _nameController;
  String? _nameError;

  /// The name this route already had, to tell an edit from an untouched
  /// field. Typing the same name back is not a rename, and must not flip
  /// the route from following the sheet to overriding it.
  late final String? _originalName;

  /// True once the owner has dragged anything. Gates whether Confirm sends a
  /// manual order at all - an untouched list must stay the optimizer's
  /// result, not be re-asserted by the client as a hand-picked order.
  bool _reordered = false;
  bool _submitting = false;

  /// Stops the owner has taken off this run, newest first, kept whole so the
  /// removal can be undone without re-uploading the sheet.
  ///
  /// Nothing is written until Confirm. Removing a stop means leaving its id
  /// out of `manual_order`, which is what `_apply_manual_order` in
  /// confirm_run_sheet_upload.py reads as "drop this one" - so the entire
  /// edit lives in this list until the owner commits it.
  final List<({RunStop stop, int index})> _removed = [];

  RunSheetDiff get _diff => RunSheetDiff.fromMap(widget.data['diff'] as Map<String, dynamic>?);
  String? get _draftRunId => widget.data['draft_run_id'] as String?;

  @override
  void initState() {
    super.initState();
    _future = _load();
    // route_name is resolved server-side and already accounts for a name the
    // owner gave this route on an earlier upload; `round` is only the fallback
    // for uploads written before naming existed.
    _originalName = widget.data['route_name'] as String? ?? widget.data['round'] as String?;
    _nameController = TextEditingController(text: _originalName ?? '');
  }

  @override
  void dispose() {
    _nameController.dispose();
    _listController.dispose();
    super.dispose();
  }

  /// What leaving this screen right now would throw away. Both halves are
  /// decisions the owner made by hand and neither is written anywhere until
  /// Confirm, so both are worth stopping for.
  PendingChanges get _pendingChanges => PendingChanges(
        renamed: RouteName.isRenameOf(_nameController.text, _originalName),
        reordered: _reordered || _removed.isNotEmpty,
      );

  /// Whether Confirm has to send a stop list at all.
  ///
  /// An untouched review must not re-assert the pipeline's own sequence as
  /// though a person had chosen it - see `_reordered`. A removal counts for
  /// the same reason a drag does: it is a decision only the owner could make.
  bool get _stopsEdited => _reordered || _removed.isNotEmpty;

  /// Back was pressed with unapplied edits. Unlike the update screen this
  /// offers no "save" - the two ways to resolve a review are already on
  /// screen as Confirm and Discard, and a third path that half-applied one
  /// of them would leave an upload in a state neither button produces.
  Future<void> _confirmLeave(PendingChanges pending) async {
    final leave = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Leave without confirming?'),
        content: Text(
          '${pending.summary} won\u2019t be applied, and this run sheet stays waiting for review. '
          'Use Confirm to make it the live route, or Discard to throw the upload away.',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialogContext, false), child: const Text('Keep reviewing')),
          TextButton(onPressed: () => Navigator.pop(dialogContext, true), child: const Text('Leave')),
        ],
      ),
    );
    if (leave != true || !mounted) {
      AppLog.owner('leave review canceled', {'uploadId': widget.uploadId});
      return;
    }
    AppLog.owner('leaving review unconfirmed', {
      'uploadId': widget.uploadId,
      'renamed': pending.renamed,
      'reordered': pending.reordered,
    });
    // Navigator.pop, not maybePop: PopScope gates the latter and would ask
    // again immediately.
    Navigator.of(context).pop();
  }

  Future<_ReviewData> _load() async {
    final runId = _draftRunId;
    if (runId == null) throw StateError('This upload has no draft run to review.');

    final db = FirebaseFirestore.instance;
    final run = await db.collection('delivery_run').doc(runId).get();
    final stopDocs = await db
        .collection('delivery_run')
        .doc(runId)
        .collection('delivery_stop')
        .orderBy('seq_order')
        .get();

    final stops = <RunStop>[];
    final unlocatedIds = <String>[];
    for (final doc in stopDocs.docs) {
      final stop = RunStop.fromDoc(doc);
      if (stop == null) {
        unlocatedIds.add(doc.id);
      } else {
        stops.add(stop);
      }
    }
    final skipped = unlocatedIds.length;

    final depot = await DepotLocator().resolve(run.data()?['depot_address'] as String?);
    AppLog.owner('run sheet review loaded', {
      'runId': runId,
      'stops': stops.length,
      'skipped': skipped,
      'depotResolved': depot != null,
    });

    return _ReviewData(
      stops: stops,
      depot: depot,
      unlocatedIds: unlocatedIds,
      roadLegs: RoadLegs.fromRun(run.data()?['road_legs']),
      estimateInputs: EstimateInputs.fromRun(
        run.data(),
        roadSeconds: roadSecondsFromRun(run.data()?['road_legs']),
      ),
    );
  }

  /// Wired to `onReorderItem`, not the deprecated `onReorder`: the newer
  /// callback already compensates for the dragged item being lifted out of
  /// the list, so the classic `if (newIndex > oldIndex) newIndex -= 1` fixup
  /// must NOT be repeated here - doing both drops the stop one slot short.
  void _onReorderItem(int oldIndex, int newIndex) {
    setState(() {
      final stops = [..._stops];
      stops.insert(newIndex, stops.removeAt(oldIndex));
      _stops = stops;
      _reordered = true;
    });
  }

  void _resetOrder() {
    setState(() {
      // Removed stops stay removed. The button says "Reset order", and a
      // button that also quietly put three deleted rows back would be doing
      // something its label does not admit to - the header's own Undo is
      // where a removal is taken back.
      final gone = {for (final entry in _removed) entry.stop.id};
      _stops = [for (final stop in _optimizedOrder) if (!gone.contains(stop.id)) stop];
      _reordered = false;
    });
  }

  /// Takes a stop off this run. Nothing is written - see [_removed].
  void _removeStop(int index) {
    final messenger = ScaffoldMessenger.of(context);
    final stop = _stops[index];
    setState(() {
      _stops = [..._stops]..removeAt(index);
      _removed.insert(0, (stop: stop, index: index));
    });

    // Undo on the snackbar as well as in the header. Removing the wrong row
    // of 59 near-identical addresses is easy, and the moment someone notices
    // is the moment the snackbar is still up.
    messenger.hideCurrentSnackBar();
    messenger.showSnackBar(
      SnackBar(
        content: Text('Removed ${stop.customerName.isEmpty ? stop.address : stop.customerName}'),
        // Auto-closes like any snackbar: Flutter would otherwise keep one with
        // an action up until tapped. The header's Undo stays for later.
        persist: false,
        duration: const Duration(seconds: 5),
        action: SnackBarAction(label: 'Undo', onPressed: () => _restoreStop(stop.id)),
      ),
    );
  }

  /// Puts a removed stop back where it was, if that position still exists.
  void _restoreStop(String stopId) {
    final entry = _removed.where((r) => r.stop.id == stopId).firstOrNull;
    if (entry == null) return;
    setState(() {
      _removed.removeWhere((r) => r.stop.id == stopId);
      final at = entry.index.clamp(0, _stops.length);
      _stops = [..._stops]..insert(at, entry.stop);
    });
  }

  /// Search, then take the owner to the stop: its pin pulses on the map (and
  /// the map pans to it if it is off screen) and the list scrolls to its card.
  Future<void> _findStop() async {
    final index = await searchForStop(context, _stops);
    if (index == null || !mounted || index >= _stops.length) return;
    final stop = _stops[index];
    setState(() => _highlight = StopHighlight.after(_highlight, stop.id));
    WidgetsBinding.instance.addPostFrameCallback((_) => _scrollToCard(stop.id, index));
  }

  /// The list is built lazily, so a card far down it has no context to scroll
  /// to yet. Jump to roughly where it must be first - cards are near enough
  /// the same height - then let ensureVisible settle it exactly.
  void _scrollToCard(String stopId, int index, {bool jumped = false}) {
    if (!mounted) return;
    final cardContext = _cardKeys[stopId]?.currentContext;
    if (cardContext != null) {
      Scrollable.ensureVisible(
        cardContext,
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeOutCubic,
        alignment: 0.1,
      );
      return;
    }
    if (jumped || !_listController.hasClients) return;
    final position = _listController.position;
    final fraction = _stops.length <= 1 ? 0.0 : index / (_stops.length - 1);
    _listController.jumpTo(position.maxScrollExtent * fraction);
    WidgetsBinding.instance.addPostFrameCallback((_) => _scrollToCard(stopId, index, jumped: true));
  }

  void _showStop(RunStop stop) {
    final runId = _draftRunId;
    if (runId == null) return;
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (_) => _ReviewStopSheet(
        stop: stop,
        position: _stops.indexOf(stop) + 1,
        onRemove: () {
          Navigator.pop(context);
          _removeStop(_stops.indexOf(stop));
        },
      ),
    );
  }

  Future<void> _respond(String status) async {
    final renamed = status == 'confirmed' && RouteName.isRenameOf(_nameController.text, _originalName);
    if (renamed) {
      // Checked before the write, not after: the rules cap the name's length
      // and reject the whole confirm if it's over, which surfaces as a bare
      // permission-denied and reads as a sign-in problem.
      final nameError = RouteName.validationError(_nameController.text);
      if (nameError != null) {
        setState(() => _nameError = nameError);
        return;
      }
    }

    setState(() {
      _submitting = true;
      _nameError = null;
    });
    final manualOrder = [for (final stop in _stops) stop.id, ..._unlocatedIds];
    AppLog.owner('run sheet $status', {
      'uploadId': widget.uploadId,
      'reordered': _reordered,
      'removed': _removed.length,
      'renamed': renamed,
      'stops': manualOrder.length,
    });

    try {
      await FirebaseFirestore.instance.collection('run_sheet_upload').doc(widget.uploadId).update({
        'status': status,
        // The stops this run keeps, in order. A stop the owner removed is
        // simply absent - confirm_run_sheet_upload reads a short list as
        // "drop the rest" and marks them excluded rather than deleting them.
        if (status == 'confirmed' && _stopsEdited) 'manual_order': manualOrder,
        // Only when a person actually changed it. An untouched field leaves
        // the backend's own route_name standing, and leaves the route
        // following the sheet's heading rather than pinning it to a name
        // nobody chose - see _resolve_route_name in
        // process_run_sheet_upload.py for the other half of that rule.
        if (renamed) ...{
          'route_name': RouteName.toSubmit(_nameController.text)!,
          'route_name_source': 'owner',
        },
      });
      if (mounted) Navigator.of(context).popUntil((route) => route.isFirst);
    } on FirebaseException catch (error, stack) {
      AppLog.owner.error('run sheet $status failed', error, stack);
      if (!mounted) return;
      setState(() => _submitting = false);
      // A reordered or renamed confirm is rejected until firestore.rules
      // allows those fields alongside `status`. Saying so beats a bare
      // "permission denied", which reads as a sign-in problem.
      final blockedFields = status != 'confirmed'
          ? const <String>[]
          : [
              if (_reordered) 'a custom stop order',
              if (renamed) 'a route name',
            ];
      final rulesBlocked = error.code == 'permission-denied' && blockedFields.isNotEmpty;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            rulesBlocked
                ? 'Saving ${blockedFields.join(' and ')} needs the backend rules update deployed first.'
                : 'Could not $status this run sheet: ${error.message ?? error.code}',
          ),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    // Rebuilt per keystroke so `canPop` tracks the name field; `_reordered`
    // already arrives through setState. See the update screen for why
    // PopScope needs the rebuild rather than reading state at pop time.
    return ValueListenableBuilder<TextEditingValue>(
      valueListenable: _nameController,
      builder: (context, _, child) {
        final pending = _pendingChanges;
        return PopScope(
          canPop: pending.isEmpty,
          onPopInvokedWithResult: (didPop, _) {
            if (!didPop) _confirmLeave(pending);
          },
          child: child!,
        );
      },
      child: Scaffold(
      backgroundColor: AppColors.surfaceMuted,
      appBar: AppBar(
        // Follows the name field below rather than restating the stored
        // name, so renaming a route reads as renaming it and not as editing
        // some other value that happens to be shown twice.
        title: ValueListenableBuilder<TextEditingValue>(
          valueListenable: _nameController,
          builder: (context, value, _) {
            final name = value.text.trim();
            return Text(name.isEmpty ? 'Review run sheet' : name, overflow: TextOverflow.ellipsis);
          },
        ),
        actions: [
          IconButton(
            tooltip: 'Find a stop',
            icon: const Icon(Icons.search_rounded),
            onPressed: _stops.isEmpty ? null : _findStop,
          ),
          // A real action, not a status pill. The pill that used to sit here
          // read as a button and did nothing when tapped, which is worse
          // than no affordance at all - if it looks pressable it has to do
          // something. Undoing a drag is the thing an owner actually wants
          // at this point, and it needs no round trip.
          if (_reordered)
            TextButton.icon(
              onPressed: _submitting ? null : _resetOrder,
              icon: const Icon(Icons.undo_rounded, size: 18),
              label: const Text('Reset order'),
            ),
        ],
      ),
      body: FutureBuilder<_ReviewData>(
        future: _future,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Text(
                  'Could not load this run sheet: ${snapshot.error}',
                  style: const TextStyle(color: Colors.red, fontSize: 13),
                  textAlign: TextAlign.center,
                ),
              ),
            );
          }

          // Seeded once. Rebuilds after a drag must not re-read the future's
          // (original) order, or every reorder would snap back.
          if (_stops.isEmpty && snapshot.hasData) {
            final data = snapshot.data!;
            _stops = data.stops;
            _optimizedOrder = data.stops;
            _depot = data.depot;
            _skipped = data.unlocatedIds.length;
            _unlocatedIds = data.unlocatedIds;
            _roadLegs = data.roadLegs;
            _estimateInputs = data.estimateInputs;
          }

          return LayoutBuilder(
            builder: (context, constraints) => Column(
              children: [
                AnimatedContainer(
                  duration: const Duration(milliseconds: 220),
                  curve: Curves.easeOutCubic,
                  // Enlarged, the map takes most of the screen but leaves the
                  // top of the list and the confirm bar in view, so checking a
                  // pin never hides what the check is for.
                  height: _mapExpanded ? constraints.maxHeight * 0.62 : 240,
                  width: double.infinity,
                  child: RoutePreviewMap(
                    stops: _stops,
                    depot: _depot,
                    highlight: _highlight,
                    roadLegs: _roadLegs,
                    expanded: _mapExpanded,
                    onToggleExpanded: () => setState(() => _mapExpanded = !_mapExpanded),
                    // The pins were dead on this screen while the confirmed
                    // route screen's were tappable - backwards, since this is
                    // the one screen where an owner is actively checking
                    // whether a pin belongs on the run at all.
                    onStopTap: (index) => _showStop(_stops[index]),
                  ),
                ),
                Expanded(child: _buildList()),
                _buildActions(),
              ],
            ),
          );
        },
      ),
      ),
    );
  }

  Widget _buildList() {
    final totals = milkTotals(_stops);
    final unitCount = totals.fold(0, (running, total) => running + total.quantity);
    // Recomputed on every build, so a drag re-estimates at once. Sixty-odd
    // straight-line legs is nothing next to laying out the list itself.
    // The same figures the backend used, so dragging a stop moves the total
    // without the number jumping when the screen is reopened.
    final estimate = _estimateInputs.estimate(depot: _depot, stops: _stops);

    return ReorderableListView.builder(
      scrollController: _listController,
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
      // Explicit handles instead of the platform defaults: on a phone the
      // default is long-press-anywhere, which collides with tapping a stop
      // to read its instructions.
      buildDefaultDragHandles: false,
      onReorderItem: _onReorderItem,
      header: _ReviewHeader(
        diff: _diff,
        noChanges: widget.data['status'] == 'no_changes',
        stopCount: _stops.length,
        unitCount: unitCount,
        totals: totals,
        skipped: _skipped,
        estimate: estimate,
        estimateInputs: _estimateInputs,
        removed: _removed,
        onRestore: _restoreStop,
        depotResolved: _depot != null,
        nameController: _nameController,
        nameError: _nameError,
        nameEnabled: !_submitting,
        onNameChanged: () {
          if (_nameError != null) setState(() => _nameError = null);
        },
      ),
      itemCount: _stops.length,
      itemBuilder: (context, index) {
        final stop = _stops[index];
        // Two ways to pick a card up, because one is discoverable and the
        // other is fast: a long press anywhere (the gesture people try
        // first on a list of cards) or the handle, which drags instantly.
        // A tap is a third, shorter gesture and does not collide with either.
        //
        // The reorder key must sit on the widget the builder *returns* -
        // nesting it inside throws "Every item of ReorderableListView must
        // have a key", which is the trap this list is easiest to get wrong.
        return ReorderableDelayedDragStartListener(
          key: ValueKey(stop.id),
          index: index,
          child: Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: GestureDetector(
              // Scrolling a long run and asking "where is this one?" is the
              // question this list cannot answer on its own - an address in
              // Dunedin means nothing to somebody who has not driven it.
              // Tapping the card pulses its pin, which is the cheapest
              // possible answer and costs the card no other gesture.
              behavior: HitTestBehavior.opaque,
              onTap: () => setState(() => _highlight = StopHighlight.after(_highlight, stop.id)),
              child: StopCard(
                key: _cardKeys.putIfAbsent(stop.id, GlobalKey.new),
                stop: stop,
                position: index + 1,
                arrival: estimate.arrivalOffsets[index],
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    IconButton(
                      onPressed: _submitting ? null : () => _removeStop(index),
                      icon: const Icon(Icons.close_rounded, size: 18),
                      color: AppColors.inkMuted,
                      tooltip: 'Remove this stop',
                      visualDensity: VisualDensity.compact,
                    ),
                    ReorderableDragStartListener(
                      index: index,
                      child: const Padding(
                        padding: EdgeInsets.symmetric(horizontal: 8, vertical: 10),
                        child: Icon(Icons.drag_indicator_rounded, color: AppColors.inkMuted),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildActions() {
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
        child: Row(
          children: [
            Expanded(
              child: PrimaryButton(
                label: _submitting ? 'Saving…' : 'Confirm',
                icon: Icons.check_rounded,
                onPressed: _submitting ? null : () => _respond('confirmed'),
              ),
            ),
            const SizedBox(width: 12),
            TextButton(
              onPressed: _submitting ? null : () => _respond('discarded'),
              child: const Text('Discard'),
            ),
          ],
        ),
      ),
    );
  }
}

class _ReviewData {
  const _ReviewData({
    required this.stops,
    required this.depot,
    required this.unlocatedIds,
    required this.roadLegs,
    required this.estimateInputs,
  });

  final List<RunStop> stops;
  final LatLng? depot;
  final List<String> unlocatedIds;
  final RoadLegs roadLegs;
  final EstimateInputs estimateInputs;
}

/// Everything above the draggable list: what this route is called, what
/// changed, what's going on the van, and the caveats worth surfacing before
/// an approval.
class _ReviewHeader extends StatelessWidget {
  const _ReviewHeader({
    required this.diff,
    required this.noChanges,
    required this.stopCount,
    required this.unitCount,
    required this.totals,
    required this.skipped,
    required this.estimate,
    required this.estimateInputs,
    required this.removed,
    required this.onRestore,
    required this.depotResolved,
    required this.nameController,
    required this.nameError,
    required this.nameEnabled,
    required this.onNameChanged,
  });

  final RunSheetDiff diff;
  final bool noChanges;
  final int stopCount;
  final int unitCount;
  final List<MilkTotal> totals;
  final int skipped;
  final DeliveryEstimate estimate;
  final EstimateInputs estimateInputs;

  /// Stops the owner has taken off this run, newest first. Shown rather than
  /// hidden: a removal is not written until Confirm, so this panel is the
  /// only record that it happened, and the only way back.
  final List<({RunStop stop, int index})> removed;
  final void Function(String stopId) onRestore;

  final bool depotResolved;

  /// Owned by the screen's State, not by this widget: the list this header
  /// sits in rebuilds on every drag, and a controller created here would
  /// lose the owner's half-typed name each time a stop moved.
  final TextEditingController nameController;
  final String? nameError;
  final bool nameEnabled;
  final VoidCallback onNameChanged;

  @override
  Widget build(BuildContext context) {
    final orderNote = diff.orderNote;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SectionLabel('Route name'),
        const SizedBox(height: 8),
        SurfaceCard(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              TextField(
                controller: nameController,
                enabled: nameEnabled,
                maxLength: RouteName.maxLength,
                textCapitalization: TextCapitalization.sentences,
                decoration: InputDecoration(
                  hintText: 'e.g. Mosgiel morning',
                  border: const OutlineInputBorder(),
                  errorText: nameError,
                  counterText: '',
                ),
                onChanged: (_) => onNameChanged(),
              ),
              const SizedBox(height: 8),
              Text(
                // Naming the route and sequencing it are the same decision,
                // so they are made on the same screen: this is the route,
                // called this, run in this order.
                'Saved when you confirm. Later sheets won’t rename it.',
                style: const TextStyle(fontSize: 12, color: AppColors.inkMuted),
              ),
            ],
          ),
        ),
        const SizedBox(height: 20),
        const SectionLabel('This upload'),
        const SizedBox(height: 8),
        SurfaceCard(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              Icon(
                noChanges ? Icons.check_circle_rounded : Icons.fact_check_rounded,
                color: noChanges ? AppColors.success : AppColors.brand,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '$stopCount stops · $unitCount units',
                      style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      diff.changeSummary,
                      style: const TextStyle(fontSize: 12, color: AppColors.inkMuted),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 10),
        DeliveryTimeCard(estimate: estimate, depotResolved: depotResolved, inputs: estimateInputs),
        // Not a warning - the opposite. It answers the question a re-upload
        // actually raises ("did I just lose the order I set last week?"),
        // which otherwise goes unanswered until a driver is out on the run.
        if (orderNote != null) ...[
          const SizedBox(height: 10),
          _Note(orderNote),
        ],
        if (diff.roundMismatch) ...[
          const SizedBox(height: 10),
          _Warning('This PDF says "${diff.pdfRound}", which differs from the sheet this route was built from.'),
        ],
        if (skipped > 0) ...[
          const SizedBox(height: 10),
          _Warning(
            '$skipped stop${skipped == 1 ? '' : 's'} could not be found near the round. '
            '${skipped == 1 ? 'It stays' : 'They stay'} on the run, last in the order, but '
            '${skipped == 1 ? 'is' : 'are'} not on the map or in the time estimate.',
          ),
        ],
        if (!depotResolved) ...[
          const SizedBox(height: 10),
          _Warning(
            'The depot has not been geocoded yet, so the route is drawn stop-to-stop '
            'rather than from and back to base.',
          ),
        ],
        if (removed.isNotEmpty) ...[
          const SizedBox(height: 10),
          _RemovedStops(removed: removed, onRestore: onRestore),
        ],
        if (totals.isNotEmpty) ...[
          const SizedBox(height: 20),
          const SectionLabel('Load out'),
          const SizedBox(height: 8),
          SurfaceCard(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
            child: Column(children: [for (final total in totals) _TotalRow(total: total)]),
          ),
        ],
        const SizedBox(height: 20),
        const SectionLabel('Stop order'),
        const SizedBox(height: 4),
        const Text(
          'Drag to resequence. The map follows the order below.',
          style: TextStyle(fontSize: 12, color: AppColors.inkMuted),
        ),
        const SizedBox(height: 10),
      ],
    );
  }
}

/// A neutral piece of information, styled apart from _Warning so that "your
/// order was kept" doesn't arrive looking like something went wrong.
class _Note extends StatelessWidget {
  const _Note(this.message);

  final String message;

  @override
  Widget build(BuildContext context) {
    return SurfaceCard(
      padding: const EdgeInsets.all(12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.low_priority_rounded, size: 16, color: AppColors.brand),
          const SizedBox(width: 8),
          Expanded(
            child: Text(message, style: const TextStyle(fontSize: 12, color: AppColors.brand)),
          ),
        ],
      ),
    );
  }
}

class _Warning extends StatelessWidget {
  const _Warning(this.message);

  final String message;

  @override
  Widget build(BuildContext context) {
    return SurfaceCard(
      padding: const EdgeInsets.all(12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.info_outline_rounded, size: 16, color: AppColors.warning),
          const SizedBox(width: 8),
          Expanded(
            child: Text(message, style: const TextStyle(fontSize: 12, color: AppColors.warning)),
          ),
        ],
      ),
    );
  }
}

class _TotalRow extends StatelessWidget {
  const _TotalRow({required this.total});

  final MilkTotal total;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        children: [
          Expanded(
            child: Text(total.product, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
          ),
          if (total.loose > 0)
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: Text(
                '${total.loose} loose',
                style: const TextStyle(fontSize: 11, color: AppColors.inkMuted),
              ),
            ),
          Text(
            '${total.quantity}',
            style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w800, color: AppColors.brand),
          ),
        ],
      ),
    );
  }
}

/// The stops the owner has taken off this run, with a way back.
///
/// On screen rather than tucked behind a count, because none of this is
/// written until Confirm: leave the screen and the removals evaporate, and
/// confirm it and they become permanent. A panel the owner can read is the
/// only thing standing between those two outcomes.
class _RemovedStops extends StatelessWidget {
  const _RemovedStops({required this.removed, required this.onRestore});

  final List<({RunStop stop, int index})> removed;
  final void Function(String stopId) onRestore;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 10, 8, 10),
      decoration: BoxDecoration(
        color: AppColors.surfaceMuted,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.hairline),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            removed.length == 1
                ? '1 stop removed from this run'
                : '${removed.length} stops removed from this run',
            style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13),
          ),
          const SizedBox(height: 2),
          const Text(
            'They stay on the uploaded sheet — confirming just leaves them off the route.',
            style: TextStyle(fontSize: 11, color: AppColors.inkMuted),
          ),
          for (final entry in removed)
            Row(
              children: [
                Expanded(
                  child: Text(
                    entry.stop.customerName.isEmpty ? entry.stop.address : entry.stop.customerName,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 12, color: AppColors.inkMuted),
                  ),
                ),
                TextButton(
                  onPressed: () => onRestore(entry.stop.id),
                  style: TextButton.styleFrom(visualDensity: VisualDensity.compact),
                  child: const Text('Undo'),
                ),
              ],
            ),
        ],
      ),
    );
  }
}

/// What a pin on the review map says when you tap it.
///
/// Deliberately not `StopInstructionsSheet`: that one edits
/// `stop_instructions`, which is a durable per-address note, and this run is
/// a draft the owner may be about to discard. Here the useful actions are
/// read it and decide whether it belongs on the route at all.
class _ReviewStopSheet extends StatelessWidget {
  const _ReviewStopSheet({required this.stop, required this.position, required this.onRemove});

  final RunStop stop;
  final int position;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    final instructions = stop.instructions?.trim();

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                StopPin(number: position, compact: true),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    stop.customerName.isEmpty ? stop.address : stop.customerName,
                    style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Text(stop.address, style: const TextStyle(fontSize: 13, color: AppColors.inkMuted)),
            if (stop.itemsSummary.isNotEmpty) ...[
              const SizedBox(height: 10),
              Text(stop.itemsSummary, style: const TextStyle(fontSize: 13)),
            ],
            if (instructions != null && instructions.isNotEmpty) ...[
              const SizedBox(height: 10),
              const SectionLabel('Instructions'),
              const SizedBox(height: 4),
              Text(instructions, style: const TextStyle(fontSize: 13)),
            ],
            const SizedBox(height: 18),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: onRemove,
                    icon: const Icon(Icons.close_rounded, size: 18),
                    label: const Text('Remove from run'),
                  ),
                ),
                const SizedBox(width: 12),
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('Close'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
