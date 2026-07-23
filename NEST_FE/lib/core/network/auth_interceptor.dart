import 'package:dio/dio.dart';
import 'package:nest_fe/core/network/api_config.dart';
import 'package:nest_fe/core/storage/secure_token_storage.dart';

/// Attaches the access token to every request, and on a 401 transparently swaps in a fresh
/// access token via the (rotating, server-tracked) refresh token before retrying - this is the
/// client half of the "stay logged in until you log out" session model the backend enforces.
/// The user only ever sees a login screen again if the refresh token itself is invalid, expired,
/// or they tapped Logout.
///
/// Concurrent 401s (e.g. a screen fires 4 requests at once right as the access token expires)
/// must not each independently call /auth/refresh - that would race against the backend's
/// single-use refresh-token rotation and only one would win. [_refreshing] makes every caller
/// share one in-flight refresh.
class AuthInterceptor extends Interceptor {
  AuthInterceptor();

  /// Called when the refresh token itself is no longer usable - the app should route to /login.
  /// Deliberately mutable and unset at construction time (rather than a constructor arg): the
  /// session layer that wants to be notified is built ON TOP OF DioClient, so wiring this the
  /// other way around would make DioClient's provider depend on the session provider, which
  /// depends on DioClient's provider - a cycle. Assigned once, after both exist.
  void Function() onSessionExpired = _noop;

  static void _noop() {}

  final Dio _refreshDio = Dio(BaseOptions(baseUrl: ApiConfig.baseUrl));
  Future<String?>? _refreshing;

  @override
  Future<void> onRequest(RequestOptions options, RequestInterceptorHandler handler) async {
    // Runs before EVERY request - SecureTokenStorage degrades a failed/hung read to null
    // internally, so this can never stall a request indefinitely. No token just means no
    // Authorization header, which the backend 401s normally and this interceptor already
    // knows how to recover from below.
    final token = await SecureTokenStorage.instance.readAccessToken();
    if (token != null) {
      options.headers['Authorization'] = 'Bearer $token';
    }
    handler.next(options);
  }

  @override
  Future<void> onError(DioException err, ErrorInterceptorHandler handler) async {
    final isUnauthorized = err.response?.statusCode == 401;
    final alreadyRetried = err.requestOptions.extra['nest_retried'] == true;

    if (!isUnauthorized || alreadyRetried) {
      handler.next(err);
      return;
    }

    final newAccessToken = await _refreshAccessToken();
    if (newAccessToken == null) {
      onSessionExpired();
      handler.next(err);
      return;
    }

    try {
      final retryOptions = err.requestOptions;
      retryOptions.headers['Authorization'] = 'Bearer $newAccessToken';
      retryOptions.extra['nest_retried'] = true;
      final response = await Dio(BaseOptions(baseUrl: ApiConfig.baseUrl)).fetch(retryOptions);
      handler.resolve(response);
    } on DioException catch (retryError) {
      handler.next(retryError);
    }
  }

  Future<String?> _refreshAccessToken() {
    // Share one in-flight refresh across every concurrent 401 instead of racing.
    return _refreshing ??= _doRefresh().whenComplete(() => _refreshing = null);
  }

  Future<String?> _doRefresh() async {
    final refreshToken = await SecureTokenStorage.instance.readRefreshToken();
    if (refreshToken == null) return null;

    try {
      final response = await _refreshDio.post('/auth/refresh', data: {'refreshToken': refreshToken});
      final newAccessToken = response.data['accessToken'] as String;
      final newRefreshToken = response.data['refreshToken'] as String;
      await SecureTokenStorage.instance.saveTokens(accessToken: newAccessToken, refreshToken: newRefreshToken);
      return newAccessToken;
    } on DioException {
      await SecureTokenStorage.instance.clear();
      return null;
    }
  }
}
