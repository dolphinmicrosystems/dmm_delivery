import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import '../models/load_sheet.dart';
import '../models/run_stop.dart';
import '../models/run_time.dart';
import '../services/load_writer.dart';
import '../state/auth_state.dart';
import '../theme/app_colors.dart';
import '../util/app_log.dart';
import 'pill_badge.dart';
import 'section_label.dart';
import 'surface_card.dart';

/// Who is looking at a load sheet, which decides what they can do with it.
enum LoadRole {
  /// Adds extra or takes some off; sees the driver's ticks and shortages.
  owner,

  /// Ticks products off as they go on the truck; reports a shortage.
  driver,
}

/// A run's load sheet, live: every product to put on the truck and how many
/// (the run sheet's stops, totalled, plus the owner's changes), the driver's
/// ticks, shortages, and the history of changes. Shared by the driver's Load
/// tab and the owner's run screen, so both read the same numbers.
///
/// A body, not a Scaffold: [header] goes above the list (the driver's run
/// picker), and the action button sits at the bottom.
class LoadSheetView extends StatefulWidget {
  const LoadSheetView({
    super.key,
    required this.authState,
    required this.runId,
    required this.role,
    this.header,
    this.editable = true,
    this.driverAssigned = true,
  });

  final AuthState authState;
  final String runId;
  final LoadRole role;
  final Widget? header;

  /// False once the run is finished: the sheet is history then.
  final bool editable;

  /// Whether the run has a driver to tell (owner side). A change to a run
  /// nobody drives yet tells nobody; whoever gets it sees the sheet as it is.
  final bool driverAssigned;

  @override
  State<LoadSheetView> createState() => _LoadSheetViewState();
}

class _LoadSheetViewState extends State<LoadSheetView> {
  late DocumentReference<Map<String, dynamic>> _run;
  late Stream<QuerySnapshot<Map<String, dynamic>>> _stops, _changes;
  late Stream<DocumentSnapshot<Map<String, dynamic>>> _checklist;

  /// Ticks waiting for Firestore, so a checkbox moves under the thumb.
  final _pending = <String, int?>{};

  @override
  void initState() {
    super.initState();
    _subscribe();
  }

  @override
  void didUpdateWidget(LoadSheetView old) {
    super.didUpdateWidget(old);
    if (old.runId != widget.runId) {
      _pending.clear();
      _subscribe();
    }
  }

  void _subscribe() {
    _run = FirebaseFirestore.instance.collection('delivery_run').doc(widget.runId);
    _stops = _run.collection('delivery_stop').snapshots();
    _changes = _run.collection('load_changes').snapshots();
    _checklist = _run.collection('load_state').doc('checklist').snapshots();
  }

  LoadWriter get _writer => LoadWriter(widget.runId);

  String? get _myName => widget.authState.user?.displayName?.split(' ').first;

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: _stops,
      builder: (context, stopsSnap) => StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
        stream: _changes,
        builder: (context, changesSnap) => StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
          stream: _checklist,
          builder: (context, checkSnap) {
            for (final snap in [stopsSnap, changesSnap]) {
              if (snap.hasError) AppLog.owner.error('load sheet stream failed', snap.error, snap.stackTrace);
            }
            if (stopsSnap.hasError) {
              return const Center(child: Text("Couldn't load this run's products."));
            }
            if (!stopsSnap.hasData) return const Center(child: CircularProgressIndicator());

            // Every stop that is still on the run - located or not: a stop
            // the geocoder couldn't place still needs its milk.
            final items = [
              for (final doc in stopsSnap.data!.docs)
                if (doc.data()['excluded'] != true)
                  for (final raw in (doc.data()['items'] as List?) ?? const [])
                    if (raw is Map) StopItem.fromMap(Map<String, dynamic>.from(raw)),
            ];
            final changes = [
              for (final doc
                  in changesSnap.data?.docs ?? const <QueryDocumentSnapshot<Map<String, dynamic>>>[])
                ?LoadChange.fromDoc(doc),
            ];
            final saved = (checkSnap.data?.data()?['checked'] as Map?) ?? const {};
            final checked = <String, int>{
              for (final entry in saved.entries)
                if (entry.value is num) '${entry.key}': (entry.value as num).toInt(),
            };
            for (final entry in _pending.entries) {
              if (entry.value == null) {
                checked.remove(entry.key);
              } else {
                checked[entry.key] = entry.value!;
              }
            }
            final sheet = LoadSheet.build(items: items, changes: changes, checked: checked);
            return _body(context, sheet);
          },
        ),
      ),
    );
  }

  Widget _body(BuildContext context, LoadSheet sheet) {
    final driver = widget.role == LoadRole.driver;
    return Column(
      children: [
        Expanded(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
            children: [
              ?widget.header,
              _Summary(sheet: sheet, driver: driver),
              const SizedBox(height: 16),
              if (sheet.lines.isEmpty)
                const SurfaceCard(
                  padding: EdgeInsets.all(16),
                  child: Text(
                    'No products on this run sheet.',
                    style: TextStyle(fontSize: 13, color: AppColors.inkMuted),
                  ),
                )
              else
                SurfaceCard(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  child: Column(
                    children: [
                      for (final (index, line) in sheet.lines.indexed) ...[
                        if (index > 0) const Divider(height: 1, indent: 16, color: AppColors.hairline),
                        _LineRow(
                          line: line,
                          canTick: driver && widget.editable,
                          onTick: (on) => _tick(line, on),
                        ),
                      ],
                    ],
                  ),
                ),
              if (sheet.changes.isNotEmpty) ...[
                const SizedBox(height: 22),
                const SectionLabel('Changes'),
                const SizedBox(height: 8),
                SurfaceCard(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  child: Column(
                    children: [for (final change in sheet.changes.reversed) _ChangeRow(change: change)],
                  ),
                ),
              ],
            ],
          ),
        ),
        if (widget.editable)
          SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
              child: SizedBox(
                width: double.infinity,
                child: driver
                    ? OutlinedButton.icon(
                        onPressed: sheet.lines.isEmpty ? null : () => _openChange(sheet),
                        icon: const Icon(Icons.report_problem_outlined),
                        label: const Text('Report a shortage'),
                        style: OutlinedButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 14)),
                      )
                    : FilledButton.icon(
                        onPressed: () => _openChange(sheet),
                        icon: const Icon(Icons.edit_note_rounded),
                        label: const Text('Add or take off'),
                        style: FilledButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 14)),
                      ),
              ),
            ),
          ),
      ],
    );
  }

  Future<void> _tick(LoadLine line, bool on) async {
    final value = on ? line.total : null;
    setState(() => _pending[line.code] = value);
    try {
      await _writer.setChecked(line.code, value);
    } on FirebaseException catch (error, stack) {
      AppLog.auth.error('load tick failed', error, stack);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Couldn't save that tick.")));
      }
    } finally {
      if (mounted) setState(() => _pending.remove(line.code));
    }
  }

  Future<void> _openChange(LoadSheet sheet) async {
    final uid = widget.authState.user?.uid;
    if (uid == null) return;
    final messenger = ScaffoldMessenger.of(context);
    final driver = widget.role == LoadRole.driver;
    final result = await showModalBottomSheet<_ChangeChoice>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => _ChangeSheet(lines: sheet.lines, driver: driver),
    );
    if (result == null) return;
    try {
      await _writer.addChange(
        kind: driver ? LoadChangeKind.short : LoadChangeKind.adjust,
        code: result.code,
        product: result.product,
        delta: result.delta,
        byUid: uid,
        byName: _myName,
        note: result.note,
      );
      messenger.showSnackBar(
        SnackBar(
          content: Text(
            driver
                ? 'Reported - your owner has been told.'
                : widget.driverAssigned
                ? 'Saved - the driver has been told.'
                : 'Saved. Nobody drives this run yet - whoever you assign will see it.',
          ),
        ),
      );
    } on FirebaseException catch (error, stack) {
      AppLog.owner.error('load change failed', error, stack);
      messenger.showSnackBar(const SnackBar(content: Text("Couldn't save that change. Try again.")));
    }
  }
}

class _Summary extends StatelessWidget {
  const _Summary({required this.sheet, required this.driver});

  final LoadSheet sheet;
  final bool driver;

  @override
  Widget build(BuildContext context) {
    final count = sheet.lines.length;
    final done = sheet.checkedCount;
    final shortages = sheet.shortages.fold(0, (running, c) => running + c.delta);
    return SurfaceCard(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                '${sheet.units}',
                style: const TextStyle(
                  fontSize: 30,
                  fontWeight: FontWeight.w800,
                  height: 1,
                  letterSpacing: -0.6,
                ),
              ),
              const SizedBox(width: 8),
              Padding(
                padding: const EdgeInsets.only(bottom: 3),
                child: Text(
                  'units · $count product${count == 1 ? '' : 's'}',
                  style: const TextStyle(
                    fontSize: 13,
                    color: AppColors.inkMuted,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              const Spacer(),
              if (shortages > 0)
                PillBadge(
                  label: 'Short $shortages',
                  background: const Color(0x1AD64545),
                  foreground: AppColors.danger,
                ),
            ],
          ),
          const SizedBox(height: 12),
          ClipRRect(
            borderRadius: BorderRadius.circular(999),
            child: LinearProgressIndicator(
              value: count == 0 ? 0 : done / count,
              minHeight: 6,
              backgroundColor: AppColors.hairline,
              color: sheet.allChecked ? AppColors.success : AppColors.brand,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            sheet.allChecked
                ? 'All loaded'
                : driver
                ? 'Loaded $done of $count - tick each one as it goes on the truck'
                : 'Driver has loaded $done of $count',
            style: TextStyle(
              fontSize: 12.5,
              fontWeight: FontWeight.w600,
              color: sheet.allChecked ? AppColors.success : AppColors.inkMuted,
            ),
          ),
        ],
      ),
    );
  }
}

class _LineRow extends StatelessWidget {
  const _LineRow({required this.line, required this.canTick, required this.onTick});

  final LoadLine line;
  final bool canTick;
  final ValueChanged<bool> onTick;

  @override
  Widget build(BuildContext context) {
    final changed = line.extra != 0;
    return InkWell(
      onTap: canTick ? () => onTick(!line.checked) : null,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(4, 8, 16, 8),
        child: Row(
          children: [
            Checkbox(value: line.checked, onChanged: canTick ? (on) => onTick(on ?? false) : null),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    line.product,
                    style: TextStyle(
                      fontSize: 14.5,
                      fontWeight: FontWeight.w700,
                      color: line.checked ? AppColors.inkMuted : AppColors.ink,
                      decoration: line.checked ? TextDecoration.lineThrough : null,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Wrap(
                    spacing: 6,
                    runSpacing: 4,
                    children: [
                      if (changed) ...[
                        _Chip('Sheet ${line.fromSheet}', AppColors.inkMuted),
                        _Chip(
                          line.extra > 0 ? '+${line.extra} extra' : '−${-line.extra} less',
                          line.extra > 0 ? AppColors.brand : const Color(0xFFB7791F),
                        ),
                      ] else if (line.crates > 0)
                        _Chip(
                          '${line.crates} crate${line.crates == 1 ? '' : 's'}'
                          '${line.loose > 0 ? ' + ${line.loose} loose' : ''}',
                          AppColors.inkMuted,
                        ),
                      if (line.short > 0) _Chip('Short ${line.short}', AppColors.danger),
                    ],
                  ),
                ],
              ),
            ),
            Text(
              '${line.total}',
              style: TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.w800,
                color: line.checked ? AppColors.inkMuted : AppColors.ink,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Chip extends StatelessWidget {
  const _Chip(this.text, this.color);

  final String text;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        text,
        style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w700, color: color),
      ),
    );
  }
}

class _ChangeRow extends StatelessWidget {
  const _ChangeRow({required this.change});

  final LoadChange change;

  @override
  Widget build(BuildContext context) {
    final short = change.kind == LoadChangeKind.short;
    final at = change.at?.toLocal();
    final (icon, tint) = short
        ? (Icons.report_problem_rounded, AppColors.danger)
        : change.delta > 0
        ? (Icons.add_circle_rounded, AppColors.brand)
        : (Icons.remove_circle_rounded, const Color(0xFFB7791F));
    return ListTile(
      dense: true,
      leading: Icon(icon, color: tint),
      title: Text(change.label, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13.5)),
      subtitle: Text(
        [?change.byName, if (at != null) formatClock(at.hour, at.minute), ?change.note].join(' · '),
        style: const TextStyle(fontSize: 12),
      ),
    );
  }
}

/// What the owner or driver chose in the change sheet.
typedef _ChangeChoice = ({String code, String product, int delta, String? note});

/// Pick the product, how many, and (owner) more or less; a note either way.
class _ChangeSheet extends StatefulWidget {
  const _ChangeSheet({required this.lines, required this.driver});

  final List<LoadLine> lines;
  final bool driver;

  @override
  State<_ChangeSheet> createState() => _ChangeSheetState();
}

class _ChangeSheetState extends State<_ChangeSheet> {
  static const _other = '__other__';

  late String? _code = widget.lines.isEmpty ? (widget.driver ? null : _other) : widget.lines.first.code;
  final _otherName = TextEditingController();
  final _note = TextEditingController();
  int _quantity = 1;
  bool _more = true;

  @override
  void dispose() {
    _otherName.dispose();
    _note.dispose();
    super.dispose();
  }

  bool get _isOther => _code == _other;

  String? get _product => _isOther
      ? (_otherName.text.trim().isEmpty ? null : _otherName.text.trim())
      : widget.lines.where((l) => l.code == _code).firstOrNull?.product;

  void _save() {
    final product = _product;
    if (product == null || _code == null) return;
    Navigator.pop<_ChangeChoice>(context, (
      code: _isOther ? LoadChange.codeFor(product) : _code!,
      product: product,
      delta: widget.driver || _more ? _quantity : -_quantity,
      note: _note.text.trim().isEmpty ? null : _note.text.trim(),
    ));
  }

  @override
  Widget build(BuildContext context) {
    final driver = widget.driver;
    return Padding(
      padding: EdgeInsets.fromLTRB(20, 0, 20, MediaQuery.viewInsetsOf(context).bottom + 20),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              driver ? 'Report a shortage' : 'Change the load',
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 4),
            Text(
              driver
                  ? "What isn't on the truck in full. Your owner gets a notification."
                  : 'Extra to take, or some to leave behind. The driver gets a notification.',
              style: const TextStyle(fontSize: 13, color: AppColors.inkMuted),
            ),
            const SizedBox(height: 16),
            if (!driver) ...[
              SegmentedButton<bool>(
                segments: const [
                  ButtonSegment(value: true, icon: Icon(Icons.add_rounded), label: Text('Add extra')),
                  ButtonSegment(value: false, icon: Icon(Icons.remove_rounded), label: Text('Take off')),
                ],
                selected: {_more},
                onSelectionChanged: (choice) => setState(() => _more = choice.first),
              ),
              const SizedBox(height: 16),
            ],
            DropdownButtonFormField<String>(
              initialValue: _code,
              isExpanded: true,
              decoration: const InputDecoration(labelText: 'Product', border: OutlineInputBorder()),
              items: [
                for (final line in widget.lines)
                  DropdownMenuItem(
                    value: line.code,
                    child: Text('${line.product}  (${line.total})', overflow: TextOverflow.ellipsis),
                  ),
                if (!driver) const DropdownMenuItem(value: _other, child: Text('Another product…')),
              ],
              onChanged: (code) => setState(() => _code = code),
            ),
            if (_isOther) ...[
              const SizedBox(height: 12),
              TextField(
                controller: _otherName,
                maxLength: LoadWriter.maxProduct,
                textCapitalization: TextCapitalization.sentences,
                decoration: const InputDecoration(
                  labelText: 'Product name',
                  hintText: 'e.g. Butter 500 g',
                  border: OutlineInputBorder(),
                ),
                onChanged: (_) => setState(() {}),
              ),
            ],
            const SizedBox(height: 16),
            Row(
              children: [
                Text(
                  driver ? 'How many missing' : (_more ? 'How many extra' : 'How many to take off'),
                  style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
                ),
                const Spacer(),
                IconButton.filledTonal(
                  onPressed: _quantity > 1 ? () => setState(() => _quantity--) : null,
                  icon: const Icon(Icons.remove_rounded),
                ),
                SizedBox(
                  width: 52,
                  child: Text(
                    '$_quantity',
                    textAlign: TextAlign.center,
                    style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800),
                  ),
                ),
                IconButton.filledTonal(
                  onPressed: _quantity < LoadWriter.maxQuantity ? () => setState(() => _quantity++) : null,
                  icon: const Icon(Icons.add_rounded),
                ),
              ],
            ),
            const SizedBox(height: 4),
            // Quick steps: milk comes in crates of 12.
            Wrap(
              spacing: 8,
              children: [
                for (final step in const [6, 12, 24])
                  ActionChip(
                    label: Text('+$step'),
                    onPressed: () =>
                        setState(() => _quantity = (_quantity + step).clamp(1, LoadWriter.maxQuantity)),
                  ),
              ],
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _note,
              maxLength: LoadWriter.maxNote,
              textCapitalization: TextCapitalization.sentences,
              decoration: InputDecoration(
                labelText: 'Note (optional)',
                hintText: driver
                    ? 'e.g. Only 2 crates left at the depot'
                    : 'e.g. Extra for the café on George St',
                border: const OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 8),
            FilledButton(
              onPressed: _product == null ? null : _save,
              style: FilledButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 14)),
              child: Text(driver ? 'Report' : 'Save and tell the driver'),
            ),
          ],
        ),
      ),
    );
  }
}
