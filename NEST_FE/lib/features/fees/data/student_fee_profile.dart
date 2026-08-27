import 'package:nest_fe/features/fees/data/fee_roster.dart';

/// One course's fee position for one student in one period.
///
/// A student can be enrolled in several courses, so the profile shows a row per course and makes
/// the admin choose which one a payment is for. Recording against the wrong course is silent and
/// awkward to unpick, so it is never guessed.
class CourseFeeRow {
  const CourseFeeRow({
    required this.courseId,
    required this.courseName,
    required this.agreedFee,
    required this.totalPaid,
    required this.balance,
    required this.status,
    this.batchName,
    this.lastPaymentId,
    this.lastPaidOn,
    this.lastPaymentMode,
    this.closed = false,
  });

  final String courseId;
  final String courseName;

  /// Which batch they sit in for this course. Context only - a regular fee is keyed by course and
  /// period, never by batch.
  final String? batchName;

  final num agreedFee;
  final num totalPaid;
  final num balance;
  final PaymentStatus status;
  final String? lastPaymentId;
  final DateTime? lastPaidOn;
  final String? lastPaymentMode;

  /// The period was closed - any shortfall is written off rather than carried forward.
  final bool closed;

  bool get isSettled => status.isSettled;
  bool get canUndo => lastPaymentId != null;

  /// What a "mark as paid" would collect. Never negative, so an overpaid row doesn't offer to
  /// take money back.
  num get outstanding => balance > 0 ? balance : 0;

  factory CourseFeeRow.fromJson(Map<String, dynamic> json) => CourseFeeRow(
        courseId: json['courseId'] as String,
        courseName: json['courseName'] as String? ?? 'Unknown course',
        batchName: json['batchName'] as String?,
        agreedFee: json['agreedFee'] as num? ?? 0,
        totalPaid: json['totalPaid'] as num? ?? 0,
        balance: json['balance'] as num? ?? 0,
        status: PaymentStatus.fromWire(json['status'] as String?),
        lastPaymentId: json['lastPaymentId'] as String?,
        lastPaidOn: DateTime.tryParse(json['lastPaidOn'] as String? ?? ''),
        lastPaymentMode: json['lastPaymentMode'] as String?,
        closed: json['closed'] as bool? ?? false,
      );
}

/// A student's whole fee position for a period, across every course.
class StudentFeeProfile {
  const StudentFeeProfile({
    required this.membershipId,
    required this.studentName,
    required this.period,
    required this.totalAgreedFee,
    required this.totalPaid,
    required this.totalBalance,
    required this.courses,
  });

  final String membershipId;
  final String studentName;
  final String period;
  final num totalAgreedFee;
  final num totalPaid;
  final num totalBalance;
  final List<CourseFeeRow> courses;

  /// True once there is more than one course to choose between - the point at which the screen
  /// stops being able to assume which one a payment belongs to.
  bool get hasBreakdown => courses.length > 1;

  /// Only what is still collectable. Summing balances would let an overpaid course cancel out an
  /// unpaid one and show nothing owing when something is.
  num get outstanding =>
      courses.fold<num>(0, (sum, c) => sum + c.outstanding);

  factory StudentFeeProfile.fromJson(Map<String, dynamic> json) => StudentFeeProfile(
        membershipId: json['membershipId'] as String,
        studentName: json['studentName'] as String? ?? 'Unknown',
        period: json['period'] as String,
        totalAgreedFee: json['totalAgreedFee'] as num? ?? 0,
        totalPaid: json['totalPaid'] as num? ?? 0,
        totalBalance: json['totalBalance'] as num? ?? 0,
        courses: (json['courses'] as List<dynamic>? ?? [])
            .map((e) => CourseFeeRow.fromJson(e as Map<String, dynamic>))
            .toList(),
      );
}
