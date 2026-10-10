import 'dart:async';
import 'dart:typed_data';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:geolocator/geolocator.dart';
import 'package:image_picker/image_picker.dart';
import 'package:latlong2/latlong.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

import '../../models/delivery_estimate.dart';
import '../../models/road_legs.dart';
import '../../models/run_stop.dart';
import '../../settings/settings_store.dart';
import '../../state/auth_state.dart';
import '../../theme/app_colors.dart';
import '../../util/app_log.dart';
import '../../widgets/basemap.dart';
import '../../widgets/basemap_attribution.dart';
import '../../widgets/route_preview_map.dart';
import 'delivery_writer.dart';
import 'driving_logic.dart';
import 'photo_stamp.dart';
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
    this.vehicle,
  });

  final AuthState authState;
  final String runId;
  final String routeName;
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
  String? _announcedNext;
  String? _announcedApproach;

  // The latest run and stops, for the position callback.
  Map<String, dynamic> _run = const {};
  List<_Stop> _stops = const [];
  Object? _roadSource;
  RoadLegs _road = const RoadLegs();

  bool get _started => _run['driver_started_at'] != null || _run['started_at'] != null;
  bool get _finished => _run['completed_at'] != null || _run['driver_ended_at'] != null;

  _Stop? get _current {
    final index = DrivingLogic.currentIndex(
      [for (final s in _stops) s.id],
      {
        for (final s in _stops)
          if (s.delivered) s.id,
      },
    );
    return index == null ? null : _stops[index];
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
  }

  @override
  void dispose() {
    _positionSub?.cancel();
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
    if (_follow && _mapReady) {
      final zoom = _map.camera.zoom < 15.5 ? 16.5 : _map.camera.zoom;
      _map.move(LatLng(position.latitude, position.longitude), zoom);
    }
    _speakIfDue();
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
    final meters = _metersTo(stop);
    if (meters != null && !DrivingLogic.isNear(meters, accuracy: _position?.accuracy)) {
      final go = await showDialog<bool>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: const Text('Arrived?'),
          content: Text(
            'You look to be ${DrivingLogic.distanceLabel(meters)} from ${stop.stop.customerName}. '
            'Mark it arrived anyway?',
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(dialogContext, false), child: const Text('Not yet')),
            FilledButton(onPressed: () => Navigator.pop(dialogContext, true), child: const Text('Arrived')),
          ],
        ),
      );
      if (go != true || !mounted) return;
    }
    await _attempt('mark it arrived', () async {
      await _writer.arrived(stop.id);
      setState(() => _arrived.add(stop.id));
    });
  }

  Future<void> _deliver(_Stop stop, {required bool withPhoto}) async {
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
      await _writer.delivered(stop.id, position: _position, photo: photo);
      // The stream brings the next stop; say it when it does.
      _announcedNext = null;
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

  Future<void> _navigate(_Stop stop) async {
    final destination = stop.located
        ? '${stop.stop.location.latitude},${stop.stop.location.longitude}'
        : Uri.encodeComponent(stop.stop.address);
    final turnByTurn = Uri.parse('google.navigation:q=$destination&mode=d');
    final web = Uri.parse(
      'https://www.google.com/maps/dir/?api=1&destination=$destination&travelmode=driving',
    );
    if (!await launchUrl(turnByTurn, mode: LaunchMode.externalApplication)) {
      await launchUrl(web, mode: LaunchMode.externalApplication);
    }
  }

  Future<void> _toggleMute() async {
    final on = _voice.muted; // muted now -> turning voice on
    setState(() => _voice.muted = !on);
    if (!on) await _voice.stop();
    await SettingsStore(widget.authState).setVoicePrompts(on);
  }

  void _recentre() {
    setState(() => _follow = true);
    final here = _position;
    if (here != null && _mapReady) _map.move(LatLng(here.latitude, here.longitude), 16.5);
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.routeName, overflow: TextOverflow.ellipsis),
        actions: [
          IconButton(
            tooltip: _voice.muted ? 'Voice off - tap to turn on' : 'Voice on - tap to mute',
            icon: Icon(_voice.muted ? Icons.volume_off_rounded : Icons.volume_up_rounded),
            onPressed: _toggleMute,
          ),
          if (_started && !_finished)
            PopupMenuButton<String>(
              onSelected: (_) => _end(),
              itemBuilder: (_) => const [PopupMenuItem(value: 'end', child: Text('End run'))],
            ),
        ],
      ),
      body: StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
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
              if (mounted) _speakIfDue();
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
                Positioned(left: 0, right: 0, bottom: 0, child: _buildPanel()),
              ],
            );
          },
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

    // The road still to drive: from the last delivered stop (or the depot)
    // through every stop left, along the run's road shapes where it has them.
    final legs = <List<LatLng>>[];
    String? previousKey = DeliveryEstimate.depotKey;
    LatLng? previous = depot;
    for (final stop in _stops) {
      if (!stop.located) continue;
      if (stop.delivered) {
        previousKey = stop.stop.addressKey;
        previous = stop.stop.location;
        continue;
      }
      final shape = previousKey == null || stop.stop.addressKey == null
          ? null
          : _road.shapes[DeliveryEstimate.legKey(previousKey, stop.stop.addressKey!)];
      if (shape != null) {
        legs.add(shape);
      } else if (previous != null) {
        legs.add([previous, stop.stop.location]);
      }
      previousKey = stop.stop.addressKey;
      previous = stop.stop.location;
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
        // Dragging the map stops it following the van until "Follow me".
        onPositionChanged: (camera, hasGesture) {
          if (hasGesture && _follow) setState(() => _follow = false);
        },
      ),
      children: [
        const BasemapLayer(),
        PolylineLayer(
          polylines: [
            for (final (index, points) in legs.indexed)
              Polyline(
                points: points,
                strokeWidth: index == 0 ? 6 : 4,
                color: index == 0 ? AppColors.brand : AppColors.brand.withValues(alpha: 0.35),
              ),
          ],
        ),
        MarkerLayer(
          markers: [
            for (final (index, stop) in _stops.indexed)
              if (stop.located)
                Marker(
                  point: stop.stop.location,
                  width: stop.id == current?.id ? 44 : 28,
                  height: stop.id == current?.id ? 52 : 28,
                  alignment: stop.id == current?.id ? Alignment.topCenter : Alignment.center,
                  child: StopPin(
                    number: index + 1,
                    compact: stop.id != current?.id,
                    selected: stop.id == current?.id,
                    delivered: stop.delivered,
                  ),
                ),
            if (here != null)
              Marker(
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
      content = _StopPanel(
        stop: current,
        number: _stops.indexOf(current) + 1,
        total: _stops.length,
        meters: meters,
        direction: here == null || !current.located
            ? null
            : DrivingLogic.direction(LatLng(here.latitude, here.longitude), current.stop.location),
        near: meters != null && DrivingLogic.isNear(meters, accuracy: here?.accuracy),
        arrived: _arrived.contains(current.id) || current.data['arrived_at'] != null,
        busy: _busy,
        photos: DeliveryWriter.photosAvailable,
        onNavigate: () => _navigate(current),
        onArrived: () => _arrive(current),
        onDeliver: (withPhoto) => _deliver(current, withPhoto: withPhoto),
      );
    }
    return SafeArea(
      top: false,
      child: Container(
        margin: const EdgeInsets.all(12),
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(20),
          boxShadow: const [BoxShadow(color: Color(0x33000000), blurRadius: 16, offset: Offset(0, 4))],
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
            content,
          ],
        ),
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

class _StopPanel extends StatelessWidget {
  const _StopPanel({
    required this.stop,
    required this.number,
    required this.total,
    required this.meters,
    required this.direction,
    required this.near,
    required this.arrived,
    required this.busy,
    required this.photos,
    required this.onNavigate,
    required this.onArrived,
    required this.onDeliver,
  });

  final _Stop stop;
  final int number;
  final int total;
  final double? meters;
  final String? direction;
  final bool near;
  final bool arrived;
  final bool busy;
  final bool photos;
  final VoidCallback onNavigate;
  final VoidCallback onArrived;
  final void Function(bool withPhoto) onDeliver;

  @override
  Widget build(BuildContext context) {
    final details = stop.stop;
    final note = details.instructions?.trim();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Text(
              'Stop $number of $total',
              style: const TextStyle(fontSize: 12, color: AppColors.inkMuted, fontWeight: FontWeight.w700),
            ),
            const Spacer(),
            if (meters != null)
              Text(
                arrived ? 'Here' : '${DrivingLogic.distanceLabel(meters!)} ${direction ?? ''}'.trim(),
                style: const TextStyle(fontSize: 12, color: AppColors.brand, fontWeight: FontWeight.w700),
              ),
          ],
        ),
        const SizedBox(height: 4),
        Text(details.customerName, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
        Text(details.address, style: const TextStyle(fontSize: 13, color: AppColors.inkMuted)),
        if (details.items.isNotEmpty) ...[
          const SizedBox(height: 8),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              for (final item in details.items)
                Chip(
                  label: Text(item.label, style: const TextStyle(fontSize: 12)),
                  visualDensity: VisualDensity.compact,
                  materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
            ],
          ),
        ],
        if (note != null && note.isNotEmpty) ...[
          const SizedBox(height: 8),
          Text(note, style: const TextStyle(fontSize: 13, fontStyle: FontStyle.italic)),
        ],
        const SizedBox(height: 12),
        if (!arrived)
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: onNavigate,
                  icon: const Icon(Icons.navigation_rounded),
                  label: const Text('Navigate'),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                // Offered by itself once close; still there (and asks) when
                // the GPS disagrees.
                child: near
                    ? FilledButton.icon(
                        onPressed: busy ? null : onArrived,
                        icon: const Icon(Icons.place_rounded),
                        label: const Text('Arrived'),
                      )
                    : OutlinedButton(onPressed: busy ? null : onArrived, child: const Text('Arrived?')),
              ),
            ],
          )
        else ...[
          if (photos)
            FilledButton.icon(
              onPressed: busy ? null : () => onDeliver(true),
              icon: const Icon(Icons.photo_camera_rounded),
              label: const Text('Take photo & deliver'),
              style: FilledButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 14)),
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
