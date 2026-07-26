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

/// A Super Admin's-eye view of one academy - enough to list, pick, and see if it's suspended.
class AcademyBrief {
  final String id;
  final String name;
  final String status;

  AcademyBrief({required this.id, required this.name, required this.status});

  bool get isSuspended => status == 'SUSPENDED';

  factory AcademyBrief.fromJson(Map<String, dynamic> json) => AcademyBrief(
        id: json['id'] as String,
        name: json['name'] as String,
        status: json['status'] as String? ?? 'ACTIVE',
      );
}

class AcademyOnboardingApi {
  AcademyOnboardingApi(this._client);
  final DioClient _client;

  /// Super Admin only - every academy including suspended ones (broadcast picker + suspend screen).
  Future<List<AcademyBrief>> listAll() {
    return _client.call(
      (dio) => dio.get('/academies'),
      (data) => (data as List).map((e) => AcademyBrief.fromJson(e as Map<String, dynamic>)).toList(),
    );
  }

  /// Super Admin only - suspend a tenant (e.g. non-payment) or reactivate it. [status] is
  /// 'ACTIVE' or 'SUSPENDED'. A suspended academy disappears for all its members and trainers.
  Future<void> setStatus(String academyId, String status) {
    return _client.callVoid(
      (dio) => dio.put('/academies/$academyId/status', queryParameters: {'status': status}),
    );
  }

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
