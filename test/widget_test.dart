import 'package:flutter_test/flutter_test.dart';

import 'package:dmm_delivery/main.dart';

void main() {
  testWidgets('Customer home renders and role switch reaches rider orders', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(const MyApp());

    expect(find.text('Where to?'), findsOneWidget);

    await tester.tap(find.text('Rider'));
    await tester.pumpAndSettle();

    expect(find.text('Orders'), findsWidgets);
    expect(find.text('Accept order'), findsWidgets);
  });

  testWidgets('Accepting an order moves it to the Active tab', (WidgetTester tester) async {
    await tester.pumpWidget(const MyApp());

    await tester.tap(find.text('Rider'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Accept order').first);
    await tester.pumpAndSettle();

    expect(find.textContaining('In transit'), findsOneWidget);

    await tester.scrollUntilVisible(find.text('Mark as delivered'), 300);
    expect(find.text('Mark as delivered'), findsOneWidget);
  });
}
