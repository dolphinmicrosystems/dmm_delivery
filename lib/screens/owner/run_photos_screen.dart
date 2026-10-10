import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/material.dart';

import '../../models/run_time.dart';
import '../../theme/app_colors.dart';
import '../../util/app_log.dart';

/// A run's delivery photos - the driver's evidence that each stop was
/// delivered - in route order, each with the stop and the time it was
/// delivered. Tap one to see it full size.
///
/// Each photo is the driver's camera shot, shrunk and stamped on the phone
/// with the time it was taken and the run and stop (PhotoStamp), stored at
/// `{ownerUid}/{runId}/{stopId}.jpg` in the pod-photos bucket, and linked
/// from its stop's `pod_photo_url`. storage_pod_photos.rules lets the
/// business's owners read them.
class RunPhotosScreen extends StatelessWidget {
  const RunPhotosScreen({super.key, required this.routeName, required this.stops});

  final String routeName;

  /// The run's stops, in route order; those without a photo are skipped.
  final List<QueryDocumentSnapshot<Map<String, dynamic>>> stops;

  @override
  Widget build(BuildContext context) {
    final withPhotos = [
      for (final (index, doc) in stops.indexed)
        if (doc.data()['pod_photo_url'] is String) (number: index + 1, doc: doc),
    ];
    return Scaffold(
      backgroundColor: AppColors.surfaceMuted,
      appBar: AppBar(title: Text('$routeName - photos', overflow: TextOverflow.ellipsis)),
      body: withPhotos.isEmpty
          ? const Center(
              child: Padding(
                padding: EdgeInsets.all(24),
                child: Text('No delivery photos on this run.', style: TextStyle(color: AppColors.inkMuted)),
              ),
            )
          : GridView.builder(
              padding: const EdgeInsets.all(12),
              gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                maxCrossAxisExtent: 220,
                mainAxisSpacing: 12,
                crossAxisSpacing: 12,
                childAspectRatio: 0.78,
              ),
              itemCount: withPhotos.length,
              itemBuilder: (context, index) {
                final entry = withPhotos[index];
                final data = entry.doc.data();
                final at = (data['delivered_at'] as Timestamp?)?.toDate().toLocal();
                final caption = '${entry.number}. ${data['customer_name'] as String? ?? ''}';
                return InkWell(
                  onTap: () => Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => _PhotoViewer(url: data['pod_photo_url'] as String, caption: caption),
                    ),
                  ),
                  borderRadius: BorderRadius.circular(14),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(14),
                          child: PodPhoto(url: data['pod_photo_url'] as String, fit: BoxFit.cover),
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        caption,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600),
                      ),
                      if (at != null)
                        Text(
                          'Delivered ${formatClock(at.hour, at.minute)}',
                          style: const TextStyle(fontSize: 11.5, color: AppColors.inkMuted),
                        ),
                    ],
                  ),
                );
              },
            ),
    );
  }
}

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

/// One photo, full screen, pinch to zoom.
class _PhotoViewer extends StatelessWidget {
  const _PhotoViewer({required this.url, required this.caption});

  final String url;
  final String caption;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        title: Text(caption, overflow: TextOverflow.ellipsis),
      ),
      body: InteractiveViewer(
        maxScale: 5,
        child: Center(child: PodPhoto(url: url)),
      ),
    );
  }
}
