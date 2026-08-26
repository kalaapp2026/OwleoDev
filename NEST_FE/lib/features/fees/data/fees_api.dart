import 'package:dio/dio.dart';
import 'package:nest_fe/core/network/dio_client.dart';
import 'package:nest_fe/features/fees/data/fee_roster.dart';
import 'package:nest_fe/features/fees/data/fee_transaction.dart';

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

  Future<List<FeeTransaction>> historyForStudent(String membershipId) {
    return _client.call(
      (dio) => dio.get('/students/$membershipId/fees'),
      (data) => (data as List).map((e) => FeeTransaction.fromJson(e as Map<String, dynamic>)).toList(),
    );
  }

  /// Manual "generate now" trigger - same calculation the daily billing-day cron runs, for
  /// testing or catching up a course whose billing day already passed this month. Idempotent:
  /// re-running for a period that already has a slip just skips that student server-side.
  Future<List<FeeSlip>> generateFeeSlips(String courseId) {
    return _client.call(
      (dio) => dio.post('/courses/$courseId/fee-slips/generate'),
      (data) => (data as List).map((e) => FeeSlip.fromJson(e as Map<String, dynamic>)).toList(),
    );
  }

  Future<List<FeeSlip>> feeSlipHistory(String membershipId) {
    return _client.call(
      (dio) => dio.get('/students/$membershipId/fee-slips'),
      (data) => (data as List).map((e) => FeeSlip.fromJson(e as Map<String, dynamic>)).toList(),
    );
  }

  /// The download button - a CSV of every student mapped to this course for this period.
  Future<List<int>> downloadReport({required String courseId, required String period}) {
    return _client.call(
      (dio) => dio.get(
        '/fees/report',
        queryParameters: {'courseId': courseId, 'period': period},
        options: Options(responseType: ResponseType.bytes),
      ),
      (data) => data as List<int>,
    );
  }
}
