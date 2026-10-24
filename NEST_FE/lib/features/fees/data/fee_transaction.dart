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
