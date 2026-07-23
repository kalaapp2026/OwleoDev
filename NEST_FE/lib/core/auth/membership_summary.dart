/// Mirrors identity-service's MembershipSummary DTO - one academy relationship, with the
/// caller's resolved feature grants and course map already baked in (PRD 4.3).
class MembershipSummary {
  final String membershipId;
  final String academyId;
  final String? academyName;
  final String roleType;
  final String status;
  final Set<String> features;
  final Set<String> courseIds;

  const MembershipSummary({
    required this.membershipId,
    required this.academyId,
    required this.academyName,
    required this.roleType,
    required this.status,
    required this.features,
    required this.courseIds,
  });

  factory MembershipSummary.fromJson(Map<String, dynamic> json) => MembershipSummary(
        membershipId: json['membershipId'] as String,
        academyId: json['academyId'] as String,
        academyName: json['academyName'] as String?,
        roleType: json['roleType'] as String,
        status: json['status'] as String,
        features: Set<String>.from(json['features'] as List? ?? []),
        courseIds: Set<String>.from(json['courseIds'] as List? ?? []),
      );

  bool hasFeature(String key) => features.contains(key);

  bool get isAcademyAdmin => roleType == 'ACADEMY_ADMIN';
}
