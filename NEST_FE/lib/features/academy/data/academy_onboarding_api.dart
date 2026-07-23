import 'package:nest_fe/core/network/dio_client.dart';

/// Result of onboarding a new academy - the created academy plus the first Academy Admin's
/// generated credentials. The temp password is surfaced here (Phase 1) so the Super Admin can
/// hand it over manually; a real deploy would email/SMS it instead (PRD 3.2).
class OnboardAcademyResult {
  final String academyId;
  final String academyName;
  final String adminUsername;
  final String adminTemporaryPassword;

  OnboardAcademyResult({
    required this.academyId,
    required this.academyName,
    required this.adminUsername,
    required this.adminTemporaryPassword,
  });

  factory OnboardAcademyResult.fromJson(Map<String, dynamic> json) {
    final academy = json['academy'] as Map<String, dynamic>;
    return OnboardAcademyResult(
      academyId: academy['id'] as String,
      academyName: academy['name'] as String,
      adminUsername: json['adminUsername'] as String,
      adminTemporaryPassword: json['adminTemporaryPassword'] as String,
    );
  }
}

class AcademyOnboardingApi {
  AcademyOnboardingApi(this._client);
  final DioClient _client;

  Future<OnboardAcademyResult> onboard({
    required String academyName,
    required String category,
    required String address,
    required String city,
    required String state,
    required String contactNumber,
    String? email,
    String? plan,
    required String adminUsername,
    required String adminFullName,
    required String adminPhone,
    String? adminEmail,
  }) {
    return _client.call(
      (dio) => dio.post('/academies', data: {
        'academyName': academyName,
        'category': category,
        'address': address,
        'city': city,
        'state': state,
        'contactNumber': contactNumber,
        'email': email,
        'plan': plan,
        'adminUsername': adminUsername,
        'adminFullName': adminFullName,
        'adminPhone': adminPhone,
        'adminEmail': adminEmail,
      }),
      (data) => OnboardAcademyResult.fromJson(data as Map<String, dynamic>),
    );
  }
}
