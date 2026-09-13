import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import '../../models/driver_invitation.dart';
import '../../models/owner_profile.dart';
import '../../services/driver_access_api.dart';
import '../../services/driver_inviter.dart';
import '../../state/auth_state.dart';
import '../../theme/app_colors.dart';
import '../../util/app_log.dart';
import '../../widgets/pill_badge.dart';
import '../../widgets/primary_button.dart';
import '../../widgets/section_label.dart';
import '../../widgets/surface_card.dart';
import 'owner_profile_screen.dart';

/// Reached from the hamburger menu. Account, the driver roster, and how long
/// an invitation stays good for.
class OwnerSettingsScreen extends StatelessWidget {
  const OwnerSettingsScreen({super.key, required this.authState});

  final AuthState authState;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.surfaceMuted,
      appBar: AppBar(title: const Text('Settings')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _AccountCard(authState: authState),
          const SizedBox(height: 24),
          const SectionLabel('Drivers'),
          const SizedBox(height: 8),
          PrimaryButton(
            label: 'Register driver',
            icon: Icons.person_add_alt_1_rounded,
            onPressed: () => showInviteDriverDialog(context, authState),
          ),
          const SizedBox(height: 16),
          _DriverList(authState: authState),
          const SizedBox(height: 24),
          const SectionLabel('Invitation validity'),
          const SizedBox(height: 8),
          _InvitationValidityCard(authState: authState),
          const SizedBox(height: 24),
        ],
      ),
    );
  }
}

/// The account card, which is also the way into the profile.
///
/// Streamed rather than read once so the summary line updates the moment the
/// profile screen saves - the owner comes straight back to this card, and a
/// stale line under their own name is the first thing they would notice.
class _AccountCard extends StatelessWidget {
  const _AccountCard({required this.authState});

  final AuthState authState;

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<OwnerProfile>(
      stream: authState.profile(),
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          AppLog.owner.error('profile stream failed', snapshot.error, snapshot.stackTrace);
        }
        final profile = snapshot.data ?? OwnerProfile.empty;
        // The owner's own choice beats the name Google supplied, the same
        // precedence rule route names and driver names follow.
        final name = profile.displayName ?? authState.user?.displayName ?? authState.user?.email ?? 'Owner';

        return SurfaceCard(
          padding: EdgeInsets.zero,
          child: Column(
            children: [
              InkWell(
                onTap: () {
                  AppLog.owner('open OwnerProfileScreen');
                  Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => OwnerProfileScreen(authState: authState, initial: profile),
                    ),
                  );
                },
                borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Row(
                    children: [
                      const CircleAvatar(radius: 20, child: Icon(Icons.person_rounded)),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              name,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(fontWeight: FontWeight.w700),
                            ),
                            Text(
                              authState.user?.email ?? '',
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(fontSize: 12, color: AppColors.inkMuted),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              profile.summary,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(fontSize: 12, color: AppColors.inkMuted),
                            ),
                          ],
                        ),
                      ),
                      const Icon(Icons.chevron_right_rounded, color: AppColors.inkMuted),
                    ],
                  ),
                ),
              ),
              const Divider(height: 1, color: AppColors.hairline),
              Align(
                alignment: Alignment.centerLeft,
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  child: TextButton(onPressed: authState.signOut, child: const Text('Sign out')),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

/// How long a new invitation stays good for.
///
/// Worth a control rather than a constant because the right answer is a
/// judgement about people, not about software: an owner onboarding a driver
/// who starts on Monday wants a short window, and one inviting a relief
/// driver for the season wants a long one. The old value was seven days,
/// hardcoded in the client, and nothing said so anywhere on screen.
class _InvitationValidityCard extends StatelessWidget {
  const _InvitationValidityCard({required this.authState});

  final AuthState authState;

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<int>(
      stream: authState.invitationTtlDays(),
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          AppLog.owner.error('invitation ttl stream failed', snapshot.error, snapshot.stackTrace);
        }
        final days = snapshot.data ?? InvitationTtl.fallback;

        return SurfaceCard(
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'New invitations expire after ${InvitationTtl.label(days)}',
                style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 4),
              const Text(
                'After that a driver signing in is turned away and has to be invited '
                'again. Changing this affects new invitations only — invitations '
                'already sent keep the date they were given.',
                style: TextStyle(fontSize: 12, color: AppColors.inkMuted, height: 1.4),
              ),
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final preset in InvitationTtl.presets)
                    ChoiceChip(
                      label: Text(InvitationTtl.label(preset)),
                      selected: preset == days,
                      onSelected: (selected) {
                        if (!selected || preset == days) return;
                        _set(context, preset);
                      },
                    ),
                ],
              ),
            ],
          ),
        );
      },
    );
  }

  Future<void> _set(BuildContext context, int days) async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      await authState.setInvitationTtlDays(days);
    } on FirebaseException catch (error, stack) {
      AppLog.owner.error('invitation ttl write failed', error, stack, {'days': days});
      messenger.showSnackBar(SnackBar(content: Text(DriverInviter.errorMessage(error))));
    }
  }
}

/// Only ever invites a **driver**. Each owner is a separate business, so
/// minting another owner is creating a company rather than adding a
/// colleague - that is Blue Dot's decision, and its mechanism is the
/// OWNER_EMAILS allowlist in Terraform, unreachable from any session here.
/// `firestore.rules` enforces it too: a client write may only say `rider`.
///
/// Shared by this screen's "Register driver" button and the Owner home
/// "Invite riders" quick action - the same invitation, reached from the two
/// places an owner looks for it.
///
/// There is no link and nothing for the driver to click. The invitation
/// document authorises the address on its next Google sign-in, so the email
/// is a courtesy: an owner can invite someone and tell them in person, and
/// acceptance works identically. The dialog says as much, because "invite
/// sent" otherwise implies something is in flight that has to arrive.
void showInviteDriverDialog(BuildContext context, AuthState authState) {
  showDialog<void>(
    context: context,
    builder: (_) => _InviteDriverDialog(authState: authState),
  );
}

class _InviteDriverDialog extends StatefulWidget {
  const _InviteDriverDialog({required this.authState});

  final AuthState authState;

  @override
  State<_InviteDriverDialog> createState() => _InviteDriverDialogState();
}

class _InviteDriverDialogState extends State<_InviteDriverDialog> {
  final _emailController = TextEditingController();
  final _nameController = TextEditingController();
  String? _error;
  bool _sending = false;

  @override
  void dispose() {
    _emailController.dispose();
    _nameController.dispose();
    super.dispose();
  }

  Future<void> _submit(int ttlDays) async {
    final emailError = InviteForm.emailError(_emailController.text);
    final nameError = InviteForm.nameError(_nameController.text);
    if (emailError != null || nameError != null) {
      setState(() => _error = emailError ?? nameError);
      return;
    }

    setState(() {
      _error = null;
      _sending = true;
    });

    try {
      await DriverInviter.invite(
        email: _emailController.text,
        ownerUid: widget.authState.user!.uid,
        ttlDays: ttlDays,
        name: InviteForm.nameToSubmit(_nameController.text),
      );
      if (mounted) Navigator.pop(context);
    } on FirebaseException catch (error, stack) {
      AppLog.owner.error('driver invite failed', error, stack);
      if (mounted) {
        setState(() {
          _error = DriverInviter.errorMessage(error);
          _sending = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    // The validity is read live rather than passed in, so the dialog quotes
    // the window the owner set moments ago on the screen behind it.
    return StreamBuilder<int>(
      stream: widget.authState.invitationTtlDays(),
      builder: (context, snapshot) {
        final ttlDays = snapshot.data ?? InvitationTtl.fallback;

        return AlertDialog(
          title: const Text('Register driver'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              TextField(
                controller: _emailController,
                autofocus: true,
                keyboardType: TextInputType.emailAddress,
                decoration: const InputDecoration(labelText: 'Driver\'s Gmail address'),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _nameController,
                textCapitalization: TextCapitalization.words,
                decoration: const InputDecoration(
                  labelText: 'Their name (optional)',
                  // Without a name the roster row is an email address, which
                  // tells the owner nothing about who they invited until the
                  // driver signs in and Google supplies one.
                  helperText: 'Shown in your driver list straight away',
                ),
              ),
              const SizedBox(height: 12),
              Text(
                'They accept by signing in to the app with that Google account. '
                'Valid for ${InvitationTtl.label(ttlDays)}.',
                style: const TextStyle(fontSize: 12, color: AppColors.inkMuted, height: 1.4),
              ),
              if (_error != null) ...[
                const SizedBox(height: 8),
                Text(_error!, style: const TextStyle(color: Colors.red, fontSize: 12)),
              ],
            ],
          ),
          actions: [
            TextButton(
              onPressed: _sending ? null : () => Navigator.pop(context),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: _sending ? null : () => _submit(ttlDays),
              child: Text(_sending ? 'Sending…' : 'Send invite'),
            ),
          ],
        );
      },
    );
  }
}

/// The roster: everyone invited, whatever state they are in.
///
/// One list rather than a filtered one. An owner looking here is asking "who
/// drives for me and is anything stuck?", and the answer to the second half
/// lives entirely in the rows a filtered list would have hidden.
class _DriverList extends StatelessWidget {
  const _DriverList({required this.authState});

  final AuthState authState;

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: authState.invitations(),
      builder: (context, snapshot) {
        // Same trap as the circuits stream: a rules rejection would
        // otherwise render as the benign "No drivers yet" empty state.
        if (snapshot.hasError) {
          AppLog.owner.error('invitations stream failed', snapshot.error, snapshot.stackTrace);
        }
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(
            child: Padding(padding: EdgeInsets.all(24), child: CircularProgressIndicator()),
          );
        }

        // One clock for the whole list, taken once per build: rows computed
        // against slightly different `now`s could disagree about which side
        // of midnight an expiry falls on.
        final now = DateTime.now();
        final invitations = [
          for (final doc in snapshot.data?.docs ?? const []) DriverInvitation.fromDoc(doc, now: now),
        ]..sort(DriverInvitation.compare);

        AppLog.owner('invitations snapshot', {
          'total': invitations.length,
          'expired': invitations.where((i) => i.status == InvitationStatus.expired).length,
        });

        // Split rather than sorted-to-the-bottom. Former staff are a different
        // question from current ones, and a roster that runs straight from
        // "Active driver" into "Removed" invites the owner to act on a row
        // that no longer means anything.
        final working = invitations.where((i) => !i.isRemoved).toList();
        final removed = invitations.where((i) => i.isRemoved).toList();

        if (invitations.isEmpty) {
          return const SurfaceCard(
            padding: EdgeInsets.all(16),
            child: Text(
              'No drivers yet. Register one, and they appear here as soon as you invite '
              'them — the row becomes active once they sign in.',
              style: TextStyle(color: AppColors.inkMuted, fontSize: 13),
            ),
          );
        }

        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (working.isEmpty)
              const SurfaceCard(
                padding: EdgeInsets.all(16),
                child: Text(
                  'Nobody drives for you at the moment. Everyone you have invited has been '
                  'removed — restore one below, or invite somebody new.',
                  style: TextStyle(color: AppColors.inkMuted, fontSize: 13),
                ),
              )
            else
              SurfaceCard(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Column(
                  children: [
                    for (final invitation in working)
                      _DriverRow(invitation: invitation, authState: authState),
                  ],
                ),
              ),
            // Kept on screen rather than tidied away: nothing is deleted, the
            // rounds these people drove still point at them, and restoring
            // somebody is the only way they get back in.
            if (removed.isNotEmpty) ...[
              const SizedBox(height: 20),
              const SectionLabel('Removed'),
              const SizedBox(height: 8),
              SurfaceCard(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Column(
                  children: [
                    for (final invitation in removed)
                      _DriverRow(invitation: invitation, authState: authState),
                  ],
                ),
              ),
            ],
          ],
        );
      },
    );
  }
}

enum _DriverAction { rename, resend, remove, restore }

class _DriverRow extends StatefulWidget {
  const _DriverRow({required this.invitation, required this.authState});

  final DriverInvitation invitation;
  final AuthState authState;

  @override
  State<_DriverRow> createState() => _DriverRowState();
}

class _DriverRowState extends State<_DriverRow> {
  bool _busy = false;

  /// One client per row rather than a shared static: it holds an http.Client,
  /// and a row disposed mid-request should take its connection with it.
  final _api = DriverAccessApi();

  DriverInvitation get _invitation => widget.invitation;

  ({Color color, Color background}) get _tone => switch (_invitation.status) {
    InvitationStatus.accepted => (color: AppColors.success, background: AppColors.brandSoft),
    InvitationStatus.pending => (color: AppColors.inkMuted, background: AppColors.surfaceMuted),
    // The only row that is actually stuck, and the only one coloured to say so.
    InvitationStatus.expired => (color: AppColors.warning, background: Color(0x1AE4A83A)),
    // Deliberately the quietest of the four. A removed driver needs nothing
    // done about them; the row is here so the record is visible, not so it
    // competes with the people who are actually working.
    InvitationStatus.removed => (color: AppColors.inkMuted, background: AppColors.surfaceMuted),
  };

  @override
  Widget build(BuildContext context) {
    final tone = _tone;

    return ListTile(
      leading: Icon(
        switch (_invitation.status) {
          InvitationStatus.accepted => Icons.local_shipping_rounded,
          InvitationStatus.removed => Icons.person_off_outlined,
          _ => Icons.mark_email_unread_outlined,
        },
        color: switch (_invitation.status) {
          InvitationStatus.expired => AppColors.warning,
          InvitationStatus.removed => AppColors.inkMuted,
          _ => AppColors.brand,
        },
      ),
      title: Text(
        _invitation.displayName,
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14),
      ),
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SizedBox(height: 2),
          Text(
            _invitation.email,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontSize: 12, color: AppColors.inkMuted),
          ),
          const SizedBox(height: 6),
          Row(
            children: [
              PillBadge(label: _invitation.statusLabel, background: tone.background, foreground: tone.color),
              // Shown for an owner in every state, not just once accepted: a
              // pending owner invitation is the row most worth noticing, and
              // 'Invited' alone says nothing about what was invited.
              if (_invitation.isOwnerInvite) ...[const SizedBox(width: 6), const PillBadge(label: 'Owner')],
              const SizedBox(width: 8),
              Flexible(
                child: Text(
                  _invitation.detailLabel,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 11, color: AppColors.inkMuted),
                ),
              ),
            ],
          ),
        ],
      ),
      isThreeLine: true,
      trailing: _busy
          ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
          : PopupMenuButton<_DriverAction>(
              tooltip: 'Driver options',
              onSelected: _run,
              // A removed row offers one thing. Rename and Resend are both
              // edits to a live invitation, and neither means anything for
              // somebody who no longer works here.
              itemBuilder: (context) => _invitation.canRestore
                  ? [const PopupMenuItem(value: _DriverAction.restore, child: Text('Restore'))]
                  : [
                      PopupMenuItem(
                        value: _DriverAction.rename,
                        enabled: _invitation.canRename,
                        child: const Text('Rename'),
                      ),
                      PopupMenuItem(
                        value: _DriverAction.resend,
                        // A resend aimed at an accepted driver would write their
                        // acceptance back to null. The rules refuse it; disabling
                        // it here stops the app offering a button that can't work.
                        //
                        // The rate-limit policy layers two more refusals on top:
                        // at least 1 day between consecutive invites, and at most
                        // 14 in any rolling 14-day window. When disabled for one of
                        // those reasons, show when the next resend is available.
                        enabled: _invitation.canResend,
                        child: Text(
                          _invitation.resendAvailableAt != null
                              ? 'Resend invite (${_resendCountdown(_invitation.resendAvailableAt!)})'
                              : 'Resend invite',
                        ),
                      ),
                      const PopupMenuItem(value: _DriverAction.remove, child: Text('Remove')),
                    ],
            ),
    );
  }

  Future<void> _run(_DriverAction action) async {
    switch (action) {
      case _DriverAction.rename:
        await _rename();
      case _DriverAction.resend:
        await _resend();
      case _DriverAction.remove:
        await _remove();
      case _DriverAction.restore:
        await _restore();
    }
  }

  Future<void> _rename() async {
    final name = await showDialog<String>(
      context: context,
      builder: (_) => _DriverNameDialog(current: _invitation.driverName),
    );
    if (name == null || !mounted) return;

    await _guard(() => DriverInviter.rename(email: _invitation.email, name: name));
  }

  Future<void> _resend() async {
    final ttlDays = await widget.authState.invitationTtlDays().first;
    if (!mounted) return;

    await _guard(
      () => DriverInviter.resend(
        invitation: _invitation,
        ownerUid: widget.authState.user!.uid,
        ttlDays: ttlDays,
      ),
      success: 'Invite resent — valid for ${InvitationTtl.label(ttlDays)}.',
    );
  }

  /// Human-readable countdown for the "Resend invite (in 7h)" subtitle.
  /// Mirrors the day/hour grain the rest of this screen uses; sub-hour
  /// precision would change between page loads and read as flicker.
  String _resendCountdown(DateTime when) {
    final delta = when.difference(_invitation.now);
    if (delta.isNegative) return 'now';
    if (delta.inHours >= 24) return 'in ${delta.inDays}d';
    if (delta.inHours >= 1) return 'in ${delta.inHours}h';
    return 'in <1h';
  }

  Future<void> _remove() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text('Remove ${_invitation.displayName}?'),
        content: Text(
          // Both branches used to over-promise, in opposite directions. The
          // pending one claimed they "won't be able to sign in" while an
          // uninvited account still became an owner; the accepted one admitted
          // the role claim could not be taken back at all. Removal now disables
          // the Firebase account, so the honest version is neither - it works,
          // with an hour of slack.
          _invitation.status == InvitationStatus.accepted
              ? 'Their account is switched off and they lose access within the hour. '
                    'Nothing is deleted — their rounds stay on record, and you can restore '
                    'them later.'
              : 'Their invitation is withdrawn, so they can\'t sign in. Nothing is '
                    'deleted — you can restore them later.',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialogContext, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(dialogContext, true), child: const Text('Remove')),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    await _guard(() async {
      final result = await _api.remove(_invitation.email);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          // Says what actually happened rather than one sentence for two
          // different events. A pending driver had no account to switch off,
          // and telling their owner they were "signed out" would be describing
          // something that never occurred.
          content: Text(
            result.accountChanged
                ? '${_invitation.displayName} removed — they lose access within the hour.'
                : 'Invitation for ${_invitation.displayName} withdrawn.',
          ),
        ),
      );
    });
  }

  /// The only way a removed driver gets back in - their account is disabled,
  /// so they cannot sign in to ask. No confirmation: restoring is the
  /// reversible direction, and the row says plainly what it does.
  Future<void> _restore() async {
    await _guard(() async {
      final result = await _api.restore(_invitation.email);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            result.accountChanged
                ? '${_invitation.displayName} restored — they can sign in again.'
                : 'Invitation for ${_invitation.displayName} restored.',
          ),
        ),
      );
    });
  }

  /// Runs a write with the spinner, the mounted checks and the one error
  /// translation every action on this row needs, so three call sites don't
  /// each grow their own half of it.
  Future<void> _guard(Future<void> Function() write, {String? success}) async {
    final messenger = ScaffoldMessenger.of(context);
    setState(() => _busy = true);
    try {
      await write();
      if (success != null) messenger.showSnackBar(SnackBar(content: Text(success)));
    } on FirebaseException catch (error, stack) {
      AppLog.owner.error('driver action failed', error, stack, {'code': error.code});
      messenger.showSnackBar(SnackBar(content: Text(DriverInviter.errorMessage(error))));
    } on DriverAccessException catch (error, stack) {
      // Remove and restore go over HTTP, not Firestore, so they fail with a
      // different type entirely - and one whose message is already written
      // for a person to read.
      AppLog.owner.error('driver access failed', error, stack);
      messenger.showSnackBar(SnackBar(content: Text(error.message)));
    } finally {
      // The row survives the write - the stream rebuilds it rather than
      // replacing it - so the spinner has to be cleared explicitly.
      if (mounted) setState(() => _busy = false);
    }
  }
}

/// Renaming a driver. Pops the normalized name, or null if nothing changed -
/// so a dialog dismissed with the same text writes nothing.
class _DriverNameDialog extends StatefulWidget {
  const _DriverNameDialog({required this.current});

  final String? current;

  @override
  State<_DriverNameDialog> createState() => _DriverNameDialogState();
}

class _DriverNameDialogState extends State<_DriverNameDialog> {
  late final TextEditingController _controller;
  String? _error;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.current ?? '');
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _save() {
    final error = InviteForm.nameError(_controller.text);
    if (error != null) {
      setState(() => _error = error);
      return;
    }
    final name = InviteForm.nameToSubmit(_controller.text);
    if (name == null) {
      setState(() => _error = 'Enter a name.');
      return;
    }
    // Not raw text inequality: respacing a name, or typing it back exactly,
    // is not a change worth a write.
    Navigator.pop(context, InviteForm.isRenameOf(name, widget.current) ? name : null);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Rename driver'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          TextField(
            controller: _controller,
            autofocus: true,
            textCapitalization: TextCapitalization.words,
            decoration: const InputDecoration(labelText: 'Name'),
            onSubmitted: (_) => _save(),
          ),
          const SizedBox(height: 8),
          const Text(
            'This is what you call them. Signing in won\'t overwrite it.',
            style: TextStyle(fontSize: 12, color: AppColors.inkMuted),
          ),
          if (_error != null) ...[
            const SizedBox(height: 8),
            Text(_error!, style: const TextStyle(color: Colors.red, fontSize: 12)),
          ],
        ],
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
        FilledButton(onPressed: _save, child: const Text('Save')),
      ],
    );
  }
}
