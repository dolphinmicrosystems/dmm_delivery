import 'package:cloud_firestore/cloud_firestore.dart';

/// What kind of vehicle - the wire values are what `firestore.rules`
/// accepts (`vehicles.kind in ['truck', 'van', 'ute', 'car']`).
enum VehicleKind {
  truck('Truck'),
  van('Van'),
  ute('Ute'),
  car('Car');

  const VehicleKind(this.label);

  final String label;

  /// Anything unrecognised reads as a van - the commonest delivery vehicle -
  /// rather than failing to show the vehicle at all.
  static VehicleKind parse(String? wire) =>
      VehicleKind.values.firstWhere((kind) => kind.name == wire, orElse: () => VehicleKind.van);
}

/// One vehicle in the owner's fleet: `vehicles/{id}`.
class Vehicle {
  const Vehicle({
    required this.id,
    required this.name,
    required this.kind,
    this.registration,
    this.assignedDriverUid,
  });

  /// Mirror `firestore.rules` (`name.size() <= 40`, `registration.size() <= 10`):
  /// over-length values come back as a bare permission-denied.
  static const maxNameLength = 40;
  static const maxRegistrationLength = 10;

  final String id;
  final String name;
  final VehicleKind kind;

  /// The number plate, e.g. "ABC123". Optional - a yard vehicle may not have one.
  final String? registration;

  /// Who drives it now. At most one driver per vehicle, and the app keeps it
  /// to one vehicle per driver (VehicleService.assign).
  final String? assignedDriverUid;

  /// "Isuzu truck · ABC123"
  String get description => [name, if (registration != null && registration!.isNotEmpty) registration].join(' · ');

  factory Vehicle.fromDoc(DocumentSnapshot<Map<String, dynamic>> doc) {
    final data = doc.data() ?? const {};
    return Vehicle(
      id: doc.id,
      name: data['name'] as String? ?? 'Vehicle',
      kind: VehicleKind.parse(data['kind'] as String?),
      registration: data['registration'] as String?,
      assignedDriverUid: data['assigned_driver_uid'] as String?,
    );
  }

  /// Tidies a typed number plate: upper case, no spaces - "abc 123" and
  /// "ABC123" are the same plate.
  static String? normaliseRegistration(String raw) {
    final plate = raw.replaceAll(RegExp(r'\s+'), '').toUpperCase();
    return plate.isEmpty ? null : plate;
  }
}
