import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:nest_fe/core/network/dio_client.dart';
import 'package:nest_fe/core/providers/core_providers.dart';
import 'package:nest_fe/features/curriculum/data/course.dart';

final curriculumApiProvider = Provider((ref) => CurriculumApi(ref.watch(dioClientProvider)));

/// Active academy's course list - re-fetches whenever the caller switches which academy
/// membership is active (see activeMembershipIdProvider), not just on app start.
final activeCoursesProvider = FutureProvider.autoDispose((ref) {
  ref.watch(activeMembershipIdProvider);
  return ref.watch(curriculumApiProvider).listActiveCourses();
});

/// Course-management admin view - every course regardless of status, so a deactivated course can
/// still be found and reactivated. Only ever watched from screens already gated on
/// COURSE_MANAGEMENT, since the backend 403s this endpoint for anyone without that feature.
final allCoursesProvider = FutureProvider.autoDispose((ref) {
  ref.watch(activeMembershipIdProvider);
  return ref.watch(curriculumApiProvider).listAllCourses();
});

/// Courses a specific membership (student) is actually mapped to - keyed by membershipId so the
/// Fees screen's course picker only ever offers courses that student can plausibly owe fees for.
final coursesForMembershipProvider = FutureProvider.autoDispose.family<List<Course>, String>((ref, membershipId) {
  ref.watch(activeMembershipIdProvider);
  return ref.watch(curriculumApiProvider).listCoursesForMembership(membershipId);
});

class CurriculumApi {
  CurriculumApi(this._client);
  final DioClient _client;

  Future<List<Course>> listActiveCourses() {
    return _client.call(
      (dio) => dio.get('/courses'),
      (data) => (data as List).map((e) => Course.fromJson(e as Map<String, dynamic>)).toList(),
    );
  }

  Future<List<Course>> listAllCourses() {
    return _client.call(
      (dio) => dio.get('/courses/all'),
      (data) => (data as List).map((e) => Course.fromJson(e as Map<String, dynamic>)).toList(),
    );
  }

  /// Just the courses this one membership is actually mapped to - e.g. the Fees screen's "look up
  /// a student" course picker, so a student mapped to 1 of the academy's 2 courses doesn't appear
  /// to have access to both.
  Future<List<Course>> listCoursesForMembership(String membershipId) {
    return _client.call(
      (dio) => dio.get('/courses', queryParameters: {'membershipId': membershipId}),
      (data) => (data as List).map((e) => Course.fromJson(e as Map<String, dynamic>)).toList(),
    );
  }

  Future<Course> getCourse(String id) {
    return _client.call(
      (dio) => dio.get('/courses/$id'),
      (data) => Course.fromJson(data as Map<String, dynamic>),
    );
  }

  Future<Course> createCourse({
    required String category,
    required String name,
    String? description,
    String? durationLevel,
    required FeeModel feeModel,
    num? defaultFee,
    num? feePerClass,
    int? hybridExpectedClassesPerPeriod,
    int? hybridThresholdAttendance,
    int? hybridFeeAboveThresholdPercent,
    int? hybridFeeBelowThresholdPercent,
    num? hybridMinFeeAmount,
    required String feeCycle,
    String? thumbnailUrl,
    int? billingDayOfMonth,
  }) {
    return _client.call(
      (dio) => dio.post('/courses', data: {
        'category': category,
        'name': name,
        'description': description,
        'durationLevel': durationLevel,
        'feeModel': feeModelToApiString(feeModel),
        'defaultFee': defaultFee,
        'feePerClass': feePerClass,
        'hybridExpectedClassesPerPeriod': hybridExpectedClassesPerPeriod,
        'hybridThresholdAttendance': hybridThresholdAttendance,
        'hybridFeeAboveThresholdPercent': hybridFeeAboveThresholdPercent,
        'hybridFeeBelowThresholdPercent': hybridFeeBelowThresholdPercent,
        'hybridMinFeeAmount': hybridMinFeeAmount,
        'feeCycle': feeCycle,
        'thumbnailUrl': thumbnailUrl,
        'billingDayOfMonth': billingDayOfMonth,
      }),
      (data) => Course.fromJson(data as Map<String, dynamic>),
    );
  }

  Future<Course> updateCourse(
    String id, {
    required String name,
    String? description,
    String? durationLevel,
    required FeeModel feeModel,
    num? defaultFee,
    num? feePerClass,
    int? hybridExpectedClassesPerPeriod,
    int? hybridThresholdAttendance,
    int? hybridFeeAboveThresholdPercent,
    int? hybridFeeBelowThresholdPercent,
    num? hybridMinFeeAmount,
    String? thumbnailUrl,
    int? billingDayOfMonth,
  }) {
    return _client.call(
      (dio) => dio.put('/courses/$id', data: {
        'name': name,
        'description': description,
        'durationLevel': durationLevel,
        'feeModel': feeModelToApiString(feeModel),
        'defaultFee': defaultFee,
        'feePerClass': feePerClass,
        'hybridExpectedClassesPerPeriod': hybridExpectedClassesPerPeriod,
        'hybridThresholdAttendance': hybridThresholdAttendance,
        'hybridFeeAboveThresholdPercent': hybridFeeAboveThresholdPercent,
        'hybridFeeBelowThresholdPercent': hybridFeeBelowThresholdPercent,
        'hybridMinFeeAmount': hybridMinFeeAmount,
        'thumbnailUrl': thumbnailUrl,
        'billingDayOfMonth': billingDayOfMonth,
      }),
      (data) => Course.fromJson(data as Map<String, dynamic>),
    );
  }

  Future<Course> setStatus(String id, String status) {
    return _client.call(
      (dio) => dio.patch('/courses/$id/status', queryParameters: {'status': status}),
      (data) => Course.fromJson(data as Map<String, dynamic>),
    );
  }
}
