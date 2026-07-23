// Minimal smoke test. A full app-boot test would need flutter_secure_storage's platform channel
// mocked (it throws MissingPluginException under plain widget tests) plus a fake Dio client -
// worth adding once there's a dedicated test-infrastructure pass; out of scope for now.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nest_fe/core/widgets/owleo_wordmark.dart';

void main() {
  testWidgets('OwleoWordmark renders the brand name', (WidgetTester tester) async {
    await tester.pumpWidget(const MaterialApp(home: Scaffold(body: OwleoWordmark())));

    expect(find.text('Owleo'), findsOneWidget);
    expect(find.text('NEST'), findsOneWidget);
  });
}
