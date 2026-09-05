import 'package:flutter/widgets.dart';
import 'package:nest_fe/app/theme/app_tokens.dart';

/// Present or absent. Deliberately only two - the prototype's marking flow is a single tap per
/// student, and a third state (late, excused) would turn every row into a menu.
enum AttendanceStatus {
  present('PRESENT', 'Present'),
  absent('ABSENT', 'Absent');

  const AttendanceStatus(this.wire, this.label);

  final String wire;
  final String label;

  static AttendanceStatus fromWire(String? value) =>
      value == 'ABSENT' ? AttendanceStatus.absent : AttendanceStatus.present;

  Color color(AppPalette p) =>
      this == AttendanceStatus.present ? p.paidManual : p.notPaid;

  Color softColor(AppPalette p) =>
      this == AttendanceStatus.present ? p.paidManualSoft : p.notPaidSoft;
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
