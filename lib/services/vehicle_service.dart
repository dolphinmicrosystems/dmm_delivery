import 'package:cloud_firestore/cloud_firestore.dart';

import '../models/vehicle.dart';

/// Every `vehicles` write the app makes. The rules accept exact shapes
/// (`isValidVehicle`), so they are built in one place, like RouteAssigner.
///
/// One vehicle per driver and one driver per vehicle: giving a driver a
/// vehicle takes back whichever vehicle they had, and takes this one off
/// whoever had it - in one batch, so the fleet is never briefly showing a
/// driver in two trucks.
class VehicleService {
  VehicleService._();

  static CollectionReference<Map<String, dynamic>> get _vehicles =>
      FirebaseFirestore.instance.collection('vehicles');

  static Stream<List<Vehicle>> fleet(String ownerUid) => _vehicles
      .where('owner_uid', isEqualTo: ownerUid)
      .snapshots()
      .map((snap) => [for (final doc in snap.docs) Vehicle.fromDoc(doc)]..sort((a, b) => a.name.compareTo(b.name)));

  /// Adds a vehicle to the fleet, optionally straight onto [driverUid].
  static Future<void> add({
    required String ownerUid,
    required String name,
    required VehicleKind kind,
    String? registration,
    String? driverUid,
    List<Vehicle> fleet = const [],
  }) async {
    final batch = FirebaseFirestore.instance.batch();
    if (driverUid != null) _takeBackFrom(batch, driverUid, fleet, except: null);
    batch.set(_vehicles.doc(), {
      'owner_uid': ownerUid,
      'name': name.trim(),
      'registration': registration,
      'kind': kind.name,
      'assigned_driver_uid': driverUid,
      if (driverUid != null) 'assigned_at': FieldValue.serverTimestamp(),
      'updated_at': FieldValue.serverTimestamp(),
    });
    await batch.commit();
  }

  /// Gives [vehicle] to [driverUid].
  static Future<void> assign(Vehicle vehicle, String driverUid, List<Vehicle> fleet) async {
    final batch = FirebaseFirestore.instance.batch();
    _takeBackFrom(batch, driverUid, fleet, except: vehicle.id);
    batch.update(_vehicles.doc(vehicle.id), {
      'assigned_driver_uid': driverUid,
      'assigned_at': FieldValue.serverTimestamp(),
      'updated_at': FieldValue.serverTimestamp(),
    });
    await batch.commit();
  }

  /// Takes [vehicle] off whoever is driving it. The vehicle stays in the fleet.
  static Future<void> unassign(Vehicle vehicle) => _vehicles.doc(vehicle.id).update({
    'assigned_driver_uid': null,
    'updated_at': FieldValue.serverTimestamp(),
  });

  static void _takeBackFrom(WriteBatch batch, String driverUid, List<Vehicle> fleet, {required String? except}) {
    for (final other in fleet) {
      if (other.assignedDriverUid == driverUid && other.id != except) {
        batch.update(_vehicles.doc(other.id), {
          'assigned_driver_uid': null,
          'updated_at': FieldValue.serverTimestamp(),
        });
      }
    }
  }

  /// A message fit to show for a failed write.
  static String errorMessage(FirebaseException error) => error.code == 'permission-denied'
      ? 'That vehicle could not be saved. Check the name is under ${Vehicle.maxNameLength} characters '
            'and the plate under ${Vehicle.maxRegistrationLength}.'
      : 'Could not save the vehicle (${error.code}). Check your connection and try again.';
}
