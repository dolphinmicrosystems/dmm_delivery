import 'package:flutter/material.dart';

import '../config/map_config.dart';
import '../theme/app_colors.dart';

/// The tile credit that has to sit on every map in the app.
///
/// CARTO's terms and OpenStreetMap's before them both require it, and neither
/// accepts it tucked behind a tap - so this is a permanent label rather than
/// flutter_map's expanding "i" button. It is also not
/// [SimpleAttributionWidget], which hardcodes a "flutter_map |" credit in
/// front of the text: crediting the rendering library is not what either
/// licence asks for, and on a 240px-high review map it is most of the line.
///
/// Sized down and half-transparent on purpose. It has to be readable, not
/// noticeable: the map is being read for a route, and the pins and the line
/// are what the owner is here for.
class BasemapAttribution extends StatelessWidget {
  const BasemapAttribution({super.key});

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.bottomRight,
      child: Padding(
        padding: const EdgeInsets.all(4),
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.72),
            borderRadius: BorderRadius.circular(4),
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
            child: Text(
              MapConfig.basemapAttribution,
              style: const TextStyle(fontSize: 9, color: AppColors.inkMuted),
            ),
          ),
        ),
      ),
    );
  }
}
