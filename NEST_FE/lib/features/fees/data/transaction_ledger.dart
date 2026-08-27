import 'package:nest_fe/features/fees/data/student_statement.dart';

/// One payment - or one reversal - from the academy's ledger.
class LedgerEntry {
  const LedgerEntry({
    required this.transactionId,
    required this.membershipId,
    required this.studentName,
    required this.category,
    required this.context,
    required this.amount,
    required this.occurredOn,
    this.mode,
    this.reversal = false,
  });

  final String transactionId;
  final String membershipId;
  final String studentName;
  final FeeCategory category;

  /// What the money was for - the course and period, or the fee type.
  final String context;

  /// Negative for a reversal, which is how the totals stay net without a special case.
  final num amount;

  final DateTime? occurredOn;
  final String? mode;
  final bool reversal;

  factory LedgerEntry.fromJson(Map<String, dynamic> json) => LedgerEntry(
        transactionId: json['transactionId'] as String,
        membershipId: json['membershipId'] as String,
        studentName: json['studentName'] as String? ?? 'Unknown',
        category: FeeCategory.fromWire(json['category'] as String?),
        context: json['context'] as String? ?? '',
        amount: json['amount'] as num? ?? 0,
        occurredOn: DateTime.tryParse(json['occurredOn'] as String? ?? ''),
        mode: json['mode'] as String?,
        reversal: json['reversal'] as bool? ?? false,
      );
}

/// The academy's ledger for a date range, with totals matching whatever filter produced it.
class TransactionLedger {
  const TransactionLedger({
    required this.regularTotal,
    required this.otherTotal,
    required this.total,
    required this.entries,
  });

  final num regularTotal;
  final num otherTotal;
  final num total;
  final List<LedgerEntry> entries;

  factory TransactionLedger.fromJson(Map<String, dynamic> json) => TransactionLedger(
        regularTotal: json['regularTotal'] as num? ?? 0,
        otherTotal: json['otherTotal'] as num? ?? 0,
        total: json['total'] as num? ?? 0,
        entries: (json['entries'] as List<dynamic>? ?? [])
            .map((e) => LedgerEntry.fromJson(e as Map<String, dynamic>))
            .toList(),
      );
}
