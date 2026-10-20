import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../api/api_exception.dart';
import '../api/dio_client.dart';
import '../api/token_store.dart';
import 'hq_access.dart';

enum SessionStatus { bootstrapping, signedOut, signedIn }

class SessionState {
  const SessionState(this.status, {this.user, this.error});
  final SessionStatus status;
  final HqUser? user;
  final String? error;
}

final dioClientProvider = Provider<DioClient>((ref) => DioClient());

final sessionProvider = StateNotifierProvider<SessionController, SessionState>((ref) {
  return SessionController(ref.watch(dioClientProvider));
});

/// The signed-in HQ user, for screens that only exist while signed in.
final hqUserProvider = Provider<HqUser>((ref) {
  final u = ref.watch(sessionProvider).user;
  if (u == null) throw StateError('hqUserProvider read while signed out');
  return u;
});

class SessionController extends StateNotifier<SessionState> {
  SessionController(this._client) : super(const SessionState(SessionStatus.bootstrapping)) {
    _client.onSessionExpired = () => state = const SessionState(SessionStatus.signedOut);
    _restore();
  }

  final DioClient _client;

  /// On a reload, pick the session back up from the stored token instead of asking for a password.
  Future<void> _restore() async {
    final token = await TokenStore.instance.readAccess();
    if (token == null) {
      state = const SessionState(SessionStatus.signedOut);
      return;
    }
    try {
      state = SessionState(SessionStatus.signedIn, user: await _loadMe());
    } on ApiException {
      await TokenStore.instance.clear();
      state = const SessionState(SessionStatus.signedOut);
    }
  }

  Future<HqUser> _loadMe() async => HqUser.fromJson(await _client.getMap('/admin/hq/me'));

  /// Returns null on success, or a message to show under the form.
  Future<String?> login(String username, String password) async {
    try {
      final res = await _client.postMap('/auth/login', body: {'username': username.trim(), 'password': password});
      final role = (res['user'] as Map?)?['role'];
      if (role != 'SUPER_ADMIN') {
        // The same backend serves the academy app, so a valid student or trainer login must be
        // turned away here rather than shown an empty console.
        return 'This console is for Owleo HQ staff. Use the Owleo Nest app instead.';
      }
      await TokenStore.instance.save(access: res['accessToken'] as String, refresh: res['refreshToken'] as String);
      state = SessionState(SessionStatus.signedIn, user: await _loadMe());
      return null;
    } on ApiException catch (e) {
      return e.isUnauthorized ? 'That username or password is not right.' : e.message;
    }
  }

  Future<void> logout() async {
    final refresh = await TokenStore.instance.readRefresh();
    try {
      if (refresh != null) await _client.callVoid((d) => d.post('/auth/logout', data: {'refreshToken': refresh}));
    } catch (_) {
      // Signing out must always work, even when the server is unreachable.
    }
    await TokenStore.instance.clear();
    state = const SessionState(SessionStatus.signedOut);
  }
}
