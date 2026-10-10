import 'dart:typed_data';

import 'package:dmm_delivery/driver/driving/photo_stamp.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;

Uint8List photo(int width, int height) {
  final image = img.Image(width: width, height: height);
  img.fill(image, color: img.ColorRgb8(200, 220, 240)); // a pale sky
  return Uint8List.fromList(img.encodeJpg(image, quality: 95));
}

void main() {
  test('a camera-sized photo comes out at most 1280 px and smaller', () {
    // The picker already caps photos at 1600 px; 2400 keeps the test quick.
    final original = photo(2400, 1800);

    final stamped = PhotoStamp.stampSync(original, ['Fri 10 Oct 2026, 5:42:10 am', 'Run 3']);

    final decoded = img.decodeJpg(stamped)!;
    expect((decoded.width, decoded.height), (1280, 960));
    expect(stamped.length, lessThan(original.length));
  });

  test('a portrait photo keeps its shape', () {
    final decoded = img.decodeJpg(PhotoStamp.stampSync(photo(1500, 2000), ['x']))!;
    expect((decoded.width, decoded.height), (960, 1280));
  });

  test('the stamp is a dark bar along the bottom, the top untouched', () {
    final decoded = img.decodeJpg(PhotoStamp.stampSync(photo(800, 600), ['Fri 10 Oct 2026, 5:42:10 am']))!;

    final top = decoded.getPixel(400, 20), bottom = decoded.getPixel(790, decoded.height - 5);
    expect(top.r, greaterThan(150));
    expect(bottom.r, lessThan(120));
  });

  test('the lines say when, and which run and stop, in characters the font can draw', () {
    final lines = PhotoStamp.linesFor(
      takenAt: DateTime(2026, 10, 10, 5, 42, 10),
      routeName: 'Run 3',
      stopNumber: 5,
      stopCount: 60,
      customerName: 'Café Mōkihi',
      address: '12 Orari Street',
    );

    expect(lines, ['Sat 10 Oct 2026, 5:42:10 am', 'Run 3 - Stop 5 of 60 - Caf- M-kihi, 12 Orari Street']);
  });
}
