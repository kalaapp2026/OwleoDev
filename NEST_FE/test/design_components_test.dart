import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nest_fe/app/theme/app_theme.dart';
import 'package:nest_fe/core/design/charts.dart';
import 'package:nest_fe/core/design/confirm_dialog.dart';
import 'package:nest_fe/core/design/flip_toggle.dart';

Widget _host(Widget child) => MaterialApp(
      theme: AppTheme.dark,
      home: Scaffold(body: Center(child: child)),
    );

void main() {
  group('FlipToggle', () {
    testWidgets('swaps its label only after the halfway point', (tester) async {
      // The whole point of the flip is that the content changes while edge-on. If the label
      // swapped immediately the rotation would just look like a wobble.
      await tester.pumpWidget(_host(const FlipToggle(
        isOn: false, onLabel: 'Mark Not Paid', offLabel: 'Mark Paid',
      )));
      expect(find.text('Mark Paid'), findsOneWidget);

      await tester.pumpWidget(_host(const FlipToggle(
        isOn: true, onLabel: 'Mark Not Paid', offLabel: 'Mark Paid',
      )));
      // Mid-close: still showing the OLD label.
      await tester.pump(const Duration(milliseconds: 80));
      expect(find.text('Mark Paid'), findsOneWidget);

      // Past the swap, and settled.
      await tester.pumpAndSettle();
      expect(find.text('Mark Not Paid'), findsOneWidget);
      expect(find.text('Mark Paid'), findsNothing);
    });

    testWidgets('never rotates beyond 90 degrees, so the label is never mirrored', (tester) async {
      await tester.pumpWidget(_host(const FlipToggle(
        isOn: false, onLabel: 'On', offLabel: 'Off',
      )));
      await tester.pumpWidget(_host(const FlipToggle(
        isOn: true, onLabel: 'On', offLabel: 'Off',
      )));

      // Sample the rotation across the whole animation. A 0->180 flip would show the text
      // upside-down; this must stay within a quarter turn at every frame.
      for (var elapsed = 0; elapsed < 400; elapsed += 20) {
        await tester.pump(const Duration(milliseconds: 20));
        final transform = tester.widget<Transform>(find.byType(Transform).first).transform;
        // m[5] is the cos of the X rotation. Staying >= ~0 means |angle| <= 90 degrees.
        expect(transform.storage[5], greaterThanOrEqualTo(-0.001),
            reason: 'rotated past 90 degrees at ${elapsed}ms - label would render mirrored');
      }
    });
  });

  group('DonutChart', () {
    testWidgets('clamps out-of-range percentages', (tester) async {
      // Rounding upstream can produce 103%; the ring must not overdraw.
      await tester.pumpWidget(_host(const DonutChart(percent: 137)));
      await tester.pumpAndSettle();
      expect(find.text('100%'), findsOneWidget);
    });
  });

  group('AppProgressBar', () {
    testWidgets('survives a zero total instead of dividing by zero', (tester) async {
      // A batch with no students yet is a normal state, not an error.
      await tester.pumpWidget(_host(const AppProgressBar(paid: 0, total: 0)));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    });
  });

  group('showAppConfirmDialog', () {
    testWidgets('dismissing returns false, never null', (tester) async {
      // Every caller guards a destructive action; "dismissed" must read as "declined".
      bool? outcome;
      await tester.pumpWidget(_host(Builder(builder: (context) {
        return ElevatedButton(
          onPressed: () async {
            outcome = await showAppConfirmDialog(
              context: context, title: 'Undo?', message: 'Revert this payment?');
          },
          child: const Text('go'),
        );
      })));
      await tester.tap(find.text('go'));
      await tester.pumpAndSettle();

      // Tap the barrier to dismiss.
      await tester.tapAt(const Offset(10, 10));
      await tester.pumpAndSettle();
      expect(outcome, isFalse);
    });
  });
}
