import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nest_fe/app/theme/app_theme.dart';
import 'package:nest_fe/features/events/presentation/event_common.dart';

void main() {
  testWidgets('the event menu button sits flush at the right edge of its padded card', (tester) async {
    await tester.pumpWidget(MaterialApp(
      theme: AppTheme.dark,
      home: Scaffold(
        body: Align(
          alignment: Alignment.topLeft,
          child: Container(
            key: const Key('card'),
            width: 360,
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                const Text('In-house'),
                const Spacer(),
                EventMenuButton(cancelled: false, includeEdit: false, onSelected: (_) {}),
              ],
            ),
          ),
        ),
      ),
    ));

    final card = tester.getRect(find.byKey(const Key('card')));
    final button = tester.getRect(find.byType(EventMenuButton));

    // The button is its drawn 30x30 square and nothing more: its right edge is the card's content
    // edge (card right minus the 16px padding), with no hidden tap-target margin pushing it left.
    expect(button.width, 30);
    expect(button.right, card.right - 16);
  });
}
