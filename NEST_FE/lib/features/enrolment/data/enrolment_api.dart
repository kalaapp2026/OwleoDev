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

  StudentRegistrationResult({
    required this.userId,
    required this.membershipId,
    required this.username,
    required this.fullName,
    required this.courseFees,
    required this.pendingConfirmation,
  });

  factory StudentRegistrationResult.fromJson(Map<String, dynamic> json) => StudentRegistrationResult(
        userId: json['userId'] as String,
        membershipId: json['membershipId'] as String,
        username: json['username'] as String,
        fullName: json['fullName'] as String,
        courseFees: Map<String, num>.from(json['courseFees'] as Map),
        pendingConfirmation: json['pendingConfirmation'] as bool? ?? false,
      );
}

class TrainerRegistrationResult {
  final String userId;
  final String membershipId;
  final String username;
  final String temporaryPassword;
  final Set<String> features;

  TrainerRegistrationResult({
    required this.userId,
    required this.membershipId,
    required this.username,
    required this.temporaryPassword,
    required this.features,
  });

  factory TrainerRegistrationResult.fromJson(Map<String, dynamic> json) => TrainerRegistrationResult(
        userId: json['userId'] as String,
        membershipId: json['membershipId'] as String,
        username: json['username'] as String,
        temporaryPassword: json['temporaryPassword'] as String,
        features: Set<String>.from(json['features'] as List? ?? []),
      );
}

/// One row for a batch roster picker - a real name to check off, not a bare membership UUID.
class StudentSummary {
  final String membershipId;
  final String userId;
  final String username;
  final String fullName;

  StudentSummary({required this.membershipId, required this.userId, required this.username, required this.fullName});

  factory StudentSummary.fromJson(Map<String, dynamic> json) => StudentSummary(
        membershipId: json['membershipId'] as String,
        userId: json['userId'] as String,
        username: json['username'] as String,
        fullName: json['fullName'] as String,
      );
}

/// One row for a batch's default-trainer picker - a real name to pick, not a bare membership UUID.
class TrainerSummary {
  final String membershipId;
  final String userId;
  final String username;
  final String fullName;

  TrainerSummary({required this.membershipId, required this.userId, required this.username, required this.fullName});

  factory TrainerSummary.fromJson(Map<String, dynamic> json) => TrainerSummary(
        membershipId: json['membershipId'] as String,
        userId: json['userId'] as String,
        username: json['username'] as String,
        fullName: json['fullName'] as String,
      );
}

class EnrolmentApi {
  EnrolmentApi(this._client);
  final DioClient _client;

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

  Future<TrainerRegistrationResult> registerTrainer({
    required String username,
    required String fullName,
    required String phone,
    String? email,
    required Set<String> features,
    required Set<String> courseIds,
  }) {
    return _client.call(
      (dio) => dio.post('/trainers', data: {
        'username': username,
        'fullName': fullName,
        'phone': phone,
        'email': email,
        'features': features.toList(),
        'courseIds': courseIds.toList(),
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

  /// Every active Trainer enrolled in this course - the default-trainer picker source for batch
  /// creation, so students can see who's actually taking the class.
  Future<List<TrainerSummary>> trainersForCourse(String courseId) {
    return _client.call(
      (dio) => dio.get('/courses/$courseId/trainers'),
      (data) => (data as List).map((e) => TrainerSummary.fromJson(e as Map<String, dynamic>)).toList(),
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

  /// Every active Student enrolled in this course - the roster picker source for creating or
  /// editing a batch's membership.
  Future<List<StudentSummary>> studentsForCourse(String courseId) {
    return _client.call(
      (dio) => dio.get('/courses/$courseId/students'),
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
