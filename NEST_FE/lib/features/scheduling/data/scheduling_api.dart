import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:nest_fe/core/network/dio_client.dart';
import 'package:nest_fe/core/providers/core_providers.dart';
import 'package:nest_fe/features/attendance/data/class_instance.dart';
import 'package:nest_fe/features/scheduling/data/schedule_entry.dart';

final schedulingApiProvider = Provider((ref) => SchedulingApi(ref.watch(dioClientProvider)));

/// The schedule feed, keyed by the window and course filter. A record key gives value equality,
/// so scrolling back to a month already fetched reuses the cached result instead of refetching.
typedef ScheduleFeedKey = ({DateTime from, DateTime to, String? courseId});

final scheduleFeedProvider =
    FutureProvider.autoDispose.family<List<ScheduleEntry>, ScheduleFeedKey>((ref, key) {
  ref.watch(activeMembershipIdProvider);
  return ref
      .watch(schedulingApiProvider)
      .feed(from: key.from, to: key.to, courseId: key.courseId);
});

/// A batch's current weekly pattern - what the batch form pre-fills its day and time pickers
/// from when editing.
final batchScheduleProvider =
    FutureProvider.autoDispose.family<List<ScheduleSlotResponse>, String>((ref, batchId) {
  return ref.watch(schedulingApiProvider).currentSchedule(batchId);
});

class ScheduleSlotResponse {
  final String id;
  final String batchId;
  final String dayOfWeek;
  final String startTime;
  final String endTime;
  final String effectiveFrom;
  final String? effectiveTo;

  ScheduleSlotResponse({
    required this.id,
    required this.batchId,
    required this.dayOfWeek,
    required this.startTime,
    required this.endTime,
    required this.effectiveFrom,
    required this.effectiveTo,
  });

  factory ScheduleSlotResponse.fromJson(Map<String, dynamic> json) => ScheduleSlotResponse(
        id: json['id'] as String,
        batchId: json['batchId'] as String,
        dayOfWeek: json['dayOfWeek'] as String,
        startTime: json['startTime'] as String,
        endTime: json['endTime'] as String,
        effectiveFrom: json['effectiveFrom'] as String,
        effectiveTo: json['effectiveTo'] as String?,
      );
}

class SchedulingApi {
  SchedulingApi(this._client);
  final DioClient _client;

  /// Also how an existing batch's schedule gets CHANGED, not just set for the first time - the
  /// backend closes out whatever's currently in effect as of the day before effectiveFrom and
  /// cancels its not-yet-held future classes, so the new pattern "continues from here on".
  Future<void> setSchedule({
    required String batchId,
    required List<Map<String, String>> slots, // [{dayOfWeek, startTime, endTime}]
    required String effectiveFrom, // yyyy-MM-dd
  }) {
    return _client.callVoid((dio) => dio.post('/schedules', data: {
          'batchId': batchId,
          'slots': slots,
          'effectiveFrom': effectiveFrom,
        }));
  }

  /// Current weekly pattern (still-open rows only) - pre-fills the Edit batch schedule form.
  Future<List<ScheduleSlotResponse>> currentSchedule(String batchId) {
    return _client.call(
      (dio) => dio.get('/batches/$batchId/schedule'),
      (data) => (data as List).map((e) => ScheduleSlotResponse.fromJson(e as Map<String, dynamic>)).toList(),
    );
  }

  Future<List<ClassInstance>> upcomingClassInstances(String batchId) {
    return _client.call(
      (dio) => dio.get('/batches/$batchId/class-instances'),
      (data) => (data as List).map((e) => ClassInstance.fromJson(e as Map<String, dynamic>)).toList(),
    );
  }

  Future<ClassInstance> reschedule({
    required String classInstanceId,
    required String newDate,
    required String newStartTime,
    required String newEndTime,
    required String reason,
  }) {
    return _client.call(
      (dio) => dio.post('/class-instances/$classInstanceId/reschedule', data: {
        'newDate': newDate,
        'newStartTime': newStartTime,
        'newEndTime': newEndTime,
        'reason': reason,
      }),
      (data) => ClassInstance.fromJson(data as Map<String, dynamic>),
    );
  }

  /// Every class in the academy over a window, joined to batch, course and instructors.
  Future<List<ScheduleEntry>> feed({
    required DateTime from,
    required DateTime to,
    String? courseId,
  }) {
    return _client.call(
      (dio) => dio.get('/schedule/feed', queryParameters: {
        'from': isoDate(from),
        'to': isoDate(to),
        // Omitted rather than sent as null - the backend reads absence as "every course".
        'courseId': ?courseId,
      }),
      (data) => (data as List)
          .map((e) => ScheduleEntry.fromJson(e as Map<String, dynamic>))
          .toList(),
    );
  }

  Future<void> cancelClass({required String classInstanceId, required String reason}) {
    return _client.callVoid(
      (dio) => dio.post('/class-instances/$classInstanceId/cancel', data: {'reason': reason}),
    );
  }

  Future<void> restoreClass(String classInstanceId) {
    return _client.callVoid((dio) => dio.post('/class-instances/$classInstanceId/restore'));
  }

  Future<void> swapInstructor({
    required String classInstanceId,
    required String substituteMembershipId,
    String? reason,
  }) {
    return _client.callVoid(
      (dio) => dio.post('/class-instances/$classInstanceId/swap-instructor', data: {
        'substituteMembershipId': substituteMembershipId,
        'reason': reason,
      }),
    );
  }

  Future<void> undoSwap(String classInstanceId) {
    return _client.callVoid((dio) => dio.post('/class-instances/$classInstanceId/undo-swap'));
  }

  /// Accepts either half of the reschedule - the caller is holding one row and needn't work out
  /// whether it's the origin or the replacement.
  Future<void> undoReschedule(String classInstanceId) {
    return _client
        .callVoid((dio) => dio.post('/class-instances/$classInstanceId/undo-reschedule'));
  }

  /// `yyyy-MM-dd`. A full ISO instant would be rejected by LocalDate, and sending a local
  /// date-time can shift the day across timezones.
  static String isoDate(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-'
      '${d.month.toString().padLeft(2, '0')}-'
      '${d.day.toString().padLeft(2, '0')}';
}
