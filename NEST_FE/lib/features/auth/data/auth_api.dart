import 'package:nest_fe/core/auth/user_profile.dart';
import 'package:nest_fe/core/network/dio_client.dart';

class LoginResult {
  final String accessToken;
  final String refreshToken;
  final UserProfile user;

  LoginResult({required this.accessToken, required this.refreshToken, required this.user});

  factory LoginResult.fromJson(Map<String, dynamic> json) => LoginResult(
        accessToken: json['accessToken'] as String,
        refreshToken: json['refreshToken'] as String,
        user: UserProfile.fromJson(json['user'] as Map<String, dynamic>),
      );
}

enum AuthMethod { password, otp }

class IdentifyResult {
  final AuthMethod authMethod;
  final String username;
  final String? maskedPhone;

  IdentifyResult({required this.authMethod, required this.username, required this.maskedPhone});

  factory IdentifyResult.fromJson(Map<String, dynamic> json) => IdentifyResult(
        authMethod: (json['authMethod'] as String) == 'OTP' ? AuthMethod.otp : AuthMethod.password,
        username: json['username'] as String,
        maskedPhone: json['maskedPhone'] as String?,
      );
}

/// Thin wrapper around identity-service's /auth/** and /users/me endpoints (see the published
/// API reference for exact request/response shapes).
class AuthApi {
  AuthApi(this._client);

  final DioClient _client;

  /// Single unified entry point - one identifier (username or phone), backend decides whether
  /// the next step needs a password or an OTP. For OTP accounts the code is already sent as a
  /// side effect of this call.
  Future<IdentifyResult> identify(String identifier) {
    return _client.call(
      (dio) => dio.post('/auth/identify', data: {'identifier': identifier}),
      (data) => IdentifyResult.fromJson(data as Map<String, dynamic>),
    );
  }

  Future<LoginResult> login(String username, String password) {
    return _client.call(
      (dio) => dio.post('/auth/login', data: {'username': username, 'password': password}),
      (data) => LoginResult.fromJson(data as Map<String, dynamic>),
    );
  }

  /// Public self-signup - username and password chosen together, same screen. Always creates a
  /// GUEST account and logs them straight in, same response shape as login.
  Future<LoginResult> signup({
    required String username,
    required String password,
    required String fullName,
    required String phone,
    required String email,
  }) {
    return _client.call(
      (dio) => dio.post('/auth/signup', data: {
        'username': username,
        'password': password,
        'fullName': fullName,
        'phone': phone,
        'email': email,
      }),
      (data) => LoginResult.fromJson(data as Map<String, dynamic>),
    );
  }

  Future<void> resendOtp(String identifier) {
    return _client.callVoid((dio) => dio.post('/auth/otp/request', data: {'identifier': identifier, 'purpose': 'LOGIN'}));
  }

  Future<LoginResult> verifyOtp(String identifier, String code) {
    return _client.call(
      (dio) => dio.post('/auth/otp/verify', data: {'identifier': identifier, 'code': code, 'purpose': 'LOGIN'}),
      (data) => LoginResult.fromJson(data as Map<String, dynamic>),
    );
  }

  Future<void> logout(String refreshToken) {
    return _client.callVoid((dio) => dio.post('/auth/logout', data: {'refreshToken': refreshToken}));
  }

  Future<void> changePassword(String currentPassword, String newPassword) {
    return _client.callVoid((dio) => dio.post('/auth/password/change', data: {
          'currentPassword': currentPassword,
          'newPassword': newPassword,
        }));
  }

  Future<UserProfile> fetchProfile() {
    return _client.call(
      (dio) => dio.get('/users/me'),
      (data) => UserProfile.fromJson(data as Map<String, dynamic>),
    );
  }

  Future<void> updateTheme(ThemePreference preference) {
    return _client.callVoid(
        (dio) => dio.patch('/users/me/theme', data: {'themePreference': themePreferenceToApiString(preference)}));
  }

  /// [tag] is a BCP 47 language tag ("en", "hi", "pt-BR").
  Future<void> updateLanguage(String tag) {
    return _client.callVoid((dio) => dio.patch('/users/me/language', data: {'languagePreference': tag}));
  }
}
