import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/material.dart';
import 'package:open_filex/open_filex.dart';
import 'package:path_provider/path_provider.dart';

import '../config/infra_config.dart';
import '../util/app_log.dart';

/// The original run-sheet PDF the owner uploaded, opened in the phone's own
/// PDF viewer (which can save, share or print it).
///
/// Where it is: a run carries its sheet's path in the run-sheets bucket
/// (`delivery_run.source_object`; a "Start this route today" copy carries its
/// source's), and a route card carries its latest confirmed sheet's
/// (`circuits.sheet_object`, written by the backend's confirm). The backend's
/// storage.rules let a driver read a sheet of their own business, and nothing
/// else in that bucket.
class RunSheetPdf {
  const RunSheetPdf._();

  /// Size cap for the download - the same 20 MB the upload allows.
  static const _maxBytes = 20 * 1024 * 1024;

  /// The sheet's path for [runId] (its own), else for the route [roundKey]
  /// (its latest); null when neither has one.
  static Future<String?> locate({String? runId, String? roundKey}) async {
    final db = FirebaseFirestore.instance;
    var route = roundKey;
    if (runId != null) {
      final run = (await db.collection('delivery_run').doc(runId).get()).data();
      if (run?['source_object'] case final String path when path.isNotEmpty) return path;
      route ??= run?['round_key'] as String?;
    }
    if (route == null) return null;
    final circuit = (await db.collection('circuits').doc(route).get()).data();
    return switch (circuit?['sheet_object']) {
      final String path when path.isNotEmpty => path,
      _ => null,
    };
  }

  /// A file name a person can recognise in their PDF viewer: "Run 3 run sheet.pdf".
  static String fileName(String routeName) {
    final safe = routeName.replaceAll(RegExp(r'[^A-Za-z0-9 _-]'), '').trim();
    return '${safe.isEmpty ? 'Route' : safe} run sheet.pdf';
  }

  /// Downloads and opens it, saying so on [context]'s snack bar if it can't.
  static Future<void> open(
    BuildContext context, {
    required String routeName,
    String? runId,
    String? roundKey,
  }) async {
    final messenger = ScaffoldMessenger.of(context);
    void say(String text) => messenger
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(text)));
    try {
      final path = await locate(runId: runId, roundKey: roundKey);
      if (path == null) {
        say('No run sheet PDF for this route yet.');
        return;
      }
      say('Getting the run sheet...');
      final bytes = await FirebaseStorage.instanceFor(
        bucket: InfraConfig.runSheetsBucket,
      ).ref(path).getData(_maxBytes);
      if (bytes == null) {
        say("Couldn't get the run sheet.");
        return;
      }
      final file = File('${(await getTemporaryDirectory()).path}/${fileName(routeName)}');
      await file.writeAsBytes(bytes, flush: true);
      messenger.hideCurrentSnackBar();
      final result = await OpenFilex.open(file.path, type: 'application/pdf');
      AppLog.auth('run sheet pdf opened', {'result': result.type.name, 'bytes': bytes.length});
      if (result.type == ResultType.noAppToOpen) {
        say('No app on this phone can open a PDF.');
      } else if (result.type != ResultType.done) {
        say("Couldn't open the run sheet.");
      }
    } catch (error, stack) {
      AppLog.auth.error('run sheet pdf failed', error, stack);
      say("Couldn't get the run sheet. Check your connection.");
    }
  }
}

/// The app-bar button: "Run sheet (PDF)".
class RunSheetPdfButton extends StatefulWidget {
  const RunSheetPdfButton({super.key, required this.routeName, this.runId, this.roundKey});

  final String routeName;
  final String? runId;
  final String? roundKey;

  @override
  State<RunSheetPdfButton> createState() => _RunSheetPdfButtonState();
}

class _RunSheetPdfButtonState extends State<RunSheetPdfButton> {
  bool _busy = false;

  Future<void> _open() async {
    setState(() => _busy = true);
    await RunSheetPdf.open(
      context,
      routeName: widget.routeName,
      runId: widget.runId,
      roundKey: widget.roundKey,
    );
    if (mounted) setState(() => _busy = false);
  }

  @override
  Widget build(BuildContext context) {
    return IconButton(
      tooltip: 'Run sheet (PDF)',
      onPressed: _busy ? null : _open,
      icon: _busy
          ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2.5))
          : const Icon(Icons.picture_as_pdf_outlined),
    );
  }
}
