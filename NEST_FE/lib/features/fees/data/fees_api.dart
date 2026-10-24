import 'package:nest_fe/core/providers/core_providers.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:nest_fe/core/network/dio_client.dart';
import 'package:nest_fe/features/fees/data/fee_roster.dart';
import 'package:nest_fe/features/fees/data/fee_summary.dart';
import 'package:nest_fe/features/fees/data/fee_type.dart';
import 'package:nest_fe/features/fees/data/fee_transaction.dart';
import 'package:nest_fe/features/fees/data/student_fee_profile.dart';
import 'package:nest_fe/features/fees/data/student_other_fees.dart';
import 'package:nest_fe/features/fees/data/student_statement.dart';
import 'package:nest_fe/features/fees/data/transaction_ledger.dart';

/// A Razorpay order the server opened for one fee. [keyId] is the public half of the key.
class OnlineOrder {
  const OnlineOrder({required this.orderId, required this.keyId, required this.amountPaise});
  final String orderId;
  final String keyId;
  final int amountPaise;

  factory OnlineOrder.fromJson(Map<String, dynamic> j) => OnlineOrder(
        orderId: j['orderId'] as String,
        keyId: j['keyId'] as String,
        amountPaise: (j['amountPaise'] as num).toInt(),
      );
}

final feesApiProvider = Provider((ref) => FeesApi(ref.watch(dioClientProvider)));

class FeesApi {
  FeesApi(this._client);
  final DioClient _client;

  /// closePeriod=true is the "Close" choice - writes off whatever's left unpaid for good.
  /// false/omitted ("Partial pay", or paying in full) leaves the period OPEN so any shortfall
  /// rolls into the next fee slip generated for it.
  Future<FeeTransaction> recordEntry({
    required String membershipId,
    required String courseId,
    required String period,
    required num amountPaid,
    required String mode,
    String? note,
    String? gatewayRef,
    bool closePeriod = false,
  }) {
    return _client.call(
      (dio) => dio.post('/fees/entries', data: {
        'membershipId': membershipId,
        'courseId': courseId,
        'period': period,
        'amountPaid': amountPaid,
        'mode': mode,
        'note': note,
        'gatewayRef': gatewayRef,
        'closePeriod': closePeriod,
      }),
      (data) => FeeTransaction.fromJson(data as Map<String, dynamic>),
    );
  }

  Future<FeeBalance> balance({required String membershipId, required String courseId, required String period}) {
    return _client.call(
      (dio) => dio.get('/fees/balance', queryParameters: {
        'membershipId': membershipId,
        'courseId': courseId,
        'period': period,
      }),
      (data) => FeeBalance.fromJson(data as Map<String, dynamic>),
    );
  }

  /// A whole batch's fee position for a period, in one call. The per-student alternative is a
  /// request per row, which is what this endpoint exists to avoid.
  Future<FeeRoster> roster({
    required String courseId,
    required String batchId,
    required String period,
  }) {
    return _client.call(
      (dio) => dio.get('/fees/roster', queryParameters: {
        'courseId': courseId,
        'batchId': batchId,
        'period': period,
      }),
      (data) => FeeRoster.fromJson(data as Map<String, dynamic>),
    );
  }

  /// Undo a payment. Posts a compensating negative transaction server-side - the ledger is
  /// append-only, so there is no delete to call.
  Future<FeeTransaction> reverseEntry({required String transactionId, String? reason}) {
    return _client.call(
      (dio) => dio.post('/fees/entries/$transactionId/reverse',
          data: {'reason': ?reason}),
      (data) => FeeTransaction.fromJson(data as Map<String, dynamic>),
    );
  }

  /// One student's fee position for a period across every course they're enrolled in.
  Future<StudentFeeProfile> feeProfile({required String membershipId, required String period}) {
    return _client.call(
      (dio) => dio.get('/students/$membershipId/fee-profile',
          queryParameters: {'period': period}),
      (data) => StudentFeeProfile.fromJson(data as Map<String, dynamic>),
    );
  }

  /// Change what this student is charged for this course. Nothing recalculates server-side -
  /// status is derived, so the next read compares the new fee against the same ledger.
  Future<void> updateAgreedFee({
    required String membershipId,
    required String courseId,
    required num agreedFee,
  }) {
    return _client.call(
      (dio) => dio.patch('/fees/agreed-fee', data: {
        'membershipId': membershipId,
        'courseId': courseId,
        'agreedFee': agreedFee,
      }),
      (_) {},
    );
  }

  /// A student's whole fee history. The optional category matches the screen's own chips, and
  /// the totals come back filtered to it.
  Future<StudentStatement> statement({required String membershipId, FeeCategory? category}) {
    return _client.call(
      (dio) => dio.get('/students/$membershipId/statement',
          queryParameters: {'category': ?category?.wire}),
      (data) => StudentStatement.fromJson(data as Map<String, dynamic>),
    );
  }

  /// The caller's OWN statement / Other fees - the student-facing screens. Separate routes rather
  /// than the per-membership ones, which are FEES_ENTRY-gated and meant for staff.
  Future<StudentStatement> myStatement({FeeCategory? category}) {
    return _client.call(
      (dio) => dio.get('/me/fees/statement', queryParameters: {'category': ?category?.wire}),
      (data) => StudentStatement.fromJson(data as Map<String, dynamic>),
    );
  }

  /// Whether the server has online payment switched on, and through which provider:
  /// `RAZORPAY` (real checkout), `MOCK` (dev placeholder that moves no money) or `NONE`.
  Future<({bool enabled, String provider})> paymentConfig() {
    return _client.call(
      (dio) => dio.get('/me/fees/payment-config'),
      (data) {
        final m = data as Map<String, dynamic>;
        return (enabled: m['enabled'] as bool? ?? false, provider: m['provider'] as String? ?? 'NONE');
      },
    );
  }

  /// Step 1 of a real payment: the server prices the fee and opens a Razorpay order for it.
  Future<OnlineOrder> createOnlineOrder({
    required FeeCategory category,
    String? courseId,
    String? period,
    String? feeTypeId,
    String? studentFeeId,
  }) {
    return _client.call(
      (dio) => dio.post('/me/fees/pay/order', data: {
        'category': category.wire,
        'courseId': courseId,
        'period': period,
        'feeTypeId': feeTypeId,
        'studentFeeId': studentFeeId,
        'method': 'UPI',
      }),
      (data) => OnlineOrder.fromJson(data as Map<String, dynamic>),
    );
  }

  /// Step 3: hand the checkout's signed result to the server, which checks it before settling.
  /// Returns the payment reference. Safe to repeat - the server settles an order once.
  Future<String> confirmOnlinePayment({
    required String orderId,
    required String paymentId,
    required String signature,
  }) {
    return _client.call(
      (dio) => dio.post('/me/fees/pay/verify', data: {
        'orderId': orderId,
        'paymentId': paymentId,
        'signature': signature,
      }),
      (data) => (data as Map<String, dynamic>)['gatewayRef'] as String? ?? paymentId,
    );
  }

  /// Pay one of my own fees in full. No amount is sent - the server works out what is owed.
  Future<String> payMyFee({
    required FeeCategory category,
    String? courseId,
    String? period,
    String? feeTypeId,
    String? studentFeeId,
    required String method,
  }) {
    return _client.call(
      (dio) => dio.post('/me/fees/pay', data: {
        'category': category.wire,
        'courseId': courseId,
        'period': period,
        'feeTypeId': feeTypeId,
        'studentFeeId': studentFeeId,
        'method': method,
      }),
      (data) => (data as Map<String, dynamic>)['gatewayRef'] as String? ?? '',
    );
  }

  Future<StudentOtherFees> myOtherFees() {
    return _client.call(
      (dio) => dio.get('/me/fees/other'),
      (data) => StudentOtherFees.fromJson(data as Map<String, dynamic>),
    );
  }

  /// Every payment the academy took between two dates. Totals come back matching the filters.
  Future<TransactionLedger> transactions({
    required DateTime from,
    required DateTime to,
    FeeCategory? category,
    String? query,
  }) {
    String day(DateTime d) => d.toIso8601String().split('T').first;
    return _client.call(
      (dio) => dio.get('/fees/transactions', queryParameters: {
        'from': day(from),
        'to': day(to),
        'category': ?category?.wire,
        'query': ?(query != null && query.trim().isNotEmpty ? query.trim() : null),
      }),
      (data) => TransactionLedger.fromJson(data as Map<String, dynamic>),
    );
  }

  /// Both categories' totals for the landing, optionally narrowed to a course and/or batch.
  Future<FeeSummary> summary({required String period, String? courseId, String? batchId}) {
    return _client.call(
      (dio) => dio.get('/fees/summary', queryParameters: {
        'period': period,
        'courseId': ?courseId,
        'batchId': ?batchId,
      }),
      (data) => FeeSummary.fromJson(data as Map<String, dynamic>),
    );
  }

  Future<List<StudentSearchResult>> searchStudents(String query) {
    return _client.call(
      (dio) => dio.get('/fees/students/search', queryParameters: {'query': query}),
      (data) => (data as List)
          .map((e) => StudentSearchResult.fromJson(e as Map<String, dynamic>))
          .toList(),
    );
  }

  /// Every Other fee that applies to one student - shared types plus their own one-offs.
  Future<StudentOtherFees> studentOtherFees(String membershipId) {
    return _client.call(
      (dio) => dio.get('/students/$membershipId/other-fees'),
      (data) => StudentOtherFees.fromJson(data as Map<String, dynamic>),
    );
  }

  // ---- Other Fees ----

  Future<List<FeeType>> feeTypes({bool includeRetired = false}) {
    return _client.call(
      (dio) => dio.get('/fees/other/types',
          queryParameters: {'includeRetired': includeRetired}),
      (data) => (data as List).map((e) => FeeType.fromJson(e as Map<String, dynamic>)).toList(),
    );
  }

  Future<FeeType> createFeeType({
    required String name,
    required num amount,
    required List<String> batchIds,
    DateTime? dueDate,
    String? defaultMode,
    List<String>? paymentMethods,
  }) {
    return _client.call(
      (dio) => dio.post('/fees/other/types', data: {
        'name': name,
        'amount': amount,
        'batchIds': batchIds,
        'dueDate': ?dueDate?.toIso8601String().split('T').first,
        'defaultMode': ?defaultMode,
        'paymentMethods': ?paymentMethods,
      }),
      (data) => FeeType.fromJson(data as Map<String, dynamic>),
    );
  }

  /// Edits a shared fee in place. Everything is replaced as sent, so a null [dueDate] clears it.
  Future<FeeType> updateFeeType({
    required String feeTypeId,
    required String name,
    required num amount,
    required List<String> batchIds,
    DateTime? dueDate,
    List<String>? paymentMethods,
  }) {
    return _client.call(
      (dio) => dio.put('/fees/other/types/$feeTypeId', data: {
        'name': name,
        'amount': amount,
        'batchIds': batchIds,
        'dueDate': dueDate?.toIso8601String().split('T').first,
        'paymentMethods': ?paymentMethods,
      }),
      (data) => FeeType.fromJson(data as Map<String, dynamic>),
    );
  }

  /// Changes what ONE student owes for one Other fee - a discount on a shared fee, or the price of
  /// their own one-off. Exactly one of [feeTypeId] and [studentFeeId] is set.
  Future<void> updateOtherAmount({
    required String membershipId,
    String? feeTypeId,
    String? studentFeeId,
    required num amount,
  }) {
    return _client.call(
      (dio) => dio.patch('/fees/other/amount', data: {
        'membershipId': membershipId,
        'feeTypeId': ?feeTypeId,
        'studentFeeId': ?studentFeeId,
        'amount': amount,
      }),
      (_) {},
    );
  }

  Future<FeeRoster> otherRoster({required String feeTypeId, required String batchId}) {
    return _client.call(
      (dio) => dio.get('/fees/other/roster',
          queryParameters: {'feeTypeId': feeTypeId, 'batchId': batchId}),
      (data) => FeeRoster.fromJson(data as Map<String, dynamic>),
    );
  }

  Future<void> recordOtherPayment({
    required String membershipId,
    String? feeTypeId,
    String? studentFeeId,
    required num amountPaid,
    required String mode,
    String? gatewayRef,
  }) {
    return _client.call(
      (dio) => dio.post('/fees/other/entries', data: {
        'membershipId': membershipId,
        'feeTypeId': ?feeTypeId,
        'studentFeeId': ?studentFeeId,
        'amountPaid': amountPaid,
        'mode': mode,
        'gatewayRef': ?gatewayRef,
      }),
      (_) {},
    );
  }

  Future<void> createStudentFee({
    required String membershipId,
    required String name,
    required num amount,
    DateTime? dueDate,
    String? defaultMode,
    List<String>? paymentMethods,
    String? note,
  }) {
    return _client.call(
      (dio) => dio.post('/fees/other/student-fees', data: {
        'membershipId': membershipId,
        'name': name,
        'amount': amount,
        'dueDate': ?dueDate?.toIso8601String().split('T').first,
        'defaultMode': ?defaultMode,
        'paymentMethods': ?paymentMethods,
        'note': ?note,
      }),
      (_) {},
    );
  }

}
