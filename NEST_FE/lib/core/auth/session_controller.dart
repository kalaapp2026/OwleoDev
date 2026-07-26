import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:nest_fe/core/auth/session_state.dart';
import 'package:nest_fe/core/auth/user_profile.dart';
import 'package:nest_fe/core/error/api_exception.dart';
import 'package:nest_fe/core/network/dio_client.dart';
import 'package:nest_fe/core/providers/core_providers.dart';
import 'package:nest_fe/core/storage/secure_token_storage.dart';
import 'package:nest_fe/features/auth/data/auth_api.dart';

final sessionControllerProvider = NotifierProvider<SessionController, SessionState>(SessionController.new);

/// The single source of truth for "is anyone logged in, and as whom." Every screen that needs to
/// know the current role/features/active academy reads through here, never through raw token
/// storage directly.
class SessionController extends Notifier<SessionState> {
  late final AuthApi _authApi;
  late final DioClient _dioClient;

  @override
  SessionState build() {
    _authApi = ref.watch(authApiProvider);
    _dioClient = ref.watch(dioClientProvider);
    // Assigned post-construction on purpose - see AuthInterceptor's doc comment on why this
    // can't be a constructor argument without creating a provider cycle.
    _dioClient.authInterceptor.onSessionExpired = _handleSessionExpired;

    _bootstrap();
    return SessionState.bootstrapping();
  }

  Future<void> _bootstrap() async {
    // SecureTokenStorage degrades a failed/hung read to null internally, so this never leaves
    // the app stuck on the splash screen even if the browser's local storage is unreadable.
    final accessToken = await SecureTokenStorage.instance.readAccessToken();
    if (accessToken == null) {
      state = SessionState.unauthenticated();
      return;
    }
    try {
      final profile = await _authApi.fetchProfile();
      _applyActiveMembership(profile);
      state = SessionState.authenticated(profile);
    } on ApiException {
      // AuthInterceptor already tried a silent refresh before this bubbled up - if we're here,
      // the session really is gone.
      await SecureTokenStorage.instance.clear();
      state = SessionState.unauthenticated();
    }
  }

  /// Step 1 of the unified login flow - one identifier (username or phone), backend decides
  /// whether the next step is a password field or an OTP field. For OTP accounts the code has
  /// already been sent as a side effect of this call.
  Future<IdentifyResult> identify(String identifier) => _authApi.identify(identifier);

  Future<void> loginWithPassword(String username, String password) async {
    final result = await _authApi.login(username, password);
    await _onLoginSuccess(result);
  }

  /// Public self-signup - username and password chosen together, same screen. Always creates a
  /// GUEST account and logs them straight in, same as a normal login.
  Future<void> signup({
    required String username,
    required String password,
    required String fullName,
    required String phone,
    required String email,
  }) async {
    final result = await _authApi.signup(
      username: username,
      password: password,
      fullName: fullName,
      phone: phone,
      email: email,
    );
    await _onLoginSuccess(result);
  }

  Future<void> resendOtp(String identifier) => _authApi.resendOtp(identifier);

  Future<void> verifyOtp(String identifier, String code) async {
    final result = await _authApi.verifyOtp(identifier, code);
    await _onLoginSuccess(result);
  }

  Future<void> _onLoginSuccess(LoginResult result) async {
    await SecureTokenStorage.instance.saveTokens(accessToken: result.accessToken, refreshToken: result.refreshToken);
    _applyActiveMembership(result.user);
    state = SessionState.authenticated(result.user);
  }

  Future<void> logout() async {
    final refreshToken = await SecureTokenStorage.instance.readRefreshToken();
    if (refreshToken != null) {
      try {
        await _authApi.logout(refreshToken);
      } on ApiException {
        // Best-effort - the important part (clearing local tokens) still happens below even if
        // the server call fails (e.g. offline).
      }
    }
    await _clearAndSetUnauthenticated();
  }

  /// Invoked by AuthInterceptor when a refresh attempt fails - the refresh token itself is
  /// invalid/expired/revoked, so there is nothing left to do server-side.
  void _handleSessionExpired() {
    _clearAndSetUnauthenticated();
  }

  Future<void> _clearAndSetUnauthenticated() async {
    await SecureTokenStorage.instance.clear();
    ActiveMembershipHolder.instance.membershipId = null;
    state = SessionState.unauthenticated();
  }

  /// PRD 3.1.1 Academy Switcher - which membership's Fees/Attendance/Syllabus data is in view.
  void switchActiveMembership(String membershipId) {
    final user = state.user;
    if (user == null) return;
    ActiveMembershipHolder.instance.membershipId = membershipId;
    state = SessionState.authenticated(UserProfile(
      id: user.id,
      username: user.username,
      fullName: user.fullName,
      maskedPhone: user.maskedPhone,
      email: user.email,
      city: user.city,
      state: user.state,
      role: user.role,
      temporaryPassword: user.temporaryPassword,
      themePreference: user.themePreference,
      memberships: user.memberships,
      activeMembershipId: membershipId,
      profileImageUrl: user.profileImageUrl,
    ));
  }

  Future<void> refreshProfile() async {
    final profile = await _authApi.fetchProfile();
    _applyActiveMembership(profile);
    state = SessionState.authenticated(profile);
  }

  void _applyActiveMembership(UserProfile profile) {
    ActiveMembershipHolder.instance.membershipId = profile.activeMembershipId ?? profile.activeMembership?.membershipId;
  }
}
