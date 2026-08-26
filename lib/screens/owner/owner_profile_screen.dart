import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../models/owner_profile.dart';
import '../../state/auth_state.dart';
import '../../theme/app_colors.dart';
import '../../util/app_log.dart';
import '../../widgets/primary_button.dart';
import '../../widgets/section_label.dart';
import '../../widgets/surface_card.dart';

/// The signed-in owner's own details, editable.
///
/// Placeholder data: nothing in the delivery pipeline reads any of it. It is
/// here so the account is more than the name and avatar Google hands over,
/// and so the screen exists against a real Firestore document rather than a
/// mock that has to be rebuilt later.
///
/// Takes its starting values as an argument rather than reading them itself.
/// Settings already streams the profile for its account card, so a second
/// read would only add a loading state - and a *live* stream would fight the
/// owner's typing, rewriting fields under the cursor on every snapshot.
class OwnerProfileScreen extends StatefulWidget {
  const OwnerProfileScreen({super.key, required this.authState, required this.initial});

  final AuthState authState;
  final OwnerProfile initial;

  @override
  State<OwnerProfileScreen> createState() => _OwnerProfileScreenState();
}

enum _LeaveChoice { stay, discard, save }

class _OwnerProfileScreenState extends State<OwnerProfileScreen> {
  late final TextEditingController _nameController;
  late final TextEditingController _ageController;
  late final TextEditingController _phoneController;
  late ProfileGender? _gender;

  String? _error;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    // Prefilled from Google's display name when the owner has never chosen
    // one, so the field reads as "this is what you're called" rather than as
    // a blank waiting to be filled in.
    _nameController = TextEditingController(
      text: widget.initial.displayName ?? widget.authState.user?.displayName ?? '',
    );
    _ageController = TextEditingController(text: widget.initial.age?.toString() ?? '');
    _phoneController = TextEditingController(text: widget.initial.phone ?? '');
    _gender = widget.initial.gender;
  }

  @override
  void dispose() {
    _nameController.dispose();
    _ageController.dispose();
    _phoneController.dispose();
    super.dispose();
  }

  /// What saving would write. Rebuilt on demand rather than held in state, so
  /// there is exactly one definition of "what is currently in this form".
  OwnerProfile get _current => OwnerProfile.fromForm(
    name: _nameController.text,
    age: _ageController.text,
    phone: _phoneController.text,
    gender: _gender,
  );

  /// Compared field by field, never as raw controller text: respacing a name
  /// or typing a value back exactly is not a change worth stopping someone
  /// over, and a dialog that fires when nothing changed is what teaches
  /// people to dismiss it unread.
  bool get _dirty => !_saving && _current.differsFrom(widget.initial);

  Future<bool> _save() async {
    final error = OwnerProfile.formError(
      name: _nameController.text,
      age: _ageController.text,
      phone: _phoneController.text,
    );
    if (error != null) {
      setState(() => _error = error);
      return false;
    }

    setState(() {
      _error = null;
      _saving = true;
    });

    try {
      await widget.authState.saveProfile(_current);
      return true;
    } on FirebaseException catch (e, s) {
      AppLog.owner.error('profile save failed', e, s, {'code': e.code});
      if (mounted) {
        setState(() {
          _error = e.code == 'permission-denied'
              // The rules are the only thing that rejects a well-formed
              // profile, and "permission denied" reads as a sign-in problem.
              ? 'Saving your profile needs the backend rules update deployed first.'
              : 'Couldn\'t save your profile: ${e.message ?? e.code}';
          _saving = false;
        });
      }
      return false;
    }
  }

  Future<void> _saveAndLeave() async {
    if (await _save() && mounted) Navigator.of(context).pop();
  }

  /// Back was pressed with unsaved edits. Re-issues the pop itself, because
  /// `PopScope` has already blocked the original one.
  Future<void> _confirmLeave() async {
    final choice = await showDialog<_LeaveChoice>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Save your profile?'),
        content: const Text('Your changes haven’t been saved yet.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, _LeaveChoice.stay),
            child: const Text('Keep editing'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, _LeaveChoice.discard),
            child: const Text('Discard'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, _LeaveChoice.save),
            child: const Text('Save'),
          ),
        ],
      ),
    );

    if (!mounted || choice == null || choice == _LeaveChoice.stay) {
      AppLog.owner('leave profile canceled');
      return;
    }

    if (choice == _LeaveChoice.save && !await _save()) return;
    if (!mounted) return;

    AppLog.owner('leaving profile', {'choice': choice.name});
    // Navigator.pop, not maybePop: PopScope gates the latter, and re-asking
    // the question we have just answered would trap the owner on the screen.
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    // Merged rather than one controller: `canPop` is only as fresh as the
    // last build, and typing in any of the three fields has to refresh it.
    // The dropdown already calls setState.
    return ListenableBuilder(
      listenable: Listenable.merge([_nameController, _ageController, _phoneController]),
      builder: (context, child) => PopScope(
        canPop: !_dirty,
        onPopInvokedWithResult: (didPop, _) {
          if (!didPop) _confirmLeave();
        },
        child: child!,
      ),
      child: Scaffold(
        backgroundColor: AppColors.surfaceMuted,
        appBar: AppBar(title: const Text('Your profile')),
        body: SafeArea(
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              const SectionLabel('About you'),
              const SizedBox(height: 8),
              SurfaceCard(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                child: Column(
                  children: [
                    TextField(
                      controller: _nameController,
                      textCapitalization: TextCapitalization.words,
                      maxLength: OwnerProfile.maxNameLength,
                      decoration: const InputDecoration(
                        labelText: 'Name',
                        helperText: 'Overrides the name on your Google account',
                      ),
                    ),
                    TextField(
                      controller: _ageController,
                      keyboardType: TextInputType.number,
                      // Digits only at the keyboard, so the validator below is
                      // a backstop for pasted text rather than the first line
                      // of defence.
                      inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                      maxLength: 3,
                      decoration: const InputDecoration(labelText: 'Age'),
                    ),
                    const SizedBox(height: 8),
                    DropdownButtonFormField<ProfileGender>(
                      initialValue: _gender,
                      decoration: const InputDecoration(labelText: 'Gender'),
                      items: [
                        for (final option in ProfileGender.values)
                          DropdownMenuItem(value: option, child: Text(option.label)),
                      ],
                      onChanged: (value) => setState(() => _gender = value),
                    ),
                    const SizedBox(height: 8),
                    TextField(
                      controller: _phoneController,
                      keyboardType: TextInputType.phone,
                      maxLength: OwnerProfile.maxPhoneLength,
                      decoration: const InputDecoration(labelText: 'Phone'),
                    ),
                  ],
                ),
              ),
              if (_error != null) ...[
                const SizedBox(height: 12),
                Text(_error!, style: const TextStyle(color: Colors.red, fontSize: 13)),
              ],
              const SizedBox(height: 16),
              PrimaryButton(
                label: _saving ? 'Saving…' : 'Save profile',
                icon: Icons.check_rounded,
                onPressed: _saving || !_dirty ? null : _saveAndLeave,
              ),
              const SizedBox(height: 12),
              const Text(
                'These details aren’t used anywhere yet — they’re here so your '
                'account is more than a Google name.',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 12, color: AppColors.inkMuted, height: 1.4),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
