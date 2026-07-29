import 'package:nest_fe/core/network/dio_client.dart';

class BillingPlan {
  final String code;
  final String displayName;
  final double monthlyPrice;
  final int? maxStudents;
  final int? maxTrainers;

  const BillingPlan({
    required this.code,
    required this.displayName,
    required this.monthlyPrice,
    required this.maxStudents,
    required this.maxTrainers,
  });

  factory BillingPlan.fromJson(Map<String, dynamic> json) => BillingPlan(
        code: json['code'] as String,
        displayName: json['displayName'] as String,
        monthlyPrice: (json['monthlyPrice'] as num?)?.toDouble() ?? 0,
        maxStudents: (json['maxStudents'] as num?)?.toInt(),
        maxTrainers: (json['maxTrainers'] as num?)?.toInt(),
      );
}

class Invoice {
  final String id;
  final String academyId;
  final String? academyName;
  final String period;
  final String planCode;
  final double amount;
  final String status;
  final DateTime? issuedOn;
  final DateTime? dueOn;

  /// Derived server-side from the due date rather than stored, so it can never be stale.
  final bool overdue;
  final int daysOverdue;

  final DateTime? paidAt;
  final double? paidAmount;
  final String? paymentMethod;
  final String? paymentRef;
  final String? note;

  const Invoice({
    required this.id,
    required this.academyId,
    required this.academyName,
    required this.period,
    required this.planCode,
    required this.amount,
    required this.status,
    required this.issuedOn,
    required this.dueOn,
    required this.overdue,
    required this.daysOverdue,
    required this.paidAt,
    required this.paidAmount,
    required this.paymentMethod,
    required this.paymentRef,
    required this.note,
  });

  bool get isPaid => status == 'PAID';
  bool get isWaived => status == 'WAIVED';
  bool get isDue => status == 'DUE';

  factory Invoice.fromJson(Map<String, dynamic> json) => Invoice(
        id: json['id'] as String,
        academyId: json['academyId'] as String,
        academyName: json['academyName'] as String?,
        period: json['period'] as String,
        planCode: json['planCode'] as String? ?? '',
        amount: (json['amount'] as num?)?.toDouble() ?? 0,
        status: json['status'] as String? ?? 'DUE',
        issuedOn: json['issuedOn'] == null ? null : DateTime.parse(json['issuedOn'] as String),
        dueOn: json['dueOn'] == null ? null : DateTime.parse(json['dueOn'] as String),
        overdue: json['overdue'] as bool? ?? false,
        daysOverdue: (json['daysOverdue'] as num?)?.toInt() ?? 0,
        paidAt: json['paidAt'] == null ? null : DateTime.parse(json['paidAt'] as String),
        paidAmount: (json['paidAmount'] as num?)?.toDouble(),
        paymentMethod: json['paymentMethod'] as String?,
        paymentRef: json['paymentRef'] as String?,
        note: json['note'] as String?,
      );
}

class PlanBreakdown {
  final String planCode;
  final String displayName;
  final int academies;
  final double monthlyValue;

  const PlanBreakdown({
    required this.planCode,
    required this.displayName,
    required this.academies,
    required this.monthlyValue,
  });

  factory PlanBreakdown.fromJson(Map<String, dynamic> json) => PlanBreakdown(
        planCode: json['planCode'] as String,
        displayName: json['displayName'] as String? ?? json['planCode'] as String,
        academies: (json['academies'] as num?)?.toInt() ?? 0,
        monthlyValue: (json['monthlyValue'] as num?)?.toDouble() ?? 0,
      );
}

class BillingSummary {
  /// Monthly recurring revenue - what a normal month SHOULD bill, from every active academy's
  /// plan price. Deliberately not the same as [billedThisMonth], which is what actually went out.
  final double mrr;
  final double arr;
  final double billedThisMonth;
  final double collectedThisMonth;
  final double outstanding;
  final int overdueCount;
  final int payingAcademies;
  final int freeAcademies;
  final String currentPeriod;
  final List<PlanBreakdown> byPlan;

  const BillingSummary({
    required this.mrr,
    required this.arr,
    required this.billedThisMonth,
    required this.collectedThisMonth,
    required this.outstanding,
    required this.overdueCount,
    required this.payingAcademies,
    required this.freeAcademies,
    required this.currentPeriod,
    required this.byPlan,
  });

  factory BillingSummary.fromJson(Map<String, dynamic> json) => BillingSummary(
        mrr: (json['mrr'] as num?)?.toDouble() ?? 0,
        arr: (json['arr'] as num?)?.toDouble() ?? 0,
        billedThisMonth: (json['billedThisMonth'] as num?)?.toDouble() ?? 0,
        collectedThisMonth: (json['collectedThisMonth'] as num?)?.toDouble() ?? 0,
        outstanding: (json['outstanding'] as num?)?.toDouble() ?? 0,
        overdueCount: (json['overdueCount'] as num?)?.toInt() ?? 0,
        payingAcademies: (json['payingAcademies'] as num?)?.toInt() ?? 0,
        freeAcademies: (json['freeAcademies'] as num?)?.toInt() ?? 0,
        currentPeriod: json['currentPeriod'] as String? ?? '',
        byPlan: (json['byPlan'] as List? ?? [])
            .map((e) => PlanBreakdown.fromJson(e as Map<String, dynamic>))
            .toList(),
      );
}

class BillingApi {
  BillingApi(this._client);
  final DioClient _client;

  Future<BillingSummary> summary() => _client.call(
        (dio) => dio.get('/admin/billing/summary'),
        (data) => BillingSummary.fromJson(data as Map<String, dynamic>),
      );

  Future<List<BillingPlan>> plans() => _client.call(
        (dio) => dio.get('/admin/billing/plans'),
        (data) => (data as List).map((e) => BillingPlan.fromJson(e as Map<String, dynamic>)).toList(),
      );

  Future<List<Invoice>> invoices({String? period}) => _client.call(
        (dio) => dio.get('/admin/billing/invoices',
            queryParameters: period == null ? null : {'period': period}),
        (data) => (data as List).map((e) => Invoice.fromJson(e as Map<String, dynamic>)).toList(),
      );

  Future<List<Invoice>> overdue() => _client.call(
        (dio) => dio.get('/admin/billing/invoices/overdue'),
        (data) => (data as List).map((e) => Invoice.fromJson(e as Map<String, dynamic>)).toList(),
      );

  /// Idempotent per (academy, period) server-side, so a double tap can't double-charge.
  Future<int> generate({String? period}) => _client.call(
        (dio) => dio.post('/admin/billing/invoices/generate',
            queryParameters: period == null ? null : {'period': period}),
        (data) => ((data as Map<String, dynamic>)['created'] as num).toInt(),
      );

  Future<Invoice> markPaid(String invoiceId,
          {required double amount, required String method, String? reference, String? note}) =>
      _client.call(
        (dio) => dio.post('/admin/billing/invoices/$invoiceId/pay', data: {
          'amount': amount,
          'method': method,
          'reference': reference,
          'note': note,
        }),
        (data) => Invoice.fromJson(data as Map<String, dynamic>),
      );

  Future<Invoice> waive(String invoiceId, String note) => _client.call(
        (dio) => dio.post('/admin/billing/invoices/$invoiceId/waive', queryParameters: {'note': note}),
        (data) => Invoice.fromJson(data as Map<String, dynamic>),
      );

  Future<void> changePlan(String academyId, String planCode) =>
      _client.callVoid((dio) => dio.put('/admin/billing/academies/$academyId/plan', data: {'planCode': planCode}));
}
