import 'package:flutter_test/flutter_test.dart';
import 'package:nest_fe/features/attendance/data/student_attendance.dart';

Map<String, dynamic> _json(String status, {String? note, String? markedBy}) => {
      'classInstanceId': 'c1',
      'date': '2026-10-19',
      'startTime': '20:00:00',
      'endTime': '21:00:00',
      'status': status,
      'batchId': 'b1',
      'batchName': 'Morning batch',
      'courseId': 'k1',
      'courseName': 'Bharatanatyam',
      'note': note,
      'markedByName': markedBy,
      'markedAt': '2026-10-19T14:30:00Z',
    };

void main() {
  group('student attendance record', () {
    test('a cancelled class arrives as a holiday and is not counted either way', () {
      final holiday = StudentAttendanceRecord.fromJson(_json('HOLIDAY', note: 'Public holiday'));
      expect(holiday.isHoliday, isTrue);
      expect(holiday.status, AttendanceStatus.holiday);
      expect(holiday.note, 'Public holiday');

      final month = AttendanceMonthSummary.of([
        holiday,
        StudentAttendanceRecord.fromJson(_json('PRESENT')),
        StudentAttendanceRecord.fromJson(_json('ABSENT')),
      ], DateTime(2026, 10));
      expect(month.present, 1);
      expect(month.absent, 1);
      expect(month.total, 2);
    });

    test('who marked it and when are read when the server sends them', () {
      final r = StudentAttendanceRecord.fromJson(_json('PRESENT', markedBy: 'Bhuvana Holla'));
      expect(r.markedByName, 'Bhuvana Holla');
      expect(r.markedAt, isNotNull);
      expect(r.isHoliday, isFalse);
    });

    test('anything unrecognised still reads as present, as before', () {
      expect(AttendanceStatus.fromWire(null), AttendanceStatus.present);
      expect(AttendanceStatus.fromWire('ABSENT'), AttendanceStatus.absent);
      expect(AttendanceStatus.fromWire('HOLIDAY'), AttendanceStatus.holiday);
    });
  });
}
