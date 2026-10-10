import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import '../util/app_log.dart';

/// A delivery photo from its `gs://bucket/path` link.
class PodPhoto extends StatefulWidget {
  const PodPhoto({super.key, required this.url, this.fit = BoxFit.contain});

  final String url;
  final BoxFit fit;

  @override
  State<PodPhoto> createState() => _PodPhotoState();
}

class _PodPhotoState extends State<PodPhoto> {
  late final Future<String> _download = _resolve(widget.url);

  static Future<String> _resolve(String gsUrl) {
    final match = RegExp(r'^gs://([^/]+)/(.+)$').firstMatch(gsUrl);
    if (match == null) throw ArgumentError('not a gs:// link');
    return FirebaseStorage.instanceFor(bucket: 'gs://${match.group(1)}').ref(match.group(2)).getDownloadURL();
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<String>(
      future: _download,
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          AppLog.owner.error('photo link failed', snapshot.error, snapshot.stackTrace);
          return const _Placeholder(icon: Icons.broken_image_outlined);
        }
        if (!snapshot.hasData) return const _Placeholder(icon: Icons.photo_outlined);
        return Image.network(
          snapshot.data!,
          fit: widget.fit,
          loadingBuilder: (context, child, progress) =>
              progress == null ? child : const _Placeholder(icon: Icons.photo_outlined),
          errorBuilder: (context, error, stack) => const _Placeholder(icon: Icons.broken_image_outlined),
        );
      },
    );
  }
}

class _Placeholder extends StatelessWidget {
  const _Placeholder({required this.icon});

  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return Container(
      color: AppColors.hairline,
      alignment: Alignment.center,
      child: Icon(icon, color: AppColors.inkMuted),
    );
  }
}
