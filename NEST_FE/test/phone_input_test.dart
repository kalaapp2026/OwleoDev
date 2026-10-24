import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nest_fe/app/theme/app_theme.dart';
import 'package:nest_fe/core/design/app_text_field.dart';
import 'package:nest_fe/core/validation/countries.dart';
import 'package:nest_fe/core/validation/phone_rules.dart';

/// Hosts a PhoneInput the way a screen does: the screen owns the dial code and the digits.
class _Host extends StatefulWidget {
  const _Host({this.kind = PhoneKind.mobile, this.required = true, this.showErrors = false});

  final PhoneKind kind;
  final bool required;
  final bool showErrors;

  @override
  State<_Host> createState() => _HostState();
}

class _HostState extends State<_Host> {
  final controller = TextEditingController();
  final other = FocusNode();
  String dial = '+91';

  @override
  Widget build(BuildContext context) => MaterialApp(
        theme: AppTheme.light,
        home: Scaffold(
          body: SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: Column(
              children: [
                PhoneInput(
                  dial: dial,
                  controller: controller,
                  kind: widget.kind,
                  required: widget.required,
                  showErrors: widget.showErrors,
                  onDialChanged: (c) => setState(() => dial = c),
                ),
                // Somewhere for focus to go, so the phone field can lose it.
                TextField(focusNode: other, key: const Key('other')),
              ],
            ),
          ),
        ),
      );
}

void main() {
  final hostState = find.byType(_Host);

  Future<void> blur(WidgetTester tester) async {
    await tester.tap(find.byKey(const Key('other')));
    await tester.pump();
  }

  group('PhoneInput', () {
    testWidgets('starts on India and shows the digit count as its hint', (tester) async {
      await tester.pumpWidget(const _Host());
      expect(find.text('+91'), findsOneWidget);
      expect(find.text('10 digits'), findsOneWidget);
    });

    testWidgets('keeps only digits and stops at the country\'s length', (tester) async {
      await tester.pumpWidget(const _Host());
      await tester.enterText(find.byType(TextField).first, '98a-76 54321099999');
      await tester.pump();
      final text = tester.widget<TextField>(find.byType(TextField).first).controller!.text;
      expect(text, matches(RegExp(r'^[0-9]+$')));
      expect(text, '98765432109', reason: 'letters and dashes dropped, capped at 11 (10 plus a trunk 0)');
      expect(text.length, lessThanOrEqualTo(11));
    });

    testWidgets('says nothing while typing the first time, then explains once the field is left', (tester) async {
      await tester.pumpWidget(const _Host());
      await tester.enterText(find.byType(TextField).first, '98765');
      await tester.pump();
      expect(find.textContaining('digits.'), findsNothing);

      await blur(tester);
      expect(find.textContaining('10 digits'), findsWidgets);
    });

    testWidgets('the error clears as the number becomes valid', (tester) async {
      await tester.pumpWidget(const _Host());
      await tester.enterText(find.byType(TextField).first, '98765');
      await blur(tester);
      expect(find.textContaining('needs 10 digits'), findsOneWidget);

      await tester.enterText(find.byType(TextField).first, '9876543210');
      await tester.pump();
      expect(find.textContaining('needs 10 digits'), findsNothing);
    });

    testWidgets('showErrors reveals a missing required number without visiting the field', (tester) async {
      await tester.pumpWidget(const _Host(showErrors: true));
      expect(find.text('Enter a phone number.'), findsOneWidget);
    });

    testWidgets('an optional empty field shows no error even when errors are forced', (tester) async {
      await tester.pumpWidget(const _Host(showErrors: true, required: false, kind: PhoneKind.any));
      expect(find.text('Enter a phone number.'), findsNothing);
    });

    testWidgets('choosing the country first does not accuse a field nobody has typed in yet', (tester) async {
      await tester.pumpWidget(const _Host());
      await tester.tap(find.text('+91'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('United Arab Emirates'));
      await tester.pumpAndSettle();

      expect(find.text('Enter a phone number.'), findsNothing);
      expect(tester.state<_HostState>(hostState).dial, '+971');
      // ...and, once the sheet has closed, the cursor is in the digits ready to type - still with
      // no accusation.
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.text('Enter a phone number.'), findsNothing);
      final digits = tester.widget<TextField>(find.byType(TextField).first);
      expect(digits.focusNode!.hasFocus, isTrue);
    });

    testWidgets('tapping the code opens a searchable list of every country', (tester) async {
      await tester.pumpWidget(const _Host());
      await tester.tap(find.text('+91'));
      await tester.pumpAndSettle();

      expect(find.text('Search country or code'), findsOneWidget);
      expect(find.text('${Country.all.length} countries'.toUpperCase()), findsNothing); // shown in normal case
      expect(find.text('${Country.all.length} countries'), findsOneWidget);
      expect(find.text('POPULAR'), findsOneWidget);
      expect(find.text('India'), findsOneWidget);
    });

    testWidgets('searching by name, then choosing, switches the country code', (tester) async {
      await tester.pumpWidget(const _Host());
      await tester.tap(find.text('+91'));
      await tester.pumpAndSettle();

      await tester.enterText(find.widgetWithText(TextField, '').last, 'germany');
      await tester.pumpAndSettle();
      expect(find.text('Germany'), findsOneWidget);
      expect(find.text('India'), findsNothing);

      await tester.tap(find.text('Germany'));
      await tester.pumpAndSettle();
      expect(find.text('+49'), findsOneWidget);
      expect(tester.state<_HostState>(hostState).dial, '+49');
    });

    testWidgets('searching by calling code finds the country', (tester) async {
      await tester.pumpWidget(const _Host());
      await tester.tap(find.text('+91'));
      await tester.pumpAndSettle();
      await tester.enterText(find.widgetWithText(TextField, '').last, '+971');
      await tester.pumpAndSettle();
      expect(find.text('United Arab Emirates'), findsOneWidget);
    });

    testWidgets('a search with no match says so', (tester) async {
      await tester.pumpWidget(const _Host());
      await tester.tap(find.text('+91'));
      await tester.pumpAndSettle();
      await tester.enterText(find.widgetWithText(TextField, '').last, 'zzzz');
      await tester.pumpAndSettle();
      expect(find.textContaining('No country matches'), findsOneWidget);
    });

    testWidgets('choosing a shorter-numbered country trims what was typed', (tester) async {
      await tester.pumpWidget(const _Host());
      await tester.enterText(find.byType(TextField).first, '9876543210');
      await tester.tap(find.text('+91'));
      await tester.pumpAndSettle();
      await tester.enterText(find.widgetWithText(TextField, '').last, 'singapore');
      await tester.pumpAndSettle();
      await tester.tap(find.text('Singapore'));
      await tester.pumpAndSettle();

      final text = tester.widget<TextField>(find.byType(TextField).first).controller!.text;
      expect(text.length, lessThanOrEqualTo(PhoneRules.maxDigits('+65', iso: Country.forDial('+65')!.iso, kind: PhoneKind.mobile)));
    });

    testWidgets('pasting a full international number picks its country and keeps the digits', (tester) async {
      await tester.pumpWidget(const _Host());
      await tester.enterText(find.byType(TextField).first, '+44 7400 123456');
      await tester.pumpAndSettle();

      expect(tester.state<_HostState>(hostState).dial, '+44');
      expect(tester.widget<TextField>(find.byType(TextField).first).controller!.text, '7400123456');
    });
  });

  group('AppTextField with a preset', () {
    Widget host(TextEditingController c, {FieldPreset? preset, bool showErrors = false}) => MaterialApp(
          theme: AppTheme.light,
          home: Scaffold(
            body: Column(children: [
              AppTextField(controller: c, hint: 'field', preset: preset, showErrors: showErrors),
              TextField(key: const Key('other')),
            ]),
          ),
        );

    testWidgets('a name keeps what was typed and says what is wrong, instead of dropping keys silently', (tester) async {
      final c = TextEditingController();
      await tester.pumpWidget(host(c, preset: FieldPreset.personName(label: 'first name')));
      await tester.enterText(find.byType(TextField).first, 'Aarav123 @Shah!');
      expect(c.text, 'Aarav123 @Shah!', reason: 'nothing is silently removed');

      await tester.tap(find.byKey(const Key('other')));
      await tester.pump();
      expect(find.text('A first name can only have letters and spaces - no numbers or symbols.'), findsOneWidget);
    });

    testWidgets('a name with only letters shows no error', (tester) async {
      final c = TextEditingController();
      await tester.pumpWidget(host(c, preset: FieldPreset.personName(label: 'first name')));
      await tester.enterText(find.byType(TextField).first, 'Aarav Shah');
      await tester.tap(find.byKey(const Key('other')));
      await tester.pump();
      expect(find.textContaining('can only have letters'), findsNothing);
    });

    testWidgets('an email preset refuses spaces', (tester) async {
      final c = TextEditingController();
      await tester.pumpWidget(host(c, preset: FieldPreset.email()));
      await tester.enterText(find.byType(TextField).first, 'a b@c.com');
      expect(c.text, 'ab@c.com');
    });

    testWidgets('an amount preset takes at most two decimals', (tester) async {
      final c = TextEditingController();
      await tester.pumpWidget(host(c, preset: FieldPreset.amount()));
      await tester.enterText(find.byType(TextField).first, '1500.567');
      expect(c.text, isNot('1500.567'));
      await tester.enterText(find.byType(TextField).first, '1500.50');
      expect(c.text, '1500.50');
    });

    testWidgets('shows the rule\'s message after the field is left', (tester) async {
      final c = TextEditingController();
      await tester.pumpWidget(host(c, preset: FieldPreset.email()));
      await tester.enterText(find.byType(TextField).first, 'nope');
      await tester.pump();
      expect(find.text('That email address looks incomplete.'), findsNothing);

      await tester.tap(find.byKey(const Key('other')));
      await tester.pump();
      expect(find.text('That email address looks incomplete.'), findsOneWidget);
    });

    testWidgets('showErrors reveals it immediately', (tester) async {
      final c = TextEditingController();
      await tester.pumpWidget(host(c, preset: FieldPreset.email(), showErrors: true));
      expect(find.text('Enter an email address.'), findsOneWidget);
    });

    testWidgets('without a rule it is just a styled field', (tester) async {
      final c = TextEditingController();
      await tester.pumpWidget(host(c, showErrors: true));
      await tester.enterText(find.byType(TextField).first, 'anything at all');
      await tester.pump();
      expect(c.text, 'anything at all');
    });
  });
}
