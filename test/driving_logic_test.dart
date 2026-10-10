import 'package:dmm_delivery/driver/driving/driving_logic.dart';
import 'package:dmm_delivery/models/run_stop.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';

// Two real South Runsheet neighbours in Dunedin.
const orari = LatLng(-45.8907, 170.4958);

RunStop stop(String id, {String name = 'Otago Glass', String note = '', List<StopItem> items = const []}) =>
    RunStop(
      id: id,
      seqOrder: 0,
      customerName: name,
      address: '12 Orari Street',
      location: orari,
      items: items,
      instructions: note,
    );

void main() {
  test('the current stop is the first in order not yet delivered', () {
    const stops = ['a', 'b', 'c'];

    expect(DrivingLogic.currentIndex(stops, {}), 0);
    expect(DrivingLogic.currentIndex(stops, {'a', 'c'}), 1);
    expect(DrivingLogic.currentIndex(stops, {'a', 'b', 'c'}), isNull);
  });

  test('"Arrived" is offered within 60 m, with up to 40 m for a rough fix', () {
    expect(DrivingLogic.isNear(55), isTrue);
    expect(DrivingLogic.isNear(80), isFalse);
    expect(DrivingLogic.isNear(80, accuracy: 25), isTrue);
    expect(DrivingLogic.isNear(120, accuracy: 300), isFalse); // allowance capped
  });

  test('direction and distance read as a driver would say them', () {
    const northEast = LatLng(-45.8860, 170.5025);

    expect(DrivingLogic.direction(orari, northEast), 'north-east');
    expect(DrivingLogic.distanceLabel(612), '600 m');
    expect(DrivingLogic.distanceLabel(1430), '1.4 km');
    expect(DrivingLogic.spokenDistance(30), '30 metres');
  });

  test('what the voice says', () {
    final glass = stop(
      'a',
      note: 'Leave at the back door',
      items: const [
        StopItem(code: 'T2', product: 'Trim 2L', quantity: 2, crates: 0, loose: 2),
        StopItem(code: 'B1', product: 'Blue top 1L', quantity: 1, crates: 0, loose: 1),
      ],
    );

    expect(
      DrivingLogic.startLine('Run 3', 60, glass),
      'Starting Run 3. 60 stops. First: Otago Glass, 12 Orari Street.',
    );
    expect(
      DrivingLogic.nextLine(glass, meters: 612, direction: 'north-east'),
      'Next: Otago Glass, 12 Orari Street. 600 metres north-east.',
    );
    expect(
      DrivingLogic.approachLine(glass),
      'Approaching Otago Glass. 2 Trim 2L, 1 Blue top 1L. Leave at the back door.',
    );
    expect(DrivingLogic.doneLine(60), "That's all 60 delivered. Head back to the depot.");
  });
}
