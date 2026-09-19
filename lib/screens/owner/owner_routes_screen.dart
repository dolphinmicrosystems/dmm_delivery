import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import '../../models/route_assignment.dart';
import '../../models/route_name.dart';
import '../../services/route_assigner.dart';
import '../../services/route_renamer.dart';
import '../../state/auth_state.dart';
import '../../theme/app_colors.dart';
import '../../util/app_log.dart';
import '../../widgets/primary_button.dart';
import '../../widgets/section_label.dart';
import '../../widgets/surface_card.dart';
import 'route_map_screen.dart';
import '../../widgets/schedule_run_sheet.dart';
import 'upload_run_sheet_screen.dart';

/// FR3 (DMM-08-10) lite: one card per circuit ("latest state per route" -
/// circuits/{roundKey}), ordered most recently updated first, so the owner
/// never scans a list of dates to remember.
///
/// The Routes tab. A body, not a Scaffold: the owner shell hosts the header,
/// menu and bottom bar for every tab. Home's "Update routes" action switches
/// to this tab rather than pushing a second copy of it, because choosing
/// *which* route a PDF belongs to is the first step of an upload - a new
/// route or an existing one - and this list is how that choice is made.
///
/// The per-card action says **Update**, not "Upload sheet". Uploading is the
/// mechanism; what the owner is doing is bringing an existing route up to
/// date with this week's sheet, keeping its name, its stop order and its
/// delivery instructions. "Upload" described the file and left the outcome
/// to be guessed at, and guessing wrong here means guessing that the route
/// is about to be replaced.
class OwnerRoutesScreen extends StatelessWidget {
  const OwnerRoutesScreen({super.key, required this.authState});

  final AuthState authState;

  @override
  Widget build(BuildContext context) {
    AppLog.owner('OwnerRoutesScreen build', {'uid': authState.user?.uid});
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
      children: [
        const SectionLabel('Your routes'),
        const SizedBox(height: 8),
        _CircuitList(authState: authState),
        const SizedBox(height: 24),
        PrimaryButton(
          label: 'New route',
          icon: Icons.add_rounded,
          onPressed: () => startUpload(context, authState, roundKey: null, roundLabel: null),
        ),
      ],
    );
  }
}

/// Shared by this screen and the Owner home quick action, which both open
/// the same upload flow - the home card just skips choosing an existing
/// route first.
void startUpload(
  BuildContext context,
  AuthState authState, {
  required String? roundKey,
  required String? roundLabel,
}) {
  AppLog.owner('open UploadRunSheetScreen', {'roundKey': roundKey ?? '<new>', 'roundLabel': roundLabel});
  Navigator.of(context).push(
    MaterialPageRoute(
      builder: (_) => UploadRunSheetScreen(authState: authState, roundKey: roundKey, roundLabel: roundLabel),
    ),
  );
}

class _CircuitList extends StatelessWidget {
  const _CircuitList({required this.authState});

  final AuthState authState;

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: FirebaseFirestore.instance
          .collection('circuits')
          .where('owner_uid', isEqualTo: authState.ownerUid)
          .orderBy('updated_at', descending: true)
          .snapshots(),
      builder: (context, snapshot) {
        // A firestore.rules rejection surfaces here as snapshot.hasError and
        // otherwise renders as the innocuous "No routes yet" empty state -
        // log it so a permission problem can't masquerade as no data.
        if (snapshot.hasError) {
          AppLog.owner.error('circuits stream failed', snapshot.error, snapshot.stackTrace);
        }
        if (snapshot.connectionState == ConnectionState.waiting) {
          AppLog.owner('circuits stream waiting');
          return const Center(
            child: Padding(padding: EdgeInsets.all(24), child: CircularProgressIndicator()),
          );
        }
        final docs = snapshot.data?.docs ?? [];
        AppLog.owner('circuits snapshot', {'count': docs.length, 'ids': docs.map((d) => d.id).toList()});
        if (docs.isEmpty) {
          return const SurfaceCard(
            padding: EdgeInsets.all(16),
            child: Text(
              // A route only appears here once its uploaded sheet has been
              // confirmed - circuits/{roundKey} is written by
              // confirm-run-sheet, not by the upload itself - so say so
              // rather than implying nothing was ever uploaded.
              'No routes yet. Upload a run sheet and confirm the changes to get started.',
              style: TextStyle(color: AppColors.inkMuted, fontSize: 13),
            ),
          );
        }
        // One assignments query for the whole list, grouped here. Per-card
        // queries would be N reads to answer a question about a handful of
        // rows, and which row is in force is a comparison against the clock
        // that Firestore cannot express as a query anyway.
        return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
          stream: authState.routeAssignments(),
          builder: (context, assignmentSnapshot) {
            if (assignmentSnapshot.hasError) {
              AppLog.owner.error(
                'route assignments stream failed',
                assignmentSnapshot.error,
                assignmentSnapshot.stackTrace,
              );
            }
            final byRoute = RouteAssignment.byRoute([
              for (final doc in assignmentSnapshot.data?.docs ?? const []) RouteAssignment.fromDoc(doc),
            ]);

            return Column(
              children: [
                for (final doc in docs) ...[
                  _CircuitCard(
                    roundKey: doc.id,
                    data: doc.data(),
                    authState: authState,
                    assignments: byRoute[doc.id] ?? const [],
                  ),
                  const SizedBox(height: 12),
                ],
              ],
            );
          },
        );
      },
    );
  }
}

class _CircuitCard extends StatefulWidget {
  const _CircuitCard({
    required this.roundKey,
    required this.data,
    required this.authState,
    required this.assignments,
  });

  /// Every assignment ever made for this route. Resolved to "who drives it
  /// today" by RouteAssignment.activeAt, which mirrors the backend's rule.
  final List<RouteAssignment> assignments;

  final String roundKey;
  final Map<String, dynamic> data;
  final AuthState authState;

  @override
  State<_CircuitCard> createState() => _CircuitCardState();
}

class _CircuitCardState extends State<_CircuitCard> {
  /// Long-press reveals rename and delete together. They are the two things
  /// you can do *to* a route rather than *with* it, and both are destructive
  /// enough to a shared list that neither belongs on the card's resting face
  /// next to the everyday Update action.
  bool _revealActions = false;

  // Takes no BuildContext: everything after the dialog's await uses
  // State.context guarded by this State's own `mounted`, which is the check
  // the analyzer can actually reason about across the gap.
  Future<void> _rename(String round) async {
    final name = await showDialog<String>(
      context: context,
      builder: (dialogContext) => _RenameDialog(initialName: round),
    );
    if (name == null) {
      AppLog.owner('rename route canceled', {'roundKey': widget.roundKey});
      if (mounted) setState(() => _revealActions = false);
      return;
    }

    try {
      // Shared with the update screen's "Save name", which reaches the same
      // document by a different road - see RouteRenamer for why the field
      // set is not duplicated at each call site.
      await RouteRenamer.rename(roundKey: widget.roundKey, name: name);
      if (mounted) setState(() => _revealActions = false);
    } on FirebaseException catch (error, stack) {
      AppLog.owner.error('route rename failed', error, stack, {'roundKey': widget.roundKey});
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(RouteRenamer.errorMessage(error))));
    }
  }

  /// Assigns, reassigns, or takes the route off everybody.
  ///
  /// Takes no BuildContext, for the same reason `_rename` doesn't - see its
  /// comment.
  Future<void> _assignDriver() async {
    final ownerUid = widget.authState.ownerUid;
    if (ownerUid == null) return;

    // The shared scheduling sheet, with this route fixed: pick the driver,
    // the day, the start time and whether it repeats. The driver page opens
    // the same sheet with the driver fixed instead.
    final choice = await showScheduleRunSheet(
      context,
      authState: widget.authState,
      roundKey: widget.roundKey,
      routeName: (widget.data['round'] as String?) ?? 'this route',
      current: RouteAssignment.activeAt(widget.assignments, DateTime.now()),
    );

    if (choice == null || !mounted) {
      AppLog.owner('assign driver canceled', {'roundKey': widget.roundKey});
      if (mounted) setState(() => _revealActions = false);
      return;
    }

    try {
      await RouteAssigner.assign(
        ownerUid: ownerUid,
        roundKey: widget.roundKey,
        effectiveFrom: choice.date,
        driver: choice.driver,
        startTime: choice.startTime,
        oneDay: choice.oneDay,
      );
      if (mounted) setState(() => _revealActions = false);
    } on FirebaseException catch (error, stack) {
      AppLog.owner.error('route assign failed', error, stack, {'roundKey': widget.roundKey});
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(RouteAssigner.errorMessage(error))));
    }
  }

  Future<void> _confirmDelete(BuildContext context, String round) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Delete route?'),
        content: Text('"$round" will be removed from your list. This can\'t be undone.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialogContext, false), child: const Text('Cancel')),
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Delete', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
    if (confirmed != true) {
      AppLog.owner('delete route canceled', {'roundKey': widget.roundKey});
      if (mounted) setState(() => _revealActions = false);
      return;
    }
    AppLog.owner('deleting route', {'roundKey': widget.roundKey, 'round': round});
    try {
      await FirebaseFirestore.instance.collection('circuits').doc(widget.roundKey).delete();
      AppLog.owner('route deleted', {'roundKey': widget.roundKey});
    } catch (e, s) {
      AppLog.owner.error('route delete failed', e, s, {'roundKey': widget.roundKey});
      rethrow;
    }
  }

  @override
  Widget build(BuildContext context) {
    final round = widget.data['round'] as String? ?? 'Unnamed route';
    final stopCount = widget.data['stop_count'] as int? ?? 0;
    // Resolved per build against the clock, because an assignment dated for
    // next Monday becomes the answer on Monday without anything being
    // rewritten - see RouteAssignment.activeAt.
    final active = RouteAssignment.activeAt(widget.assignments, DateTime.now());
    final assigned = active != null && !active.isUnassignment;
    final driverLabel = RouteAssignment.driverLabel(widget.assignments, DateTime.now());

    return InkWell(
      onTap: () {
        if (_revealActions) {
          setState(() => _revealActions = false);
          return;
        }
        AppLog.owner('open RouteMapScreen', {'roundKey': widget.roundKey});
        Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => RouteMapScreen(authState: widget.authState, roundKey: widget.roundKey),
          ),
        );
      },
      onLongPress: () => setState(() => _revealActions = true),
      borderRadius: BorderRadius.circular(20),
      child: SurfaceCard(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(color: AppColors.brandSoft, borderRadius: BorderRadius.circular(12)),
              alignment: Alignment.center,
              child: const Icon(Icons.alt_route_rounded, color: AppColors.brand),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(round, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
                  const SizedBox(height: 2),
                  Text('$stopCount stops', style: const TextStyle(fontSize: 12, color: AppColors.inkMuted)),
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      Icon(
                        assigned ? Icons.person_rounded : Icons.person_outline_rounded,
                        size: 13,
                        color: assigned ? AppColors.brand : AppColors.warning,
                      ),
                      const SizedBox(width: 4),
                      Flexible(
                        child: Text(
                          driverLabel,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: assigned ? AppColors.brand : AppColors.warning,
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            if (_revealActions) ...[
              IconButton(
                onPressed: _assignDriver,
                icon: const Icon(Icons.person_add_alt_rounded, color: AppColors.brand),
                tooltip: 'Assign driver',
              ),
              IconButton(
                onPressed: () => _rename(round),
                icon: const Icon(Icons.drive_file_rename_outline_rounded, color: AppColors.brand),
                tooltip: 'Rename route',
              ),
              IconButton(
                onPressed: () => _confirmDelete(context, round),
                icon: const Icon(Icons.delete_outline_rounded, color: Colors.red),
                tooltip: 'Delete route',
              ),
            ] else
              TextButton.icon(
                onPressed: () =>
                    startUpload(context, widget.authState, roundKey: widget.roundKey, roundLabel: round),
                icon: const Icon(Icons.published_with_changes_rounded, size: 18),
                label: const Text('Update'),
              ),
          ],
        ),
      ),
    );
  }
}

/// Renaming a route from the list. Stateful so the name can be validated as
/// it's typed - the length cap here is the one firestore.rules enforces, and a
/// name that breaks it comes back as a bare permission-denied, which reads as
/// a sign-in problem rather than as "that's too long".
///
/// **The dialog owns its text controller.** It used to be created by the
/// caller and disposed the moment `showDialog` returned - but that returns
/// when the dialog is *popped*, while it is still on screen animating out
/// with its TextField (and the keyboard) attached. Disposing it then tripped
/// Flutter's `'_dependents.isEmpty': is not true` assertion on every Save and
/// every Cancel. State.dispose runs only once the dialog is really gone.
class _RenameDialog extends StatefulWidget {
  const _RenameDialog({required this.initialName});

  final String initialName;

  @override
  State<_RenameDialog> createState() => _RenameDialogState();
}

class _RenameDialogState extends State<_RenameDialog> {
  late final _controller = TextEditingController(text: widget.initialName);
  String? _error;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _submit() {
    final error = RouteName.validationError(_controller.text);
    final name = RouteName.toSubmit(_controller.text);
    if (error != null || name == null) {
      // A blank name is rejected rather than silently reverting to the run
      // sheet's heading: the owner opened this dialog to choose a name, and
      // quietly picking a different one for them is not an answer.
      setState(() => _error = error ?? 'Give the route a name.');
      return;
    }
    Navigator.pop(context, name);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Rename route'),
      content: TextField(
        controller: _controller,
        autofocus: true,
        maxLength: RouteName.maxLength,
        textCapitalization: TextCapitalization.sentences,
        textInputAction: TextInputAction.done,
        onSubmitted: (_) => _submit(),
        onChanged: (_) {
          if (_error != null) setState(() => _error = null);
        },
        decoration: InputDecoration(
          labelText: 'Route name',
          hintText: 'e.g. Mosgiel morning',
          border: const OutlineInputBorder(),
          errorText: _error,
          counterText: '',
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
        TextButton(onPressed: _submit, child: const Text('Save')),
      ],
    );
  }
}
