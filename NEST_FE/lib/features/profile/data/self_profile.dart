import 'package:flutter/material.dart';
import 'package:nest_fe/app/theme/app_tokens.dart';

/// `yyyy-MM-dd` - what the backend's LocalDate reads. A full ISO instant is rejected.
String wireDate(DateTime d) =>
    '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

const _months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];

/// "15 Mar 2026".
String longDate(DateTime d) => '${d.day} ${_months[d.month - 1]} ${d.year}';

/// "15-03-2026" - the compact form used on enrolment rows.
String dmyDate(DateTime d) =>
    '${d.day.toString().padLeft(2, '0')}-${d.month.toString().padLeft(2, '0')}-${d.year}';

DateTime? _date(Object? v) => v == null ? null : DateTime.tryParse(v as String);

class EnrolledCourse {
  const EnrolledCourse({required this.courseId, required this.courseName, required this.trainers});
  final String courseId;
  final String courseName;
  final List<String> trainers;

  factory EnrolledCourse.fromJson(Map<String, dynamic> j) => EnrolledCourse(
        courseId: j['courseId'] as String,
        courseName: j['courseName'] as String,
        trainers: (j['trainers'] as List? ?? []).cast<String>(),
      );
}

class AcademyEnrolment {
  const AcademyEnrolment({
    required this.academyId,
    required this.academyName,
    required this.joiningDate,
    required this.courses,
  });
  final String academyId;
  final String academyName;
  final DateTime? joiningDate;
  final List<EnrolledCourse> courses;

  factory AcademyEnrolment.fromJson(Map<String, dynamic> j) => AcademyEnrolment(
        academyId: j['academyId'] as String,
        academyName: (j['academyName'] as String?) ?? 'Academy',
        joiningDate: _date(j['joiningDate']),
        courses: (j['courses'] as List? ?? [])
            .map((c) => EnrolledCourse.fromJson(c as Map<String, dynamic>))
            .toList(),
      );
}

/// The signed-in person's own profile, unmasked.
class SelfProfile {
  const SelfProfile({
    required this.userId,
    required this.username,
    required this.fullName,
    this.email,
    this.phone,
    this.altPhone,
    this.dob,
    this.gender,
    this.bloodGroup,
    this.guardianName,
    this.addressLine1,
    this.addressLine2,
    this.landmark,
    this.city,
    this.district,
    this.state,
    this.pinCode,
    this.profileImageUrl,
    this.onPlatformSince,
    required this.academies,
  });

  final String userId;
  final String username;
  final String fullName;
  final String? email;
  final String? phone;
  final String? altPhone;
  final DateTime? dob;
  final String? gender;
  final String? bloodGroup;
  final String? guardianName;
  final String? addressLine1;
  final String? addressLine2;
  final String? landmark;
  final String? city;
  final String? district;
  final String? state;
  final String? pinCode;
  final String? profileImageUrl;
  final DateTime? onPlatformSince;
  final List<AcademyEnrolment> academies;

  factory SelfProfile.fromJson(Map<String, dynamic> j) => SelfProfile(
        userId: j['userId'] as String,
        username: j['username'] as String,
        fullName: j['fullName'] as String,
        email: j['email'] as String?,
        phone: j['phone'] as String?,
        altPhone: j['altPhone'] as String?,
        dob: _date(j['dob']),
        gender: j['gender'] as String?,
        bloodGroup: j['bloodGroup'] as String?,
        guardianName: j['guardianName'] as String?,
        addressLine1: j['addressLine1'] as String?,
        addressLine2: j['addressLine2'] as String?,
        landmark: j['landmark'] as String?,
        city: j['city'] as String?,
        district: j['district'] as String?,
        state: j['state'] as String?,
        pinCode: j['pinCode'] as String?,
        profileImageUrl: j['profileImageUrl'] as String?,
        onPlatformSince: _date(j['onPlatformSince']),
        academies: (j['academies'] as List? ?? [])
            .map((a) => AcademyEnrolment.fromJson(a as Map<String, dynamic>))
            .toList(),
      );

  /// "7 MG Road, Bengaluru, ..." - only the parts that are filled in.
  String get formattedAddress => [addressLine1, addressLine2, landmark, city, district, state, pinCode]
      .where((p) => p != null && p.trim().isNotEmpty)
      .join(', ');
}

/// A student as staff see them: the profile plus the student's own achievements and log.
class StudentProfile {
  const StudentProfile({required this.profile, required this.achievements, required this.performanceLogs});
  final SelfProfile profile;
  final List<Achievement> achievements;
  final List<PerformanceLog> performanceLogs;

  factory StudentProfile.fromJson(Map<String, dynamic> j) => StudentProfile(
        profile: SelfProfile.fromJson(j['profile'] as Map<String, dynamic>),
        achievements: (j['achievements'] as List? ?? [])
            .map((e) => Achievement.fromJson(e as Map<String, dynamic>))
            .toList(),
        performanceLogs: (j['performanceLogs'] as List? ?? [])
            .map((e) => PerformanceLog.fromJson(e as Map<String, dynamic>))
            .toList(),
      );
}

/// Kinds of achievement. [wire] is what the backend stores.
class AchievementType {
  const AchievementType(this.wire, this.label, this.icon, this.color);
  final String wire;
  final String label;
  final IconData icon;
  final Color Function(AppPalette) color;

  static final all = <AchievementType>[
    AchievementType('AWARD', 'Award', Icons.emoji_events_outlined, (p) => p.gold),
    AchievementType('STREAK', 'Streak', Icons.local_fire_department_outlined, (p) => p.coral),
    AchievementType('CERTIFICATE', 'Certificate', Icons.school_outlined, (p) => p.primary),
    AchievementType('MILESTONE', 'Milestone', Icons.star_outline, (p) => p.violet),
  ];

  static AchievementType of(String wire) => all.firstWhere((t) => t.wire == wire, orElse: () => all.first);
}

class PerformanceCategory {
  const PerformanceCategory(this.wire, this.label, this.icon, this.color);
  final String wire;
  final String label;
  final IconData icon;
  final Color Function(AppPalette) color;

  static final all = <PerformanceCategory>[
    PerformanceCategory('EXAM', 'Exam', Icons.description_outlined, (p) => p.gateway),
    PerformanceCategory('RECITAL', 'Recital', Icons.music_note_outlined, (p) => p.gold),
    PerformanceCategory('ASSESSMENT', 'Assessment', Icons.fact_check_outlined, (p) => p.primary),
    PerformanceCategory('FEEDBACK', 'Trainer Feedback', Icons.chat_bubble_outline, (p) => p.violet),
  ];

  static PerformanceCategory of(String wire) => all.firstWhere((c) => c.wire == wire, orElse: () => all.first);
}

class Achievement {
  const Achievement({
    required this.id,
    required this.title,
    required this.description,
    required this.type,
    required this.date,
    required this.academyId,
  });
  final String id;
  final String title;
  final String description;
  final String type;
  final DateTime date;
  final String? academyId;

  factory Achievement.fromJson(Map<String, dynamic> j) => Achievement(
        id: j['id'] as String,
        title: j['title'] as String,
        description: (j['description'] as String?) ?? '',
        type: j['type'] as String,
        date: DateTime.parse(j['date'] as String),
        academyId: j['academyId'] as String?,
      );
}

class PerformanceLog {
  const PerformanceLog({
    required this.id,
    required this.title,
    required this.category,
    required this.result,
    required this.date,
    required this.academyId,
    required this.notes,
  });
  final String id;
  final String title;
  final String category;
  final String result;
  final DateTime date;
  final String? academyId;
  final String notes;

  factory PerformanceLog.fromJson(Map<String, dynamic> j) => PerformanceLog(
        id: j['id'] as String,
        title: j['title'] as String,
        category: j['category'] as String,
        result: j['result'] as String,
        date: DateTime.parse(j['date'] as String),
        academyId: j['academyId'] as String?,
        notes: (j['notes'] as String?) ?? '',
      );
}
