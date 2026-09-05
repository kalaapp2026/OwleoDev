import 'package:flutter_test/flutter_test.dart';
import 'package:nest_fe/app/theme/app_tokens.dart';
import 'package:nest_fe/features/attendance/data/student_attendance.dart';
import 'package:nest_fe/features/scheduling/data/schedule_entry.dart';

ScheduleEntry entryOn(String date, {String status = 'SCHEDULED', bool marked = false}) =>
    ScheduleEntry.fromJson({
      'classInstanceId': 'ci1',
      'date': date,
      'startTime': '16:00:00',
      'endTime': '17:00:00',
      'status': status,
      'batchId': 'b1',
      'batchName': 'Batch A',
      'batchType': 'REGULAR',
      'courseId': 'c1',
      'courseName': 'Guitar Beginner',
      'courseCategory': 'MUSIC',
      'courseIconKey': 'guitar',
      'instructors': const [],
      'regularInstructors': const [],
      'attendanceMarked': marked,
      'studentCount': 4,
    });

StudentAttendanceRecord record(String date, AttendanceStatus status) =>
    StudentAttendanceRecord.fromJson({
      'classInstanceId': 'ci-$date',
      'date': date,
      'startTime': '16:00:00',
      'endTime': '17:00:00',
      'status': status.wire,
      'batchId': 'b1',
      'batchName': 'Batch A',
      'courseId': 'c1',
      'courseName': 'Guitar Beginner',
      'note': null,
    });

void main() {
  group('who can be marked', () {
    final today = DateTime(2026, 9, 5);

    test('a past or present class can be marked', () {
      expect(entryOn('2026-09-04').canMarkAttendance(today), isTrue);
      expect(entryOn('2026-09-05').canMarkAttendance(today), isTrue);
    });

    test('a future class cannot - marking it would be a guess', () {
      expect(entryOn('2026-09-06').canMarkAttendance(today), isFalse);
    });

    test('a cancelled or vacated class cannot be marked at any date', () {
      // There is nobody to mark for a class that is not happening.
      expect(entryOn('2026-09-04', status: 'CANCELLED').canMarkAttendance(today), isFalse);
      expect(entryOn('2026-09-04', status: 'MOVED_OUT').canMarkAttendance(today), isFalse);
    });

    test('a rescheduled class that landed in the past can still be marked', () {
      expect(entryOn('2026-09-04', status: 'MOVED_IN').canMarkAttendance(today), isTrue);
    });
  });

  group('attendance chip', () {
    final today = DateTime(2026, 9, 5);

    test('a future class reads as upcoming regardless of the marked flag', () {
      expect(entryOn('2026-09-10').attendanceChip(today), AttendanceChip.upcoming);
      expect(entryOn('2026-09-10', marked: true).attendanceChip(today),
          AttendanceChip.upcoming);
    });

    test('a past class distinguishes marked from not marked', () {
      expect(entryOn('2026-09-01').attendanceChip(today), AttendanceChip.notMarked);
      expect(entryOn('2026-09-01', marked: true).attendanceChip(today),
          AttendanceChip.marked);
    });

    test('not-marked and marked are visually distinct', () {
      // This is the whole point of the screen - finding outstanding work at a glance.
      const p = AppPalette.dark;
      expect(AttendanceChip.notMarked.color(p),
          isNot(AttendanceChip.marked.color(p)));
    });
  });

  group('status vocabulary', () {
    test('round-trips both values', () {
      for (final status in AttendanceStatus.values) {
        expect(AttendanceStatus.fromWire(status.wire), status);
      }
    });

    test('an unrecognised status falls back to present, not a crash', () {
      // Present is the safer default: it never invents an absence against a student.
      expect(AttendanceStatus.fromWire('LATE'), AttendanceStatus.present);
      expect(AttendanceStatus.fromWire(null), AttendanceStatus.present);
    });

    test('present and absent never share a colour', () {
      const p = AppPalette.dark;
      expect(AttendanceStatus.present.color(p), isNot(AttendanceStatus.absent.color(p)));
    });
  });

  group('month summary', () {
    final all = [
      record('2026-09-01', AttendanceStatus.present),
      record('2026-09-03', AttendanceStatus.present),
      record('2026-09-05', AttendanceStatus.absent),
      // A different month, which must not leak into September's counts.
      record('2026-08-28', AttendanceStatus.absent),
    ];

    test('counts only the month asked for', () {
      final september = AttendanceMonthSummary.of(all, DateTime(2026, 9));
      expect(september.present, 2);
      expect(september.absent, 1);
      expect(september.total, 3);
      expect(september.records, hasLength(3));
    });

    test('computes the present ratio', () {
      final september = AttendanceMonthSummary.of(all, DateTime(2026, 9));
      expect(september.presentRatio, closeTo(2 / 3, 0.0001));
    });

    test('an unmarked month has a null ratio, not zero', () {
      // 0% would read as terrible attendance; what actually happened is that nothing has been
      // marked yet, and those are entirely different messages.
      final october = AttendanceMonthSummary.of(all, DateTime(2026, 10));
      expect(october.total, 0);
      expect(october.presentRatio, isNull);
    });

    test('a month crossing a year boundary matches on both fields', () {
      final records = [record('2025-09-01', AttendanceStatus.present)];
      expect(AttendanceMonthSummary.of(records, DateTime(2026, 9)).total, 0);
      expect(AttendanceMonthSummary.of(records, DateTime(2025, 9)).total, 1);
    });
  });

  group('record deserialisation', () {
    test('reads the joined batch and course names', () {
      final r = record('2026-09-01', AttendanceStatus.absent);
      expect(r.date, DateTime(2026, 9, 1));
      expect(r.batchName, 'Batch A');
      expect(r.courseName, 'Guitar Beginner');
      expect(r.status, AttendanceStatus.absent);
    });

    test('survives a record whose batch or course no longer resolves', () {
      final r = StudentAttendanceRecord.fromJson({
        'classInstanceId': 'ci1',
        'date': '2026-09-01',
        'status': 'PRESENT',
        'batchId': 'b1',
      });
      expect(r.batchName, isNull);
      expect(r.courseName, isNull);
      expect(r.startTime, '');
    });
  });
}
