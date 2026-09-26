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

  /// The caller's own academy's invoice history - Academy Admin only server-side.
  Future<List<AcademyInvoice>> invoices() {
    return _client.call(
      (dio) => dio.get('/academies/me/invoices'),
      (data) => (data as List).map((e) => AcademyInvoice.fromJson(e as Map<String, dynamic>)).toList(),
    );
  }
}
