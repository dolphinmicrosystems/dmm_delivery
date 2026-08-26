import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:crypto/crypto.dart';
import 'package:latlong2/latlong.dart';

/// Resolves the depot's coordinates without hardcoding them in the client.
///
/// The backend already geocodes the depot on every upload
/// (process_run_sheet_upload.py calls `geocoder.geocode(depot_address)`),
/// and CachedGoogleGeocoder writes the result into `addresses/{key}` where
/// key is a sha256 of the normalized address. firestore.rules lets any
/// signed-in user read that collection, so the client can look up the exact
/// coordinates the router itself used - rather than shipping a second,
/// drifting copy of the depot's lat/lng in Dart, or spending a Geocoding
/// API call (and an API key) to ask the same question twice.
class DepotLocator {
  DepotLocator({FirebaseFirestore? firestore}) : _db = firestore ?? FirebaseFirestore.instance;

  final FirebaseFirestore _db;

  /// Mirrors firestore_paths.address_key exactly. If that normalization ever
  /// changes on the backend, this must change with it - the two are a
  /// contract, which is why the rule is spelled out rather than inlined.
  static String addressKey(String address) =>
      sha256.convert(utf8.encode(address.trim().toLowerCase())).toString();

  /// Document id for `stop_instructions`, scoped to one business.
  ///
  /// Mirrors `firestore_paths.stop_instructions_id` the way [addressKey]
  /// mirrors `address_key`. The address hash alone is not enough once there
  /// is more than one owner: two businesses delivering to the same street
  /// would share a document, and one owner's "leave at the side gate" would
  /// surface on the other's run.
  ///
  /// `addressKey` is untouched as the second half - the hash contract is the
  /// same, only the id built from it grew a prefix.
  static String stopInstructionsId(String ownerUid, String addressKey) =>
      '${ownerUid}__$addressKey';

  /// Null when the depot address has never been geocoded (no upload has run
  /// since it was configured). Callers render the route without a depot
  /// rather than guessing at one.
  Future<LatLng?> resolve(String? depotAddress) async {
    if (depotAddress == null || depotAddress.trim().isEmpty) return null;

    final doc = await _db.collection('addresses').doc(addressKey(depotAddress)).get();
    final data = doc.data();
    if (data == null) return null;

    final lat = (data['lat'] as num?)?.toDouble();
    final lng = (data['lng'] as num?)?.toDouble();
    if (lat == null || lng == null) return null;

    return LatLng(lat, lng);
  }
}
