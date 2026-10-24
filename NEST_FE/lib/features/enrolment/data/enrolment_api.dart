import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:nest_fe/core/network/dio_client.dart';
import 'package:nest_fe/core/providers/core_providers.dart';
import 'package:nest_fe/features/enrolment/data/batch.dart';
import 'package:nest_fe/features/enrolment/data/person_details.dart';

final enrolmentApiProvider = Provider((ref) => EnrolmentApi(ref.watch(dioClientProvider)));

/// Every batch in the active academy - the batch list screen. Re-fetches when the caller
/// switches which academy membership is active, not just on app start.
final allBatchesProvider = FutureProvider.autoDispose((ref) {
  ref.watch(activeMembershipIdProvider);
  return ref.watch(enrolmentApiProvider).allBatches();
});

/// One course's batches - the batch dropdown on Attendance, Fees and Scheduling, all of which
/// scope to a course first.
final batchesForCourseProvider =
    FutureProvider.autoDispose.family<List<Batch>, String>((ref, courseId) {
  ref.watch(activeMembershipIdProvider);
  return ref.watch(enrolmentApiProvider).batchesForCourse(courseId);
});

/// The roster picker's source. Keyed by course because a batch can only contain students already
/// enrolled in the course it belongs to.
final studentsForCourseProvider =
    FutureProvider.autoDispose.family<List<StudentSummary>, String>((ref, courseId) {
  ref.watch(activeMembershipIdProvider);
  return ref.watch(enrolmentApiProvider).studentsForCourse(courseId);
});

final trainersForCourseProvider =
    FutureProvider.autoDispose.family<List<TrainerSummary>, String>((ref, courseId) {
  ref.watch(activeMembershipIdProvider);
  return ref.watch(enrolmentApiProvider).trainersForCourse(courseId);
});

/// Which students are currently in a batch, for pre-selecting the roster picker on edit.
final batchMembersProvider =
    FutureProvider.autoDispose.family<List<String>, String>((ref, batchId) {
  return ref.watch(enrolmentApiProvider).members(batchId);
});

/// The Student Profile module's identity header.
final studentCardProvider =
    FutureProvider.autoDispose.family<StudentCard, String>((ref, membershipId) {
  return ref.watch(enrolmentApiProvider).studentCard(membershipId);
});

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

/// What the creator may know before the person has agreed: that the account exists, a masked name to
/// recognise it by, and whether they are already at this academy.
class ExistingAccountCheck {
  final bool exists;
  final String maskedName;
  final bool alreadyAtThisAcademy;
  final String? roleHere;

  const ExistingAccountCheck({
    required this.exists,
    required this.maskedName,
    required this.alreadyAtThisAcademy,
    required this.roleHere,
  });

  factory ExistingAccountCheck.fromJson(Map<String, dynamic> json) => ExistingAccountCheck(
        exists: json['exists'] as bool? ?? false,
        maskedName: json['maskedName'] as String? ?? '',
        alreadyAtThisAcademy: json['alreadyAtThisAcademy'] as bool? ?? false,
        roleHere: json['roleHere'] as String?,
      );
}

/// One academy an existing account is mapped to, with the courses it has there.
class ExistingEnrolment {
  final String academyName;
  final bool thisAcademy;
  final String role;
  final List<String> courseIds;
  final List<String> courseNames;

  const ExistingEnrolment({
    required this.academyName,
    required this.thisAcademy,
    required this.role,
    required this.courseIds,
    required this.courseNames,
  });

  factory ExistingEnrolment.fromJson(Map<String, dynamic> json) => ExistingEnrolment(
        academyName: json['academyName'] as String? ?? '',
        thisAcademy: json['thisAcademy'] as bool? ?? false,
        role: json['role'] as String? ?? '',
        courseIds: ((json['courseIds'] as List?) ?? const []).cast<String>(),
        courseNames: ((json['courseNames'] as List?) ?? const []).cast<String>(),
      );
}

/// What a verified code unlocks - see [EnrolmentApi.verifyExistingAccount].
class ExistingAccountProfile {
  final String linkGrantId;
  final String userId;
  final String username;
  final String fullName;
  final String? phone;
  final String? email;
  final DateTime? dob;
  final PersonDetails details;
  final List<ExistingEnrolment> enrolments;

  const ExistingAccountProfile({
    required this.linkGrantId,
    required this.userId,
    required this.username,
    required this.fullName,
    required this.phone,
    required this.email,
    required this.dob,
    required this.details,
    required this.enrolments,
  });

  factory ExistingAccountProfile.fromJson(Map<String, dynamic> json) => ExistingAccountProfile(
        linkGrantId: json['linkGrantId'] as String,
        userId: json['userId'] as String,
        username: json['username'] as String? ?? '',
        fullName: json['fullName'] as String? ?? '',
        phone: json['phone'] as String?,
        email: json['email'] as String?,
        dob: json['dob'] == null ? null : DateTime.tryParse(json['dob'] as String),
        details: PersonDetails.fromJson(
            (json['details'] as Map?)?.cast<String, dynamic>() ?? const <String, dynamic>{}),
        enrolments: ((json['enrolments'] as List?) ?? const [])
            .map((e) => ExistingEnrolment.fromJson((e as Map).cast<String, dynamic>()))
            .toList(),
      );
}

class TrainerRegistrationResult {
  final String userId;
  final String membershipId;
  final String username;

  /// Null when no new account was created - i.e. this linked someone who already had a NEST
  /// account (a student or trainer at another academy), so they keep their own password.
  final String? temporaryPassword;

  /// True when an EXISTING NEST user was linked to this academy. The membership is
  /// PENDING_CONFIRMATION and grants nothing until that person reads back the code sent to their
  /// notifications (PRD 7.4) - same consent step students already had.
  final bool pendingConfirmation;

  TrainerRegistrationResult({
    required this.userId,
    required this.membershipId,
    required this.username,
    required this.temporaryPassword,
    required this.pendingConfirmation,
  });

  factory TrainerRegistrationResult.fromJson(Map<String, dynamic> json) => TrainerRegistrationResult(
        userId: json['userId'] as String,
        membershipId: json['membershipId'] as String,
        username: json['username'] as String,
        // Nullable cast is load-bearing: `as String` here threw for every linked person, so the
        // registration appeared to fail outright and the confirmation step was never reached.
        temporaryPassword: json['temporaryPassword'] as String?,
        pendingConfirmation: json['pendingConfirmation'] as bool? ?? false,
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
  final String? profileImageUrl;

  StudentSummary({
    required this.membershipId,
    required this.userId,
    required this.username,
    required this.fullName,
    required this.active,
    this.profileImageUrl,
  });

  factory StudentSummary.fromJson(Map<String, dynamic> json) => StudentSummary(
        membershipId: json['membershipId'] as String,
        userId: json['userId'] as String,
        username: json['username'] as String,
        fullName: json['fullName'] as String,
        active: json['active'] as bool? ?? true,
        profileImageUrl: json['profileImageUrl'] as String?,
      );
}

/// One of a student's course enrolments, as shown on their identity card.
class StudentCardCourse {
  final String courseId;
  final String courseName;
  final String? batchName;

  StudentCardCourse({required this.courseId, required this.courseName, this.batchName});

  factory StudentCardCourse.fromJson(Map<String, dynamic> json) => StudentCardCourse(
        courseId: json['courseId'] as String,
        courseName: json['courseName'] as String,
        batchName: json['batchName'] as String?,
      );
}

/// The public-safe student identity card the Student Profile module opens - deliberately thinner
/// than a full edit form (no course fees), mirroring the Trainer Card the Academy Profile screen
/// already shows.
class StudentCard {
  final String membershipId;
  final String fullName;
  final String? photoUrl;
  final String? phone;
  final String? email;
  final String? dob;
  final String? guardianName;
  final String? address;
  final String? city;
  final String? state;
  final String? joiningDate;
  final List<StudentCardCourse> courses;

  StudentCard({
    required this.membershipId,
    required this.fullName,
    this.photoUrl,
    this.phone,
    this.email,
    this.dob,
    this.guardianName,
    this.address,
    this.city,
    this.state,
    this.joiningDate,
    required this.courses,
  });

  factory StudentCard.fromJson(Map<String, dynamic> json) => StudentCard(
        membershipId: json['membershipId'] as String,
        fullName: json['fullName'] as String,
        photoUrl: json['photoUrl'] as String?,
        phone: json['phone'] as String?,
        email: json['email'] as String?,
        dob: json['dob'] as String?,
        guardianName: json['guardianName'] as String?,
        address: json['address'] as String?,
        city: json['city'] as String?,
        state: json['state'] as String?,
        joiningDate: json['joiningDate'] as String?,
        courses: (json['courses'] as List? ?? [])
            .map((e) => StudentCardCourse.fromJson(e as Map<String, dynamic>))
            .toList(),
      );
}

/// One row for a batch's default-trainer picker / the Users management screen.
class TrainerSummary {
  final String membershipId;
  final String userId;
  final String username;
  final String fullName;
  final bool active;
  final String? profileImageUrl;

  TrainerSummary({
    required this.membershipId,
    required this.userId,
    required this.username,
    required this.fullName,
    required this.active,
    this.profileImageUrl,
  });

  factory TrainerSummary.fromJson(Map<String, dynamic> json) => TrainerSummary(
        membershipId: json['membershipId'] as String,
        userId: json['userId'] as String,
        username: json['username'] as String,
        fullName: json['fullName'] as String,
        active: json['active'] as bool? ?? true,
        profileImageUrl: json['profileImageUrl'] as String?,
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

  /// The extended profile fields (V26/V27), so opening the edit form does not silently drop
  /// everything the registration form collected.
  final PersonDetails? details;

  /// Per course, the batches this trainer is scoped to. A course absent from the map means
  /// every batch on it.
  final Map<String, Set<String>> courseBatches;
  final String? profileImageUrl;

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
    required this.details,
    required this.courseBatches,
    this.profileImageUrl,
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
        details: json['details'] == null
            ? null
            : PersonDetails.fromJson(json['details'] as Map<String, dynamic>),
        courseBatches: ((json['courseBatches'] as Map?) ?? {}).map(
          (k, v) => MapEntry(k as String, Set<String>.from(v as List)),
        ),
        profileImageUrl: json['profileImageUrl'] as String?,
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

  /// The extended profile fields (V26/V27), so opening the edit form does not silently drop
  /// everything the registration form collected.
  final PersonDetails? details;
  final String? profileImageUrl;

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
    required this.details,
    this.profileImageUrl,
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
        details: json['details'] == null
            ? null
            : PersonDetails.fromJson(json['details'] as Map<String, dynamic>),
        profileImageUrl: json['profileImageUrl'] as String?,
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
    /// Per course, which batches those grants apply to. An absent or empty set means every
    /// batch on that course.
    Map<String, Set<String>> courseBatches = const {},
    PersonDetails? details,
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
        'courseBatches': courseBatches.map((courseId, batchIds) => MapEntry(courseId, batchIds.toList())),
        'details': details?.toJson(),
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
    PersonDetails? details,
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
        'details': details?.toJson(),
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
    PersonDetails? details,

    /// Set when the creator already verified this existing account's own code - see
    /// [verifyExistingAccount]. Lets the membership activate at once instead of waiting on a code.
    String? linkGrantId,
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
        'details': details?.toJson(),
        'linkGrantId': linkGrantId,
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

  /// Is there already a NEST account for this email? Says only that, plus a masked name - the
  /// person's details wait for their own code ([verifyExistingAccount]).
  Future<ExistingAccountCheck> checkExistingAccount({required String email, required bool trainer}) {
    return _client.call(
      (dio) => dio.post('/existing-accounts/check', data: {'email': email, 'role': trainer ? 'TRAINER' : 'STUDENT'}),
      (data) => ExistingAccountCheck.fromJson(data as Map<String, dynamic>),
    );
  }

  /// Posts a confirmation code to that person's own notifications.
  Future<void> sendExistingAccountCode({required String email, required bool trainer}) {
    return _client.call(
      (dio) => dio.post('/existing-accounts/send-code', data: {'email': email, 'role': trainer ? 'TRAINER' : 'STUDENT'}),
      (_) {},
    );
  }

  /// Checks the code they read out. On success returns their details, where they are already mapped,
  /// and the single-use grant registration must present.
  Future<ExistingAccountProfile> verifyExistingAccount(
      {required String email, required bool trainer, required String code}) {
    return _client.call(
      (dio) => dio.post('/existing-accounts/verify',
          data: {'email': email, 'role': trainer ? 'TRAINER' : 'STUDENT', 'code': code}),
      (data) => ExistingAccountProfile.fromJson(data as Map<String, dynamic>),
    );
  }

  /// Trainer equivalent of [confirmMembership] - same consent step, different endpoint because the
  /// two return different shapes (a trainer has course features, not fees).
  Future<TrainerRegistrationResult> confirmTrainerMembership({required String membershipId, required String code}) {
    return _client.call(
      (dio) => dio.post('/trainers/confirm-membership', data: {'membershipId': membershipId, 'code': code}),
      (data) => TrainerRegistrationResult.fromJson(data as Map<String, dynamic>),
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

    /// Per course, which batches those grants apply to. An absent or empty set for a course means
    /// every batch on it - which is what a trainer assigned to the whole course gets.
    Map<String, Set<String>> courseBatches = const {},
    PersonDetails? details,
    String? linkGrantId,
  }) {
    return _client.call(
      (dio) => dio.post('/trainers', data: {
        'linkGrantId': linkGrantId,
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
        'courseBatches': courseBatches.map((courseId, batchIds) => MapEntry(courseId, batchIds.toList())),
        'details': details?.toJson(),
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

  /// Every batch in the active academy, across all its courses - the batch list screen's source.
  /// Distinct from [batchesForMembership], which answers "which batches is this person in".
  Future<List<Batch>> allBatches() {
    return _client.call(
      (dio) => dio.get('/batches/all'),
      (data) => (data as List).map((e) => Batch.fromJson(e as Map<String, dynamic>)).toList(),
    );
  }

  Future<Batch> getBatch(String batchId) {
    return _client.call(
      (dio) => dio.get('/batches/$batchId'),
      (data) => Batch.fromJson(data as Map<String, dynamic>),
    );
  }

  /// Creates the batch and enrols its roster in one call, so a dropped request can't leave a
  /// batch that exists but has none of the students the admin just picked.
  Future<Batch> createBatch({
    required String courseId,
    required String name,
    String? description,
    required BatchType batchType,
    required List<String> trainerMembershipIds,
    DateTime? startDate,
    DateTime? endDate,
    List<String> studentMembershipIds = const [],
    String? meetingLink,
  }) {
    return _client.call(
      (dio) => dio.post('/batches', data: {
        'courseId': courseId,
        'name': name,
        'description': description,
        'batchType': batchType.wire,
        'trainerMembershipIds': trainerMembershipIds,
        'startDate': _isoDate(startDate),
        'endDate': _isoDate(endDate),
        'studentMembershipIds': studentMembershipIds,
        'meetingLink': meetingLink,
      }),
      (data) => Batch.fromJson(data as Map<String, dynamic>),
    );
  }

  /// [studentMembershipIds] is the complete roster - anyone absent is unmapped server-side.
  Future<Batch> updateBatch(
    String batchId, {
    required String name,
    String? description,
    required List<String> trainerMembershipIds,
    DateTime? startDate,
    DateTime? endDate,
    required List<String> studentMembershipIds,

    /// Whole-set like the roster: null clears the link, so a caller that is not editing it passes the
    /// batch's current one back.
    String? meetingLink,
  }) {
    return _client.call(
      (dio) => dio.put('/batches/$batchId', data: {
        'name': name,
        'description': description,
        'trainerMembershipIds': trainerMembershipIds,
        'startDate': _isoDate(startDate),
        'endDate': _isoDate(endDate),
        'studentMembershipIds': studentMembershipIds,
        'meetingLink': meetingLink,
      }),
      (data) => Batch.fromJson(data as Map<String, dynamic>),
    );
  }

  Future<Batch> setBatchStatus(String batchId, String status) {
    return _client.call(
      (dio) => dio.patch('/batches/$batchId/status', queryParameters: {'status': status}),
      (data) => Batch.fromJson(data as Map<String, dynamic>),
    );
  }

  /// `yyyy-MM-dd`, which is what LocalDate deserialises from. Sending a full ISO instant here
  /// would be rejected, and sending the local date-time would shift the day across timezones.
  static String? _isoDate(DateTime? date) => date == null
      ? null
      : '${date.year.toString().padLeft(4, '0')}-'
          '${date.month.toString().padLeft(2, '0')}-'
          '${date.day.toString().padLeft(2, '0')}';

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

  /// Takes a trainer off one course for good. Unlike [setCourseMemberActive] the trainer does not
  /// stay on the roster greyed out; their account and other courses are untouched.
  Future<void> removeTrainerFromCourse(String courseId, String membershipId) {
    return _client.callVoid((dio) => dio.delete('/courses/$courseId/trainers/$membershipId'));
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

  /// The public-safe student card the Student Profile module opens - identity fields only, no
  /// feature gate on the backend, so any Admin or Trainer in the academy can open it.
  Future<StudentCard> studentCard(String membershipId) {
    return _client.call(
      (dio) => dio.get('/students/$membershipId/card'),
      (data) => StudentCard.fromJson(data as Map<String, dynamic>),
    );
  }
}
