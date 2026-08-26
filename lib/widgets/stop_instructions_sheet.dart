import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import '../services/depot_locator.dart';
import '../state/auth_state.dart';
import '../theme/app_colors.dart';
import 'pill_badge.dart';
import 'primary_button.dart';

/// Shows a stop's resolved instructions with provenance (owner override vs
/// run-sheet text), and lets the owner set/replace the override - which,
/// per FR2's precedence rule, wins over whatever the file says from then
/// on. Writes directly to stop_instructions/{addressKey}.owner_instructions
/// (firestore.rules allows this specific field directly from the client -
/// no Cloud Function needed for a plain text edit).
class StopInstructionsSheet extends StatefulWidget {
  const StopInstructionsSheet({super.key, required this.authState, required this.stopDoc});

  final AuthState authState;
  final QueryDocumentSnapshot<Map<String, dynamic>> stopDoc;

  @override
  State<StopInstructionsSheet> createState() => _StopInstructionsSheetState();
}

class _StopInstructionsSheetState extends State<StopInstructionsSheet> {
  late final TextEditingController _controller;
  bool _saving = false;

  Map<String, dynamic> get _stop => widget.stopDoc.data();
  String? get _addressKey => _stop['address_key'] as String?;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: _stop['instructions'] as String? ?? '');
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final addressKey = _addressKey;
    if (addressKey == null) return;
    setState(() => _saving = true);
    final ownerUid = widget.authState.ownerUid;
    if (ownerUid == null) return;
    await FirebaseFirestore.instance
        .collection('stop_instructions')
        // Scoped, not the bare address hash - see DepotLocator.stopInstructionsId.
        .doc(DepotLocator.stopInstructionsId(ownerUid, addressKey))
        .set({
          'owner_uid': ownerUid,
          'owner_instructions': _controller.text.trim().isEmpty ? null : _controller.text.trim(),
          'owner_instructions_updated_at': FieldValue.serverTimestamp(),
          'owner_instructions_updated_by': widget.authState.user!.uid,
        }, SetOptions(merge: true));
    if (mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final source = _stop['instructions_source'] as String? ?? 'none';
    return Padding(
      padding: EdgeInsets.only(
        left: 20,
        right: 20,
        top: 20,
        bottom: MediaQuery.of(context).viewInsets.bottom + 20,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            _stop['customer_name'] as String? ?? '',
            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 2),
          Text(
            _stop['address'] as String? ?? '',
            style: const TextStyle(fontSize: 13, color: AppColors.inkMuted),
          ),
          const SizedBox(height: 12),
          PillBadge(
            label: switch (source) {
              'owner' => 'YOUR NOTE',
              'file' => 'FROM RUN SHEET',
              _ => 'NO INSTRUCTIONS YET',
            },
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _controller,
            minLines: 2,
            maxLines: 4,
            decoration: const InputDecoration(
              labelText: 'Delivery instructions',
              hintText: 'e.g. Leave at gate, ring bell',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 16),
          PrimaryButton(label: _saving ? 'Saving…' : 'Save', onPressed: _saving ? null : _save),
        ],
      ),
    );
  }
}
