import 'package:flutter_test/flutter_test.dart';
import 'package:pockyh/main.dart';

void main() {
  testWidgets('App renders splash screen', (WidgetTester tester) async {
    await tester.pumpWidget(const PockyhApp());
    expect(find.text('pockyh'), findsOneWidget);
  });
}
