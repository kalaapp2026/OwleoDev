import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nest_fe/features/enrolment/data/enrolment_api.dart';
import 'package:nest_fe/features/enrolment/data/person_details.dart';
import 'package:nest_fe/features/enrolment/presentation/widgets/existing_account_dialog.dart';

ExistingAccountProfile _profile() => ExistingAccountProfile(
      linkGrantId: 'grant-1',
      userId: 'user-1',
      username: 'diya',
      fullName: 'Diya Patel',
      phone: '+91 9845123456',
      email: 'diya@example.com',
      dob: DateTime(2015, 11, 3),
      details: const PersonDetails(),
      enrolments: const [],
    );

void main() {
  late int sends;
  late String correctCode;
  ExistingAccountProfile? result;
  bool closed = false;

  Future<void> open(WidgetTester tester, {String? sendError}) async {
    sends = 0;
    result = null;
    closed = false;
    correctCode = '123456';
    await tester.pumpWidget(MaterialApp(
      home: Builder(
        builder: (context) => Scaffold(
          body: TextButton(
            onPressed: () async {
              result = await showExistingAccountOtp(
                context,
                maskedName: 'D*** P***',
                onSend: () async {
                  sends++;
                  return sendError;
                },
                onVerify: (code) async => code == correctCode
                    ? (profile: _profile(), error: null)
                    : (profile: null, error: 'Incorrect OTP code'),
              );
              closed = true;
            },
            child: const Text('open'),
          ),
        ),
      ),
    ));
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
  }

  testWidgets('shows who was found without revealing their name, and sends the code on open',
      (tester) async {
    await open(tester);

    expect(find.text('Owleo account found'), findsOneWidget);
    expect(find.text('D*** P***'), findsOneWidget);
    expect(find.text('ENTER OTP'), findsOneWidget);
    expect(find.text('Resend OTP'), findsOneWidget);
    expect(find.text('Enter manually'), findsOneWidget);
    expect(sends, 1, reason: 'the code is posted as the dialog opens');
    // Nothing about the account beyond the masked name is on screen before the code is verified.
    expect(find.textContaining('Diya'), findsNothing);
  });

  testWidgets('a wrong code turns the dialog red and Retry clears it', (tester) async {
    await open(tester);

    await tester.enterText(find.byType(TextField), '555555');
    await tester.pumpAndSettle();

    expect(find.text('INCORRECT CODE'), findsOneWidget);
    expect(find.text('ENTER OTP'), findsNothing);
    expect(find.text('Retry'), findsOneWidget);
    expect(closed, isFalse);

    await tester.tap(find.text('Retry'));
    await tester.pumpAndSettle();

    expect(find.text('ENTER OTP'), findsOneWidget);
    expect(find.text('INCORRECT CODE'), findsNothing);
    expect(tester.widget<TextField>(find.byType(TextField)).controller!.text, isEmpty);
  });

  testWidgets('the right code confirms, then closes handing back the profile', (tester) async {
    await open(tester);

    await tester.enterText(find.byType(TextField), '123456');
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    // The check is instant, but "verifying" is held so the spinners are seen - not a flicker.
    expect(find.text('VERIFIED'), findsNothing);
    expect(find.byType(CircularProgressIndicator), findsWidgets);
    expect(closed, isFalse);

    await tester.pump(const Duration(milliseconds: 1000));
    await tester.pump(const Duration(milliseconds: 500));

    expect(find.text('VERIFIED'), findsOneWidget);
    // Now that they have agreed, the dialog may use their first name.
    expect(find.textContaining('Diya'), findsOneWidget);
    expect(closed, isFalse, reason: 'it lingers on the confirmation so the check can be seen');

    await tester.pump(const Duration(milliseconds: 1000));
    expect(closed, isFalse, reason: 'still on screen a second after confirming');

    await tester.pump(const Duration(milliseconds: 1500));
    await tester.pumpAndSettle();

    expect(closed, isTrue);
    expect(result?.linkGrantId, 'grant-1');
  });

  testWidgets('a wrong code is held for the same beat, then shakes', (tester) async {
    await open(tester);

    await tester.enterText(find.byType(TextField), '555555');
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.text('INCORRECT CODE'), findsNothing, reason: 'still verifying');

    await tester.pump(const Duration(milliseconds: 900));
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.text('INCORRECT CODE'), findsOneWidget);
    await tester.pumpAndSettle();
  });

  testWidgets('Enter manually closes with nothing, leaving the form to be filled by hand',
      (tester) async {
    await open(tester);

    await tester.tap(find.text('Enter manually'));
    await tester.pumpAndSettle();

    expect(closed, isTrue);
    expect(result, isNull);
  });

  testWidgets('Resend OTP posts the code again', (tester) async {
    await open(tester);

    await tester.tap(find.text('Resend OTP'));
    await tester.pumpAndSettle();

    expect(sends, 2);
  });

  testWidgets('a code that could not be sent says why', (tester) async {
    await open(tester, sendError: 'Too many OTP requests - try again later');

    expect(find.text('Too many OTP requests - try again later'), findsOneWidget);
  });
}
