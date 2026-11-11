import 'package:dmm_delivery/notifications/live_run_art.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;

void main() {
  test('the truck moves along the track with the deliveries', () {
    expect(LiveRunArt.truckX(0, 73), 70);
    expect(LiveRunArt.truckX(73, 73), LiveRunArt.width - 70);
    expect(LiveRunArt.truckX(30, 60), LiveRunArt.width ~/ 2);
    // Never off either end, whatever the counts say.
    expect(LiveRunArt.truckX(80, 73), LiveRunArt.width - 70);
    expect(LiveRunArt.truckX(3, 0), 70);
  });

  test('the picture is a PNG of the expected size', () {
    final picture = img.decodePng(LiveRunArt.track(23, 60))!;
    expect((picture.width, picture.height), (LiveRunArt.width, LiveRunArt.height));
  });
}
