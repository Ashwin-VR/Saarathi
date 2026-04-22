import 'package:flutter_test/flutter_test.dart';
import 'package:accident_app/main.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

void main() {
  testWidgets('App smoke test', (WidgetTester tester) async {
    // Build our app and trigger a frame.
    await tester.pumpWidget(const ProviderScope(child: AccidentApp()));
    expect(find.text('Emergency SOS'), findsNothing); // map screen loads
  });
}
