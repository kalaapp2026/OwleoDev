import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nest_fe/app/theme/app_theme.dart';
import 'package:nest_fe/core/design/attached_select.dart';

Widget _host(Widget child) => MaterialApp(
      theme: AppTheme.dark,
      home: Scaffold(body: Padding(padding: const EdgeInsets.all(20), child: child)),
    );

AttachedSelect<String> _select({
  String label = 'Batch',
  String? value,
  List<String> options = const ['Morning 6AM', 'Evening 5PM', 'Weekend 10AM'],
  bool locked = false,
  bool enabled = true,
  bool searchable = false,
  bool? isOpen,
  ValueChanged<bool>? onOpenChanged,
  ValueChanged<String>? onSelected,
}) =>
    AttachedSelect<String>(
      label: label,
      value: value,
      options: options,
      labelOf: (s) => s,
      locked: locked,
      enabled: enabled,
      searchable: searchable,
      isOpen: isOpen,
      onOpenChanged: onOpenChanged,
      onSelected: onSelected ?? (_) {},
    );

void main() {
  group('AttachedSelect', () {
    testWidgets('opens on tap and reports the option count', (tester) async {
      await tester.pumpWidget(_host(_select()));
      expect(find.text('Morning 6AM'), findsNothing);

      await tester.tap(find.text('Select'));
      await tester.pumpAndSettle();

      expect(find.text('3 options'), findsOneWidget);
      expect(find.text('Morning 6AM'), findsOneWidget);
    });

    testWidgets('selecting an option closes the panel and reports the value', (tester) async {
      String? picked;
      await tester.pumpWidget(_host(_select(onSelected: (v) => picked = v)));
      await tester.tap(find.text('Select'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Evening 5PM'));
      await tester.pumpAndSettle();

      expect(picked, 'Evening 5PM');
      expect(find.text('3 options'), findsNothing);
    });

    testWidgets('tapping outside closes without selecting', (tester) async {
      String? picked;
      await tester.pumpWidget(_host(_select(onSelected: (v) => picked = v)));
      await tester.tap(find.text('Select'));
      await tester.pumpAndSettle();

      await tester.tapAt(const Offset(400, 560));
      await tester.pumpAndSettle();

      expect(find.text('3 options'), findsNothing);
      expect(picked, isNull);
    });

    testWidgets('locked refuses to open and shows a padlock, not a chevron', (tester) async {
      // Locked means "decided for you" - a fee type bound to exactly one batch - so the affordance
      // must not look merely unavailable.
      await tester.pumpWidget(_host(_select(value: 'Morning 6AM', locked: true)));
      expect(find.byIcon(Icons.lock_outline), findsOneWidget);
      expect(find.byIcon(Icons.keyboard_arrow_down_rounded), findsNothing);

      await tester.tap(find.text('Morning 6AM'));
      await tester.pumpAndSettle();
      expect(find.text('3 options'), findsNothing);
    });

    testWidgets('disabled refuses to open', (tester) async {
      await tester.pumpWidget(_host(_select(enabled: false)));
      await tester.tap(find.text('Select'));
      await tester.pumpAndSettle();
      expect(find.text('3 options'), findsNothing);
    });

    group('search', () {
      testWidgets('filters and shows the narrowed count against the total', (tester) async {
        await tester.pumpWidget(_host(_select(searchable: true)));
        await tester.tap(find.text('Select'));
        await tester.pumpAndSettle();

        await tester.tap(find.byIcon(Icons.search_rounded).last);
        await tester.pumpAndSettle();
        await tester.enterText(find.byType(TextField), 'week');
        await tester.pumpAndSettle();

        // "1 of 3" rather than "1 option" - it must be obvious the list is narrowed, not short.
        expect(find.text('1 of 3'), findsOneWidget);
        expect(find.text('Weekend 10AM'), findsOneWidget);
        expect(find.text('Morning 6AM'), findsNothing);
      });

      testWidgets('distinguishes no-match from a genuinely empty list', (tester) async {
        await tester.pumpWidget(_host(_select(searchable: true)));
        await tester.tap(find.text('Select'));
        await tester.pumpAndSettle();
        await tester.tap(find.byIcon(Icons.search_rounded).last);
        await tester.pumpAndSettle();
        await tester.enterText(find.byType(TextField), 'zzz');
        await tester.pumpAndSettle();

        expect(find.textContaining('No match for'), findsOneWidget);
        expect(find.text('No options'), findsNothing);
      });

      testWidgets('reopening starts with a cleared search', (tester) async {
        // A stale query would make the list look empty on reopen for no visible reason.
        await tester.pumpWidget(_host(_select(searchable: true)));
        await tester.tap(find.text('Select'));
        await tester.pumpAndSettle();
        await tester.tap(find.byIcon(Icons.search_rounded).last);
        await tester.pumpAndSettle();
        await tester.enterText(find.byType(TextField), 'zzz');
        await tester.pumpAndSettle();

        await tester.tapAt(const Offset(400, 560));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Select'));
        await tester.pumpAndSettle();

        expect(find.text('3 options'), findsOneWidget);
      });
    });

    testWidgets('empty option list says so rather than showing a bare panel', (tester) async {
      await tester.pumpWidget(_host(_select(options: const [])));
      await tester.tap(find.text('Select'));
      await tester.pumpAndSettle();
      expect(find.text('No options'), findsOneWidget);
    });

    group('controlled open state', () {
      testWidgets('two side-by-side selectors cannot both be open', (tester) async {
        // The reason controlled state exists: two overlapping panels are unreadable, and a
        // half-width trigger opening a double-width panel makes the overlap certain.
        String? openId;
        await tester.pumpWidget(_host(StatefulBuilder(
          builder: (context, setState) => Row(
            children: [
              Expanded(
                child: _select(
                  label: 'Course',
                  options: const ['Bharatanatyam'],
                  isOpen: openId == 'course',
                  onOpenChanged: (o) => setState(() => openId = o ? 'course' : null),
                ),
              ),
              Expanded(
                child: _select(
                  label: 'Batch',
                  options: const ['Batch A'],
                  isOpen: openId == 'batch',
                  onOpenChanged: (o) => setState(() => openId = o ? 'batch' : null),
                ),
              ),
            ],
          ),
        )));

        await tester.tap(find.text('Select').first);
        await tester.pumpAndSettle();
        expect(find.text('Bharatanatyam'), findsOneWidget);

        // The open panel's barrier absorbs the first tap, so switching to the neighbour takes two:
        // one to dismiss, one to open. Deliberate - a pass-through barrier would let a dismissing
        // tap also fire whatever sits underneath.
        await tester.tap(find.text('Select').last);
        await tester.pumpAndSettle();
        expect(find.text('Bharatanatyam'), findsNothing);

        await tester.tap(find.text('Select').last);
        await tester.pumpAndSettle();
        expect(find.text('Batch A'), findsOneWidget);
        expect(find.text('Bharatanatyam'), findsNothing);
      });

      testWidgets('a parent can close it without the user touching it', (tester) async {
        // An upstream cascade change (course switched) must be able to shut the batch panel.
        var open = true;
        late StateSetter setOuter;
        await tester.pumpWidget(_host(StatefulBuilder(builder: (context, setState) {
          setOuter = setState;
          return _select(isOpen: open, onOpenChanged: (o) => setState(() => open = o));
        })));
        await tester.pumpAndSettle();
        expect(find.text('3 options'), findsOneWidget);

        setOuter(() => open = false);
        await tester.pumpAndSettle();
        expect(find.text('3 options'), findsNothing);
      });
    });
  });
}
