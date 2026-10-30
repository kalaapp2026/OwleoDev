import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:nest_fe/core/network/dio_client.dart';
import 'package:nest_fe/core/providers/core_providers.dart';

final academyBillingApiProvider = Provider((ref) => AcademyBillingApi(ref.watch(dioClientProvider)));

/// The Academy Settings identity card's plan/status - the same AcademyResponse the Super Admin
/// onboarding/suspend screens use, just read by the academy's own admin instead.
final academyDetailProvider = FutureProvider.autoDispose.family<Academy, String>((ref, academyId) {
  return ref.watch(academyBillingApiProvider).getAcademy(academyId);
});

/// Re-fetches on academy switch, same as every other academy-scoped provider in this app.
final academyInvoicesProvider = FutureProvider.autoDispose((ref) {
  ref.watch(activeMembershipIdProvider);
  return ref.watch(academyBillingApiProvider).invoices();
});

/// The subset of AcademyResponse the Settings screen needs - name/plan/status, not the full
/// onboarding record.
class Academy {
  const Academy({required this.id, required this.name, required this.plan, required this.status});

  final String id;
  final String name;
  final String? plan;
  final String status;

  bool get isSuspended => status == 'SUSPENDED';

  factory Academy.fromJson(Map<String, dynamic> json) => Academy(
        id: json['id'] as String,
        name: json['name'] as String,
        plan: json['plan'] as String?,
        status: json['status'] as String? ?? 'ACTIVE',
      );
}

/// One billing period's invoice - mirrors the backend's BillingDtos.InvoiceResponse, trimmed to
/// what the read-only Settings card actually shows.
class AcademyInvoice {
  const AcademyInvoice({
    required this.id,
    required this.period,
    required this.planCode,
    required this.amount,
    required this.status,
    required this.issuedOn,
    required this.dueOn,
    required this.overdue,
    required this.paidAmount,
    required this.paymentMethod,
  });

  final String id;
  final String period;
  final String planCode;
  final num amount;
  final String status;
  final String issuedOn;
  final String dueOn;
  final bool overdue;
  final num? paidAmount;
  final String? paymentMethod;

  factory AcademyInvoice.fromJson(Map<String, dynamic> json) => AcademyInvoice(
        id: json['id'] as String,
        period: json['period'] as String,
        planCode: json['planCode'] as String,
        amount: json['amount'] as num,
        status: json['status'] as String,
        issuedOn: json['issuedOn'] as String,
        dueOn: json['dueOn'] as String,
        overdue: json['overdue'] as bool? ?? false,
        paidAmount: json['paidAmount'] as num?,
        paymentMethod: json['paymentMethod'] as String?,
      );
}

class AcademyBillingApi {
  AcademyBillingApi(this._client);
  final DioClient _client;

  Future<Academy> getAcademy(String academyId) {
    return _client.call(
      (dio) => dio.get('/academies/$academyId'),
      (data) => Academy.fromJson(data as Map<String, dynamic>),
    );
  }

  Future<BillingOverview> overview() {
    return _client.call(
      (dio) => dio.get('/academies/me/billing'),
      (data) => BillingOverview.fromJson(data as Map<String, dynamic>),
    );
  }

  /// Step 1 of paying a bill: the server works out the balance and opens a Razorpay order. The amount is never sent.
  Future<BillOrder> createBillOrder(String invoiceId) {
    return _client.call(
      (dio) => dio.post('/academies/me/billing/invoices/$invoiceId/pay/order'),
      (data) => BillOrder.fromJson(data as Map<String, dynamic>),
    );
  }

  /// Step 3: hand the checkout's signed result to the server, which checks it before anything is marked paid.
  Future<void> confirmBillPayment({required String orderId, required String paymentId, required String signature}) {
    return _client.call(
      (dio) => dio.post('/academies/me/billing/pay/verify', data: {'orderId': orderId, 'paymentId': paymentId, 'signature': signature}),
      (_) {},
    );
  }

  /// The caller's own academy's invoice history - Academy Admin only server-side.
  Future<List<AcademyInvoice>> invoices() {
    return _client.call(
      (dio) => dio.get('/academies/me/invoices'),
      (data) => (data as List).map((e) => AcademyInvoice.fromJson(e as Map<String, dynamic>)).toList(),
    );
  }
}

// ---------------------------------------------------------------------------------------------------------
// Billing and subscription: GET /academies/me/billing, and paying a bill.
// ---------------------------------------------------------------------------------------------------------

num _n(Object? v) => v is num ? v : num.tryParse('$v') ?? 0;

class BillingPlan {
  const BillingPlan({required this.code, required this.name, required this.price, required this.maxStudents, required this.maxTrainers, required this.popular, required this.modules, required this.current});

  final String code;
  final String name;
  final num price;
  final int? maxStudents;
  final int? maxTrainers;
  final bool popular;
  final List<String> modules;
  final bool current;

  factory BillingPlan.fromJson(Map<String, dynamic> j) => BillingPlan(
        code: j['code'] as String,
        name: j['name'] as String? ?? j['code'] as String,
        price: _n(j['price']),
        maxStudents: (j['maxStudents'] as num?)?.toInt(),
        maxTrainers: (j['maxTrainers'] as num?)?.toInt(),
        popular: j['popular'] as bool? ?? false,
        modules: [for (final m in (j['modules'] as List? ?? const [])) m.toString()],
        current: j['current'] as bool? ?? false,
      );
}

class BillingAddon {
  const BillingAddon({required this.id, required this.name, required this.description, required this.price, required this.monthly, required this.adopted, required this.fromPeriod});

  final String id;
  final String name;
  final String description;
  final num price;

  /// Charged every month, or once.
  final bool monthly;

  /// The academy has this add-on.
  final bool adopted;
  final String? fromPeriod;

  factory BillingAddon.fromJson(Map<String, dynamic> j) => BillingAddon(
        id: j['id'] as String,
        name: j['name'] as String,
        description: j['description'] as String? ?? '',
        price: _n(j['price']),
        monthly: (j['billing'] as String? ?? 'month') == 'month',
        adopted: j['adopted'] as bool? ?? false,
        fromPeriod: j['fromPeriod'] as String?,
      );
}

class BillLine {
  const BillLine({required this.kind, required this.label, required this.amount});
  final String kind;
  final String label;
  final num amount;

  factory BillLine.fromJson(Map<String, dynamic> j) => BillLine(kind: j['kind'] as String? ?? '', label: j['label'] as String? ?? '', amount: _n(j['amount']));
}

class BillPayment {
  const BillPayment({required this.paidOn, required this.amount, required this.mode, required this.reference, required this.online});
  final String paidOn;
  final num amount;
  final String mode;
  final String reference;
  final bool online;

  factory BillPayment.fromJson(Map<String, dynamic> j) => BillPayment(
        paidOn: j['paidOn'] as String? ?? '',
        amount: _n(j['amount']),
        mode: j['mode'] as String? ?? '',
        reference: j['reference'] as String? ?? '',
        online: j['online'] as bool? ?? false,
      );
}

/// One monthly bill from Owleo, with GST, what was paid and what is still owed.
class BillingBill {
  const BillingBill({
    required this.id,
    required this.number,
    required this.period,
    required this.status,
    required this.dueOn,
    required this.overdue,
    required this.daysOverdue,
    required this.payable,
    required this.discount,
    required this.gst,
    required this.gstRate,
    required this.total,
    required this.paid,
    required this.balance,
    required this.note,
    required this.lines,
    required this.payments,
  });

  final String id;
  final String number;
  final String period;
  final String status;
  final String dueOn;
  final bool overdue;
  final int daysOverdue;

  /// Something is still owed and the bill was not waived.
  final bool payable;
  final num discount;
  final num gst;
  final num gstRate;
  final num total;
  final num paid;
  final num balance;
  final String? note;
  final List<BillLine> lines;
  final List<BillPayment> payments;

  factory BillingBill.fromJson(Map<String, dynamic> j) => BillingBill(
        id: j['id'] as String,
        number: j['number'] as String? ?? '',
        period: j['period'] as String? ?? '',
        status: j['status'] as String? ?? '',
        dueOn: j['dueOn'] as String? ?? '',
        overdue: j['overdue'] as bool? ?? false,
        daysOverdue: (j['daysOverdue'] as num?)?.toInt() ?? 0,
        payable: j['payable'] as bool? ?? false,
        discount: _n(j['discount']),
        gst: _n(j['gst']),
        gstRate: _n(j['gstRate']),
        total: _n(j['total']),
        paid: _n(j['paid']),
        balance: _n(j['balance']),
        note: j['note'] as String?,
        lines: [for (final l in (j['lines'] as List? ?? const [])) BillLine.fromJson(l as Map<String, dynamic>)],
        payments: [for (final p in (j['payments'] as List? ?? const [])) BillPayment.fromJson(p as Map<String, dynamic>)],
      );
}

class BillingOverview {
  const BillingOverview({
    required this.students,
    required this.trainers,
    required this.plans,
    required this.addons,
    required this.bills,
    required this.outstanding,
    required this.overdueCount,
    required this.paymentEnabled,
  });

  final int students;
  final int trainers;
  final List<BillingPlan> plans;
  final List<BillingAddon> addons;
  final List<BillingBill> bills;
  final num outstanding;
  final int overdueCount;

  /// Owleo has online payment switched on, so a bill can be paid in the app.
  final bool paymentEnabled;

  BillingPlan? get current => plans.where((p) => p.current).firstOrNull;

  factory BillingOverview.fromJson(Map<String, dynamic> j) => BillingOverview(
        students: (j['students'] as num?)?.toInt() ?? 0,
        trainers: (j['trainers'] as num?)?.toInt() ?? 0,
        plans: [for (final p in (j['plans'] as List? ?? const [])) BillingPlan.fromJson(p as Map<String, dynamic>)],
        addons: [for (final a in (j['addons'] as List? ?? const [])) BillingAddon.fromJson(a as Map<String, dynamic>)],
        bills: [for (final b in (j['invoices'] as List? ?? const [])) BillingBill.fromJson(b as Map<String, dynamic>)],
        outstanding: _n(j['outstanding']),
        overdueCount: (j['overdueCount'] as num?)?.toInt() ?? 0,
        paymentEnabled: (j['payment'] as Map?)?['enabled'] as bool? ?? false,
      );
}

/// A Razorpay order for one bill: what the checkout needs to open.
class BillOrder {
  const BillOrder({required this.orderId, required this.keyId, required this.amountPaise, required this.amount, required this.invoice});
  final String orderId;
  final String keyId;
  final int amountPaise;
  final num amount;
  final String invoice;

  factory BillOrder.fromJson(Map<String, dynamic> j) => BillOrder(
        orderId: j['orderId'] as String,
        keyId: j['keyId'] as String,
        amountPaise: (j['amountPaise'] as num).toInt(),
        amount: _n(j['amount']),
        invoice: j['invoice'] as String? ?? '',
      );
}

/// Plans, add-ons and bills in one read; re-fetches on academy switch like every academy-scoped provider.
final academyBillingProvider = FutureProvider.autoDispose<BillingOverview>((ref) {
  ref.watch(activeMembershipIdProvider);
  return ref.watch(academyBillingApiProvider).overview();
});
