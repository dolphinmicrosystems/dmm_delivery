import 'package:file_picker/file_picker.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/material.dart';
import 'package:uuid/uuid.dart';

import '../../config/infra_config.dart';
import '../../models/route_name.dart';
import '../../services/route_renamer.dart';
import '../../state/auth_state.dart';
import '../../theme/app_colors.dart';
import '../../util/app_log.dart';
import '../../widgets/primary_button.dart';
import '../../widgets/section_label.dart';
import '../../widgets/surface_card.dart';
import 'run_sheet_progress_screen.dart';

class UploadRunSheetScreen extends StatefulWidget {
  const UploadRunSheetScreen({super.key, required this.authState, required this.roundKey, required this.roundLabel});

  final AuthState authState;

  /// Null means "new route" - a fresh grouping key is generated on upload.
  /// The Firestore-side circuits/{roundKey} document is keyed by whatever
  /// value is used here, not by re-deriving it from the PDF's own round
  /// text - see process_run_sheet_upload.py for how a later mismatch
  /// between this and the PDF's own round header is surfaced, not silently
  /// resolved.
  final String? roundKey;
  final String? roundLabel;

  /// True when this upload amends a route that already exists, which is the
  /// common case: the same run, this week's sheet. Everything the owner has
  /// already decided about it - the name, the stop order, the per-stop
  /// instructions - survives, so the screen says "update" rather than
  /// implying a fresh import.
  bool get isUpdate => roundKey != null;

  @override
  State<UploadRunSheetScreen> createState() => _UploadRunSheetScreenState();
}

class _UploadRunSheetScreenState extends State<UploadRunSheetScreen> {
  late final TextEditingController _nameController;
  double? _uploadProgress;
  String? _error;
  String? _nameError;

  @override
  void initState() {
    super.initState();
    // Prefilled for an existing route so the field reads as "this is what
    // it's called" rather than as a blank waiting to be filled in - editing
    // is the point, not re-entering.
    _nameController = TextEditingController(text: widget.roundLabel ?? '');
  }

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  /// Whether backing out now would throw away a name the owner typed.
  ///
  /// `isRenameOf` rather than `text != roundLabel`: re-spacing the existing
  /// name, or typing it back character for character, is not a change, and a
  /// confirmation dialog for a non-change is worse than none - it teaches
  /// people to dismiss the dialog without reading it, which is precisely
  /// when it needs to be read.
  ///
  /// False once the upload is under way: by then the name has already
  /// travelled with the PDF as Storage metadata, so there is nothing left
  /// unsaved to warn about.
  bool get _hasUnsavedName =>
      _uploadProgress == null && RouteName.isRenameOf(_nameController.text, widget.roundLabel);

  /// Back was pressed with a changed name. Returns without popping unless the
  /// owner chooses to leave - the pop is re-issued here rather than allowed
  /// through, because `PopScope` has already blocked the original one.
  Future<void> _confirmLeave() async {
    final choice = await showDialog<_LeaveChoice>(
      context: context,
      builder: (dialogContext) => _LeaveDialog(
        name: RouteName.normalize(_nameController.text),
        // Only an existing route has somewhere to put the name. A new one is
        // created by confirming its first upload, so there is no
        // circuits/{roundKey} document to write to yet and nothing to offer
        // beyond keeping or discarding what was typed.
        canSave: widget.isUpdate,
      ),
    );
    if (!mounted || choice == null || choice == _LeaveChoice.stay) {
      AppLog.owner('leave update screen canceled', {'roundKey': widget.roundKey});
      return;
    }

    if (choice == _LeaveChoice.save) {
      final saved = await _saveNameOnly();
      if (!saved || !mounted) return;
    }

    AppLog.owner('leaving update screen', {'roundKey': widget.roundKey, 'choice': choice.name});
    // Navigator.pop, not maybePop: PopScope gates the latter, and re-asking
    // the question we have just answered would trap the owner on the screen.
    Navigator.of(context).pop();
  }

  /// Renames the route without uploading anything. Returns false if the write
  /// was refused, in which case the owner stays put with the reason on
  /// screen rather than losing the name to a silent failure.
  Future<bool> _saveNameOnly() async {
    final name = RouteName.toSubmit(_nameController.text);
    if (name == null) return true;
    // The field's maxLength already caps this, paste included, so reaching
    // here means something got past it - still worth failing as "too long"
    // rather than as the rules' permission-denied, which reads as a
    // deployment problem and sends the reader somewhere useless.
    final nameError = RouteName.validationError(name);
    if (nameError != null) {
      if (mounted) setState(() => _nameError = nameError);
      return false;
    }
    try {
      await RouteRenamer.rename(roundKey: widget.roundKey!, name: name);
      return true;
    } on FirebaseException catch (error, stack) {
      AppLog.owner.error('route rename failed', error, stack, {'roundKey': widget.roundKey});
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(RouteRenamer.errorMessage(error))),
        );
      }
      return false;
    }
  }

  Future<void> _pickAndUpload() async {
    final routeName = RouteName.toSubmit(_nameController.text);
    // Checked before the file picker rather than after the upload: the name
    // travels as Storage metadata, and a rejected one would surface as a
    // failed parse minutes later with nothing pointing at the cause.
    final nameError = RouteName.validationError(_nameController.text);
    if (nameError != null) {
      setState(() => _nameError = nameError);
      return;
    }

    AppLog.owner('pick run sheet PDF', {
      'roundKey': widget.roundKey ?? '<new>',
      'hasRouteName': routeName != null,
    });
    setState(() {
      _error = null;
      _nameError = null;
    });
    final file = await FilePicker.pickFile(type: FileType.custom, allowedExtensions: ['pdf']);
    if (file == null) {
      AppLog.owner('file pick canceled');
      return;
    }
    final bytes = await file.readAsBytes();

    const uuid = Uuid();
    final uploadId = uuid.v4();
    final roundKey = widget.roundKey ?? 'route-${uuid.v4()}';
    final ownerUid = widget.authState.user!.uid;

    // Bucket + path together are what decide whether the backend's Storage
    // trigger ever fires - the previous object-not-found bug was exactly a
    // wrong bucket, so log the destination before the write, not after.
    AppLog.owner('uploading run sheet', {
      'bucket': InfraConfig.runSheetsBucket,
      'path': '$roundKey/$uploadId.pdf',
      'bytes': bytes.length,
      'ownerUid': ownerUid,
    });

    setState(() => _uploadProgress = 0);

    final task = FirebaseStorage.instanceFor(bucket: InfraConfig.runSheetsBucket)
        .ref('$roundKey/$uploadId.pdf')
        .putData(
          bytes,
          SettableMetadata(
            contentType: 'application/pdf',
            customMetadata: {
              'uploadId': uploadId,
              'roundKey': roundKey,
              'ownerUid': ownerUid,
              // Omitted entirely rather than sent empty when the owner has
              // no opinion: process_run_sheet_upload_fn.py reads this key as
              // optional and falls back to the PDF's "Round:" heading, and a
              // present-but-blank value would beat that heading to it.
              'routeName': ?routeName,
            },
          ),
        );
    task.snapshotEvents.listen((snapshot) {
      if (snapshot.totalBytes > 0 && mounted) {
        setState(() => _uploadProgress = snapshot.bytesTransferred / snapshot.totalBytes);
      }
    });

    try {
      await task;
      AppLog.owner('run sheet upload complete', {'uploadId': uploadId, 'roundKey': roundKey});
    } catch (e, s) {
      AppLog.owner.error('run sheet upload failed', e, s, {
        'bucket': InfraConfig.runSheetsBucket,
        'path': '$roundKey/$uploadId.pdf',
      });
      // Clearing the progress brings the button back: a failed upload with
      // the picker still hidden leaves the owner on a dead screen.
      if (mounted) {
        setState(() {
          _uploadProgress = null;
          _error = 'Upload failed: $e';
        });
      }
      return;
    }

    if (!mounted) return;
    AppLog.owner('open RunSheetProgressScreen', {'uploadId': uploadId});
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(
        builder: (_) => RunSheetProgressScreen(authState: widget.authState, uploadId: uploadId),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isUploading = _uploadProgress != null;
    // Rebuilt per keystroke so `canPop` tracks the field: PopScope takes its
    // answer as a constructor argument, so the guard is only as current as
    // the last build. Listening to the controller beats a setState in
    // onChanged, which would also have to fire for every keystroke that
    // changes nothing.
    return ValueListenableBuilder<TextEditingValue>(
      valueListenable: _nameController,
      builder: (context, _, child) => PopScope(
        canPop: !_hasUnsavedName,
        onPopInvokedWithResult: (didPop, _) {
          if (!didPop) _confirmLeave();
        },
        child: child!,
      ),
      child: Scaffold(
      backgroundColor: AppColors.surfaceMuted,
      appBar: AppBar(title: Text(widget.isUpdate ? 'Update ${widget.roundLabel}' : 'New route')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            const SectionLabel('Route name'),
            const SizedBox(height: 8),
            SurfaceCard(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  TextField(
                    controller: _nameController,
                    enabled: !isUploading,
                    maxLength: RouteName.maxLength,
                    textCapitalization: TextCapitalization.sentences,
                    decoration: InputDecoration(
                      hintText: 'e.g. Mosgiel morning',
                      border: const OutlineInputBorder(),
                      errorText: _nameError,
                      counterText: '',
                    ),
                    onChanged: (_) {
                      if (_nameError != null) setState(() => _nameError = null);
                    },
                  ),
                  const SizedBox(height: 8),
                  Text(
                    widget.isUpdate
                        // Renaming here is deliberate: the alternative was
                        // making the owner confirm the upload first and then
                        // go back to the list to rename, for a route they are
                        // already looking at.
                        ? 'Rename it if you like — the run sheet won’t change it back.'
                        : 'Leave this blank to use the name printed on the sheet.',
                    style: const TextStyle(fontSize: 12, color: AppColors.inkMuted),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 24),
            const SectionLabel('Run sheet'),
            const SizedBox(height: 8),
            SurfaceCard(
              padding: const EdgeInsets.all(24),
              child: Column(
                children: [
                  const Icon(Icons.picture_as_pdf_rounded, size: 40, color: AppColors.brand),
                  const SizedBox(height: 12),
                  Text(
                    isUploading ? 'Uploading…' : 'Select the run sheet PDF',
                    style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
                  ),
                  if (widget.isUpdate && !isUploading) ...[
                    const SizedBox(height: 8),
                    const Text(
                      'Your stop order and delivery instructions are kept.',
                      textAlign: TextAlign.center,
                      style: TextStyle(fontSize: 12, color: AppColors.inkMuted),
                    ),
                  ],
                  if (isUploading) ...[
                    const SizedBox(height: 16),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(4),
                      child: LinearProgressIndicator(value: _uploadProgress, minHeight: 8),
                    ),
                    const SizedBox(height: 8),
                    Text('${((_uploadProgress ?? 0) * 100).toStringAsFixed(0)}%',
                        style: const TextStyle(fontSize: 12, color: AppColors.inkMuted)),
                  ],
                ],
              ),
            ),
            if (_error != null) ...[
              const SizedBox(height: 16),
              Text(_error!, style: const TextStyle(color: Colors.red, fontSize: 13), textAlign: TextAlign.center),
            ],
            const SizedBox(height: 24),
            if (!isUploading)
              PrimaryButton(
                label: widget.isUpdate ? 'Choose updated PDF' : 'Choose PDF',
                icon: Icons.upload_file_rounded,
                onPressed: _pickAndUpload,
              ),
          ],
        ),
      ),
      ),
    );
  }
}

enum _LeaveChoice { stay, discard, save }

/// Shown when back is pressed with a route name that hasn't been applied to
/// anything yet.
///
/// Three ways out rather than the usual two, because for an existing route
/// "save" is genuinely available: the circuit is already there, and renaming
/// it needs no PDF. Offering only Discard would mean an owner who opened this
/// screen just to fix a name had to back out, lose it, and retype it in the
/// route list.
class _LeaveDialog extends StatelessWidget {
  const _LeaveDialog({required this.name, required this.canSave});

  final String name;
  final bool canSave;

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(canSave ? 'Save this name?' : 'Discard this name?'),
      content: Text(
        canSave
            ? 'You renamed this route to “$name” but haven’t chosen a PDF yet. '
                'Saving keeps the name; the route is otherwise unchanged.'
            : 'A new route takes its name from the sheet you upload. '
                '“$name” won’t be kept unless you choose a PDF now.',
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, _LeaveChoice.stay),
          child: const Text('Keep editing'),
        ),
        TextButton(
          onPressed: () => Navigator.pop(context, _LeaveChoice.discard),
          child: const Text('Discard'),
        ),
        if (canSave)
          TextButton(
            onPressed: () => Navigator.pop(context, _LeaveChoice.save),
            child: const Text('Save name'),
          ),
      ],
    );
  }
}
