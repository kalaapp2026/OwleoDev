/// One calendar entry - a class instance already joined with batch/course/academy names, plus
/// which of the caller's own memberships it came from (the colour-coding key for a multi-academy
/// calendar).
class CalendarClass {
  final String classInstanceId;
  final String date;
  final String startTime;
  final String endTime;
  final String status;
  final String batchId;
  final String batchName;
  final String? courseId;
  final String? courseName;
  final String academyId;
  final String? academyName;
  final String membershipId;

  const CalendarClass({
    required this.classInstanceId,
    required this.date,
    required this.startTime,
    required this.endTime,
    required this.status,
    required this.batchId,
    required this.batchName,
    required this.courseId,
    required this.courseName,
    required this.academyId,
    required this.academyName,
    required this.membershipId,
  });

  factory CalendarClass.fromJson(Map<String, dynamic> json) => CalendarClass(
        classInstanceId: json['classInstanceId'] as String,
        date: json['date'] as String,
        startTime: json['startTime'] as String,
        endTime: json['endTime'] as String,
        status: json['status'] as String,
        batchId: json['batchId'] as String,
        batchName: json['batchName'] as String,
        courseId: json['courseId'] as String?,
        courseName: json['courseName'] as String?,
        academyId: json['academyId'] as String,
        academyName: json['academyName'] as String?,
        membershipId: json['membershipId'] as String,
      );
}
