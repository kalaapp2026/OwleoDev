import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:nest_fe/core/network/dio_client.dart';
import 'package:nest_fe/features/enrolment/data/batch.dart';

class StudentRegistrationResult {
  final String userId;
  final String membershipId;
  final String username;
  final String fullName;
  final Map<String, num> courseFees;
  final bool pendingConfirmation;
  final String? temporaryPassword;

  StudentRegistrationResult({
    required this.userId,
    required this.membershipId,
    required this.username,
    required this.fullName,
    required this.courseFees,
    required this.pendingConfirmation,
    required this.temporaryPassword,
  });

  factory StudentRegistrationResult.fromJson(Map<String, dynamic> json) => StudentRegistrationResult(
        userId: json['userId'] as String,
        membershipId: json['membershipId'] as String,
        username: json['username'] as String,
        fullName: json['fullName'] as String,
        courseFees: Map<String, num>.from(json['courseFees'] as Map),
        pendingConfirmation: json['pendingConfirmation'] as bool? ?? false,
        temporaryPassword: json['temporaryPassword'] as String?,
      );
}

class TrainerRegistrationResult {
  final String userId;
  final String membershipId;
  final String username;
  final String temporaryPassword;

  TrainerRegistrationResult({
    required this.userId,
    required this.membershipId,
    required this.username,
    required this.temporaryPassword,
  });

  factory TrainerRegistrationResult.fromJson(Map<String, dynamic> json) => TrainerRegistrationResult(
        userId: json['userId'] as String,
        membershipId: json['membershipId'] as String,
        username: json['username'] as String,
        temporaryPassword: json['temporaryPassword'] as String,
      );
}

/// One row for a batch roster picker / the Users management screen. [active] is this person's
/// per-course enrolment state - false means an admin deactivated them from this one course.
class StudentSummary {
  final String membershipId;
  final String userId;
  final String username;
  final String fullName;
  final bool active;

  StudentSummary({
    required this.membershipId,
    required this.userId,
    required this.username,
    required this.fullName,
    required this.active,
  });

  factory StudentSummary.fromJson(Map<String, dynamic> json) => StudentSummary(
        membershipId: json['membershipId'] as String,
        userId: json['userId'] as String,
        username: json['username'] as String,
        fullName: json['fullName'] as String,
        active: json['active'] as bool? ?? true,
      );
}

/// One row for a batch's default-trainer picker / the Users management screen.
class TrainerSummary {
  final String membershipId;
  final String userId;
  final String username;
  final String fullName;
  final bool active;

  TrainerSummary({
    required this.membershipId,
    required this.userId,
    required this.username,
    required this.fullName,
    required this.active,
  });

  factory TrainerSummary.fromJson(Map<String, dynamic> json) => TrainerSummary(
        membershipId: json['membershipId'] as String,
        userId: json['userId'] as String,
        username: json['username'] as String,
        fullName: json['fullName'] as String,
        active: json['active'] as bool? ?? true,
      );
}

/// Pre-fill payload for the trainer edit form.
class TrainerDetail {
  final String userId;
  final String membershipId;
  final String username;
  final String fullName;
  final String? phone;
  final String? email;
  final String? dob;
  final String? address;
  final String? city;
  final String? state;
  final int? yearsOfExperience;
  final Map<String, Set<String>> courseFeatures;

  TrainerDetail({
    required this.userId,
    required this.membershipId,
    required this.username,
    required this.fullName,
    required this.phone,
    required this.email,
    required this.dob,
    required this.address,
    required this.city,
    required this.state,
    required this.yearsOfExperience,
    required this.courseFeatures,
  });

  factory TrainerDetail.fromJson(Map<String, dynamic> json) => TrainerDetail(
        userId: json['userId'] as String,
        membershipId: json['membershipId'] as String,
        username: json['username'] as String,
        fullName: json['fullName'] as String,
        phone: json['phone'] as String?,
        email: json['email'] as String?,
        dob: json['dob'] as String?,
        address: json['address'] as String?,
        city: json['city'] as String?,
        state: json['state'] as String?,
        yearsOfExperience: json['yearsOfExperience'] as int?,
        courseFeatures: ((json['courseFeatures'] as Map?) ?? {}).map(
          (k, v) => MapEntry(k as String, Set<String>.from(v as List)),
        ),
      );
}

/// Pre-fill payload for the student edit form.
class StudentDetail {
  final String userId;
  final String membershipId;
  final String username;
  final String fullName;
  final String? phone;
  final String? email;
  final String? dob;
  final String? address;
  final String? city;
  final String? state;
  final Map<String, num?> courseFees;

  StudentDetail({
    required this.userId,
    required this.membershipId,
    required this.username,
    required this.fullName,
    required this.phone,
    required this.email,
    required this.dob,
    required this.address,
    required this.city,
    required this.state,
    required this.courseFees,
  });

  factory StudentDetail.fromJson(Map<String, dynamic> json) => StudentDetail(
        userId: json['userId'] as String,
        membershipId: json['membershipId'] as String,
        username: json['username'] as String,
        fullName: json['fullName'] as String,
        phone: json['phone'] as String?,
        email: json['email'] as String?,
        dob: json['dob'] as String?,
        address: json['address'] as String?,
        city: json['city'] as String?,
        state: json['state'] as String?,
        courseFees: ((json['courseFees'] as Map?) ?? {}).map(
          (k, v) => MapEntry(k as String, v as num?),
        ),
      );
}

class EnrolmentApi {
  EnrolmentApi(this._client);
  final DioClient _client;

  Future<TrainerDetail> trainerDetail(String membershipId) {
    return _client.call(
      (dio) => dio.get('/trainers/$membershipId'),
      (data) => TrainerDetail.fromJson(data as Map<String, dynamic>),
    );
  }

  Future<void> updateTrainer(
    String membershipId, {
    required String fullName,
    required String phone,
    required String email,
    required String dob,
    String? address,
    String? city,
    String? state,
    int? yearsOfExperience,
    required Map<String, Set<String>> courseFeatures,
  }) {
    return _client.callVoid(
      (dio) => dio.put('/trainers/$membershipId', data: {
        'fullName': fullName,
        'phone': phone,
        'email': email,
        'dob': dob,
        'address': address,
        'city': city,
        'state': state,
        'yearsOfExperience': yearsOfExperience,
        'courseFeatures': courseFeatures.map((courseId, features) => MapEntry(courseId, features.toList())),
      }),
    );
  }

  Future<StudentDetail> studentDetail(String membershipId) {
    return _client.call(
      (dio) => dio.get('/students/$membershipId'),
      (data) => StudentDetail.fromJson(data as Map<String, dynamic>),
    );
  }

  Future<void> updateStudent(
    String membershipId, {
    required String fullName,
    required String phone,
    required String dob,
    String? email,
    String? address,
    String? city,
    String? state,
    required List<Map<String, dynamic>> courses,
  }) {
    return _client.callVoid(
      (dio) => dio.put('/students/$membershipId', data: {
        'fullName': fullName,
        'phone': phone,
        'dob': dob,
        'email': email,
        'address': address,
        'city': city,
        'state': state,
        'courses': courses,
      }),
    );
  }

  Future<StudentRegistrationResult> registerStudent({
    required String username,
    required String fullName,
    required String phone,
    required String dob, // yyyy-MM-dd
    String? email,
    String? address,
    String? city,
    String? state,
    required List<Map<String, dynamic>> courses, // [{courseId, fee}]
  }) {
    return _client.call(
      (dio) => dio.post('/students', data: {
        'username': username,
        'fullName': fullName,
        'phone': phone,
        'dob': dob,
        'email': email,
        'address': address,
        'city': city,
        'state': state,
        'courses': courses,
      }),
      (data) => StudentRegistrationResult.fromJson(data as Map<String, dynamic>),
    );
  }

  /// Completes registerStudent() when it came back with pendingConfirmation=true - the student
  /// reads the OTP from their Notifications tab back to whoever's at the desk, confirming they
  /// approve joining this academy/course. Keyed by membershipId (from the registerStudent result),
  /// not phone - phone is no longer unique so it can't safely identify which pending request this is.
  Future<StudentRegistrationResult> confirmMembership({required String membershipId, required String code}) {
    return _client.call(
      (dio) => dio.post('/students/confirm-membership', data: {'membershipId': membershipId, 'code': code}),
      (data) => StudentRegistrationResult.fromJson(data as Map<String, dynamic>),
    );
  }

  /// [courseFeatures] maps each assigned courseId -> the features granted on that course. The
  /// "same features for all courses" toggle just sends the same set for every course. Email is
  /// required - it's this app's platform-wide identity key (PRD 7.4 addendum), so every account,
  /// trainers included, needs one.
  Future<TrainerRegistrationResult> registerTrainer({
    required String username,
    required String fullName,
    required String phone,
    required String email,
    required String dob, // yyyy-MM-dd
    String? address,
    String? city,
    String? state,
    int? yearsOfExperience,
    required Map<String, Set<String>> courseFeatures,
  }) {
    return _client.call(
      (dio) => dio.post('/trainers', data: {
        'username': username,
        'fullName': fullName,
        'phone': phone,
        'email': email,
        'dob': dob,
        'address': address,
        'city': city,
        'state': state,
        'yearsOfExperience': yearsOfExperience,
        'courseFeatures': courseFeatures.map((courseId, features) => MapEntry(courseId, features.toList())),
      }),
      (data) => TrainerRegistrationResult.fromJson(data as Map<String, dynamic>),
    );
  }

  Future<List<Batch>> batchesForCourse(String courseId) {
    return _client.call(
      (dio) => dio.get('/courses/$courseId/batches'),
      (data) => (data as List).map((e) => Batch.fromJson(e as Map<String, dynamic>)).toList(),
    );
  }

  /// Just the batch(es) this one membership actually belongs to, across every course - a
  /// Student's "my batches" view, never a course's full batch list.
  Future<List<Batch>> batchesForMembership(String membershipId) {
    return _client.call(
      (dio) => dio.get('/batches', queryParameters: {'membershipId': membershipId}),
      (data) => (data as List).map((e) => Batch.fromJson(e as Map<String, dynamic>)).toList(),
    );
  }

  Future<Batch> createBatch({
    required String courseId,
    required String name,
    String? description,
    required String batchType,
    String? trainerMembershipId,
  }) {
    return _client.call(
      (dio) => dio.post('/batches', data: {
        'courseId': courseId,
        'name': name,
        'description': description,
        'batchType': batchType,
        'trainerMembershipId': trainerMembershipId,
      }),
      (data) => Batch.fromJson(data as Map<String, dynamic>),
    );
  }

  /// Trainers for this course. [includeInactive] false (batch picker) drops course-deactivated
  /// trainers; true (Users management screen) keeps them so they can be reactivated.
  Future<List<TrainerSummary>> trainersForCourse(String courseId, {bool includeInactive = false}) {
    return _client.call(
      (dio) => dio.get('/courses/$courseId/trainers', queryParameters: {'includeInactive': includeInactive}),
      (data) => (data as List).map((e) => TrainerSummary.fromJson(e as Map<String, dynamic>)).toList(),
    );
  }

  /// Academy Admin (or Trainer with student-registration access) deactivates/reactivates a person
  /// for one course - works for both students and trainers (both live in course_map).
  Future<void> setCourseMemberActive(String courseId, String membershipId, bool active) {
    return _client.callVoid(
      (dio) => dio.put('/courses/$courseId/members/$membershipId/active', queryParameters: {'active': active}),
    );
  }

  /// Issues a fresh temp password for a student and returns it once (unified login - students log
  /// in with a password now). The admin hands it over; the student changes it on first login.
  Future<String> resetStudentPassword(String membershipId) {
    return _client.call(
      (dio) => dio.post('/students/$membershipId/reset-password'),
      (data) => (data as Map<String, dynamic>)['temporaryPassword'] as String,
    );
  }

  /// Blocked server-side (ConflictException) if the batch still has members, or if it has ever
  /// held a class (real attendance history) - the caller should surface that message as-is.
  Future<void> deleteBatch(String batchId) {
    return _client.callVoid((dio) => dio.delete('/batches/$batchId'));
  }

  Future<void> addMember(String batchId, String membershipId) {
    return _client.callVoid((dio) => dio.post('/batches/$batchId/members', queryParameters: {'membershipId': membershipId}));
  }

  Future<void> removeMember(String batchId, String membershipId) {
    return _client.callVoid((dio) => dio.delete('/batches/$batchId/members', queryParameters: {'membershipId': membershipId}));
  }

  Future<List<String>> members(String batchId) {
    return _client.call(
      (dio) => dio.get('/batches/$batchId/members'),
      (data) => List<String>.from(data as List),
    );
  }

  /// Students for this course. [includeInactive] false (batch roster picker) drops course-
  /// deactivated students; true (Users management screen) keeps them so they can be reactivated.
  Future<List<StudentSummary>> studentsForCourse(String courseId, {bool includeInactive = false}) {
    return _client.call(
      (dio) => dio.get('/courses/$courseId/students', queryParameters: {'includeInactive': includeInactive}),
      (data) => (data as List).map((e) => StudentSummary.fromJson(e as Map<String, dynamic>)).toList(),
    );
  }

  /// Called right after a Student/Trainer is registered (their userId, not membershipId - a
  /// person's photo belongs to the User row, shared across every academy they're a member of).
  /// Reads bytes rather than a file path so it works the same on web and Android/iOS.
  Future<void> uploadProfileImage(String userId, Uint8List bytes, String filename) {
    final formData = FormData.fromMap({'file': MultipartFile.fromBytes(bytes, filename: filename)});
    return _client.callVoid((dio) => dio.post('/users/$userId/profile-image', data: formData));
  }
}
