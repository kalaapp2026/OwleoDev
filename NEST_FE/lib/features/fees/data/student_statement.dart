import 'package:nest_fe/features/fees/data/fee_roster.dart';

/// Which side of the fees module a statement row belongs to.
enum FeeCategory {
  regular('REGULAR', 'Regular'),
  other('OTHER', 'Other');

  const FeeCategory(this.wire, this.label);

  final String wire;
  final String label;

  static FeeCategory fromWire(String? value) =>
      FeeCategory.values.firstWhere((c) => c.wire == value, orElse: () => FeeCategory.regular);
}

/// One period of one course - or, once Other Fees lands, one one-off charge.
class StatementRow {
  const StatementRow({
    required this.label,
    required this.category,
    required this.context,
    required this.fee,
    required this.paid,
    required this.status,
    this.paidOn,
    this.mode,
  });

  /// The period ("2026-08") for a regular fee, or the fee's name for an Other one.
  final String label;
  final FeeCategory category;

  /// Which course or batch it belongs to.
  final String context;

  final num fee;
  final num paid;
  final PaymentStatus status;
  final DateTime? paidOn;
  final String? mode;

  num get balance => fee - paid;

  factory StatementRow.fromJson(Map<String, dynamic> json) => StatementRow(
        label: json['label'] as String? ?? '',
        category: FeeCategory.fromWire(json['category'] as String?),
        context: json['context'] as String? ?? '',
        fee: json['fee'] as num? ?? 0,
        paid: json['paid'] as num? ?? 0,
        status: PaymentStatus.fromWire(json['status'] as String?),
        paidOn: DateTime.tryParse(json['paidOn'] as String? ?? ''),
        mode: json['mode'] as String?,
      );
}

/// A student's whole fee history, with the totals for whatever filter produced it.
class StudentStatement {
  const StudentStatement({
    required this.membershipId,
    required this.studentName,
    required this.totalBilled,
    required this.totalPaid,
    required this.outstanding,
    required this.rows,
  });

  final String membershipId;
  final String studentName;
  final num totalBilled;
  final num totalPaid;
  final num outstanding;
  final List<StatementRow> rows;

  factory StudentStatement.fromJson(Map<String, dynamic> json) => StudentStatement(
        membershipId: json['membershipId'] as String,
        studentName: json['studentName'] as String? ?? 'Unknown',
        totalBilled: json['totalBilled'] as num? ?? 0,
        totalPaid: json['totalPaid'] as num? ?? 0,
        outstanding: json['outstanding'] as num? ?? 0,
        rows: (json['rows'] as List<dynamic>? ?? [])
            .map((e) => StatementRow.fromJson(e as Map<String, dynamic>))
            .toList(),
      );
}
