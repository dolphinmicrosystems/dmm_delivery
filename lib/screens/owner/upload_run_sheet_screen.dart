import 'package:file_picker/file_picker.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/material.dart';
import 'package:uuid/uuid.dart';

import '../../config/infra_config.dart';
import '../../state/auth_state.dart';
import '../../theme/app_colors.dart';
import '../../widgets/primary_button.dart';
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

  @override
  State<UploadRunSheetScreen> createState() => _UploadRunSheetScreenState();
}

class _UploadRunSheetScreenState extends State<UploadRunSheetScreen> {
  double? _uploadProgress;
  String? _error;

  Future<void> _pickAndUpload() async {
    setState(() => _error = null);
    final file = await FilePicker.pickFile(type: FileType.custom, allowedExtensions: ['pdf']);
    if (file == null) return;
    final bytes = await file.readAsBytes();

    const uuid = Uuid();
    final uploadId = uuid.v4();
    final roundKey = widget.roundKey ?? 'route-${uuid.v4()}';
    final ownerUid = widget.authState.user!.uid;

    setState(() => _uploadProgress = 0);

    final task = FirebaseStorage.instanceFor(bucket: InfraConfig.runSheetsBucket)
        .ref('$roundKey/$uploadId.pdf')
        .putData(
          bytes,
          SettableMetadata(
            contentType: 'application/pdf',
            customMetadata: {'uploadId': uploadId, 'roundKey': roundKey, 'ownerUid': ownerUid},
          ),
        );
    task.snapshotEvents.listen((snapshot) {
      if (snapshot.totalBytes > 0 && mounted) {
        setState(() => _uploadProgress = snapshot.bytesTransferred / snapshot.totalBytes);
      }
    });

    try {
      await task;
    } catch (e) {
      if (mounted) setState(() => _error = 'Upload failed: $e');
      return;
    }

    if (!mounted) return;
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(
        builder: (_) => RunSheetProgressScreen(authState: widget.authState, uploadId: uploadId),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isUploading = _uploadProgress != null;
    return Scaffold(
      backgroundColor: AppColors.surfaceMuted,
      appBar: AppBar(title: Text(widget.roundLabel ?? 'New route')),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
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
            if (!isUploading) PrimaryButton(label: 'Choose PDF', icon: Icons.upload_file_rounded, onPressed: _pickAndUpload),
          ],
        ),
      ),
    );
  }
}
