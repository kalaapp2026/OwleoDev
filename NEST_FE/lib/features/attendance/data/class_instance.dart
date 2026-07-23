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

  const BatchMemberSummary({
    required this.membershipId,
    required this.userId,
    required this.username,
    required this.fullName,
    required this.profileImageUrl,
  });

  factory BatchMemberSummary.fromJson(Map<String, dynamic> json) => BatchMemberSummary(
        membershipId: json['membershipId'] as String,
        userId: json['userId'] as String,
        username: json['username'] as String,
        fullName: json['fullName'] as String,
        profileImageUrl: json['profileImageUrl'] as String?,
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
