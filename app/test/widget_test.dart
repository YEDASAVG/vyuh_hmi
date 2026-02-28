import 'package:flutter_test/flutter_test.dart';

import 'package:app/main.dart';

void main() {
  testWidgets('HmiApp smoke test', (WidgetTester tester) async {
    await tester.pumpWidget(const HmiApp());
    expect(find.text('Dashboard'), findsWidgets);
  });
}
