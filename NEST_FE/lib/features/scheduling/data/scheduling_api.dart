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

/// The same feed for the Dashboard's "today" card: a class is shown if the person holds Attendance,
/// Reschedule or Batch scheduling on its course - whichever of the three they were given - rather
/// than only the Schedule screen's pair. A trainer who only marks attendance still sees their classes.
final dashboardFeedProvider =
    FutureProvider.autoDispose.family<List<ScheduleEntry>, ScheduleFeedKey>((ref, key) {
  ref.watch(activeMembershipIdProvider);
  return ref
      .watch(schedulingApiProvider)
      .feed(from: key.from, to: key.to, courseId: key.courseId, feature: 'ALL');
});

/// The same feed, scoped by the Attendance permission - what the Attendance screen and its calendar
/// read. A separate provider rather than another field on [ScheduleFeedKey], which several other
/// screens build by hand.
final attendanceFeedProvider =
    FutureProvider.autoDispose.family<List<ScheduleEntry>, ScheduleFeedKey>((ref, key) {
  ref.watch(activeMembershipIdProvider);
  return ref
      .watch(schedulingApiProvider)
      .feed(from: key.from, to: key.to, courseId: key.courseId, feature: 'ATTENDANCE');
});

/// A batch's current weekly pattern - what the batch form pre-fills its day and time pickers
/// from when editing.
final batchScheduleProvider =
    FutureProvider.autoDispose.family<List<ScheduleSlotResponse>, String>((ref, batchId) {
  return ref.watch(schedulingApiProvider).currentSchedule(batchId);
});

/// Who a class reminder reached.
class ClassReminderResult {
  const ClassReminderResult({required this.students, required this.trainers});

  final int students;
  final int trainers;

  /// "12 students and 2 trainers" - the confirmation toast.
  String get summary {
    String part(int n, String noun) => '$n $noun${n == 1 ? '' : 's'}';
    if (students > 0 && trainers > 0) {
      return '${part(students, 'student')} and ${part(trainers, 'trainer')}';
    }
    return students > 0 ? part(students, 'student') : part(trainers, 'trainer');
  }

  factory ClassReminderResult.fromJson(Map<String, dynamic> json) => ClassReminderResult(
        students: (json['students'] as num?)?.toInt() ?? 0,
        trainers: (json['trainers'] as num?)?.toInt() ?? 0,
      );
}

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

    /// Which permission scopes the courses shown - `ATTENDANCE` for the Attendance screen. Omitted
    /// for the Schedule screen, which is scoped by Reschedule.
    String? feature,
  }) {
    return _client.call(
      (dio) => dio.get('/schedule/feed', queryParameters: {
        'from': isoDate(from),
        'to': isoDate(to),
        // Omitted rather than sent as null - the backend reads absence as "every course".
        'courseId': ?courseId,
        'feature': ?feature,
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

  /// Tells the batch's students and the teaching trainers that this class is coming up - an
  /// in-app notification and a push. The server refuses a second reminder within a few minutes.
  Future<ClassReminderResult> remindClass(String classInstanceId) {
    return _client.call(
      (dio) => dio.post('/class-instances/$classInstanceId/remind'),
      (data) => ClassReminderResult.fromJson(data as Map<String, dynamic>),
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
