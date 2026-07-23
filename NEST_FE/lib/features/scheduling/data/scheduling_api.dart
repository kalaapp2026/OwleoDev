import 'package:nest_fe/core/network/dio_client.dart';
import 'package:nest_fe/features/attendance/data/class_instance.dart';

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
}
