import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nest_fe/app/theme/app_theme.dart';
import 'package:nest_fe/core/design/app_date_picker.dart';
import 'package:nest_fe/core/design/calendar_modal.dart';

Future<void> openPicker(WidgetTester tester, DateTime? value) async {
  tester.view.physicalSize = const Size(900, 1600);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(MaterialApp(
    theme: AppTheme.light,
    home: Scaffold(
      body: Builder(
        builder: (context) => TextButton(
          onPressed: () => showAppDatePicker(context: context, title: 'Date of birth', value: value, maxDate: DateTime.now()),
          child: const Text('open'),
        ),
      ),
    ),
  ));
  await tester.tap(find.text('open'));
  await tester.pumpAndSettle();
}

/// Day view -> month view -> year view, by tapping the header each time.
Future<void> openYearList(WidgetTester tester, int year) async {
  await tester.tap(find.textContaining('$year').first); // "May 1996" opens the month view
  await tester.pumpAndSettle();
  await tester.tap(find.text('$year').first); // the year in the month view opens the year list
  await tester.pumpAndSettle();
  expect(find.text('Select year'), findsOneWidget);
}

void main() {
  final thisYear = DateTime.now().year;

  testWidgets('the year list opens on this year, at the bottom, and older years are a scroll up', (tester) async {
    await openPicker(tester, null);
    await openYearList(tester, thisYear);

    expect(find.text('$thisYear'), findsWidgets, reason: 'opens showing this year');
    final latest = tester.getTopLeft(find.text('$thisYear').last).dy;
    final previous = tester.getTopLeft(find.text('${thisYear - 1}')).dy;
    expect(previous, lessThan(latest), reason: 'last year is above this year: older years are up');
    expect(find.text('${thisYear - 100}'), findsNothing, reason: 'the oldest years are a long scroll up');

    // Scrolling UP reaches earlier years.
    await tester.drag(find.text('${thisYear - 1}'), const Offset(0, 250));
    await tester.pumpAndSettle();
    expect(find.text('${thisYear - 6}'), findsOneWidget, reason: 'dragging down the screen shows older years');
  });

  testWidgets('a year far back opens in view, in the middle, not out of sight', (tester) async {
    await openPicker(tester, DateTime(1996, 5, 10));
    await openYearList(tester, 1996);

    expect(find.text('1996'), findsOneWidget, reason: 'the browsed year is on screen');
    // ...with its neighbours either side, older above and newer below.
    final above = tester.getTopLeft(find.text('1995')).dy;
    final here = tester.getTopLeft(find.text('1996')).dy;
    final below = tester.getTopLeft(find.text('1997')).dy;
    expect(above, lessThan(here));
    expect(here, lessThan(below));
  });

  calendarGridTests();

  testWidgets('choosing a year from the list goes back to its months', (tester) async {
    await openPicker(tester, DateTime(1996, 5, 10));
    await openYearList(tester, 1996);
    await tester.tap(find.text('1995'));
    await tester.pumpAndSettle();
    expect(find.text('Select year'), findsNothing);
    expect(find.text('1995'), findsWidgets);
  });
}

/// The app's other calendar (showAppCalendar) has a year grid that behaves the same way.
void calendarGridTests() {
  final thisYear = DateTime.now().year;

  testWidgets('the calendar\'s year grid opens on the latest year, with earlier ones above', (tester) async {
    tester.view.physicalSize = const Size(900, 1600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MaterialApp(
      theme: AppTheme.light,
      home: Scaffold(
        body: Builder(
          builder: (context) => TextButton(
            onPressed: () => showAppCalendar(
              context: context,
              month: DateTime(thisYear, 3),
              earliestMonth: DateTime(thisYear - 100, 1),
              latestMonth: DateTime(thisYear, 12),
            ),
            child: const Text('open'),
          ),
        ),
      ),
    ));
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    await tester.tap(find.textContaining('$thisYear').first); // March 2026 -> month grid
    await tester.pumpAndSettle();
    await tester.tap(find.text('$thisYear').first);           // the year -> year grid
    await tester.pumpAndSettle();

    final latest = tester.getTopLeft(find.text('$thisYear').last);
    final before = tester.getTopLeft(find.text('${thisYear - 1}'));
    expect(latest.dy, greaterThanOrEqualTo(before.dy), reason: 'this year is on the last row, last year on or above it');
    expect(before.dy < latest.dy || before.dx < latest.dx, isTrue, reason: 'last year comes before this year in reading order');
    expect(find.text('${thisYear - 100}'), findsNothing, reason: 'the oldest year is a long scroll up');
  });
}
