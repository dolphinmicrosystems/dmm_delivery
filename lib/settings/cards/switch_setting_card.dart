import 'package:flutter/material.dart';

import '../../theme/app_colors.dart';
import '../../util/app_log.dart';
import '../../widgets/surface_card.dart';
import 'save_setting.dart';

/// One on/off setting: a title, a line saying what it does, and a switch that
/// saves the moment it is flipped.
class SwitchSettingCard extends StatelessWidget {
  const SwitchSettingCard({
    super.key,
    required this.title,
    required this.subtitle,
    required this.value,
    required this.onChanged,
    required this.what,
  });

  final String title;
  final String subtitle;
  final Stream<bool> value;
  final Future<void> Function(bool on) onChanged;

  /// For the log line if the write fails.
  final String what;

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<bool>(
      stream: value,
      builder: (context, snapshot) {
        if (snapshot.hasError) AppLog.owner.error('$what stream failed', snapshot.error, snapshot.stackTrace);
        return SurfaceCard(
          padding: const EdgeInsets.fromLTRB(16, 6, 8, 6),
          child: SwitchListTile(
            contentPadding: EdgeInsets.zero,
            value: snapshot.data ?? true,
            onChanged: snapshot.hasData ? (on) => saveSetting(context, what, () => onChanged(on)) : null,
            title: Text(title, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700)),
            subtitle: Text(
              subtitle,
              style: const TextStyle(fontSize: 12, color: AppColors.inkMuted, height: 1.4),
            ),
          ),
        );
      },
    );
  }
}
