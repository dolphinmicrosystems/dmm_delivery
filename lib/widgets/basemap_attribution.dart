import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';

import '../config/map_config.dart';
import '../models/map_style.dart';
import '../services/google_map_tiles.dart';
import '../theme/app_colors.dart';

/// The credit that has to sit on every map in the app, for whichever
/// basemap is showing.
///
///  * **Simple (CARTO):** CARTO's terms and OpenStreetMap's both require
///    "© CARTO © OpenStreetMap contributors", as a permanent label rather than
///    flutter_map's expanding "i" button - neither accepts it tucked behind a
///    tap. Not SimpleAttributionWidget, which prefixes a "flutter_map |"
///    credit neither licence asks for.
///  * **Detailed / Satellite (Google):** the Google Maps logo, unobscured and
///    16-19dp tall with clear space around it, plus the copyright line
///    Google returns for the current viewport - Map Tiles API policies.
///
/// Sized down and half-transparent on purpose. It has to be readable, not
/// noticeable: the map is being read for a route.
class BasemapAttribution extends StatelessWidget {
  const BasemapAttribution({super.key, this.atTop = false});

  /// For a map with a sheet pulled up over its lower edge (the route
  /// screen): Google's logo must never be covered, and neither licence
  /// accepts a credit hidden behind a panel.
  final bool atTop;

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<MapStyle>(
      valueListenable: MapStyle.current,
      builder: (context, style, _) => style.isGoogle
          ? _GoogleAttribution(style: style, atTop: atTop)
          : _CreditLabel(MapConfig.basemapAttribution, atTop: atTop),
    );
  }
}

class _CreditLabel extends StatelessWidget {
  const _CreditLabel(this.text, {required this.atTop});

  final String text;
  final bool atTop;

  @override
  Widget build(BuildContext context) {
    return Align(
      // Top-left when at the top: the zoom controls own the top-right.
      alignment: atTop ? Alignment.topLeft : Alignment.bottomRight,
      child: Padding(
        padding: const EdgeInsets.all(4),
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.72),
            borderRadius: BorderRadius.circular(4),
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
            child: Text(text, style: const TextStyle(fontSize: 9, color: AppColors.inkMuted)),
          ),
        ),
      ),
    );
  }
}

class _GoogleAttribution extends StatefulWidget {
  const _GoogleAttribution({required this.style, required this.atTop});

  final MapStyle style;
  final bool atTop;

  @override
  State<_GoogleAttribution> createState() => _GoogleAttributionState();
}

class _GoogleAttributionState extends State<_GoogleAttribution> {
  Timer? _debounce;
  String? _copyright;
  String? _requestedFor;

  @override
  void dispose() {
    _debounce?.cancel();
    super.dispose();
  }

  /// Asked for once the map settles, not on every frame of a pan: the text
  /// only changes when the view crosses into imagery from another provider.
  void _refresh(MapCamera camera) {
    final bounds = camera.visibleBounds;
    final key = '${widget.style.name}:${camera.zoom.round()}:'
        '${bounds.north.toStringAsFixed(2)},${bounds.west.toStringAsFixed(2)}';
    if (key == _requestedFor) return;
    _requestedFor = key;
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 600), () async {
      try {
        final session = await GoogleMapTiles.session(widget.style);
        final text = await GoogleMapTiles.copyright(
          session,
          zoom: camera.zoom.round(),
          northEast: bounds.northEast,
          southWest: bounds.southWest,
        );
        if (mounted && text != null && text != _copyright) setState(() => _copyright = text);
      } on Exception {
        // The logo stays up either way; a missing line is retried on the
        // next pan rather than surfaced as an error.
        _requestedFor = null;
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    _refresh(MapCamera.of(context));
    final logo = widget.style == MapStyle.satellite
        ? 'assets/google_maps/google_maps_logo_withdarkoutline.png'
        : 'assets/google_maps/google_maps_logo_withlightoutline.png';
    final copyright = _copyright ?? 'Map data © Google';
    if (widget.atTop) {
      return Align(
        alignment: Alignment.topLeft,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              // Google's clear space: 10dp left/right/top, 5dp below.
              padding: const EdgeInsets.fromLTRB(10, 10, 10, 5),
              child: Image.asset(logo, height: 18),
            ),
            _CreditLabel(copyright, atTop: true),
          ],
        ),
      );
    }
    return Stack(
      children: [
        Align(
          alignment: Alignment.bottomLeft,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(10, 10, 10, 5),
            child: Image.asset(logo, height: 18),
          ),
        ),
        _CreditLabel(copyright, atTop: false),
      ],
    );
  }
}
