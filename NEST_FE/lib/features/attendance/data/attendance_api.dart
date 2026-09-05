import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:nest_fe/core/network/dio_client.dart';
import 'package:nest_fe/core/providers/core_providers.dart';
import 'package:nest_fe/features/attendance/data/class_instance.dart';
import 'package:nest_fe/features/attendance/data/student_attendance.dart';

final attendanceApiProvider = Provider((ref) => AttendanceApi(ref.watch(dioClientProvider)));

/// The roster for one class, with names - the marking screen's source.
final batchRosterProvider =
    FutureProvider.autoDispose.family<List<BatchMemberSummary>, String>((ref, batchId) {
  return ref.watch(attendanceApiProvider).memberSummariesForBatch(batchId);
});

/// Whatever has already been marked for a class, so reopening it shows the existing answers
/// rather than resetting everyone to present.
final classAttendanceProvider =
    FutureProvider.autoDispose.family<List<AttendanceRecord>, String>((ref, classInstanceId) {
  return ref.watch(attendanceApiProvider).forClassInstance(classInstanceId);
});

/// A student's marked sessions joined to their dates - the attendance profile.
final studentAttendanceProvider =
    FutureProvider.autoDispose.family<List<StudentAttendanceRecord>, String>((ref, membershipId) {
  ref.watch(activeMembershipIdProvider);
  return ref.watch(attendanceApiProvider).detailedHistory(membershipId);
});

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

  /// Marked sessions joined to the dates they were held, newest first. Distinct from the plain
  /// history endpoint, which carries when someone pressed submit rather than the class date -
  /// those diverge as soon as a record is corrected later.
  Future<List<StudentAttendanceRecord>> detailedHistory(String membershipId, {String? batchId}) {
    return _client.call(
      (dio) => dio.get('/students/$membershipId/attendance/detailed',
          queryParameters: {'batchId': ?batchId}),
      (data) => (data as List)
          .map((e) => StudentAttendanceRecord.fromJson(e as Map<String, dynamic>))
          .toList(),
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
