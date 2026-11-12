import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:image/image.dart' as img;

import '../models/business_profile.dart';
import '../util/app_log.dart';

/// Reads and writes `business_profile/{ownerUid}` (BusinessProfile), in the
/// exact fields firestore.rules accepts.
class BusinessProfileStore {
  const BusinessProfileStore(this.ownerUid);

  final String ownerUid;

  /// Longest side of a saved logo. Shown at app-bar size; twice that is sharp
  /// on any phone and keeps the document small.
  static const logoSide = 256;

  DocumentReference<Map<String, dynamic>> get _doc =>
      FirebaseFirestore.instance.collection('business_profile').doc(ownerUid);

  Stream<BusinessProfile> watch() => _doc.snapshots().map((snap) => BusinessProfile.fromMap(snap.data()));

  Future<void> _save(Map<String, Object?> fields) => _doc.set({
    ...fields,
    'owner_uid': ownerUid,
    'updated_at': FieldValue.serverTimestamp(),
  }, SetOptions(merge: true));

  Future<void> setName(String name) {
    final trimmed = name.trim();
    AppLog.owner('business name', {'length': trimmed.length});
    return _save({'business_name': trimmed.isEmpty ? null : trimmed});
  }

  Future<void> setPlace(String country, String timezone) {
    AppLog.owner('business place', {'country': country, 'timezone': timezone});
    return _save({'country': country, 'timezone': timezone});
  }

  Future<void> setRequirePhoto(bool on) {
    AppLog.owner('require photo', {'on': on});
    return _save({'require_photo': on});
  }

  /// Shrinks a picked image and saves it as the logo. Throws [LogoException]
  /// with a sentence fit to show when the file can't be used.
  Future<void> setLogo(Uint8List picked) async {
    final shrunk = await compute(shrinkLogo, picked);
    if (shrunk == null) throw LogoException("That file isn't an image Blue Dot can read.");
    AppLog.owner('business logo', {'bytes': shrunk.length});
    await _save({'logo': Blob(shrunk)});
  }

  Future<void> removeLogo() => _save({'logo': null});
}

class LogoException implements Exception {
  LogoException(this.message);
  final String message;
  @override
  String toString() => message;
}

/// The picked image at most [BusinessProfileStore.logoSide] on its longest
/// side: a PNG (keeps transparency), or a JPEG if the PNG would be over the
/// size the rules allow. Null when it isn't an image at all. Top-level so it
/// can run off the UI thread.
Uint8List? shrinkLogo(Uint8List bytes) {
  img.Image? decoded;
  try {
    decoded = img.decodeImage(bytes);
  } catch (_) {
    // The decoders throw on some junk (a short file read as a PSD header).
    return null;
  }
  if (decoded == null) return null;
  const side = BusinessProfileStore.logoSide;
  final resized = decoded.width >= decoded.height
      ? (decoded.width > side ? img.copyResize(decoded, width: side) : decoded)
      : (decoded.height > side ? img.copyResize(decoded, height: side) : decoded);
  final png = img.encodePng(resized);
  if (png.length <= BusinessProfile.maxLogoBytes) return png;
  return img.encodeJpg(resized, quality: 85);
}
