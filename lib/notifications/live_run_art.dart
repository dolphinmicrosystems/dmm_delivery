import 'dart:typed_data';

import 'package:image/image.dart' as img;

/// The picture in the owner's live-run notification: a truck part-way along a
/// track, the way a delivery app shows an order on its way.
///
/// Drawn with the `image` package (plain Dart, no Flutter engine), because
/// the notification is drawn from the background message handler too, which
/// runs in its own isolate with no widgets to render.
class LiveRunArt {
  const LiveRunArt._();

  static const width = 960, height = 200;
  static const _margin = 70, _trackY = 132;

  /// Where the truck sits along the track, 0..1.
  static double fraction(int delivered, int total) => total <= 0 ? 0 : (delivered / total).clamp(0.0, 1.0);

  /// The truck's centre, in pixels from the left.
  static int truckX(int delivered, int total) =>
      (_margin + (width - 2 * _margin) * fraction(delivered, total)).round();

  /// A PNG of the track with the truck at [delivered] of [total].
  static Uint8List track(int delivered, int total) {
    final brand = img.ColorRgb8(26, 86, 219);
    final soft = img.ColorRgb8(219, 228, 245);
    final ink = img.ColorRgb8(30, 41, 59);
    final white = img.ColorRgb8(255, 255, 255);
    final green = img.ColorRgb8(22, 163, 74);

    final image = img.Image(width: width, height: height);
    img.fill(image, color: white);
    final x = truckX(delivered, total);
    const end = width - _margin;

    // The road: all of it faint, the part driven in blue.
    img.fillRect(image, x1: _margin, y1: _trackY - 5, x2: end, y2: _trackY + 5, color: soft, radius: 5);
    if (x > _margin) {
      img.fillRect(image, x1: _margin, y1: _trackY - 5, x2: x, y2: _trackY + 5, color: brand, radius: 5);
    }
    // The depot at the start, the finish at the end.
    img.fillCircle(image, x: _margin, y: _trackY, radius: 11, color: brand, antialias: true);
    img.fillCircle(
      image,
      x: end,
      y: _trackY,
      radius: 13,
      color: delivered >= total && total > 0 ? green : soft,
      antialias: true,
    );
    img.fillCircle(image, x: end, y: _trackY, radius: 6, color: white, antialias: true);

    // The truck, driving right: box, cab, window, wheels - sat on the road.
    const base = _trackY - 8;
    img.fillRect(image, x1: x - 46, y1: base - 52, x2: x + 10, y2: base - 8, color: brand, radius: 6);
    img.fillRect(image, x1: x + 14, y1: base - 38, x2: x + 44, y2: base - 8, color: brand, radius: 6);
    img.fillRect(image, x1: x + 22, y1: base - 32, x2: x + 38, y2: base - 22, color: white, radius: 2);
    for (final wheel in [x - 26, x + 28]) {
      img.fillCircle(image, x: wheel, y: base - 6, radius: 11, color: ink, antialias: true);
      img.fillCircle(image, x: wheel, y: base - 6, radius: 4, color: white, antialias: true);
    }
    return img.encodePng(image);
  }
}
