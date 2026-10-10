import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import '../../models/driver_invitation.dart';
import '../../models/route_assignment.dart';
import '../../models/run_listing.dart';
import '../../models/vehicle.dart';
import '../../state/auth_state.dart';
import '../../util/app_log.dart';

/// Everything the owner's run lists need - the Runs tab and Home's Live now
/// - gathered once.
class OwnerRunData {
  const OwnerRunData({
    required this.runs,
    required this.routeNames,
    required this.assignmentsByRoute,
    required this.driverNames,
    this.vehiclesByDriver = const {},
  });

  final List<RunListing> runs;
  final Map<String, String> routeNames;
  final Map<String, List<RouteAssignment>> assignmentsByRoute;
  final Map<String, String> driverNames;

  /// The vehicle each driver is assigned (one per driver, VehicleService).
  final Map<String, Vehicle> vehiclesByDriver;

  /// Who drives [run], in what, and from what time. The driver stamped on the
  /// run at confirm wins; otherwise it is whoever the route's schedule names
  /// for that day - which is also where the times always come from.
  ({String? driver, String? driverUid, Vehicle? vehicle, String? startTime, String? endTime}) crewFor(
    RunListing run,
  ) {
    final day = run.date ?? DateTime.now();
    final scheduled = RouteAssignment.activeAt(
      assignmentsByRoute[run.roundKey] ?? const [],
      DateTime(day.year, day.month, day.day, 12),
    );
    final uid = run.riderId ?? scheduled?.driverUid;
    return (
      driver: uid == null ? null : (driverNames[uid] ?? scheduled?.driverName),
      driverUid: uid,
      vehicle: uid == null ? null : vehiclesByDriver[uid],
      startTime: scheduled?.startTime,
      endTime: scheduled?.endTime,
    );
  }
}

/// Streams [OwnerRunData] for the signed-in owner's business.
class OwnerRunDataBuilder extends StatelessWidget {
  const OwnerRunDataBuilder({
    super.key,
    required this.authState,
    required this.ownerUid,
    required this.builder,
    this.loading = const Center(child: CircularProgressIndicator()),
  });

  final AuthState authState;
  final String ownerUid;
  final Widget Function(BuildContext context, OwnerRunData data) builder;
  final Widget loading;

  @override
  Widget build(BuildContext context) {
    final db = FirebaseFirestore.instance;
    // Only confirmed runs: drafts under review and runs a same-day re-upload
    // replaced ('superseded') are not deliveries anyone will make.
    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: db
          .collection('delivery_run')
          .where('owner_uid', isEqualTo: ownerUid)
          .where('status', isEqualTo: 'sequenced')
          .snapshots(),
      builder: (context, runsSnap) {
        if (runsSnap.hasError) {
          AppLog.owner.error('runs stream failed', runsSnap.error, runsSnap.stackTrace);
        }
        return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
          stream: db.collection('circuits').where('owner_uid', isEqualTo: ownerUid).snapshots(),
          builder: (context, circuitsSnap) => StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
            stream: authState.routeAssignments(),
            builder: (context, assignmentsSnap) => StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
              stream: authState.invitations(),
              builder: (context, invitationsSnap) => StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                stream: db.collection('vehicles').where('owner_uid', isEqualTo: ownerUid).snapshots(),
                builder: (context, vehiclesSnap) {
                  if (!runsSnap.hasData || !circuitsSnap.hasData) return loading;
                  final routeNames = {
                    for (final doc in circuitsSnap.data!.docs)
                      doc.id: doc.data()['round'] as String? ?? 'Route',
                  };
                  final now = DateTime.now();
                  return builder(
                    context,
                    OwnerRunData(
                      // Runs of deleted routes are left out: the route is gone,
                      // and so is anyone who would drive it.
                      runs: [
                        for (final doc in runsSnap.data!.docs)
                          if (routeNames.containsKey(doc.data()['round_key']))
                            RunListing.fromDoc(doc, routeName: routeNames[doc.data()['round_key']]),
                      ],
                      routeNames: routeNames,
                      assignmentsByRoute: RouteAssignment.byRoute([
                        for (final doc in assignmentsSnap.data?.docs ?? const [])
                          RouteAssignment.fromDoc(doc),
                      ]),
                      driverNames: {
                        for (final doc in invitationsSnap.data?.docs ?? const [])
                          if (DriverInvitation.fromDoc(doc, now: now) case final d when d.acceptedUid != null)
                            d.acceptedUid!: d.displayName,
                      },
                      // Optional: a fleet that fails to load must not hide runs.
                      vehiclesByDriver: {
                        for (final doc in vehiclesSnap.data?.docs ?? const [])
                          if (Vehicle.fromDoc(doc) case final v when v.assignedDriverUid != null)
                            v.assignedDriverUid!: v,
                      },
                    ),
                  );
                },
              ),
            ),
          ),
        );
      },
    );
  }
}

/// The driving screens' heartbeats (`run_live`, RunHeartbeat) for [runIds],
/// as run id -> last seen. Handed to [builder] empty until they load, and
/// for runs nobody has driven yet.
class RunLiveBuilder extends StatefulWidget {
  const RunLiveBuilder({super.key, required this.ownerUid, required this.runIds, required this.builder});

  final String ownerUid;
  final List<String> runIds;
  final Widget Function(BuildContext context, Map<String, DateTime> lastSeen) builder;

  @override
  State<RunLiveBuilder> createState() => _RunLiveBuilderState();
}

class _RunLiveBuilderState extends State<RunLiveBuilder> {
  Stream<QuerySnapshot<Map<String, dynamic>>>? _stream;
  String _key = '';

  @override
  Widget build(BuildContext context) {
    // Re-subscribed only when the set of runs changes, not on every rebuild.
    final ids = ([...widget.runIds]..sort()).take(30).toList(); // whereIn's limit
    final key = ids.join(',');
    if (key != _key) {
      _key = key;
      _stream = ids.isEmpty
          ? null
          : FirebaseFirestore.instance
                .collection('run_live')
                .where('owner_uid', isEqualTo: widget.ownerUid)
                .where(FieldPath.documentId, whereIn: ids)
                .snapshots();
    }
    if (_stream == null) return widget.builder(context, const {});
    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: _stream,
      builder: (context, snap) {
        if (snap.hasError) AppLog.owner.error('run_live stream failed', snap.error, snap.stackTrace);
        return widget.builder(context, {
          for (final doc in snap.data?.docs ?? const <QueryDocumentSnapshot<Map<String, dynamic>>>[])
            if (doc.data()['last_seen_at'] case final Timestamp t) doc.id: t.toDate(),
        });
      },
    );
  }
}
