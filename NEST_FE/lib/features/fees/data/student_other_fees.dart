import 'package:nest_fe/features/fees/data/fee_roster.dart';

/// One Other fee that applies to a student - a shared type, or a one-off raised against them.
class OtherFeeRow {
  const OtherFeeRow({
    required this.name,
    required this.amount,
    required this.paid,
    required this.balance,
    required this.status,
    required this.custom,
    this.feeTypeId,
    this.studentFeeId,
    this.dueDate,
    this.lastPaidOn,
    this.lastPaymentMode,
    this.lastPaymentId,
  });

  /// Exactly one of these is set - which one says whether it is a shared catalogue fee or a
  /// one-off. [custom] carries the same answer without inspecting nulls.
  final String? feeTypeId;
  final String? studentFeeId;

  final String name;
  final num amount;
  final num paid;
  final num balance;
  final PaymentStatus status;
  final DateTime? dueDate;
  final DateTime? lastPaidOn;
  final String? lastPaymentMode;
  final String? lastPaymentId;
  final bool custom;

  bool get isSettled => status.isSettled;
  bool get canUndo => lastPaymentId != null;

  /// Never negative, so a mark-paid cannot offer to take money back.
  num get outstanding => balance > 0 ? balance : 0;

  factory OtherFeeRow.fromJson(Map<String, dynamic> json) => OtherFeeRow(
        feeTypeId: json['feeTypeId'] as String?,
        studentFeeId: json['studentFeeId'] as String?,
        name: json['name'] as String? ?? 'Fee',
        amount: json['amount'] as num? ?? 0,
        paid: json['paid'] as num? ?? 0,
        balance: json['balance'] as num? ?? 0,
        status: PaymentStatus.fromWire(json['status'] as String?),
        dueDate: DateTime.tryParse(json['dueDate'] as String? ?? ''),
        lastPaidOn: DateTime.tryParse(json['lastPaidOn'] as String? ?? ''),
        lastPaymentMode: json['lastPaymentMode'] as String?,
        lastPaymentId: json['lastPaymentId'] as String?,
        custom: json['custom'] as bool? ?? false,
      );
}

/// Every Other fee for one student. Empty is a normal state - a newly joined student still needs
/// a screen to open so a first one-off fee can be added.
class StudentOtherFees {
  const StudentOtherFees({
    required this.membershipId,
    required this.studentName,
    required this.totalAmount,
    required this.totalPaid,
    required this.outstanding,
    required this.fees,
  });

  final String membershipId;
  final String studentName;
  final num totalAmount;
  final num totalPaid;
  final num outstanding;
  final List<OtherFeeRow> fees;

  factory StudentOtherFees.fromJson(Map<String, dynamic> json) => StudentOtherFees(
        membershipId: json['membershipId'] as String,
        studentName: json['studentName'] as String? ?? 'Unknown',
        totalAmount: json['totalAmount'] as num? ?? 0,
        totalPaid: json['totalPaid'] as num? ?? 0,
        outstanding: json['outstanding'] as num? ?? 0,
        fees: (json['fees'] as List<dynamic>? ?? [])
            .map((e) => OtherFeeRow.fromJson(e as Map<String, dynamic>))
            .toList(),
      );
}
