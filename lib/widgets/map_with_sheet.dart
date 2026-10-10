import 'package:flutter/material.dart';

/// A map filling the screen, with a list in a sheet over its lower part.
///
/// Swipe the sheet down and the map has the whole screen (a handle stays
/// visible to pull it back); swipe up for the list. It snaps to three
/// heights - map only, half and half, list - so it never stops half-way.
/// Used wherever a route's map and its stops share a screen; the map's own
/// credits belong at the top (`attributionAtTop`), where the sheet can't
/// cover them.
class MapWithSheet extends StatelessWidget {
  const MapWithSheet({
    super.key,
    required this.map,
    required this.children,
    this.initialSize = 0.45,
    this.overlay,
  });

  final Widget map;

  /// A button over the map's top-left corner (the driver's "Drive").
  final Widget? overlay;

  /// The sheet's content, top to bottom.
  final List<Widget> children;

  final double initialSize;

  static const _mapOnly = 0.1;
  static const _listOnly = 0.92;

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        Positioned.fill(child: map),
        if (overlay != null) Positioned(top: 12, left: 12, child: overlay!),
        DraggableScrollableSheet(
          initialChildSize: initialSize,
          minChildSize: _mapOnly,
          maxChildSize: _listOnly,
          snap: true,
          snapSizes: [initialSize],
          builder: (context, controller) => DecoratedBox(
            decoration: const BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
              boxShadow: [BoxShadow(color: Color(0x26000000), blurRadius: 12, offset: Offset(0, -2))],
            ),
            child: ListView(
              controller: controller,
              padding: const EdgeInsets.only(bottom: 24),
              children: [
                Center(
                  child: Container(
                    width: 40,
                    height: 4,
                    margin: const EdgeInsets.symmetric(vertical: 10),
                    decoration: BoxDecoration(
                      color: const Color(0xFFD0D5DD),
                      borderRadius: BorderRadius.circular(999),
                    ),
                  ),
                ),
                ...children,
              ],
            ),
          ),
        ),
      ],
    );
  }
}
