import 'package:flutter_test/flutter_test.dart';
import 'package:nest_fe/features/fees/data/fee_roster.dart';
import 'package:nest_fe/features/fees/data/student_fee_profile.dart';

Map<String, dynamic> _course({
  required String id,
  required String name,
  num agreedFee = 1000,
  num totalPaid = 0,
  num? balance,
  String status = 'NOT_PAID',
  String? batchName,
}) =>
    {
      'courseId': id,
      'courseName': name,
      'batchName': batchName,
      'agreedFee': agreedFee,
      'totalPaid': totalPaid,
      'balance': balance ?? (agreedFee - totalPaid),
      'status': status,
    };

StudentFeeProfile _profile(List<Map<String, dynamic>> courses, {num? totals}) =>
    StudentFeeProfile.fromJson({
      'membershipId': 'm1',
      'studentName': 'Savish Holla',
      'period': '2026-08',
      'totalAgreedFee': courses.fold<num>(0, (s, c) => s + (c['agreedFee'] as num)),
      'totalPaid': courses.fold<num>(0, (s, c) => s + (c['totalPaid'] as num)),
      'totalBalance': totals ?? 0,
      'courses': courses,
    });

void main() {
  group('outstanding', () {
    test('an overpaid course cannot cancel out an unpaid one', () {
      // Summing raw balances would net -200 against 1000 and show 800 owing when 1000 is. Real
      // enough to guard: an admin correcting an amount downward after payment leaves a negative.
      final profile = _profile([
        _course(id: 'c1', name: 'Guitar', agreedFee: 800, totalPaid: 1000, balance: -200,
            status: 'PAID_MANUAL'),
        _course(id: 'c2', name: 'Piano', agreedFee: 1000, totalPaid: 0, balance: 1000),
      ]);

      expect(profile.outstanding, 1000);
    });

    test('is zero when everything is settled', () {
      final profile = _profile([
        _course(id: 'c1', name: 'Guitar', totalPaid: 1000, balance: 0, status: 'PAID_MANUAL'),
      ]);
      expect(profile.outstanding, 0);
    });
  });

  group('CourseFeeRow.outstanding', () {
    test('never goes negative, so a mark-paid cannot offer to take money back', () {
      final row = CourseFeeRow.fromJson(
          _course(id: 'c1', name: 'Guitar', agreedFee: 800, totalPaid: 1000, balance: -200));
      expect(row.balance, -200);
      expect(row.outstanding, 0);
    });

    test('is the balance when money is genuinely owed', () {
      final row = CourseFeeRow.fromJson(
          _course(id: 'c1', name: 'Guitar', agreedFee: 1000, totalPaid: 400, balance: 600));
      expect(row.outstanding, 600);
    });
  });

  group('hasBreakdown', () {
    test('one course needs no choosing', () {
      // With a single enrolment there is no decision to make, so the screen collects against it
      // directly instead of demanding a tick first.
      expect(_profile([_course(id: 'c1', name: 'Guitar')]).hasBreakdown, isFalse);
    });

    test('two courses means the admin must pick which one they are collecting for', () {
      final profile = _profile([
        _course(id: 'c1', name: 'Guitar'),
        _course(id: 'c2', name: 'Piano'),
      ]);
      expect(profile.hasBreakdown, isTrue);
      expect(profile.courses, hasLength(2));
    });

    test('no enrolments at all is not a breakdown', () {
      expect(_profile([]).hasBreakdown, isFalse);
      expect(_profile([]).outstanding, 0);
    });
  });

  group('CourseFeeRow parsing', () {
    test('carries the batch as context and the status as derived', () {
      final row = CourseFeeRow.fromJson(_course(
        id: 'c1',
        name: 'Bharatanatyam',
        batchName: 'Batch D',
        agreedFee: 1100,
        totalPaid: 600,
        balance: 500,
        status: 'PARTIAL',
      ));

      expect(row.courseName, 'Bharatanatyam');
      expect(row.batchName, 'Batch D');
      expect(row.status, PaymentStatus.partial);
      expect(row.isSettled, isFalse);
      expect(row.outstanding, 500);
    });

    test('a closed period reads as settled even with a balance left', () {
      // Closing writes the shortfall off; it is not still owed.
      final row = CourseFeeRow.fromJson(_course(
        id: 'c1',
        name: 'Guitar',
        agreedFee: 1000,
        totalPaid: 400,
        balance: 600,
        status: 'CLOSED',
      ));
      expect(row.isSettled, isTrue);
    });

    test('missing optional fields do not break the row', () {
      final row = CourseFeeRow.fromJson({
        'courseId': 'c1',
        'courseName': 'Guitar',
        'agreedFee': 1000,
        'totalPaid': 0,
        'balance': 1000,
        'status': 'NOT_PAID',
      });
      expect(row.batchName, isNull);
      expect(row.lastPaidOn, isNull);
      expect(row.canUndo, isFalse);
      expect(row.closed, isFalse);
    });
  });
}
