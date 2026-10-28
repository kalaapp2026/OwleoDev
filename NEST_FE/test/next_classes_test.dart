import 'package:flutter_test/flutter_test.dart';
import 'package:nest_fe/features/dashboard/presentation/widgets/next_classes_card.dart';
import 'package:nest_fe/features/scheduling/data/schedule_entry.dart';
import 'package:nest_fe/features/scheduling/data/scheduling_api.dart';

ScheduleEntry _entry(
  String batch,
  DateTime date,
  String start,
  String end, {
  String status = 'SCHEDULED',
  String? lastRemindedAt,
}) =>
    ScheduleEntry.fromJson({
      'classInstanceId': '$batch-${date.toIso8601String()}-$start',
      'date': '${date.year.toString().padLeft(4, '0')}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}',
      'startTime': start,
      'endTime': end,
      'status': status,
      'batchId': batch,
      'batchName': batch,
      'batchType': 'REGULAR',
      'courseId': 'c1',
      'courseName': 'Guitar',
      'courseCategory': 'MUSIC',
      'instructors': const [],
      'regularInstructors': const [],
      'studentCount': 3,
      'lastRemindedAt': lastRemindedAt,
    });

void main() {
  // A Wednesday, 3:00 pm.
  final now = DateTime(2026, 10, 28, 15, 0);
  final today = DateTime(2026, 10, 28);
  final tomorrow = DateTime(2026, 10, 29);

  group('nextClassPerBatch', () {
    test('a course with four batches gives four rows, soonest first', () {
      final feed = [
        _entry('D', tomorrow, '09:00:00', '10:00:00'),
        _entry('A', today, '17:00:00', '18:00:00'),
        _entry('C', tomorrow, '08:00:00', '09:00:00'),
        _entry('B', today, '16:00:00', '17:00:00'),
      ];

      final next = nextClassPerBatch(feed, now);

      expect(next.map((e) => e.batchId), ['B', 'A', 'C', 'D']);
    });

    test('shows only the first upcoming class of each batch', () {
      final feed = [
        _entry('A', today, '17:00:00', '18:00:00'),
        _entry('A', tomorrow, '17:00:00', '18:00:00'),
        _entry('A', DateTime(2026, 10, 30), '17:00:00', '18:00:00'),
      ];

      final next = nextClassPerBatch(feed, now);

      expect(next, hasLength(1));
      expect(next.single.date, today);
    });

    test('a class that has already finished is skipped for the next one', () {
      final feed = [
        _entry('A', today, '09:00:00', '10:00:00'),
        _entry('A', tomorrow, '09:00:00', '10:00:00'),
      ];

      expect(nextClassPerBatch(feed, now).single.date, tomorrow);
    });

    test('a class in progress still counts as the next class', () {
      final feed = [_entry('A', today, '14:30:00', '15:30:00')];

      expect(nextClassPerBatch(feed, now), hasLength(1));
    });

    test('a cancelled class is skipped in favour of the batch\'s next real one', () {
      final feed = [
        _entry('A', today, '17:00:00', '18:00:00', status: 'CANCELLED'),
        _entry('A', tomorrow, '17:00:00', '18:00:00'),
      ];

      expect(nextClassPerBatch(feed, now).single.date, tomorrow);
    });

    test('the vacated half of a reschedule is not a class', () {
      final feed = [
        _entry('A', today, '17:00:00', '18:00:00', status: 'MOVED_OUT'),
        _entry('A', tomorrow, '17:00:00', '18:00:00', status: 'MOVED_IN'),
      ];

      final next = nextClassPerBatch(feed, now);

      expect(next.single.date, tomorrow);
      expect(next.single.status, ScheduleEntryStatus.movedIn);
    });

    test('a batch with nothing coming up is simply absent', () {
      final feed = [
        _entry('A', today, '09:00:00', '10:00:00'),
        _entry('B', tomorrow, '09:00:00', '10:00:00', status: 'HELD'),
      ];

      expect(nextClassPerBatch(feed, now), isEmpty);
    });
  });

  group('classDayLabel', () {
    test('today, tomorrow, then weekday and date', () {
      expect(classDayLabel(today, now), 'Today');
      expect(classDayLabel(tomorrow, now), 'Tomorrow');
      expect(classDayLabel(DateTime(2026, 10, 31), now), 'Sat, 31 Oct');
    });
  });

  group('ScheduleEntry.lastRemindedAt', () {
    test('absent means nobody has reminded yet', () {
      expect(_entry('A', today, '17:00:00', '18:00:00').lastRemindedAt, isNull);
    });

    test('parses the server instant into local time', () {
      final entry =
          _entry('A', today, '17:00:00', '18:00:00', lastRemindedAt: '2026-10-28T09:30:00Z');

      expect(entry.lastRemindedAt, DateTime.utc(2026, 10, 28, 9, 30).toLocal());
    });
  });

  group('ClassReminderResult.summary', () {
    test('names who it reached', () {
      expect(const ClassReminderResult(students: 12, trainers: 2).summary, '12 students and 2 trainers');
      expect(const ClassReminderResult(students: 1, trainers: 1).summary, '1 student and 1 trainer');
      expect(const ClassReminderResult(students: 0, trainers: 1).summary, '1 trainer');
      expect(const ClassReminderResult(students: 5, trainers: 0).summary, '5 students');
    });
  });
}
