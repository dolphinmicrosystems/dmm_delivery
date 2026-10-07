import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import '../models/route_assignment.dart';
import '../models/run_listing.dart';
import '../models/vehicle.dart';
import '../state/auth_state.dart';
import '../util/app_log.dart';

/// What the driver's tabs show, read live:
///
///  * their runs - `delivery_run` given to them (`rider_id`), confirmed ones
///    only. The rules let a driver read exactly these.
///  * the business's route names - `circuits`.
///  * the business's schedule - `route_assignments`. Whole, not just their
///    rows: a colleague's one-day cover is what takes a day off them.
///  * the vehicle the owner assigned them (`vehicles`, one per driver), shown
///    on every run as the one to drive.
///
/// The backend keeps `rider_id` in step with the schedule for runs still ahead
/// (assign_route_runs.py), so a route assigned after its sheet was confirmed
/// still reaches the driver.
class DriverData {
  const DriverData({required this.runs, required this.routeNames, required this.assignments, this.vehicle});

  final List<RunListing> runs;
  final Map<String, String> routeNames;
  final List<RouteAssignment> assignments;

  /// Null when the owner hasn't assigned them one.
  final Vehicle? vehicle;
}

/// Streams [DriverData] for the signed-in driver and hands it to [builder].
class DriverDataBuilder extends StatelessWidget {
  const DriverDataBuilder({super.key, required this.authState, required this.builder});

  final AuthState authState;
  final Widget Function(BuildContext context, DriverData data) builder;

  @override
  Widget build(BuildContext context) {
    final uid = authState.user?.uid, ownerUid = authState.ownerUid;
    if (uid == null || ownerUid == null) return const SizedBox.shrink();
    final db = FirebaseFirestore.instance;
    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: db
          .collection('delivery_run')
          .where('owner_uid', isEqualTo: ownerUid)
          .where('rider_id', isEqualTo: uid)
          .where('status', isEqualTo: 'sequenced')
          .snapshots(),
      builder: (context, runsSnap) => StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
        stream: db.collection('circuits').where('owner_uid', isEqualTo: ownerUid).snapshots(),
        builder: (context, circuitsSnap) => StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
          stream: db.collection('route_assignments').where('owner_uid', isEqualTo: ownerUid).snapshots(),
          builder: (context, assignmentsSnap) => StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
            stream: db
                .collection('vehicles')
                .where('owner_uid', isEqualTo: ownerUid)
                .where('assigned_driver_uid', isEqualTo: uid)
                .limit(1)
                .snapshots(),
            builder: (context, vehicleSnap) {
              for (final (name, snap) in [
                ('runs', runsSnap),
                ('routes', circuitsSnap),
                ('assignments', assignmentsSnap),
              ]) {
                if (snap.hasError) {
                  AppLog.auth.error('driver $name stream failed', snap.error, snap.stackTrace);
                }
              }
              if (!runsSnap.hasData || !circuitsSnap.hasData || !assignmentsSnap.hasData) {
                if (runsSnap.hasError || circuitsSnap.hasError || assignmentsSnap.hasError) {
                  return const _LoadFailed();
                }
                return const Center(child: CircularProgressIndicator());
              }
              final routeNames = {
                for (final doc in circuitsSnap.data!.docs) doc.id: doc.data()['round'] as String? ?? 'Route',
              };
              return builder(
                context,
                DriverData(
                  runs: [
                    for (final doc in runsSnap.data!.docs)
                      RunListing.fromDoc(doc, routeName: routeNames[doc.data()['round_key']]),
                  ],
                  routeNames: routeNames,
                  assignments: [for (final doc in assignmentsSnap.data!.docs) RouteAssignment.fromDoc(doc)],
                  // Optional: a vehicle that fails to load must not hide runs.
                  vehicle: vehicleSnap.data?.docs.isNotEmpty == true
                      ? Vehicle.fromDoc(vehicleSnap.data!.docs.first)
                      : null,
                ),
              );
            },
          ),
        ),
      ),
    );
  }
}

class _LoadFailed extends StatelessWidget {
  const _LoadFailed();

  @override
  Widget build(BuildContext context) {
    return const Center(
      child: Padding(
        padding: EdgeInsets.all(24),
        child: Text(
          "Couldn't load your runs. Check your connection, then sign out and back in if it keeps happening.",
          textAlign: TextAlign.center,
        ),
      ),
    );
  }
}
