import 'package:flutter/material.dart';

import '../../models/run_time.dart';
import '../../theme/app_colors.dart';
import '../../util/app_log.dart';
import '../../widgets/surface_card.dart';
import '../settings_store.dart';
import 'save_setting.dart';

/// How long to allow at a stop before drivers have taught us the address.
///
/// The figure every route's "about 2 h 16 min" rests on until real deliveries
/// arrive: a minute a stop across 60 stops is an hour of the estimate. Learned
/// stop times replace it address by address, which is what the second line
/// says - so an owner who sets three minutes today is not surprised when a
/// route later says something else.
class StopTimeCard extends StatelessWidget {
  const StopTimeCard({super.key, required this.settings});

  final SettingsStore settings;

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<int>(
      stream: settings.defaultStopSeconds(),
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          AppLog.owner.error('stop time stream failed', snapshot.error, snapshot.stackTrace);
        }
        final seconds = snapshot.data ?? StopTime.fallbackSeconds;
        return SurfaceCard(
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Time at each stop', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700)),
              const SizedBox(height: 4),
              const Text(
                'Used in route time estimates until your drivers have delivered to '
                'an address a few times - then its own average is used.',
                style: TextStyle(fontSize: 12, color: AppColors.inkMuted, height: 1.4),
              ),
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final preset in StopTime.presetSeconds)
                    ChoiceChip(
                      label: Text(StopTime.label(preset)),
                      selected: preset == seconds,
                      onSelected: (selected) {
                        if (!selected || preset == seconds) return;
                        saveSetting(context, 'stop time', () => settings.setDefaultStopSeconds(preset));
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
}
