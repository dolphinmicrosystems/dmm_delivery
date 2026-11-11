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
    expect(DrivingLogic.approachLine(glass), 'Approaching Otago Glass.');
    expect(
      DrivingLogic.arriveLine(glass),
      'You have arrived at Otago Glass. Deliver 2 Trim 2L, 1 Blue top 1L. Leave at the back door.',
    );
    expect(DrivingLogic.leftLine(glass), 'Did you deliver to Otago Glass?');
    expect(DrivingLogic.doneLine(60), "That's all 60 delivered. Head back to the depot.");
  });

  group('driving away from a stop', () {
    test('standing at a stop counts; driving past it does not', () {
      expect(DrivingLogic.hasStoppedAt(30, accuracy: 10, speed: 0.2), isTrue);
      expect(DrivingLogic.hasStoppedAt(30, accuracy: 10, speed: 12), isFalse);
      expect(DrivingLogic.hasStoppedAt(400, speed: 0), isFalse);
      // A phone that reports no speed is taken at its position.
      expect(DrivingLogic.hasStoppedAt(30), isTrue);
    });

    test('leaving means well clear, not GPS drift at the kerb', () {
      expect(DrivingLogic.hasLeft(90), isFalse);
      expect(DrivingLogic.hasLeft(160), isTrue);
      expect(DrivingLogic.hasLeft(160, accuracy: 30), isFalse);
      expect(DrivingLogic.hasLeft(200, accuracy: 500), isTrue);
    });
  });

  group('delivering out of order', () {
    const ids = ['s1', 's2', 's3', 's4', 's5'];

    test('in order, the next stop is simply the next', () {
      expect(DrivingLogic.nextAfterDelivery(ids, {}, 's1'), 's2');
      expect(DrivingLogic.nextAfterDelivery(ids, {'s1', 's2', 's3', 's4'}, 's5'), isNull);
    });

    test('after jumping ahead, the nearer of the skipped stop and the one after wins', () {
      // Did s3 first. s4 is 200 m on, s1 is 3 km back: carry on.
      final carryOn = DrivingLogic.nextAfterDelivery(
        ids,
        {},
        's3',
        metersTo: (id) => id == 's4' ? 200 : 3000,
      );
      expect(carryOn, 's4');
      // Did s3 on the way past; s1 is right here: go back for it.
      final goBack = DrivingLogic.nextAfterDelivery(ids, {}, 's3', metersTo: (id) => id == 's1' ? 150 : 900);
      expect(goBack, 's1');
      // No position to judge by: the planned order.
      expect(DrivingLogic.nextAfterDelivery(ids, {}, 's3'), 's1');
    });

    test('after the last stop in order, the skipped ones are what is left', () {
      expect(DrivingLogic.nextAfterDelivery(ids, {'s3', 's4'}, 's5', metersTo: (_) => 100), 's1');
    });

    test('the road ahead starts at the stop being driven to, then the planned order', () {
      expect(DrivingLogic.remainingOrder(ids, {'s3'}, 's4'), ['s4', 's1', 's2', 's5']);
      expect(DrivingLogic.remainingOrder(ids, {'s1'}, 's2'), ['s2', 's3', 's4', 's5']);
      expect(DrivingLogic.remainingOrder(ids, {'s1'}, null), ['s2', 's3', 's4', 's5']);
    });
  });

  test('a very long way reads as whole kilometres', () {
    expect(DrivingLogic.distanceLabel(1400), '1.4 km');
    expect(DrivingLogic.distanceLabel(11426000), '11,426 km');
  });
}
