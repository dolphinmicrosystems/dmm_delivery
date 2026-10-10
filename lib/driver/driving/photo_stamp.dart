import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:image/image.dart' as img;

import '../../models/run_time.dart';

/// Turns a delivery photo into evidence: smaller, and stamped with when and
/// where it was taken.
///
///  * **Smaller.** At most [maxSide] pixels on the long side, JPEG quality
///    [quality] - about 150-300 KB, plenty to see a crate at a door, a tenth
///    of what the camera produces.
///  * **Stamped.** A dark bar along the bottom with the date and time the
///    photo was taken and the run and stop, burned into the pixels so it
///    survives being downloaded, forwarded or printed:
///
///        Fri 10 Oct 2026, 5:42:10 am
///        Run 3 - Stop 5 of 60 - Otago Glass, 12 Orari Street
///
///    The stop's `delivered_at` (server time) is recorded alongside, so a
///    phone with the wrong clock can't make a photo look on time.
///
/// Runs in a background isolate ([compute]): decoding a 12-megapixel photo
/// on the UI thread would freeze the screen for a second.
class PhotoStamp {
  const PhotoStamp._();

  static const maxSide = 1280;
  static const quality = 70;

  static Future<Uint8List> stamp(Uint8List bytes, List<String> lines) =>
      compute(_stampArgs, (bytes: bytes, lines: lines));

  static Uint8List _stampArgs(({Uint8List bytes, List<String> lines}) args) =>
      stampSync(args.bytes, args.lines);

  /// The work itself, on the calling isolate (tests call this directly).
  static Uint8List stampSync(Uint8List bytes, List<String> lines) {
    final decoded = img.decodeImage(bytes);
    if (decoded == null) return bytes; // not an image we can read: keep it as taken
    // Upright first: phones store portrait shots sideways with an EXIF flag.
    var photo = img.bakeOrientation(decoded);

    final longest = math.max(photo.width, photo.height);
    if (longest > maxSide) {
      photo = photo.width >= photo.height
          ? img.copyResize(photo, width: maxSide, interpolation: img.Interpolation.average)
          : img.copyResize(photo, height: maxSide, interpolation: img.Interpolation.average);
    }

    final font = img.arial24;
    const lineHeight = 30, padding = 12;
    final barHeight = padding * 2 + lineHeight * lines.length;
    img.fillRect(
      photo,
      x1: 0,
      y1: photo.height - barHeight,
      x2: photo.width,
      y2: photo.height,
      color: img.ColorRgba8(0, 0, 0, 170),
    );
    for (final (index, line) in lines.indexed) {
      img.drawString(
        photo,
        line,
        font: font,
        x: padding,
        y: photo.height - barHeight + padding + index * lineHeight,
        color: img.ColorRgb8(255, 255, 255),
      );
    }
    return Uint8List.fromList(img.encodeJpg(photo, quality: quality));
  }

  /// "Fri 10 Oct 2026, 5:42:10 am" - plain ASCII, which the stamp's bitmap
  /// font can draw.
  static String timestamp(DateTime at) {
    const days = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
    const months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
    final clock = formatClock(at.hour, at.minute);
    final seconds = at.second.toString().padLeft(2, '0');
    final withSeconds = clock.replaceFirst(' ', ':$seconds ');
    return '${days[at.weekday - 1]} ${at.day} ${months[at.month - 1]} ${at.year}, $withSeconds';
  }

  /// The stamp's lines for a stop. Anything the font can't draw (accents,
  /// "·") is replaced, so a name never comes out as boxes.
  static List<String> linesFor({
    required DateTime takenAt,
    required String routeName,
    required int stopNumber,
    required int stopCount,
    required String customerName,
    required String address,
  }) => [
    timestamp(takenAt),
    _ascii(
      [
        routeName,
        'Stop $stopNumber of $stopCount',
        [customerName, address].where((part) => part.isNotEmpty).join(', '),
      ].join(' - '),
    ),
  ];

  static String _ascii(String text) => text.replaceAll(RegExp(r'[^\x20-\x7E]'), '-');
}
