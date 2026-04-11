import 'package:flutter_test/flutter_test.dart';
import 'package:classbyte/main.dart';

void main() {
  testWidgets('App renders with tab bar', (WidgetTester tester) async {
    await tester.pumpWidget(const ClassByteApp());
    await tester.pumpAndSettle();
    expect(find.text('Speisekarte'), findsWidgets);
  });
}
