import 'dart:async';
import 'dart:typed_data';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:geolocator/geolocator.dart';
import 'package:image_picker/image_picker.dart';
import 'package:latlong2/latlong.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

import '../../models/delivery_estimate.dart';
import '../../models/road_legs.dart';
import '../../models/run_stop.dart';
import '../../models/run_listing.dart';
import '../../models/run_time.dart';
import '../../models/run_timing.dart';
import '../../settings/settings_store.dart';
import '../../state/auth_state.dart';
import '../../theme/app_colors.dart';
import '../../util/app_log.dart';
import '../../widgets/basemap.dart';
import '../../widgets/basemap_attribution.dart';
import '../../widgets/route_preview_map.dart';
import '../../widgets/run_timing_pill.dart';
import '../../widgets/stop_details_sheet.dart';
import 'delivery_writer.dart';
import 'driving_logic.dart';
import 'photo_stamp.dart';
import 'run_heartbeat.dart';
import 'routes_client.dart';
import 'turn_by_turn.dart';
import 'voice_guide.dart';

/// Driving a run: the map in the app's chosen style with the van on it,
/// following it; the road to the next stops; and the stop to go to now.
///
///   Start run -> drive to the stop (Navigate hands it to Google Maps) ->
///   "Arrived" (offered by itself within ~60 m) -> photo -> Delivered ->
///   the next stop ... -> End run.
///
/// The voice says where to go next, and as the van gets close, what to
/// deliver and the owner's instructions (DrivingLogic decides what and when;
/// VoiceGuide speaks). Turn-by-turn directions are Google Maps' job: Navigate
/// opens it on the stop.
///
/// The screen stays awake while open. Location is used only while it is open
/// - nothing runs with the screen off yet.
class DrivingScreen extends StatefulWidget {
  const DrivingScreen({
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

  /// The schedule's times for the day ("HH:MM"), for "On time" / "12 min
  /// late"; null when unknown.
  final String? startTime;
  final String? endTime;
  final String? vehicle;

  @override
  State<DrivingScreen> createState() => _DrivingScreenState();
}

/// One stop of the run, with its pin when the geocoder placed it.
class _Stop {
  const _Stop({required this.id, required this.data, required this.stop, required this.located});

  final String id;
  final Map<String, dynamic> data;
  final RunStop stop;
  final bool located;

  bool get delivered => data['status'] == 'delivered';
}

class _DrivingScreenState extends State<DrivingScreen> {
  static const _dunedin = LatLng(-45.8788, 170.5028);

  final _map = MapController();
  final _voice = VoiceGuide();
  late final DeliveryWriter _writer = DeliveryWriter(
    runId: widget.runId,
    ownerUid: widget.authState.ownerUid ?? '',
  );
  late final RunHeartbeat _heartbeat = RunHeartbeat(
    runId: widget.runId,
    ownerUid: widget.authState.ownerUid ?? '',
    riderId: widget.authState.user?.uid ?? '',
  );
  late final DocumentReference<Map<String, dynamic>> _runRef = FirebaseFirestore.instance
      .collection('delivery_run')
      .doc(widget.runId);
  late final Stream<DocumentSnapshot<Map<String, dynamic>>> _runStream = _runRef.snapshots();
  late final Stream<QuerySnapshot<Map<String, dynamic>>> _stopsStream = _runRef
      .collection('delivery_stop')
      .orderBy('seq_order')
      .snapshots();

  StreamSubscription<Position>? _positionSub;
  StreamSubscription<bool>? _voiceSetting;
  Position? _position;
  bool _follow = true;
  bool _mapReady = false;
  String? _locationProblem;
  bool _busy = false;

  /// "Arrived" tapped this session (the stop's `arrived_at` follows).
  final _arrived = <String>{};
  // What has been said, per run, for as long as the app is open - so neither
  // turning the voice off and on nor reopening the run repeats it.
  static final _saidNext = <String, String>{};
  static final _saidApproach = <String, String>{};
  static final _saidArrive = <String, String>{};
  String? get _announcedArrive => _saidArrive[widget.runId];
  set _announcedArrive(String? id) =>
      id == null ? _saidArrive.remove(widget.runId) : _saidArrive[widget.runId] = id;

  /// Where the van stood at each stop it stopped at (DrivingLogic.hasStoppedAt)
  /// and hasn't delivered: driving away from one asks "Delivered to ...?".
  final _stoppedAt = <String, Position>{};

  /// Stops already asked about, so each is asked once.
  final _askedLeft = <String>{};
  bool _askingLeft = false;
  String? get _announcedNext => _saidNext[widget.runId];
  set _announcedNext(String? id) =>
      id == null ? _saidNext.remove(widget.runId) : _saidNext[widget.runId] = id;
  String? get _announcedApproach => _saidApproach[widget.runId];
  set _announcedApproach(String? id) =>
      id == null ? _saidApproach.remove(widget.runId) : _saidApproach[widget.runId] = id;

  // In-app turn-by-turn to the current stop (TurnByTurn, RoutesClient).
  static const _routes = RoutesClient();
  bool _guidance = true;

  /// Navigation mode, on from the start: the map turns to the way the van is
  /// heading and follows it close, and the stop panel shrinks to a bar -
  /// until the stop is near, when the full panel comes back for Arrived. It
  /// carries on to the next stop after a delivery.
  bool _navigating = true;

  /// The bar opened to the full stop panel while navigating.
  bool _panelOpen = false;

  /// The van's last known direction of travel, for the heading-up map.
  double _heading = 0;

  /// There is no top bar: the map has the screen. While driving, a tap on the
  /// map floats a back button over it for a few seconds; pressing it asks
  /// before leaving, exactly as the phone's own back does.
  bool _chrome = false;
  Timer? _chromeTimer;

  void _toggleChrome() {
    _chromeTimer?.cancel();
    setState(() => _chrome = !_chrome);
    if (_chrome) {
      _chromeTimer = Timer(const Duration(seconds: 5), () {
        if (mounted) setState(() => _chrome = false);
      });
    }
  }

  NavRoute? _nav;
  String? _navFor;
  NavProgress? _progress;
  bool _navLoading = false;

  /// Shown in the banner while there is no route: "Getting directions..." or
  /// why it failed. Null once a route is up.
  String? _navStatus;
  bool _navFailed = false;

  /// Where the van was when directions failed: once it is somewhere else,
  /// they are asked for again without the driver tapping Retry.
  LatLng? _navFailedFrom;
  DateTime? _navRequestedAt;
  int _offRouteFixes = 0;
  final _cues = <String>{};

  // The latest run and stops, for the position callback.
  Map<String, dynamic> _run = const {};
  List<_Stop> _stops = const [];
  Object? _roadSource;
  RoadLegs _road = const RoadLegs();

  bool get _started => _run['driver_started_at'] != null || _run['started_at'] != null;
  bool get _finished => _run['completed_at'] != null || _run['driver_ended_at'] != null;

  /// The run against its schedule - the same words the owner sees - while
  /// under way. This screen is the heartbeat, so it is never "no signal" here.
  RunTiming? get _timing {
    if (!_started || _finished) return null;
    final now = DateTime.now();
    return RunTiming.of(
      run: RunListing.fromMap(widget.runId, _run),
      startTime: widget.startTime,
      endTime: widget.endTime,
      lastSeen: now,
      now: now,
    );
  }

  /// The stop being driven to when it isn't simply the first one left: the
  /// driver picked it ("Go here next", or "Deliver here" beside another
  /// stop), or it was worked out after an out-of-order delivery
  /// (DrivingLogic.nextAfterDelivery). Null: the planned order.
  String? _targetId;

  /// Whether a run reopened part-way has had its next stop worked out from
  /// what was delivered last (once, when the first position arrives).
  bool _targetResolved = false;

  List<String> get _stopIds => [for (final s in _stops) s.id];
  Set<String> get _deliveredIds => {
    for (final s in _stops)
      if (s.delivered) s.id,
  };

  _Stop? get _current {
    final chosen = _stops.where((s) => s.id == _targetId && !s.delivered).firstOrNull;
    if (chosen != null) return chosen;
    final index = DrivingLogic.currentIndex(_stopIds, _deliveredIds);
    return index == null ? null : _stops[index];
  }

  double? _metersToId(String stopId) {
    final stop = _stops.where((s) => s.id == stopId).firstOrNull;
    return stop == null ? null : _metersTo(stop);
  }

  /// Another stop still to deliver that the van is standing at, while the
  /// one being driven to is somewhere else: offered as "Deliver here".
  _Stop? get _nearbyOther {
    final current = _current, accuracy = _position?.accuracy;
    if (!_started || _finished || current == null || _position == null) return null;
    bool near(_Stop stop) {
      final meters = _metersTo(stop);
      return meters != null && DrivingLogic.isNear(meters, accuracy: accuracy);
    }

    if (near(current)) return null;
    return _stops.where((s) => !s.delivered && s.id != current.id && near(s)).firstOrNull;
  }

  /// Drive to [stop] next, whatever the planned order says. Directions, the
  /// voice and the line ahead all follow from the new target.
  void _goTo(_Stop stop) {
    AppLog.auth('driving: target chosen', {'stopId': stop.id});
    setState(() {
      _targetId = stop.id;
      _targetResolved = true;
      _panelOpen = false;
      _follow = true;
      _resetDirections();
    });
    final here = _position;
    if (here != null) {
      _speakIfDue();
      _guide(here);
    }
  }

  /// A new stop to route to: forget the last one's failure or wait.
  void _resetDirections() {
    _navFailed = false;
    _navFailedFrom = null;
    _navStatus = null;
    _navRequestedAt = null;
    _offRouteFixes = 0;
  }

  /// A run opened part-way through: carry on from the stop delivered last
  /// rather than going back to the first one skipped, if that is nearer.
  void _resolveTarget() {
    if (_targetResolved || _position == null || _stops.isEmpty) return;
    _targetResolved = true;
    _Stop? last;
    for (final stop in _stops.where((s) => s.delivered)) {
      final at = stop.data['delivered_at'], lastAt = last?.data['delivered_at'];
      if (at is Timestamp && (lastAt is! Timestamp || at.compareTo(lastAt) > 0)) last = stop;
    }
    if (last == null) return;
    _targetId = DrivingLogic.nextAfterDelivery(_stopIds, _deliveredIds, last.id, metersTo: _metersToId);
  }

  double? _metersTo(_Stop stop) {
    final here = _position;
    if (here == null || !stop.located) return null;
    return DrivingLogic.metersBetween(LatLng(here.latitude, here.longitude), stop.stop.location);
  }

  @override
  void initState() {
    super.initState();
    WakelockPlus.enable();
    _voiceSetting = SettingsStore(widget.authState).voicePrompts().listen((on) {
      if (mounted) setState(() => _voice.muted = !on);
    });
    _startLocation();
    _heartbeat.start(position: () => _position, active: () => _started && !_finished);
  }

  @override
  void dispose() {
    _chromeTimer?.cancel();
    _positionSub?.cancel();
    _heartbeat.stop();
    _voiceSetting?.cancel();
    _voice.stop();
    WakelockPlus.disable();
    _map.dispose();
    super.dispose();
  }

  Future<void> _startLocation() async {
    try {
      if (!await Geolocator.isLocationServiceEnabled()) {
        setState(
          () => _locationProblem = 'Location is off on this phone - "Arrived" won\'t appear by itself.',
        );
        return;
      }
      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) permission = await Geolocator.requestPermission();
      if (permission == LocationPermission.denied || permission == LocationPermission.deniedForever) {
        setState(() => _locationProblem = 'Blue Dot can\'t see where you are - tap "Arrived" yourself.');
        return;
      }
      _positionSub =
          Geolocator.getPositionStream(
            locationSettings: const LocationSettings(accuracy: LocationAccuracy.high, distanceFilter: 5),
          ).listen(
            _onPosition,
            onError: (Object error) => AppLog.auth.error('position stream failed', error, null),
          );
      // The stream can take a while to give a first fix to a phone standing
      // still: start from where it last was, so directions come up at once.
      final last = await Geolocator.getLastKnownPosition();
      // Only a recent one: an old fix may be from another place entirely.
      final fresh =
          last != null && DateTime.now().difference(last.timestamp).abs() < const Duration(minutes: 2);
      if (fresh && mounted && _position == null) _onPosition(last);
    } catch (error, stack) {
      AppLog.auth.error('location setup failed', error, stack);
    }
  }

  void _onPosition(Position position) {
    if (!mounted) return;
    setState(() {
      _position = position;
      _locationProblem = null;
    });
    // A phone's heading is only trustworthy when it's moving.
    if (position.speed > 1.5 && position.heading >= 0) _heading = position.heading;
    _resolveTarget();
    _followVan(position);
    _speakIfDue();
    _guide(position);
    _checkLeftStop(position);
  }

  /// Stopped at the current stop and then driven away without a tap: ask,
  /// and answer "delivered" after a few seconds if the driver doesn't - on a
  /// long run, tapping at every door is the first thing to be forgotten.
  ///
  /// Only for a stop the van actually stood at (or "Arrived" was tapped
  /// for): driving past one is not a delivery.
  void _checkLeftStop(Position position) {
    final stop = _current;
    if (!_started || _finished || stop == null || !stop.located) return;
    final meters = _metersTo(stop);
    if (meters == null) return;
    if (DrivingLogic.hasStoppedAt(meters, accuracy: position.accuracy, speed: position.speed)) {
      _stoppedAt[stop.id] = position;
      return;
    }
    final wasThere = _stoppedAt.containsKey(stop.id) || _arrived.contains(stop.id);
    if (!wasThere || _askingLeft || _busy || _askedLeft.contains(stop.id)) return;
    if (!DrivingLogic.hasLeft(meters, accuracy: position.accuracy)) return;
    _askedLeft.add(stop.id);
    _askLeft(stop);
  }

  Future<void> _askLeft(_Stop stop) async {
    _askingLeft = true;
    AppLog.auth('driving: left a stop untapped', {'stopId': stop.id});
    _voice.say(DrivingLogic.leftLine(stop.stop), urgent: true);
    final answer = await showDialog<_LeftAnswer>(
      context: context,
      barrierDismissible: false,
      builder: (_) => _LeftStopDialog(
        name: stop.stop.customerName.isEmpty ? stop.stop.address : stop.stop.customerName,
        items: stop.stop.itemsSummary,
        photos: DeliveryWriter.photosAvailable,
      ),
    );
    _askingLeft = false;
    if (!mounted) return;
    // Where the van stood, not where it is now: the delivery's position
    // teaches the backend the drop point.
    final stood = _stoppedAt[stop.id];
    switch (answer) {
      case _LeftAnswer.delivered:
        await _deliver(stop, withPhoto: false, at: stood, late: true);
      case _LeftAnswer.photo:
        await _deliver(stop, withPhoto: true, at: stood, late: true);
      case _LeftAnswer.timedOut:
        await _deliver(stop, withPhoto: false, at: stood, late: true, note: DrivingLogic.autoConfirmNote);
      case _LeftAnswer.notDelivered || null:
        // Left on purpose: carry on to the next stop. This one stays on the
        // run, undelivered, and comes round again.
        setState(() {
          _targetId =
              DrivingLogic.nextAfterDelivery(_stopIds, _deliveredIds, stop.id, metersTo: _metersToId) ??
              stop.id;
          _targetResolved = true;
          _resetDirections();
        });
        _speakIfDue();
        _ensureRoute();
    }
  }

  /// Keeps the van in view. Navigating: heading up, close in, the van low on
  /// the screen so the road ahead shows. Otherwise: north up.
  void _followVan(Position position) {
    if (!_follow || !_mapReady) return;
    final here = LatLng(position.latitude, position.longitude);
    if (_navigatingNow) {
      _map.rotate(-_heading);
      _map.move(here, 17.5, offset: Offset(0, MediaQuery.sizeOf(context).height * 0.18));
    } else {
      if (_map.camera.rotation != 0) _map.rotate(0);
      _map.move(here, _map.camera.zoom < 15.5 ? 16.5 : _map.camera.zoom);
    }
  }

  /// Navigating, with a route up and the stop not yet reached.
  bool get _navigatingNow {
    final stop = _current;
    if (!_navigating || stop == null || _nav == null || _navFor != stop.id) return false;
    if (_arrived.contains(stop.id) || stop.data['arrived_at'] != null) return false;
    final meters = _metersTo(stop);
    return meters == null || !DrivingLogic.isNear(meters, accuracy: _position?.accuracy);
  }

  /// Turn-by-turn to the current stop: fetch its route once, follow the van
  /// along it, re-route after two fixes off it, and say each turn.
  void _guide(Position position) {
    final stop = _current;
    final here = LatLng(position.latitude, position.longitude);
    // A failure from somewhere else (a stale first fix, a spot with no road)
    // says nothing about here.
    final failedFrom = _navFailedFrom;
    if (_navFailed && failedFrom != null && DrivingLogic.metersBetween(failedFrom, here) > 150) {
      _resetDirections();
    }
    final ready = _guidance && _started && !_finished && RoutesClient.available && !_navFailed;
    if (!ready || stop == null) return;
    if (_arrived.contains(stop.id) || stop.data['arrived_at'] != null) return; // there: no more directions
    final nav = _nav;
    if (_navFor != stop.id || nav == null) {
      _fetchRoute(stop, here, position.heading);
      return;
    }
    final progress = TurnByTurn.progress(nav, here);
    setState(() => _progress = progress);
    if (TurnByTurn.isOffRoute(progress, accuracy: position.accuracy)) {
      if (++_offRouteFixes >= 2) _fetchRoute(stop, here, position.heading, reroute: true);
      return;
    }
    _offRouteFixes = 0;
    final cue = TurnByTurn.cue(nav, progress, stop.stop.customerName, _cues);
    if (cue != null) _voice.say(cue, urgent: progress.metersToTurn <= TurnByTurn.nowMeters);
  }

  /// Directions to the current stop without waiting for the van to move. A
  /// phone standing still reports no new fix, so a route asked for only on a
  /// fix never came when the fix arrived before the run's stops did, or
  /// before Start was pressed. Called whenever the run or its stops change.
  void _ensureRoute() {
    final stop = _current, here = _position;
    if (here == null || stop == null) return;
    if (_nav != null && _navFor == stop.id) return;
    _guide(here);
  }

  Future<void> _fetchRoute(_Stop stop, LatLng here, double heading, {bool reroute = false}) async {
    final last = _navRequestedAt;
    final tooSoon = last != null && DateTime.now().difference(last) < const Duration(seconds: 10);
    if (_navLoading || tooSoon) return;
    _navLoading = true;
    _navRequestedAt = DateTime.now();
    AppLog.auth('directions: requesting', {'stopId': stop.id, 'reroute': reroute, 'located': stop.located});
    if (mounted && _nav == null) setState(() => _navStatus = 'Getting directions...');
    try {
      final nav = await _routes.route(
        here,
        to: stop.located ? stop.stop.location : null,
        address: stop.stop.address,
        heading: heading,
      );
      AppLog.auth('directions: route', {'steps': nav.steps.length, 'meters': nav.distanceMeters});
      if (!mounted) return;
      setState(() {
        _nav = nav;
        _navFor = stop.id;
        _navStatus = null;
        _navFailed = false;
        _offRouteFixes = 0;
        _progress = TurnByTurn.progress(nav, here);
        // A new stop's turns start fresh; a re-route keeps what was said.
        if (!reroute) _cues.clear();
      });
      if (reroute) _voice.say('Recalculating.', urgent: true);
    } catch (error, stack) {
      AppLog.auth.error('directions failed', error, stack);
      if (mounted) {
        setState(() {
          _navStatus = error is RoutesException
              ? error.message
              : "Couldn't get directions. Check your connection.";
          // Stop asking on every fix; "Retry", or moving on, asks again.
          _navFailed = true;
          _navFailedFrom = here;
        });
      }
    } finally {
      _navLoading = false;
    }
  }

  /// "Next: ..." once per stop, then "Approaching ..." once, close to it.
  void _speakIfDue() {
    final stop = _current;
    if (!_started || _finished || stop == null) return;
    final meters = _metersTo(stop);
    if (_announcedNext != stop.id) {
      _announcedNext = stop.id;
      final here = _position;
      _voice.say(
        DrivingLogic.nextLine(
          stop.stop,
          meters: meters,
          direction: here == null || !stop.located
              ? null
              : DrivingLogic.direction(LatLng(here.latitude, here.longitude), stop.stop.location),
        ),
      );
      return;
    }
    // At the stop: what to deliver, and the owner's note. Said over anything
    // else, since this is the moment it is needed.
    if (meters != null &&
        DrivingLogic.isNear(meters, accuracy: _position?.accuracy) &&
        _announcedArrive != stop.id) {
      _announcedArrive = stop.id;
      _announcedApproach = stop.id; // too late for "Approaching"
      _voice.say(DrivingLogic.arriveLine(stop.stop), urgent: true);
      return;
    }
    if (meters != null && meters <= DrivingLogic.approachMeters && _announcedApproach != stop.id) {
      _announcedApproach = stop.id;
      _voice.say(DrivingLogic.approachLine(stop.stop));
    }
  }

  // --- Actions ---------------------------------------------------------------

  Future<void> _attempt(String what, Future<void> Function() action) async {
    if (_busy) return;
    setState(() => _busy = true);
    final messenger = ScaffoldMessenger.of(context);
    try {
      await action();
    } catch (error, stack) {
      AppLog.auth.error('driving: $what failed', error, stack);
      messenger.showSnackBar(SnackBar(content: Text("Couldn't $what. Check your connection and try again.")));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _start() => _attempt('start the run', () async {
    await _writer.start();
    _voice.say(DrivingLogic.startLine(widget.routeName, _stops.length, _current?.stop));
    _announcedNext = _current?.id; // the start line already named it
  });

  Future<void> _arrive(_Stop stop) async {
    await _attempt('mark it arrived', () async {
      await _writer.arrived(stop.id);
      setState(() => _arrived.add(stop.id));
    });
  }

  /// [late] is a delivery confirmed after driving away: it is saved from
  /// where the van stood ([at], possibly unknown), never from where it is now.
  Future<void> _deliver(
    _Stop stop, {
    required bool withPhoto,
    Position? at,
    bool late = false,
    String? note,
  }) async {
    Uint8List? photo;
    if (withPhoto) {
      final picked = await ImagePicker().pickImage(
        source: ImageSource.camera,
        maxWidth: 1600,
        imageQuality: 85,
      );
      if (picked == null || !mounted) return; // cancelled: still at the stop
      setState(() => _busy = true);
      try {
        // Stamped with the moment it was taken, then shrunk (PhotoStamp).
        photo = await PhotoStamp.stamp(
          await picked.readAsBytes(),
          PhotoStamp.linesFor(
            takenAt: DateTime.now(),
            routeName: widget.routeName,
            stopNumber: _stops.indexOf(stop) + 1,
            stopCount: _stops.length,
            customerName: stop.stop.customerName,
            address: stop.stop.address,
          ),
        );
      } finally {
        if (mounted) setState(() => _busy = false);
      }
    }
    await _attempt('save the delivery', () async {
      await _writer.delivered(stop.id, position: late ? at : _position, photo: photo, note: note);
      _stoppedAt.remove(stop.id);
      // Where next: the planned order, unless stops are being done out of
      // it - then the nearer of the earliest one skipped and the one after
      // this. Decided here, once, so it doesn't swap as the van moves.
      _targetId = DrivingLogic.nextAfterDelivery(_stopIds, _deliveredIds, stop.id, metersTo: _metersToId);
      _targetResolved = true;
      _panelOpen = false;
      _resetDirections();
      // The stream brings the next stop, a different id: it is said when it
      // arrives. (Clearing what was said would repeat this one meanwhile.)
      final remaining = _stops.where((s) => !s.delivered && s.id != stop.id).length;
      if (remaining == 0) _voice.say(DrivingLogic.doneLine(_stops.length));
    });
  }

  Future<void> _end() async {
    final left = _stops.where((s) => !s.delivered).length;
    if (left > 0) {
      final go = await showDialog<bool>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: const Text('End the run?'),
          content: Text(
            '$left ${left == 1 ? 'stop is' : 'stops are'} not delivered. Your owner will see that.',
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(dialogContext, false), child: const Text('Keep going')),
            FilledButton(onPressed: () => Navigator.pop(dialogContext, true), child: const Text('End run')),
          ],
        ),
      );
      if (go != true || !mounted) return;
    }
    final navigator = Navigator.of(context);
    await _attempt('end the run', () async {
      await _writer.end(hasStart: _run['driver_started_at'] != null);
      navigator.pop();
    });
  }

  /// "Directions": turn-by-turn in the app, from where the van is now.
  /// "Directions": turn-by-turn in the app, from where the van is now. Asks
  /// the phone for a fix if none has come in yet - a phone standing still
  /// indoors may not report one by itself for a long while.
  Future<void> _directions(_Stop stop) async {
    AppLog.auth('directions: tapped', {'stopId': stop.id, 'hasFix': _position != null});
    setState(() {
      _guidance = true;
      _follow = true;
      _navFailed = false;
      _navRequestedAt = null; // ask now, even if a route was just fetched
      _navStatus = 'Getting directions...';
    });
    var here = _position;
    if (here == null) {
      try {
        here =
            await Geolocator.getLastKnownPosition() ??
            await Geolocator.getCurrentPosition(
              locationSettings: const LocationSettings(
                accuracy: LocationAccuracy.high,
                timeLimit: Duration(seconds: 15),
              ),
            );
        if (mounted) setState(() => _position = here);
      } catch (error, stack) {
        AppLog.auth.error('directions: no location', error, stack);
      }
    }
    if (!mounted) return;
    if (here == null) {
      setState(() {
        _navStatus = "Can't find your location - check location is on for Blue Dot.";
        _navFailed = true;
      });
      return;
    }
    await _fetchRoute(stop, LatLng(here.latitude, here.longitude), here.heading);
    if (!mounted) return;
    if (_nav != null && _navFor == stop.id) {
      setState(() {
        _navigating = true;
        _panelOpen = false;
      });
      if (here.heading >= 0 && here.speed > 1.5) _heading = here.heading;
    }
    _recentre();
  }

  /// "Exit" on the bottom bar: no turn-by-turn, no line to follow, the map
  /// north-up again - for a driver who knows the way. The stop, its items and
  /// Arrived all stay; "Navigate" brings the directions back.
  void _exitNavigation() {
    AppLog.auth('directions: exited');
    _voice.stop();
    setState(() {
      _guidance = false;
      _nav = null;
      _navFor = null;
      _progress = null;
      _resetDirections();
    });
    if (_mapReady && _map.camera.rotation != 0) _map.rotate(0);
    _recentre();
  }

  /// The voice on or off - the button on the map, and the icon in the bar.
  /// Saved as the driver's setting (Settings -> Voice prompts), so it stays
  /// as they left it next time. Turning it back on doesn't repeat anything.
  Future<void> _toggleMute() async {
    final on = _voice.muted; // muted now -> turning voice on
    setState(() => _voice.muted = !on);
    // Back on: carries on from here - nothing already said is said again.
    if (!on) await _voice.stop();
    if (mounted) {
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          SnackBar(
            content: Text(on ? 'Voice on' : 'Voice off - tap the speaker to turn it back on'),
            duration: const Duration(seconds: 2),
          ),
        );
    }
    await SettingsStore(widget.authState).setVoicePrompts(on);
  }

  void _recentre() {
    setState(() => _follow = true);
    final here = _position;
    if (here != null) _followVan(here);
  }

  void _showStop(int number, _Stop stop) {
    showStopDetails(
      context,
      number: number,
      customerName: stop.stop.customerName,
      address: stop.stop.address,
      items: stop.stop.items,
      instructions: stop.stop.instructions,
      phone: stop.data['phone'] as String?,
      deliveredAt: (stop.data['delivered_at'] as Timestamp?)?.toDate().toLocal(),
      photoUrl: stop.data['pod_photo_url'] as String?,
      // Any stop still to do can be the next one, whatever the order says.
      actionLabel: _started && !_finished && !stop.delivered && stop.id != _current?.id
          ? 'Go here next'
          : null,
      onAction: () => _goTo(stop),
    );
  }

  // --- Build -------------------------------------------------------------------

  static _Stop _toStop(QueryDocumentSnapshot<Map<String, dynamic>> doc, int index) {
    final data = doc.data();
    final placed = RunStop.fromDoc(doc);
    return _Stop(
      id: doc.id,
      data: data,
      located: placed != null,
      stop:
          placed ??
          RunStop(
            id: doc.id,
            seqOrder: index,
            customerName: data['customer_name'] as String? ?? '',
            address: data['address'] as String? ?? '',
            location: _dunedin,
            items: [
              for (final raw in (data['items'] as List?) ?? const [])
                if (raw is Map) StopItem.fromMap(Map<String, dynamic>.from(raw)),
            ],
            instructions: data['instructions'] as String?,
          ),
    );
  }

  /// Set once "Leave" is confirmed, so a second back press doesn't ask again.
  bool _leaving = false;
  bool _resumeChecked = false;

  /// Back (the floating arrow or the phone's back gesture) on a run under
  /// way asks first, and the owner hears that the driver left. A run not
  /// started, or finished, just closes.
  Future<void> _confirmLeave() async {
    final choice = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Leave the run?'),
        content: Text(
          '${widget.routeName} is still under way. Your owner will be told you left. '
          'Open it again to carry on from where you are.',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialogContext, 'end'), child: const Text('End run')),
          TextButton(onPressed: () => Navigator.pop(dialogContext, 'leave'), child: const Text('Leave')),
          FilledButton(onPressed: () => Navigator.pop(dialogContext), child: const Text('Stay')),
        ],
      ),
    );
    if (!mounted) return;
    switch (choice) {
      case 'end':
        await _end();
      case 'leave':
        // Not awaited: offline, the write waits in Firestore's queue and
        // goes when there is signal; the driver shouldn't wait for it.
        _writer.left().catchError((Object error, StackTrace stack) {
          AppLog.auth.error('leave run failed', error, stack);
        });
        _leaving = true;
        Navigator.of(context).pop();
    }
  }

  /// Reopened after "Leave": tell the owner the driver is back. Once per
  /// screen, on the first look at the run.
  void _resumeIfLeft() {
    if (_resumeChecked) return;
    _resumeChecked = true;
    if (_started && !_finished && RunListing.fromMap(widget.runId, _run).hasLeft) {
      _writer.resumed().catchError((Object error, StackTrace stack) {
        AppLog.auth.error('resume run failed', error, stack);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    // Decided at the moment of the back press, from the latest run: the run
    // stream rebuilds only its own subtree, so a canPop worked out here
    // could be a snapshot behind.
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) return;
        if (_leaving || !_started || _finished) {
          Navigator.of(context).pop();
        } else {
          _confirmLeave();
        }
      },
      child: _scaffold(context),
    );
  }

  Widget _scaffold(BuildContext context) {
    return Scaffold(
      // No app bar: keep the map (and its credits) below the status bar.
      body: SafeArea(
        bottom: false,
        child: StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
          stream: _runStream,
          builder: (context, runSnap) => StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
            stream: _stopsStream,
            builder: (context, stopsSnap) {
              if (runSnap.hasError || stopsSnap.hasError) {
                return const Center(child: Text("This run isn't yours to drive."));
              }
              if (!runSnap.hasData || !stopsSnap.hasData) {
                return const Center(child: CircularProgressIndicator());
              }
              _run = runSnap.data!.data() ?? const {};
              _resumeIfLeft();
              _stops = [
                for (final (index, doc) in stopsSnap.data!.docs.indexed)
                  if (doc.data()['excluded'] != true) _toStop(doc, index),
              ];
              if (!identical(_run['road_legs'], _roadSource)) {
                _roadSource = _run['road_legs'];
                _road = RoadLegs.fromRun(_roadSource);
              }
              // A newly arrived stop list (a delivery landing) may need saying.
              WidgetsBinding.instance.addPostFrameCallback((_) {
                if (!mounted) return;
                _speakIfDue();
                _ensureRoute();
              });
              return Stack(
                children: [
                  Positioned.fill(child: _buildMap()),
                  Positioned(
                    top: 12,
                    right: 12,
                    child: Column(
                      children: [
                        const MapStyleButton(),
                        const SizedBox(height: 8),
                        // The voice, on the map where a driver's thumb is.
                        FloatingActionButton.small(
                          heroTag: 'voice',
                          tooltip: _voice.muted ? 'Voice off - tap to turn on' : 'Voice on - tap to turn off',
                          backgroundColor: _voice.muted ? Colors.white : AppColors.brand,
                          foregroundColor: _voice.muted ? AppColors.inkMuted : Colors.white,
                          onPressed: _toggleMute,
                          child: Icon(
                            _voice.muted ? Icons.volume_off_rounded : Icons.record_voice_over_rounded,
                          ),
                        ),
                        const SizedBox(height: 8),
                        FloatingActionButton.small(
                          heroTag: 'recentre',
                          tooltip: 'Follow me',
                          backgroundColor: _follow ? AppColors.brand : Colors.white,
                          foregroundColor: _follow ? Colors.white : AppColors.brand,
                          onPressed: _recentre,
                          child: const Icon(Icons.my_location_rounded),
                        ),
                      ],
                    ),
                  ),
                  Positioned(
                    top: 12,
                    left: 12,
                    right: 72,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Always there before the run starts and after it
                        // ends; mid-run only for a moment after a map tap.
                        if (_chrome || !_started || _finished || _current == null)
                          Padding(
                            padding: const EdgeInsets.only(bottom: 8),
                            child: FloatingActionButton.small(
                              heroTag: 'back',
                              tooltip: 'Back',
                              backgroundColor: Colors.white,
                              foregroundColor: AppColors.ink,
                              onPressed: () => Navigator.of(context).maybePop(),
                              child: const Icon(Icons.arrow_back_rounded),
                            ),
                          ),
                        ?_turnBanner(),
                      ],
                    ),
                  ),
                  Positioned(left: 0, right: 0, bottom: 0, child: _buildPanel()),
                ],
              );
            },
          ),
        ),
      ),
    );
  }

  Widget _buildMap() {
    final current = _current;
    final here = _position == null ? null : LatLng(_position!.latitude, _position!.longitude);
    final depotLat = (_run['depot_lat'] as num?)?.toDouble(),
        depotLng = (_run['depot_lng'] as num?)?.toDouble();
    final depot = depotLat == null || depotLng == null ? null : LatLng(depotLat, depotLng);

    // The road ahead. First to the stop being driven to: the directions'
    // line, else the run's own road shape from the stop before it (when that
    // is where the van has come from), else straight from the van. Then
    // through every stop left - that one first, the rest in the planned
    // order - along the run's road shapes where it has them.
    final navLine = _guidance && _navFor == current?.id ? _nav?.points : null;
    final byId = {for (final stop in _stops) stop.id: stop};
    List<LatLng>? lead = navLine;
    if (lead == null && current != null && current.located) {
      final index = _stops.indexOf(current);
      final before = index > 0 ? _stops[index - 1] : null;
      final fromKey = index == 0
          ? DeliveryEstimate.depotKey
          : (before!.delivered ? before.stop.addressKey : null);
      final toKey = current.stop.addressKey;
      lead = fromKey == null || toKey == null ? null : _road.shapes[DeliveryEstimate.legKey(fromKey, toKey)];
      lead ??= here == null ? null : [here, current.stop.location];
    }
    final legs = <List<LatLng>>[];
    _Stop? previous;
    for (final id in DrivingLogic.remainingOrder(_stopIds, _deliveredIds, current?.id)) {
      final stop = byId[id]!;
      if (!stop.located) continue;
      if (previous != null) {
        final fromKey = previous.stop.addressKey, toKey = stop.stop.addressKey;
        final shape = fromKey == null || toKey == null
            ? null
            : _road.shapes[DeliveryEstimate.legKey(fromKey, toKey)];
        legs.add(shape ?? [previous.stop.location, stop.stop.location]);
      }
      previous = stop;
    }

    return FlutterMap(
      mapController: _map,
      options: MapOptions(
        initialCenter: here ?? (current?.located == true ? current!.stop.location : (depot ?? _dunedin)),
        initialZoom: 15.5,
        minZoom: 5,
        maxZoom: 19,
        interactionOptions: const InteractionOptions(flags: InteractiveFlag.all & ~InteractiveFlag.rotate),
        onMapReady: () => _mapReady = true,
        // A tap on the map shows the top bar (back, End run); another hides it.
        onTap: (_, _) => _toggleChrome(),
        // Dragging the map stops it following the van until "Follow me".
        onPositionChanged: (camera, hasGesture) {
          if (hasGesture && _follow) setState(() => _follow = false);
        },
      ),
      children: [
        const BasemapLayer(),
        PolylineLayer(
          polylines: [
            // The rest of the run, faint; the way to the next stop leads.
            for (final points in legs)
              Polyline(points: points, strokeWidth: 4, color: AppColors.brand.withValues(alpha: 0.35)),
            if (lead != null)
              Polyline(
                points: lead,
                strokeWidth: navLine == null ? 6 : 7,
                color: AppColors.brand,
                borderStrokeWidth: navLine == null ? 0 : 2,
                borderColor: Colors.white,
              ),
          ],
        ),
        MarkerLayer(
          markers: [
            for (final (index, stop) in _stops.indexed)
              if (stop.located)
                Marker(
                  rotate: true,
                  point: stop.stop.location,
                  width: stop.id == current?.id ? 44 : 28,
                  height: stop.id == current?.id ? 52 : 28,
                  alignment: stop.id == current?.id ? Alignment.topCenter : Alignment.center,
                  child: GestureDetector(
                    onTap: () => _showStop(index + 1, stop),
                    child: StopPin(
                      number: index + 1,
                      compact: stop.id != current?.id,
                      selected: stop.id == current?.id,
                      delivered: stop.delivered,
                    ),
                  ),
                ),
            if (here != null)
              Marker(
                rotate: true,
                point: here,
                width: 46,
                height: 46,
                child: Container(
                  decoration: BoxDecoration(
                    color: AppColors.brand,
                    shape: BoxShape.circle,
                    border: Border.all(color: Colors.white, width: 3),
                    boxShadow: const [BoxShadow(color: Color(0x40000000), blurRadius: 6)],
                  ),
                  child: const Icon(Icons.local_shipping_rounded, color: Colors.white, size: 22),
                ),
              ),
          ],
        ),
        const BasemapAttribution(atTop: true),
      ],
    );
  }

  /// The next turn, over the map: its arrow, how far, and what it is. Tap the
  /// cross to hide directions (the run carries on; "Directions" brings them
  /// back).
  Widget? _turnBanner() {
    final stop = _current, nav = _nav, progress = _progress;
    if (!_guidance || stop == null) return null;
    final status = _navStatus;
    if (status != null && (nav == null || _navFor != stop.id || _navFailed)) {
      return Material(
        color: _navFailed ? AppColors.warning : AppColors.brand,
        elevation: 4,
        borderRadius: BorderRadius.circular(16),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 10, 4, 10),
          child: Row(
            children: [
              if (_navFailed)
                const Icon(Icons.error_outline_rounded, color: Colors.white)
              else
                const SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(strokeWidth: 2.5, color: Colors.white),
                ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(status, style: const TextStyle(color: Colors.white, fontSize: 13.5)),
              ),
              if (_navFailed)
                TextButton(
                  onPressed: () => _directions(stop),
                  child: const Text('Retry', style: TextStyle(color: Colors.white)),
                ),
            ],
          ),
        ),
      );
    }
    if (nav == null || progress == null || _navFor != stop.id) return null;
    if (_arrived.contains(stop.id) || stop.data['arrived_at'] != null) return null;
    final turn = TurnByTurn.ahead(nav, progress, stop.stop.customerName);
    return Material(
      color: AppColors.brand,
      elevation: 4,
      borderRadius: BorderRadius.circular(16),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 10, 4, 10),
        child: Row(
          children: [
            Icon(TurnByTurn.icon(turn.maneuver), color: Colors.white, size: 34),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    DrivingLogic.distanceLabel(progress.metersToTurn),
                    style: const TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.w800),
                  ),
                  Text(
                    turn.instruction.replaceAll('\n', ' '),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(color: Colors.white, fontSize: 13.5, height: 1.25),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 10),
          ],
        ),
      ),
    );
  }

  Widget _buildPanel() {
    final current = _current;
    final Widget content;
    if (!_started) {
      content = _StartPanel(
        routeName: widget.routeName,
        stopCount: _stops.length,
        vehicle: widget.vehicle,
        busy: _busy,
        onStart: _start,
      );
    } else if (current == null || _finished) {
      content = _DonePanel(
        stopCount: _stops.length,
        delivered: _stops.where((s) => s.delivered).length,
        ended: _finished,
        busy: _busy,
        onEnd: _end,
        onClose: () => Navigator.of(context).pop(),
      );
    } else {
      final meters = _metersTo(current);
      final here = _position;
      // Directions' own figures when there is a route to this stop.
      final nav = _guidance && _navFor == current.id ? _nav : null;
      final progress = nav == null ? null : _progress;
      final time = nav == null || progress == null ? null : TurnByTurn.remainingTime(nav, progress);
      content = _DrivePanel(
        stop: current,
        number: _stops.indexOf(current) + 1,
        total: _stops.length,
        deliveredCount: _stops.where((s) => s.delivered).length,
        timing: _timing,
        meters: meters,
        direction: here == null || !current.located
            ? null
            : DrivingLogic.direction(LatLng(here.latitude, here.longitude), current.stop.location),
        roadMeters: nav == null || progress == null ? null : TurnByTurn.remainingMeters(nav, progress),
        roadTime: time,
        near: meters != null && DrivingLogic.isNear(meters, accuracy: here?.accuracy),
        arrived: _arrived.contains(current.id) || current.data['arrived_at'] != null,
        busy: _busy,
        photos: DeliveryWriter.photosAvailable,
        guidance: _guidance,
        directionsAvailable: RoutesClient.available,
        noLocation: _locationProblem != null,
        expanded: _panelOpen,
        onToggle: () => setState(() => _panelOpen = !_panelOpen),
        onExitNavigation: _exitNavigation,
        onNavigate: () => _directions(current),
        onArrived: () => _arrive(current),
        onDeliver: (withPhoto) => _deliver(current, withPhoto: withPhoto),
      );
    }
    final other = _nearbyOther;
    // A sheet flush with the screen's edges, as map apps have it: the white
    // runs under the gesture bar, so no strip of map is stranded below it.
    final compact = content is _DrivePanel;
    return Container(
      padding: EdgeInsets.fromLTRB(
        12,
        compact ? 4 : 14,
        12,
        MediaQuery.viewPaddingOf(context).bottom + (compact ? 6 : 12),
      ),
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        boxShadow: [BoxShadow(color: Color(0x33000000), blurRadius: 16, offset: Offset(0, -2))],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (_locationProblem case final problem?)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Text(problem, style: const TextStyle(fontSize: 12, color: AppColors.warning)),
            ),
          // Standing at a different stop from the one being driven to:
          // deliver this one first, and the route carries on from here.
          if (other != null)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Material(
                color: AppColors.brandSoft,
                borderRadius: BorderRadius.circular(12),
                child: InkWell(
                  borderRadius: BorderRadius.circular(12),
                  onTap: () => _goTo(other),
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(12, 8, 8, 8),
                    child: Row(
                      children: [
                        const Icon(Icons.place_rounded, size: 18, color: AppColors.brand),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            "You're at ${other.stop.customerName} (stop ${_stops.indexOf(other) + 1})",
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
                          ),
                        ),
                        const Text(
                          'Deliver here',
                          style: TextStyle(fontSize: 13, fontWeight: FontWeight.w800, color: AppColors.brand),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          // Start and Done have no stop line to carry the run's timing.
          if (content is! _DrivePanel)
            if (_timing case final timing?)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Align(alignment: Alignment.centerLeft, child: RunTimingPill(timing)),
              ),
          content,
        ],
      ),
    );
  }
}

class _StartPanel extends StatelessWidget {
  const _StartPanel({
    required this.routeName,
    required this.stopCount,
    required this.vehicle,
    required this.busy,
    required this.onStart,
  });

  final String routeName;
  final int stopCount;
  final String? vehicle;
  final bool busy;
  final VoidCallback onStart;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(routeName, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
        const SizedBox(height: 2),
        Text(
          ['$stopCount stops', ?vehicle].join(' · '),
          style: const TextStyle(fontSize: 13, color: AppColors.inkMuted),
        ),
        const SizedBox(height: 12),
        FilledButton.icon(
          onPressed: busy ? null : onStart,
          icon: const Icon(Icons.play_arrow_rounded),
          label: const Text('Start run'),
          style: FilledButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 14)),
        ),
      ],
    );
  }
}

/// The bar across the bottom while driving to a stop, laid out like a
/// navigation app's: how long and how far, who it is, what to deliver - in a
/// few lines, so the map keeps the screen. Tap it for the address, every
/// product and the whole note.
///
///   8 min   4.0 km · arrive 3:58 pm                        (x)  ^
///   Dynes Mechanical Ltd
///   24 Donald Street, Kenmure
///   Stop 1 of 73 · 0 delivered                        [On time]
///   2 x 2 L Standard Milk
///   Previously Transport Repairs
///
/// The (x) exits navigation (no turn-by-turn, no line; the stop stays) and
/// becomes "Navigate" to bring it back. Arrived shows at the stop; the
/// deliver buttons after it.
class _DrivePanel extends StatelessWidget {
  const _DrivePanel({
    required this.stop,
    required this.number,
    required this.total,
    required this.deliveredCount,
    required this.timing,
    required this.meters,
    required this.direction,
    required this.roadMeters,
    required this.roadTime,
    required this.near,
    required this.arrived,
    required this.busy,
    required this.photos,
    required this.guidance,
    required this.directionsAvailable,
    required this.noLocation,
    required this.expanded,
    required this.onToggle,
    required this.onExitNavigation,
    required this.onNavigate,
    required this.onArrived,
    required this.onDeliver,
  });

  final _Stop stop;
  final int number;
  final int total;
  final int deliveredCount;
  final RunTiming? timing;

  /// Straight-line distance and compass direction to the pin, if known.
  final double? meters;
  final String? direction;

  /// By road, from the directions, while there is a route up.
  final double? roadMeters;
  final Duration? roadTime;

  final bool near;
  final bool arrived;
  final bool busy;
  final bool photos;

  /// Turn-by-turn is on (it may still be loading, or have failed).
  final bool guidance;
  final bool directionsAvailable;

  /// The phone can't tell where it is: Arrived is offered anyway.
  final bool noLocation;
  final bool expanded;
  final VoidCallback onToggle;
  final VoidCallback onExitNavigation;
  final VoidCallback onNavigate;
  final VoidCallback onArrived;
  final void Function(bool withPhoto) onDeliver;

  /// The big figure and the line beside it: time and distance by road while
  /// navigating, else how far and which way, else just "At the stop".
  (String, String, Color) get _headline {
    if (arrived) return ('At the stop', '', AppColors.success);
    final time = roadTime, road = roadMeters;
    if (time != null && road != null) {
      final arrive = DateTime.now().add(time);
      final minutes = (time.inSeconds / 60).ceil();
      return (
        minutes < 60 ? '$minutes min' : '${minutes ~/ 60} h ${minutes % 60} min',
        '${DrivingLogic.distanceLabel(road)} · arrive ${formatClock(arrive.hour, arrive.minute)}',
        AppColors.success,
      );
    }
    if (meters != null) return (DrivingLogic.distanceLabel(meters!), direction ?? '', AppColors.brand);
    return ('Stop $number', '', AppColors.ink);
  }

  @override
  Widget build(BuildContext context) {
    final details = stop.stop;
    final note = details.instructions?.trim() ?? '';
    final (headline, beside, tone) = _headline;
    final late = timing != null && timing!.isProblem ? timing!.label : null;
    final name = details.customerName.isEmpty ? details.address : details.customerName;
    // What to hand over matters at the door, so it opens by itself there.
    final handover = expanded || arrived;
    const muted = TextStyle(fontSize: 12.5, color: AppColors.inkMuted, fontWeight: FontWeight.w600);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // The whole strip opens and closes the details: tap, or swipe.
        GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: onToggle,
          onVerticalDragEnd: (drag) {
            final speed = drag.primaryVelocity ?? 0;
            if ((speed < -150 && !expanded) || (speed > 150 && expanded)) onToggle();
          },
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Center(
                child: Container(
                  width: 36,
                  height: 4,
                  margin: const EdgeInsets.only(bottom: 4),
                  decoration: BoxDecoration(
                    color: const Color(0x33000000),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              Row(
                children: [
                  // Exit navigation, here on the bar - or bring it back.
                  if (directionsAvailable && !arrived)
                    _RoundButton(
                      icon: guidance ? Icons.close_rounded : Icons.navigation_rounded,
                      tooltip: guidance ? 'Exit navigation' : 'Navigate',
                      color: guidance ? AppColors.ink : AppColors.brand,
                      onPressed: guidance ? onExitNavigation : onNavigate,
                    )
                  else
                    const SizedBox(width: 44),
                  Expanded(
                    child: Column(
                      children: [
                        Text.rich(
                          TextSpan(
                            text: headline,
                            children: [if (beside.isNotEmpty) TextSpan(text: '  $beside', style: muted)],
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.w800,
                            letterSpacing: -0.4,
                            height: 1.15,
                            color: tone,
                          ),
                        ),
                        Text.rich(
                          TextSpan(
                            text: '$number · $name',
                            children: [
                              if (late != null && !expanded)
                                TextSpan(
                                  text: ' · $late',
                                  style: const TextStyle(
                                    color: AppColors.warning,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                            ],
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                            fontSize: 13.5,
                            fontWeight: FontWeight.w700,
                            color: AppColors.ink,
                          ),
                        ),
                      ],
                    ),
                  ),
                  _RoundButton(
                    icon: expanded ? Icons.keyboard_arrow_down_rounded : Icons.keyboard_arrow_up_rounded,
                    tooltip: expanded ? 'Hide details' : 'Stop details',
                    color: AppColors.inkMuted,
                    onPressed: onToggle,
                  ),
                ],
              ),
              if (expanded) ...[
                const SizedBox(height: 8),
                if (details.customerName.isNotEmpty && details.address.isNotEmpty)
                  Text(details.address, style: const TextStyle(fontSize: 13, color: AppColors.inkMuted)),
                const SizedBox(height: 4),
                Row(
                  children: [
                    Expanded(child: Text('Stop $number of $total · $deliveredCount delivered', style: muted)),
                    if (timing case final timing?) RunTimingPill(timing),
                  ],
                ),
              ],
              if (handover && details.items.isNotEmpty) ...[
                const SizedBox(height: 8),
                if (expanded)
                  Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: [
                      for (final item in details.items)
                        Chip(
                          label: Text(item.label, style: const TextStyle(fontSize: 12.5)),
                          visualDensity: VisualDensity.compact,
                          materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        ),
                    ],
                  )
                else
                  Row(
                    children: [
                      const Icon(Icons.inventory_2_outlined, size: 16, color: AppColors.brand),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          details.itemsSummary,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w700),
                        ),
                      ),
                    ],
                  ),
              ],
              if (handover && note.isNotEmpty) ...[
                const SizedBox(height: 4),
                Text(
                  note,
                  maxLines: expanded ? null : 2,
                  overflow: expanded ? null : TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 13, fontStyle: FontStyle.italic),
                ),
              ],
            ],
          ),
        ),
        if (!arrived) ...[
          // Arrived only at the stop - or when the phone can't tell where it
          // is, so the driver is never stuck. Never from kilometres away.
          if (near || noLocation) ...[
            const SizedBox(height: 8),
            FilledButton.icon(
              onPressed: busy ? null : onArrived,
              icon: const Icon(Icons.place_rounded),
              label: const Text('Arrived'),
              style: FilledButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 12)),
            ),
          ],
        ] else ...[
          const SizedBox(height: 8),
          if (photos)
            FilledButton.icon(
              onPressed: busy ? null : () => onDeliver(true),
              icon: const Icon(Icons.photo_camera_rounded),
              label: const Text('Take photo & deliver'),
              style: FilledButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 12)),
            ),
          TextButton(
            onPressed: busy ? null : () => onDeliver(false),
            child: Text(photos ? 'Deliver without a photo' : 'Delivered'),
          ),
        ],
      ],
    );
  }
}

enum _LeftAnswer { delivered, photo, notDelivered, timedOut }

/// "Delivered to Otago Glass?" after driving away from a stop without a tap.
/// Counts down and answers "delivered" by itself, so a driver with their
/// hands on the wheel needn't touch the phone.
class _LeftStopDialog extends StatefulWidget {
  const _LeftStopDialog({required this.name, required this.items, required this.photos});

  final String name;
  final String items;
  final bool photos;

  @override
  State<_LeftStopDialog> createState() => _LeftStopDialogState();
}

class _LeftStopDialogState extends State<_LeftStopDialog> {
  int _left = DrivingLogic.autoConfirmSeconds;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (_left <= 1) {
        _close(_LeftAnswer.timedOut);
      } else {
        setState(() => _left--);
      }
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  void _close(_LeftAnswer answer) {
    _timer?.cancel();
    Navigator.of(context).pop(answer);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text('Delivered to ${widget.name}?'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (widget.items.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: Text(widget.items, style: const TextStyle(fontWeight: FontWeight.w700)),
            ),
          Text("You drove away without marking it. It will be marked delivered in $_left s."),
          const SizedBox(height: 16),
          FilledButton(
            onPressed: () => _close(_LeftAnswer.delivered),
            style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(48)),
            child: Text('Yes, delivered ($_left)'),
          ),
          if (widget.photos) ...[
            const SizedBox(height: 8),
            OutlinedButton.icon(
              onPressed: () => _close(_LeftAnswer.photo),
              style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(48)),
              icon: const Icon(Icons.photo_camera_rounded),
              label: const Text('Yes, and add a photo'),
            ),
          ],
          const SizedBox(height: 8),
          TextButton(
            onPressed: () => _close(_LeftAnswer.notDelivered),
            style: TextButton.styleFrom(
              minimumSize: const Size.fromHeight(48),
              foregroundColor: AppColors.danger,
            ),
            child: const Text('No, not delivered'),
          ),
        ],
      ),
    );
  }
}

/// A round outlined button on the drive bar.
class _RoundButton extends StatelessWidget {
  const _RoundButton({
    required this.icon,
    required this.tooltip,
    required this.color,
    required this.onPressed,
  });

  final IconData icon;
  final String tooltip;
  final Color color;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return SizedBox.square(
      dimension: 44,
      child: IconButton.outlined(
        onPressed: onPressed,
        tooltip: tooltip,
        style: IconButton.styleFrom(
          foregroundColor: color,
          side: const BorderSide(color: Color(0x22000000)),
        ),
        icon: Icon(icon),
      ),
    );
  }
}

class _DonePanel extends StatelessWidget {
  const _DonePanel({
    required this.stopCount,
    required this.delivered,
    required this.ended,
    required this.busy,
    required this.onEnd,
    required this.onClose,
  });

  final int stopCount;
  final int delivered;
  final bool ended;
  final bool busy;
  final VoidCallback onEnd;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          delivered == stopCount ? 'All $stopCount delivered' : '$delivered of $stopCount delivered',
          style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
        ),
        const SizedBox(height: 2),
        Text(
          ended ? 'This run is finished.' : 'Head back to the depot, then end the run.',
          style: const TextStyle(fontSize: 13, color: AppColors.inkMuted),
        ),
        const SizedBox(height: 12),
        FilledButton(
          onPressed: busy ? null : (ended ? onClose : onEnd),
          style: FilledButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 14)),
          child: Text(ended ? 'Close' : 'End run'),
        ),
      ],
    );
  }
}
