import 'package:nest_fe/core/network/dio_client.dart';
import 'package:nest_fe/features/attendance/data/class_instance.dart';

class AttendanceApi {
  AttendanceApi(this._client);
  final DioClient _client;

  Future<List<ClassInstance>> classInstancesForBatch(String batchId) {
    return _client.call(
      (dio) => dio.get('/batches/$batchId/class-instances'),
      (data) => (data as List).map((e) => ClassInstance.fromJson(e as Map<String, dynamic>)).toList(),
    );
  }

  Future<List<String>> membersForBatch(String batchId) {
    return _client.call(
      (dio) => dio.get('/batches/$batchId/members'),
      (data) => List<String>.from(data as List),
    );
  }

  /// A real name and photo per student, not a bare membership UUID - the marking screen's roster source.
  Future<List<BatchMemberSummary>> memberSummariesForBatch(String batchId) {
    return _client.call(
      (dio) => dio.get('/batches/$batchId/members/summary'),
      (data) => (data as List).map((e) => BatchMemberSummary.fromJson(e as Map<String, dynamic>)).toList(),
    );
  }

  /// "Add a class" - a one-off session not on the weekly schedule, immediately available to mark
  /// attendance against.
  Future<ClassInstance> addClassInstance({
    required String batchId,
    required String date,
    required String startTime,
    required String endTime,
  }) {
    return _client.call(
      (dio) => dio.post('/batches/$batchId/class-instances', data: {
        'date': date,
        'startTime': startTime,
        'endTime': endTime,
      }),
      (data) => ClassInstance.fromJson(data as Map<String, dynamic>),
    );
  }

  Future<List<AttendanceRecord>> forClassInstance(String classInstanceId) {
    return _client.call(
      (dio) => dio.get('/class-instances/$classInstanceId/attendance'),
      (data) => (data as List).map((e) => AttendanceRecord.fromJson(e as Map<String, dynamic>)).toList(),
    );
  }

  Future<void> submitSheet(String classInstanceId, Map<String, String> statusByMembershipId) {
    return _client.callVoid((dio) => dio.post('/class-instances/$classInstanceId/attendance', data: {
          'entries': statusByMembershipId.entries
              .map((e) => {'membershipId': e.key, 'status': e.value, 'note': null})
              .toList(),
        }));
  }
}
