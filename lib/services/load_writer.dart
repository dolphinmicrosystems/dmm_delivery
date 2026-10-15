import 'package:cloud_firestore/cloud_firestore.dart';

import '../models/load_sheet.dart';
import '../util/app_log.dart';

/// Every write to a run's load sheet, in the shapes firestore.rules accepts:
///  * a change - `delivery_run/{runId}/load_changes/{auto}`, created once,
///    never edited (the owner's 'adjust', the driver's 'short');
///  * the driver's ticks - `delivery_run/{runId}/load_state/checklist`,
///    product code -> the quantity ticked.
/// notify-load-change tells the other side about each change.
class LoadWriter {
  const LoadWriter(this.runId);

  final String runId;

  DocumentReference<Map<String, dynamic>> get _run =>
      FirebaseFirestore.instance.collection('delivery_run').doc(runId);

  Future<void> addChange({
    required LoadChangeKind kind,
    required String code,
    required String product,
    required int delta,
    required String byUid,
    String? byName,
    String? note,
  }) async {
    AppLog.owner('load change', {'runId': runId, 'kind': kind.name, 'delta': delta});
    final trimmedNote = note?.trim() ?? '';
    final trimmedName = byName?.trim() ?? '';
    await _run.collection('load_changes').add({
      'kind': kind.name,
      'code': code,
      'product': product.trim(),
      'delta': delta,
      if (trimmedNote.isNotEmpty) 'note': trimmedNote,
      if (trimmedName.isNotEmpty)
        'by_name': trimmedName.length > 60 ? trimmedName.substring(0, 60) : trimmedName,
      'by_uid': byUid,
      'created_at': FieldValue.serverTimestamp(),
    });
  }

  /// Ticks [code] at [quantity], or unticks it with null.
  Future<void> setChecked(String code, int? quantity) async {
    await _run.collection('load_state').doc('checklist').set({
      'checked': {code: quantity ?? FieldValue.delete()},
      'updated_at': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  static const maxNote = 200;
  static const maxProduct = 60;
  static const maxQuantity = 500;
}
