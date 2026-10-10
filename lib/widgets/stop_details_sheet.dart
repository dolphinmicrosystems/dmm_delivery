import 'package:flutter/material.dart';

import '../models/run_stop.dart';
import '../models/run_time.dart';
import '../theme/app_colors.dart';
import 'pod_photo.dart';

/// One stop, read-only: who, where, what to deliver and the instructions -
/// and, once delivered, when and the photo. Opened by tapping a stop on a
/// driver's map or list.
Future<void> showStopDetails(
  BuildContext context, {
  required int number,
  required String customerName,
  required String address,
  List<StopItem> items = const [],
  String? instructions,
  String? phone,
  DateTime? deliveredAt,
  String? photoUrl,
  String? missingItemsNote,
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    backgroundColor: Colors.white,
    builder: (sheetContext) => SafeArea(
      child: ConstrainedBox(
        constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(sheetContext).height * 0.8),
        child: ListView(
          shrinkWrap: true,
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
          children: [
            Text('Stop $number', style: const TextStyle(fontSize: 12, color: AppColors.inkMuted)),
            const SizedBox(height: 2),
            Text(customerName, style: const TextStyle(fontSize: 19, fontWeight: FontWeight.w800)),
            const SizedBox(height: 2),
            Text(address, style: const TextStyle(fontSize: 14, color: AppColors.inkMuted)),
            if (phone != null && phone.trim().isNotEmpty) ...[
              const SizedBox(height: 4),
              Text(phone, style: const TextStyle(fontSize: 14)),
            ],
            const SizedBox(height: 16),
            const Text('Deliver', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700)),
            const SizedBox(height: 6),
            if (items.isEmpty)
              Text(
                missingItemsNote ?? 'Nothing listed for this stop.',
                style: const TextStyle(fontSize: 13, color: AppColors.inkMuted),
              )
            else
              for (final item in items)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 2),
                  child: Text(item.label, style: const TextStyle(fontSize: 15)),
                ),
            if (instructions != null && instructions.trim().isNotEmpty) ...[
              const SizedBox(height: 16),
              const Text('Instructions', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700)),
              const SizedBox(height: 6),
              Text(instructions.trim(), style: const TextStyle(fontSize: 15, height: 1.4)),
            ],
            if (deliveredAt != null) ...[
              const SizedBox(height: 16),
              Row(
                children: [
                  const Icon(Icons.check_circle_rounded, color: AppColors.success, size: 18),
                  const SizedBox(width: 6),
                  Text(
                    'Delivered ${formatClock(deliveredAt.hour, deliveredAt.minute)}',
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                ],
              ),
            ],
            if (photoUrl != null) ...[
              const SizedBox(height: 12),
              ClipRRect(
                borderRadius: BorderRadius.circular(14),
                child: AspectRatio(
                  aspectRatio: 4 / 3,
                  child: PodPhoto(url: photoUrl, fit: BoxFit.cover),
                ),
              ),
            ],
          ],
        ),
      ),
    ),
  );
}
