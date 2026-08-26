import 'package:flutter/material.dart';
import 'package:nest_fe/app/theme/app_tokens.dart';

/// How a student's fee for one period reads on the roster.
///
/// Mirrors the server's derived status. Nothing here is stored - the server recomputes it from the
/// ledger on every read, so a reversal changes the badge with no extra call.
enum PaymentStatus {
  notPaid('NOT_PAID'),
  due('DUE'),
  partial('PARTIAL'),
  paidManual('PAID_MANUAL'),
  paidGateway('PAID_GATEWAY'),
  closed('CLOSED');

  const PaymentStatus(this.wire);

  final String wire;

  /// Unknown values fall back to notPaid rather than throwing: a server that grows a new status
  /// should not blank out an admin's whole roster screen.
  static PaymentStatus fromWire(String? value) => PaymentStatus.values
      .firstWhere((s) => s.wire == value, orElse: () => PaymentStatus.notPaid);

  bool get isSettled =>
      this == PaymentStatus.paidManual ||
      this == PaymentStatus.paidGateway ||
      this == PaymentStatus.closed;

  /// The domain type maps itself onto the design's colours, rather than StatusBadge growing a
  /// switch over every enum in the app. This is the seam that keeps StatusBadge reusable by
  /// Batches and Billing.
  Color color(AppPalette palette) => switch (this) {
        PaymentStatus.notPaid => palette.notPaid,
        PaymentStatus.due => palette.due,
        PaymentStatus.partial => palette.partial,
        PaymentStatus.paidManual => palette.paidManual,
        PaymentStatus.paidGateway => palette.gateway,
        PaymentStatus.closed => palette.textMuted,
      };
}

/// One student's fee position for one period.
class FeeRosterEntry {
  const FeeRosterEntry({
    required this.membershipId,
    required this.studentName,
    required this.agreedFee,
    required this.totalPaid,
    required this.balance,
    required this.status,
    this.lastPaymentId,
  });

  final String membershipId;
  final String studentName;
  final num agreedFee;
  final num totalPaid;
  final num balance;
  final PaymentStatus status;

  /// The payment an undo would reverse. Null when there is nothing to undo - the row hides the
  /// action rather than offering one the server would refuse.
  final String? lastPaymentId;

  bool get canUndo => lastPaymentId != null;

  factory FeeRosterEntry.fromJson(Map<String, dynamic> json) => FeeRosterEntry(
        membershipId: json['membershipId'] as String,
        studentName: json['studentName'] as String? ?? 'Unknown',
        agreedFee: json['agreedFee'] as num? ?? 0,
        totalPaid: json['totalPaid'] as num? ?? 0,
        balance: json['balance'] as num? ?? 0,
        status: PaymentStatus.fromWire(json['status'] as String?),
        lastPaymentId: json['lastPaymentId'] as String?,
      );
}

/// A whole batch's fee position for one period.
///
/// The totals arrive with the rows rather than being summed on the client, so the progress bar and
/// the list are guaranteed to agree even when the list is filtered.
class FeeRoster {
  const FeeRoster({
    required this.courseId,
    required this.batchId,
    required this.period,
    required this.studentCount,
    required this.paidCount,
    required this.expected,
    required this.collected,
    required this.entries,
  });

  final String courseId;
  final String batchId;
  final String period;
  final int studentCount;
  final int paidCount;
  final num expected;
  final num collected;
  final List<FeeRosterEntry> entries;

  factory FeeRoster.fromJson(Map<String, dynamic> json) => FeeRoster(
        courseId: json['courseId'] as String,
        batchId: json['batchId'] as String,
        period: json['period'] as String,
        studentCount: json['studentCount'] as int? ?? 0,
        paidCount: json['paidCount'] as int? ?? 0,
        expected: json['expected'] as num? ?? 0,
        collected: json['collected'] as num? ?? 0,
        entries: (json['entries'] as List<dynamic>? ?? [])
            .map((e) => FeeRosterEntry.fromJson(e as Map<String, dynamic>))
            .toList(),
      );
}
