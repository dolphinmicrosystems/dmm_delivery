import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';

import '../config/map_config.dart';
import '../models/map_style.dart';
import '../services/google_map_tiles.dart';
import '../theme/app_colors.dart';
import '../util/app_log.dart';

/// The tiles under a map, in whichever [MapStyle] is current. Every map in
/// the app uses this rather than its own TileLayer, so switching style on one
/// switches all of them.
///
/// A Google style that cannot start - no network, the key rejected - falls
/// back to Simple rather than leaving the map blank. The route and pins are
/// the point of every map here; the basemap is context.
class BasemapLayer extends StatelessWidget {
  const BasemapLayer({super.key});

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<MapStyle>(
      valueListenable: MapStyle.current,
      builder: (context, style, _) {
        if (!style.isGoogle) return const _CartoTiles();
        return FutureBuilder<GoogleTileSession>(
          // Cached per style inside GoogleMapTiles, so a rebuild is not a
          // new session.
          future: GoogleMapTiles.session(style),
          builder: (context, snapshot) {
            if (snapshot.hasError) {
              AppLog.owner('map tiles unavailable, using Simple', {'style': style.name, 'error': '${snapshot.error}'});
              return const _CartoTiles();
            }
            final session = snapshot.data;
            if (session == null) return const SizedBox.shrink();
            return TileLayer(
              key: ValueKey(session.token),
              urlTemplate: session.urlTemplate,
              // Satellite imagery stops around 20; past that the tiles are
              // stretched, which beats a grey "no imagery" square.
              maxNativeZoom: 20,
              userAgentPackageName: 'com.delivery.dmm_delivery',
              tileProvider: NetworkTileProvider(
                // A copy, not the const map itself: TileLayer adds its own
                // User-Agent to these headers, and adding to a const map
                // throws "Cannot modify unmodifiable map".
                headers: {...MapConfig.googleMapTilesHeaders},
                // Google's terms forbid storing its tiles; flutter_map keeps
                // a disk cache by default, so it is switched off for these.
                cachingProvider: const DisabledMapCachingProvider(),
              ),
            );
          },
        );
      },
    );
  }
}

class _CartoTiles extends StatelessWidget {
  const _CartoTiles();

  @override
  Widget build(BuildContext context) {
    return TileLayer(
      // Template and key both come from MapConfig - an unkeyed CARTO tile
      // still returns a perfectly valid PNG with "API KEY REQUIRED" printed
      // across it, so there is no failure here to notice.
      urlTemplate: MapConfig.basemapUrlTemplate,
      subdomains: MapConfig.basemapSubdomains,
      userAgentPackageName: 'com.delivery.dmm_delivery',
      // Fills the template's `{r}` with "@2x" on a high-density screen,
      // which is every phone this runs on. Left off, CARTO serves 256px
      // tiles stretched to twice their size and street names go soft.
      retinaMode: RetinaMode.isHighDensity(context),
    );
  }
}

/// A map control that picks the basemap style. Only shown when there is more
/// than one to pick from, i.e. when the build has a Google Map Tiles key.
class MapStyleButton extends StatelessWidget {
  const MapStyleButton({super.key});

  @override
  Widget build(BuildContext context) {
    final styles = MapStyle.available;
    if (styles.length < 2) return const SizedBox.shrink();
    return ValueListenableBuilder<MapStyle>(
      valueListenable: MapStyle.current,
      builder: (context, current, _) => Material(
        color: Colors.white,
        elevation: 3,
        shadowColor: Colors.black26,
        borderRadius: BorderRadius.circular(10),
        clipBehavior: Clip.antiAlias,
        child: PopupMenuButton<MapStyle>(
          tooltip: 'Map style',
          initialValue: current,
          onSelected: (style) {
            AppLog.owner('map style', {'style': style.name});
            MapStyle.current.value = style;
          },
          itemBuilder: (context) => [
            for (final style in styles)
              PopupMenuItem(
                value: style,
                child: ListTile(
                  contentPadding: EdgeInsets.zero,
                  dense: true,
                  leading: Icon(_icon(style), color: style == current ? AppColors.brand : AppColors.inkMuted),
                  title: Text(
                    style.label,
                    style: TextStyle(fontWeight: style == current ? FontWeight.w700 : FontWeight.w500),
                  ),
                  subtitle: Text(style.description, style: const TextStyle(fontSize: 11.5)),
                ),
              ),
          ],
          child: SizedBox(width: 38, height: 38, child: Icon(_icon(current), size: 20, color: AppColors.ink)),
        ),
      ),
    );
  }

  static IconData _icon(MapStyle style) => switch (style) {
    MapStyle.simple => Icons.map_outlined,
    MapStyle.detailed => Icons.layers_outlined,
    MapStyle.satellite => Icons.satellite_alt_outlined,
  };
}
