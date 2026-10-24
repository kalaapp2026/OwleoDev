import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nest_fe/app/theme/app_theme.dart';
import 'package:nest_fe/features/fees/data/fee_roster.dart';
import 'package:nest_fe/features/fees/presentation/widgets/fee_profile_body.dart';

FeeLine _line(String id, String title, {num fee = 1000, num paid = 0, PaymentStatus? status}) => FeeLine(
      id: id,
      title: title,
      agreedFee: fee,
      paid: paid,
      balance: fee - paid,
      status: status ?? (paid >= fee ? PaymentStatus.paidManual : paid > 0 ? PaymentStatus.partial : PaymentStatus.notPaid),
    );

Widget _host(
  List<FeeLine> lines, {
  FeePayCallback? onPay,
  FeeEditCallback? onEdit,
  VoidCallback? onAddFee,
}) =>
    MaterialApp(
      theme: AppTheme.dark,
      home: Scaffold(
        body: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: FeeProfileBody(
            lines: lines,
            noun: 'fee types',
            selectPrompt: "Select which fee you're collecting payment for:",
            selectHint: 'Select a fee above to record a payment',
            settledText: 'Fully paid',
            onPay: onPay ?? (_, _, _, _) async {},
            onEdit: onEdit ?? (_, _) async {},
            onAddFee: onAddFee,
            addFeeLabel: 'Add fee',
          ),
        ),
      ),
    );

void main() {
  group('FeeProfileBody', () {
    testWidgets('the recorder offers Cash and UPI only - a gateway payment is the student paying online',
        (tester) async {
      await tester.pumpWidget(_host([_line('a', 'Costume Fee', fee: 750)]));

      expect(find.text('Cash'), findsOneWidget);
      expect(find.text('UPI'), findsOneWidget);
      expect(find.text('Gateway'), findsNothing);
    });

    testWidgets('a single fee is collectable without selecting it first', (tester) async {
      List<FeeLine>? paidFor;
      String? paidMode;
      await tester.pumpWidget(_host(
        [_line('a', 'Costume Fee', fee: 750)],
        onPay: (targets, mode, ref, partial) async {
          paidFor = targets;
          paidMode = mode;
        },
      ));

      await tester.tap(find.text('Mark as paid (₹750)'));
      await tester.pump();

      expect(paidFor!.single.id, 'a');
      expect(paidMode, 'CASH');
    });

    testWidgets('with several fees nothing is pre-selected, so nothing can be paid by accident',
        (tester) async {
      var paid = false;
      await tester.pumpWidget(_host(
        [_line('a', 'Costume Fee', fee: 750), _line('b', 'Audio Fee', fee: 300)],
        onPay: (_, _, _, _) async => paid = true,
      ));

      expect(find.text('Select a fee above to record a payment'), findsOneWidget);
      await tester.tap(find.textContaining('Mark as paid'), warnIfMissed: false);
      await tester.pump();
      expect(paid, isFalse);
    });

    testWidgets('selecting two fees combines them into one payment for their total', (tester) async {
      List<FeeLine>? paidFor;
      await tester.pumpWidget(_host(
        [_line('a', 'Costume Fee', fee: 750), _line('b', 'Audio Fee', fee: 300)],
        onPay: (targets, mode, ref, partial) async => paidFor = targets,
      ));

      // The breakdown opens from the headline card.
      await tester.tap(find.text('Balance still to be collected'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Costume Fee').first);
      await tester.pump();
      await tester.tap(find.text('Audio Fee').first);
      await tester.pump();

      expect(find.text('Mark 2 as paid (₹1,050)'), findsOneWidget);
      await tester.tap(find.text('Mark 2 as paid (₹1,050)'));
      await tester.pump();
      expect(paidFor!.map((l) => l.id), containsAll(['a', 'b']));
    });

    testWidgets('a settled fee reads as fully paid and offers no recorder', (tester) async {
      await tester.pumpWidget(_host([_line('a', 'Costume Fee', fee: 750, paid: 750)]));

      expect(find.text('Fully paid'), findsOneWidget);
      expect(find.text('Record a payment'), findsNothing);
    });

    testWidgets('a student with no fees can still be given their first one', (tester) async {
      var added = false;
      await tester.pumpWidget(_host(const [], onAddFee: () => added = true));

      await tester.tap(find.text('Add fee'));
      expect(added, isTrue);
    });
  });
}
