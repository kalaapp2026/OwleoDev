import 'package:flutter/widgets.dart';
import 'package:nest_fe/app/theme/app_tokens.dart';

/// Present or absent when a trainer marks a class - deliberately only two, since the marking flow
/// is a single tap per student and a third state (late, excused) would turn every row into a menu.
///
/// [holiday] is never marked and never submitted: it is how a student's own history shows a class
/// that was cancelled. It counts towards neither side of their attendance.
enum AttendanceStatus {
  present('PRESENT', 'Present'),
  absent('ABSENT', 'Absent'),
  holiday('HOLIDAY', 'Holiday');

  const AttendanceStatus(this.wire, this.label);

  final String wire;
  final String label;

  static AttendanceStatus fromWire(String? value) => switch (value) {
        'ABSENT' => AttendanceStatus.absent,
        'HOLIDAY' => AttendanceStatus.holiday,
        _ => AttendanceStatus.present,
      };

  Color color(AppPalette p) => switch (this) {
        AttendanceStatus.present => p.paidManual,
        AttendanceStatus.absent => p.notPaid,
        AttendanceStatus.holiday => p.textFaint,
      };

  Color softColor(AppPalette p) => switch (this) {
        AttendanceStatus.present => p.paidManualSoft,
        AttendanceStatus.absent => p.notPaidSoft,
        AttendanceStatus.holiday => p.surfaceHigh,
      };
}

/// One marked session in a student's history, joined to the date it was actually held.
class StudentAttendanceRecord {
  const StudentAttendanceRecord({
    required this.classInstanceId,
    required this.date,
    required this.startTime,
    required this.endTime,
    required this.status,
    required this.batchId,
    required this.batchName,
    required this.courseId,
    required this.courseName,
    required this.note,
    this.markedByName,
    this.markedAt,
  });

  final String classInstanceId;
  final DateTime date;
  final String startTime;
  final String endTime;
  final AttendanceStatus status;
  final String batchId;
  final String? batchName;
  final String? courseId;
  final String? courseName;
  final String? note;

  /// Who recorded it and when; null for a holiday.
  final String? markedByName;
  final DateTime? markedAt;

  bool get isHoliday => status == AttendanceStatus.holiday;

  factory StudentAttendanceRecord.fromJson(Map<String, dynamic> json) =>
      StudentAttendanceRecord(
        classInstanceId: json['classInstanceId'] as String,
        date: DateTime.parse(json['date'] as String),
        startTime: json['startTime'] as String? ?? '',
        endTime: json['endTime'] as String? ?? '',
        status: AttendanceStatus.fromWire(json['status'] as String?),
        batchId: json['batchId'] as String,
        batchName: json['batchName'] as String?,
        courseId: json['courseId'] as String?,
        courseName: json['courseName'] as String?,
        note: json['note'] as String?,
        markedByName: json['markedByName'] as String?,
        markedAt: json['markedAt'] == null ? null : DateTime.tryParse(json['markedAt'] as String)?.toLocal(),
      );
}

/// A month's worth of a student's attendance, with the counts the profile header shows.
@immutable
class AttendanceMonthSummary {
  const AttendanceMonthSummary({
    required this.records,
    required this.present,
    required this.absent,
  });

  final List<StudentAttendanceRecord> records;
  final int present;
  final int absent;

  int get total => present + absent;

  /// Null rather than zero when nothing is recorded - "0%" reads as terrible attendance, when
  /// what actually happened is that no class in this month has been marked yet.
  double? get presentRatio => total == 0 ? null : present / total;

  static AttendanceMonthSummary of(
      List<StudentAttendanceRecord> all, DateTime month) {
    final inMonth = all
        .where((r) => r.date.year == month.year && r.date.month == month.month)
        .toList();
    return AttendanceMonthSummary(
      records: inMonth,
      present: inMonth.where((r) => r.status == AttendanceStatus.present).length,
      absent: inMonth.where((r) => r.status == AttendanceStatus.absent).length,
    );
  }
}
