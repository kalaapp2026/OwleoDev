class FeeTransaction {
  final String id;
  final String membershipId;
  final String courseId;
  final String period;
  final num amountPaid;
  final String mode;
  final String? note;
  final String? createdAt;

  const FeeTransaction({
    required this.id,
    required this.membershipId,
    required this.courseId,
    required this.period,
    required this.amountPaid,
    required this.mode,
    required this.note,
    required this.createdAt,
  });

  factory FeeTransaction.fromJson(Map<String, dynamic> json) => FeeTransaction(
        id: json['id'] as String,
        membershipId: json['membershipId'] as String,
        courseId: json['courseId'] as String,
        period: json['period'] as String,
        amountPaid: json['amountPaid'] as num,
        mode: json['mode'] as String,
        note: json['note'] as String?,
        createdAt: json['createdAt'] as String?,
      );
}

class FeeBalance {
  final String membershipId;
  final String courseId;
  final String period;
  final num agreedFee;
  final num totalPaid;
  final num balance;
  final bool closed;

  const FeeBalance({
    required this.membershipId,
    required this.courseId,
    required this.period,
    required this.agreedFee,
    required this.totalPaid,
    required this.balance,
    required this.closed,
  });

  factory FeeBalance.fromJson(Map<String, dynamic> json) => FeeBalance(
        membershipId: json['membershipId'] as String,
        courseId: json['courseId'] as String,
        period: json['period'] as String,
        agreedFee: json['agreedFee'] as num,
        totalPaid: json['totalPaid'] as num,
        balance: json['balance'] as num,
        closed: json['closed'] as bool? ?? false,
      );
}

/// A generated fee slip - "last 2nd to this 2nd, per-class/hybrid checked, slip generated on the
/// 2nd" - one row per (student, course, billing period). classesHeld/classesAttended are null for
/// FIXED-model courses, which don't compute off attendance. carriedForwardAmount is whatever
/// unpaid remainder rolled in from the previous OPEN period; status flips to CLOSED once an
/// Admin/Trainer explicitly writes off a shortfall instead of carrying it.
class FeeSlip {
  final String id;
  final String membershipId;
  final String courseId;
  final String period;
  final String billingPeriodStart;
  final String billingPeriodEnd;
  final num amountDue;
  final num carriedForwardAmount;
  final String status;
  final int? classesHeld;
  final int? classesAttended;
  final String generatedAt;

  const FeeSlip({
    required this.id,
    required this.membershipId,
    required this.courseId,
    required this.period,
    required this.billingPeriodStart,
    required this.billingPeriodEnd,
    required this.amountDue,
    required this.carriedForwardAmount,
    required this.status,
    required this.classesHeld,
    required this.classesAttended,
    required this.generatedAt,
  });

  bool get isClosed => status == 'CLOSED';

  factory FeeSlip.fromJson(Map<String, dynamic> json) => FeeSlip(
        id: json['id'] as String,
        membershipId: json['membershipId'] as String,
        courseId: json['courseId'] as String,
        period: json['period'] as String,
        billingPeriodStart: json['billingPeriodStart'] as String,
        billingPeriodEnd: json['billingPeriodEnd'] as String,
        amountDue: json['amountDue'] as num,
        carriedForwardAmount: json['carriedForwardAmount'] as num? ?? 0,
        status: json['status'] as String? ?? 'OPEN',
        classesHeld: json['classesHeld'] as int?,
        classesAttended: json['classesAttended'] as int?,
        generatedAt: json['generatedAt'] as String,
      );
}
