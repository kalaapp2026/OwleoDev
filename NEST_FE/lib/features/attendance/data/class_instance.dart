class ClassInstance {
  final String id;
  final String batchId;
  final String date;
  final String startTime;
  final String endTime;
  final String status;
  final String? rescheduleReason;
  final String? originalInstanceId;

  const ClassInstance({
    required this.id,
    required this.batchId,
    required this.date,
    required this.startTime,
    required this.endTime,
    required this.status,
    required this.rescheduleReason,
    required this.originalInstanceId,
  });

  factory ClassInstance.fromJson(Map<String, dynamic> json) => ClassInstance(
        id: json['id'] as String,
        batchId: json['batchId'] as String,
        date: json['date'] as String,
        startTime: json['startTime'] as String,
        endTime: json['endTime'] as String,
        status: json['status'] as String,
        rescheduleReason: json['rescheduleReason'] as String?,
        originalInstanceId: json['originalInstanceId'] as String?,
      );
}

/// One roster row for the attendance marking screen - a real name and photo, not a bare
/// membership UUID.
class BatchMemberSummary {
  final String membershipId;
  final String userId;
  final String username;
  final String fullName;
  final String? profileImageUrl;

  /// Which of the batch's courses this student is on - null if the server could not resolve it.
  final String? courseId;
  final String? courseName;

  const BatchMemberSummary({
    required this.membershipId,
    required this.userId,
    required this.username,
    required this.fullName,
    required this.profileImageUrl,
    this.courseId,
    this.courseName,
  });

  factory BatchMemberSummary.fromJson(Map<String, dynamic> json) => BatchMemberSummary(
        membershipId: json['membershipId'] as String,
        userId: json['userId'] as String,
        username: json['username'] as String,
        fullName: json['fullName'] as String,
        profileImageUrl: json['profileImageUrl'] as String?,
        courseId: json['courseId'] as String?,
        courseName: json['courseName'] as String?,
      );
}

/// A batch's roster as the caller may see it. A batch can span several courses and a trainer sees
/// only the students of the courses they hold; [hiddenCount] is how many others are in the batch.
class BatchRoster {
  const BatchRoster({required this.students, required this.hiddenCount});

  final List<BatchMemberSummary> students;
  final int hiddenCount;

  factory BatchRoster.fromJson(Map<String, dynamic> json) => BatchRoster(
        students: ((json['students'] as List?) ?? const [])
            .map((e) => BatchMemberSummary.fromJson(e as Map<String, dynamic>))
            .toList(),
        hiddenCount: (json['hiddenCount'] as num?)?.toInt() ?? 0,
      );
}

class AttendanceRecord {
  final String id;
  final String classInstanceId;
  final String membershipId;
  final String status;
  final String markedBy;
  final String markedAt;
  final String? note;

  const AttendanceRecord({
    required this.id,
    required this.classInstanceId,
    required this.membershipId,
    required this.status,
    required this.markedBy,
    required this.markedAt,
    required this.note,
  });

  factory AttendanceRecord.fromJson(Map<String, dynamic> json) => AttendanceRecord(
        id: json['id'] as String,
        classInstanceId: json['classInstanceId'] as String,
        membershipId: json['membershipId'] as String,
        status: json['status'] as String,
        markedBy: json['markedBy'] as String,
        markedAt: json['markedAt'] as String,
        note: json['note'] as String?,
      );
}
