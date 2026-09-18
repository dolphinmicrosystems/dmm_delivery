import 'package:dmm_delivery/models/run_stop.dart';
import 'package:dmm_delivery/models/stop_search.dart';
import 'package:dmm_delivery/widgets/stop_search_delegate.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';

RunStop _stop(String name, String address, {String? order, String? phone, List<String> products = const []}) =>
    RunStop(
      id: name,
      seqOrder: 0,
      customerName: name,
      address: address,
      location: const LatLng(-45.88, 170.50),
      orderNumber: order,
      phone: phone,
      items: [
        for (final product in products) StopItem(code: '80', product: product, quantity: 1, crates: 0, loose: 0),
      ],
    );

// Customers and addresses from the South Runsheet, in route order.
final _run = [
  _stop('Cooke Howlison Toyota', '500 Andersons Bay Road, South Dunedin', order: '122000'),
  _stop('Cooke Howlison Toyota Service Lounge', '500 Andersons Bay Road, South Dunedin'),
  _stop('Otago Glass', '18 Orari Street, South Dunedin', products: ['1 L Trim Milk']),
  _stop('Wood Solutions', '5 Orari Street, South Dunedin'),
  _stop('Mitre 10 Mega Dunedin', '20 Timaru Street, South Dunedin', phone: '027 455 1234'),
  _stop('Toyota Parts Direct', '9 Orari Street, South Dunedin'),
];

List<String> _names(String query) => [for (final m in searchStops(_run, query)) m.stop.customerName];

void main() {
  test('an empty query finds nothing rather than everything', () {
    expect(searchStops(_run, '   '), isEmpty);
  });

  test('matches customer names regardless of case', () {
    expect(_names('otago glass'), ['Otago Glass']);
  });

  test('every word must match, so a street and a number narrow to one stop', () {
    expect(_names('orari 18'), ['Otago Glass']);
    expect(_names('orari'), ['Otago Glass', 'Wood Solutions', 'Toyota Parts Direct']);
  });

  test('extra words narrow a common name', () {
    expect(_names('toyota service'), ['Cooke Howlison Toyota Service Lounge']);
  });

  test('a name that starts with the query ranks first, then route order', () {
    expect(_names('toyota'), ['Toyota Parts Direct', 'Cooke Howlison Toyota', 'Cooke Howlison Toyota Service Lounge']);
  });

  test('finds by order number, phone and product', () {
    expect(_names('122000'), ['Cooke Howlison Toyota']);
    expect(_names('0274551234'), ['Mitre 10 Mega Dunedin']);
    expect(_names('trim milk'), ['Otago Glass']);
  });

  test('ignores spacing and punctuation', () {
    expect(_names('mitre10'), ['Mitre 10 Mega Dunedin']);
  });

  test('reports each match with its position in the route', () {
    final match = searchStops(_run, 'wood').single;
    expect(match.index, 3);
  });

  testWidgets('picking a result returns that stop\'s position in the route', (tester) async {
    int? picked = -1;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => TextButton(
            onPressed: () async => picked = await searchForStop(context, _run),
            child: const Text('search'),
          ),
        ),
      ),
    );

    await tester.tap(find.text('search'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'wood');
    await tester.pumpAndSettle();
    await tester.tap(find.text('Wood Solutions'));
    await tester.pumpAndSettle();

    expect(picked, 3);
  });

  testWidgets('backing out returns nothing', (tester) async {
    int? picked = -1;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => TextButton(
            onPressed: () async => picked = await searchForStop(context, _run),
            child: const Text('search'),
          ),
        ),
      ),
    );

    await tester.tap(find.text('search'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Back'));
    await tester.pumpAndSettle();

    expect(picked, isNull);
  });
}
