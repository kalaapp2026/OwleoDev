import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nest_fe/core/auth/account_store.dart' show SavedAccount;
import 'package:nest_fe/core/auth/membership_summary.dart';
import 'package:nest_fe/core/auth/role_switch.dart';
import 'package:nest_fe/core/auth/session_controller.dart';
import 'package:nest_fe/core/auth/session_state.dart';
import 'package:nest_fe/core/auth/user_profile.dart';
import 'package:nest_fe/features/profile/presentation/account_switcher_sheet.dart' show savedAccountsProvider, showAccountMenu;
import 'package:nest_fe/features/profile/presentation/role_switch_card.dart';

MembershipSummary _membership(String id, String academyId, String role) => MembershipSummary(
      membershipId: id,
      academyId: academyId,
      academyName: academyId == 'a1' ? 'Samarpanam' : 'Sangeetha',
      roleType: role,
      status: 'ACTIVE',
      features: const {},
      courseIds: const {},
    );

UserProfile _user(List<MembershipSummary> memberships, String activeId) => UserProfile(
      id: 'u1',
      username: 'sushmitha',
      fullName: 'Sushmitha K',
      maskedPhone: null,
      email: null,
      city: null,
      state: null,
      role: 'STUDENT',
      temporaryPassword: false,
      themePreference: ThemePreference.system,
      languagePreference: 'en',
      memberships: memberships,
      activeMembershipId: activeId,
      profileImageUrl: null,
    );

/// A session that starts signed in and records which membership it was switched to.
class _FakeSession extends SessionController {
  _FakeSession(this.initial);
  final UserProfile initial;
  String? switchedTo;
  String? switchedAccountTo;

  @override
  Future<void> switchAccount(String userId) async {
    switchedAccountTo = userId;
  }

  @override
  SessionState build() => SessionState.authenticated(initial);

  @override
  void switchActiveMembership(String membershipId) {
    switchedTo = membershipId;
    state = SessionState.authenticated(_user(initial.memberships, membershipId));
  }
}

void main() {
  accountMenuTests();
  academyChoiceTests();
  Future<_FakeSession> pump(WidgetTester tester, UserProfile user) async {
    final fake = _FakeSession(user);
    await tester.pumpWidget(ProviderScope(
      overrides: [sessionControllerProvider.overrideWith(() => fake)],
      child: const MaterialApp(home: Scaffold(body: RoleSwitchCard())),
    ));
    await tester.pump();
    return fake;
  }

  testWidgets('shows the switch for someone who is both a student and a trainer at this academy',
      (tester) async {
    await pump(tester, _user([_membership('m-student', 'a1', 'STUDENT'), _membership('m-trainer', 'a1', 'TRAINER')], 'm-student'));

    expect(find.text('Switch role'), findsOneWidget);
    expect(find.text('Student'), findsOneWidget);
    expect(find.text('Trainer'), findsOneWidget);
    expect(find.textContaining('Samarpanam'), findsOneWidget);
  });

  testWidgets('tapping the other role switches to that membership and signals the shell', (tester) async {
    final fake = await pump(
        tester, _user([_membership('m-student', 'a1', 'STUDENT'), _membership('m-trainer', 'a1', 'TRAINER')], 'm-student'));
    final container = ProviderScope.containerOf(tester.element(find.byType(RoleSwitchCard)));
    expect(container.read(roleSwitchTickProvider), 0);

    await tester.tap(find.text('Trainer'));
    await tester.pump();

    expect(fake.switchedTo, 'm-trainer');
    expect(container.read(roleSwitchTickProvider), 1, reason: 'the shell goes back to the Dashboard');
    expect(find.textContaining('as a trainer'), findsOneWidget, reason: 'a toast says which role is now in use');

    // Let the toast's dismiss timer run out so nothing is left pending.
    await tester.pump(const Duration(seconds: 3));
  });

  testWidgets('tapping the role already in use does nothing', (tester) async {
    final fake = await pump(
        tester, _user([_membership('m-student', 'a1', 'STUDENT'), _membership('m-trainer', 'a1', 'TRAINER')], 'm-student'));
    final container = ProviderScope.containerOf(tester.element(find.byType(RoleSwitchCard)));

    await tester.tap(find.text('Student'));
    await tester.pump();

    expect(fake.switchedTo, isNull);
    expect(container.read(roleSwitchTickProvider), 0);
  });

  testWidgets('is hidden when there is only one role', (tester) async {
    await pump(tester, _user([_membership('m-student', 'a1', 'STUDENT')], 'm-student'));

    expect(find.text('Switch role'), findsNothing);
  });

  testWidgets('is hidden when the two memberships are at different academies', (tester) async {
    // That is the academy switcher's job, not a role switch.
    await pump(tester, _user([_membership('m-student', 'a1', 'STUDENT'), _membership('m-trainer', 'a2', 'TRAINER')], 'm-student'));

    expect(find.text('Switch role'), findsNothing);
  });
}

/// The avatar menu: name, role badge with academy, View profile, and the switch for two-role people.
void accountMenuTests() {
  Future<_FakeSession> openMenu(WidgetTester tester, UserProfile user,
      {VoidCallback? onOpenProfile, List<SavedAccount> accounts = const []}) async {
    final fake = _FakeSession(user);
    await tester.pumpWidget(ProviderScope(
      overrides: [
        sessionControllerProvider.overrideWith(() => fake),
        // The real list comes from secure storage, which a unit test doesn't have.
        savedAccountsProvider.overrideWith((ref) async => accounts),
      ],
      child: MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () => showAccountMenu(context, onOpenProfile: onOpenProfile ?? () {}),
              child: const Text('avatar'),
            ),
          ),
        ),
      ),
    ));
    await tester.tap(find.text('avatar'));
    await tester.pumpAndSettle();
    return fake;
  }

  group('avatar menu', () {
    testWidgets('shows who you are, and offers the other role to someone who holds both', (tester) async {
      await openMenu(tester,
          _user([_membership('m-student', 'a1', 'STUDENT'), _membership('m-trainer', 'a1', 'TRAINER')], 'm-student'));

      expect(find.text('Sushmitha K'), findsOneWidget);
      expect(find.text('Student'), findsOneWidget);
      expect(find.text('at Samarpanam'), findsOneWidget);
      expect(find.text('View profile'), findsOneWidget);
      expect(find.text('Switch to Trainer view'), findsOneWidget);
    });

    testWidgets('from the trainer role it offers the student view', (tester) async {
      await openMenu(tester,
          _user([_membership('m-student', 'a1', 'STUDENT'), _membership('m-trainer', 'a1', 'TRAINER')], 'm-trainer'));

      expect(find.text('Trainer'), findsOneWidget);
      expect(find.text('Switch to Student view'), findsOneWidget);
    });

    testWidgets('has no switch for someone with a single role', (tester) async {
      await openMenu(tester, _user([_membership('m-student', 'a1', 'STUDENT')], 'm-student'));

      expect(find.text('View profile'), findsOneWidget);
      expect(find.textContaining('Switch to'), findsNothing);
    });

    testWidgets('tapping the switch changes role and closes the menu', (tester) async {
      final fake = await openMenu(tester,
          _user([_membership('m-student', 'a1', 'STUDENT'), _membership('m-trainer', 'a1', 'TRAINER')], 'm-student'));

      await tester.tap(find.text('Switch to Trainer view'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));

      expect(fake.switchedTo, 'm-trainer');
      expect(find.text('View profile'), findsNothing, reason: 'the menu closed');
      await tester.pump(const Duration(seconds: 3)); // the toast's dismiss timer
    });

    testWidgets('lists the other saved logins and Add account under the role switch', (tester) async {
      final fake = await openMenu(
        tester,
        _user([_membership('m-student', 'a1', 'STUDENT'), _membership('m-trainer', 'a1', 'TRAINER')], 'm-student'),
        accounts: const [
          SavedAccount(userId: 'u1', username: 'sushmitha', fullName: 'Sushmitha K', accessToken: 't', refreshToken: 'r'),
          SavedAccount(userId: 'u2', username: 'ishaan', fullName: 'Ishaan Verma', accessToken: 't', refreshToken: 'r'),
        ],
      );

      // Both are there together: the role switch (same person) and the other accounts (other people).
      expect(find.text('Switch to Trainer view'), findsOneWidget);
      expect(find.text('SWITCH ACCOUNT'), findsOneWidget);
      expect(find.text('Ishaan Verma'), findsOneWidget);
      expect(find.text('@ishaan'), findsOneWidget);
      expect(find.text('Add account'), findsOneWidget);
      // The signed-in person is not offered as someone to switch to.
      expect(find.text('@sushmitha'), findsNothing);

      await tester.tap(find.text('Ishaan Verma'));
      await tester.pumpAndSettle();
      expect(fake.switchedAccountTo, 'u2');
    });

    testWidgets('with no other saved logins it still offers Add account', (tester) async {
      await openMenu(tester, _user([_membership('m-student', 'a1', 'STUDENT')], 'm-student'));

      expect(find.text('ACCOUNTS'), findsOneWidget);
      expect(find.text('Add account'), findsOneWidget);
    });

    testWidgets('View profile calls through and closes the menu', (tester) async {
      var opened = false;
      await openMenu(tester, _user([_membership('m-student', 'a1', 'STUDENT')], 'm-student'),
          onOpenProfile: () => opened = true);

      await tester.tap(find.text('View profile'));
      await tester.pumpAndSettle();

      expect(opened, isTrue);
      expect(find.text('View profile'), findsNothing);
    });
  });
}

/// The academy switcher lists academies, not roles - the student/trainer switch is separate.
void academyChoiceTests() {
  group('academy switcher', () {
    final student = _membership('m-student', 'a1', 'STUDENT');
    final trainer = _membership('m-trainer', 'a1', 'TRAINER');
    final otherStudent = _membership('m-other-student', 'a2', 'STUDENT');
    final otherTrainer = _membership('m-other-trainer', 'a2', 'TRAINER');

    test('two roles at one academy is still one academy - nothing to switch', () {
      final user = _user([student, trainer], 'm-student');

      expect(user.hasMultipleAcademies, isFalse);
      expect(user.academyChoices.map((m) => m.membershipId), ['m-student']);
    });

    test('lists each academy once, with the membership you are currently using for yours', () {
      final user = _user([student, trainer, otherStudent], 'm-trainer');

      expect(user.hasMultipleAcademies, isTrue);
      // Your own academy shows the role you are in right now (trainer), not the first one found.
      expect(user.academyChoices.map((m) => m.membershipId), ['m-trainer', 'm-other-student']);
    });

    test('moving academy keeps your role where the other academy has it', () {
      final user = _user([student, trainer, otherStudent, otherTrainer], 'm-trainer');

      expect(user.academyChoices.map((m) => m.membershipId), ['m-trainer', 'm-other-trainer']);
    });

    test('falls back to the first role there when the other academy lacks yours', () {
      final user = _user([student, trainer, otherStudent], 'm-trainer');

      expect(user.academyChoices.last.membershipId, 'm-other-student');
    });
  });
}
