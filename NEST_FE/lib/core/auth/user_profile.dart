import 'membership_summary.dart';

enum ThemePreference { light, dark, system }

ThemePreference themePreferenceFromString(String? value) {
  switch (value) {
    case 'LIGHT':
      return ThemePreference.light;
    case 'DARK':
      return ThemePreference.dark;
    default:
      return ThemePreference.system;
  }
}

String themePreferenceToApiString(ThemePreference pref) => pref.name.toUpperCase();

class UserProfile {
  final String id;
  final String username;
  final String fullName;
  final String? maskedPhone;
  final String? email;
  final String? city;
  final String? state;
  final String role;
  final bool temporaryPassword;
  final ThemePreference themePreference;
  /// BCP 47 tag ("en", "hi", "pt-BR"). Resolved via AppLanguage.fromTag, which falls back to
  /// English for anything this build doesn't bundle.
  final String languagePreference;
  final List<MembershipSummary> memberships;
  final String? activeMembershipId;
  final String? profileImageUrl;

  const UserProfile({
    required this.id,
    required this.username,
    required this.fullName,
    required this.maskedPhone,
    required this.email,
    required this.city,
    required this.state,
    required this.role,
    required this.temporaryPassword,
    required this.themePreference,
    required this.languagePreference,
    required this.memberships,
    required this.activeMembershipId,
    required this.profileImageUrl,
  });

  factory UserProfile.fromJson(Map<String, dynamic> json) => UserProfile(
        id: json['id'] as String,
        username: json['username'] as String,
        fullName: json['fullName'] as String,
        maskedPhone: json['maskedPhone'] as String?,
        email: json['email'] as String?,
        city: json['city'] as String?,
        state: json['state'] as String?,
        role: json['role'] as String,
        temporaryPassword: json['temporaryPassword'] as bool? ?? false,
        themePreference: themePreferenceFromString(json['themePreference'] as String?),
        languagePreference: json['languagePreference'] as String? ?? 'en',
        memberships: (json['memberships'] as List? ?? [])
            .map((m) => MembershipSummary.fromJson(m as Map<String, dynamic>))
            .toList(),
        activeMembershipId: json['activeMembershipId'] as String?,
        profileImageUrl: json['profileImageUrl'] as String?,
      );

  bool get isSuperAdmin => role == 'SUPER_ADMIN';
  bool get isArtist => role == 'ARTIST';
  bool get isGuest => role == 'GUEST';

  /// The only memberships that grant anything - see [MembershipSummary.isActive]. Everything that
  /// decides access or shows an academy to the user reads this, never the raw list.
  List<MembershipSummary> get activeMemberships => memberships.where((m) => m.isActive).toList();

  // A Super Admin has no academy membership (they operate across tenants, onboarding academies -
  // PRD 2.4), so they'd otherwise be locked out of the ERP side entirely. Their ERP home is the
  // academy-onboarding tile, not the within-academy tools an academy member sees.
  bool get hasErpAccess => activeMemberships.isNotEmpty || isSuperAdmin;
  /// More than one ACADEMY - not more than one membership. Someone who is both a student and a
  /// trainer at one academy holds two memberships there but still belongs to a single academy, and
  /// the academy switcher has nothing to offer them (their role switch lives in the avatar menu).
  bool get hasMultipleAcademies => activeMemberships.map((m) => m.academyId).toSet().length > 1;

  /// What the academy switcher lists: each academy once. The entry for the academy you are in is your
  /// current membership; for any other, the membership in the SAME role if you hold one there (so
  /// moving academy doesn't also change role), otherwise the first you have. Selecting an entry
  /// switches to that membership.
  List<MembershipSummary> get academyChoices {
    final current = activeMembership;
    final seen = <String>{};
    final choices = <MembershipSummary>[];
    for (final m in activeMemberships) {
      if (!seen.add(m.academyId)) continue;
      if (m.academyId == current?.academyId) {
        choices.add(current!);
        continue;
      }
      final here = activeMemberships.where((x) => x.academyId == m.academyId).toList();
      choices.add(here.firstWhere((x) => x.roleType == current?.roleType, orElse: () => here.first));
    }
    return choices;
  }

  MembershipSummary? get activeMembership {
    final active = activeMemberships;
    if (activeMembershipId == null) return active.isEmpty ? null : active.first;
    try {
      return active.firstWhere((m) => m.membershipId == activeMembershipId);
    } catch (_) {
      return active.isEmpty ? null : active.first;
    }
  }

  bool hasFeature(String key) => activeMembership?.hasFeature(key) ?? false;

  bool get isActiveAcademyAdmin => activeMembership?.isAcademyAdmin ?? false;
}
