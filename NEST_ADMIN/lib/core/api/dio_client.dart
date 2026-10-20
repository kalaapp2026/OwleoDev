import 'package:dio/dio.dart';

import 'api_config.dart';
import 'api_exception.dart';
import 'token_store.dart';

/// One Dio instance with the same session behaviour as the academy app: attach the access token,
/// and on a 401 swap in a fresh one through the rotating refresh token and retry once. Concurrent
/// 401s share a single in-flight refresh, because the backend's refresh token is single-use and
/// two parallel refreshes would race.
class DioClient {
  DioClient() {
    dio = Dio(BaseOptions(
      baseUrl: ApiConfig.baseUrl,
      connectTimeout: const Duration(seconds: 15),
      receiveTimeout: const Duration(seconds: 30),
      contentType: 'application/json',
      headers: {'Accept': 'application/json'},
    ));
    dio.interceptors.add(_AuthInterceptor(this));
  }

  late final Dio dio;

  /// Called when the refresh token itself is no longer usable. Assigned after construction by the
  /// session layer, which is built on top of this client.
  void Function() onSessionExpired = () {};

  final Dio _refreshDio = Dio(BaseOptions(baseUrl: ApiConfig.baseUrl));
  Future<String?>? _refreshing;

  /// Every repository call goes through here so a DioException always becomes an [ApiException].
  Future<T> call<T>(Future<Response<dynamic>> Function(Dio dio) request, T Function(dynamic data) parse) async {
    try {
      final response = await request(dio);
      return parse(response.data);
    } on DioException catch (e) {
      throw _map(e);
    }
  }

  Future<void> callVoid(Future<Response<dynamic>> Function(Dio dio) request) async {
    try {
      await request(dio);
    } on DioException catch (e) {
      throw _map(e);
    }
  }

  /// A GET that returns a JSON object.
  Future<Map<String, dynamic>> getMap(String path, {Map<String, dynamic>? query}) =>
      call((d) => d.get(path, queryParameters: query), (data) => Map<String, dynamic>.from(data as Map));

  /// A GET that returns a JSON array of objects.
  Future<List<Map<String, dynamic>>> getList(String path, {Map<String, dynamic>? query}) => call(
        (d) => d.get(path, queryParameters: query),
        (data) => (data as List).map((e) => Map<String, dynamic>.from(e as Map)).toList(),
      );

  Future<Map<String, dynamic>> postMap(String path, {Object? body, Map<String, dynamic>? query}) => call(
        (d) => d.post(path, data: body, queryParameters: query),
        (data) => data is Map ? Map<String, dynamic>.from(data) : <String, dynamic>{},
      );

  Future<Map<String, dynamic>> putMap(String path, {Object? body, Map<String, dynamic>? query}) => call(
        (d) => d.put(path, data: body, queryParameters: query),
        (data) => data is Map ? Map<String, dynamic>.from(data) : <String, dynamic>{},
      );

  Future<Map<String, dynamic>> patchMap(String path, {Object? body}) => call(
        (d) => d.patch(path, data: body),
        (data) => data is Map ? Map<String, dynamic>.from(data) : <String, dynamic>{},
      );

  Future<void> delete(String path) => callVoid((d) => d.delete(path));

  ApiException _map(DioException e) {
    final data = e.response?.data;
    if (data is Map<String, dynamic>) {
      return ApiException.fromJson(data, status: e.response?.statusCode ?? 0);
    }
    final status = e.response?.statusCode;
    if (status != null) {
      return ApiException.network('The server returned an unexpected error (HTTP $status).');
    }
    if (e.type == DioExceptionType.connectionError || e.type == DioExceptionType.connectionTimeout) {
      return ApiException.network();
    }
    return ApiException.network(e.message);
  }

  Future<String?> refreshAccessToken() => _refreshing ??= _doRefresh().whenComplete(() => _refreshing = null);

  Future<String?> _doRefresh() async {
    final refresh = await TokenStore.instance.readRefresh();
    if (refresh == null) return null;
    try {
      final res = await _refreshDio.post('/auth/refresh', data: {'refreshToken': refresh});
      final access = res.data['accessToken'] as String;
      final next = res.data['refreshToken'] as String;
      await TokenStore.instance.save(access: access, refresh: next);
      return access;
    } on DioException {
      await TokenStore.instance.clear();
      return null;
    }
  }
}

class _AuthInterceptor extends Interceptor {
  _AuthInterceptor(this._client);
  final DioClient _client;

  @override
  Future<void> onRequest(RequestOptions options, RequestInterceptorHandler handler) async {
    final token = await TokenStore.instance.readAccess();
    if (token != null) options.headers['Authorization'] = 'Bearer $token';
    handler.next(options);
  }

  @override
  Future<void> onError(DioException err, ErrorInterceptorHandler handler) async {
    final unauthorized = err.response?.statusCode == 401;
    final retried = err.requestOptions.extra['hq_retried'] == true;
    // A failed login is also a 401, and must show "wrong password", not trigger a refresh.
    final isAuthCall = err.requestOptions.path.startsWith('/auth/');
    if (!unauthorized || retried || isAuthCall) {
      handler.next(err);
      return;
    }
    final fresh = await _client.refreshAccessToken();
    if (fresh == null) {
      _client.onSessionExpired();
      handler.next(err);
      return;
    }
    try {
      final opts = err.requestOptions
        ..headers['Authorization'] = 'Bearer $fresh'
        ..extra['hq_retried'] = true;
      handler.resolve(await Dio(BaseOptions(baseUrl: ApiConfig.baseUrl)).fetch(opts));
    } on DioException catch (retryError) {
      handler.next(retryError);
    }
  }
}
