import 'dart:async';

import 'package:dio/dio.dart';
import 'package:nest_fe/core/error/api_exception.dart';
import 'package:nest_fe/core/network/api_config.dart';
import 'package:nest_fe/core/network/auth_interceptor.dart';
import 'package:nest_fe/core/network/get_cache_interceptor.dart';
import 'package:nest_fe/core/storage/secure_token_storage.dart';

/// Holds which of the caller's academy memberships is "active" right now (PRD 3.1.1's Academy
/// Switcher) and stamps it on every request via X-Active-Membership, which
/// JwtAuthFilter on the backend reads to scope Fees/Attendance/Syllabus to that one academy.
class ActiveMembershipHolder {
  ActiveMembershipHolder._();
  static final instance = ActiveMembershipHolder._();

  String? membershipId;
}

class DioClient {
  DioClient() {
    dio = Dio(BaseOptions(
      baseUrl: ApiConfig.baseUrl,
      connectTimeout: const Duration(seconds: 15),
      receiveTimeout: const Duration(seconds: 20),
      contentType: 'application/json',
      // Defense in depth: if the backend ever hits an error path outside its normal JSON error
      // handler (e.g. an exception thrown by a servlet filter before Spring MVC), an explicit
      // Accept header is what tells Boot's default error view to render JSON instead of an HTML
      // whitelabel page - which _mapError below can't parse and would otherwise misreport as a
      // generic "can't reach the server" instead of showing the real error.
      headers: {'Accept': 'application/json'},
    ));

    dio.interceptors.add(InterceptorsWrapper(
      onRequest: (options, handler) {
        final activeMembership = ActiveMembershipHolder.instance.membershipId;
        if (activeMembership != null) {
          options.headers['X-Active-Membership'] = activeMembership;
        }
        handler.next(options);
      },
    ));

    // Before the auth interceptor on purpose - see GetCacheInterceptor.
    cache = GetCacheInterceptor(identity: SecureTokenStorage.instance.readAccessToken);
    dio.interceptors.add(cache);

    authInterceptor = AuthInterceptor();
    dio.interceptors.add(authInterceptor);
  }

  late final Dio dio;
  late final AuthInterceptor authInterceptor;
  late final GetCacheInterceptor cache;

  final _mutations = StreamController<String>.broadcast();

  /// The path of every write (POST/PUT/PATCH/DELETE) that has just succeeded. This is what lets
  /// the screens showing related data refresh themselves - see DataSync - so no save has to
  /// remember which other screens to invalidate.
  Stream<String> get mutations => _mutations.stream;

  /// Writes that change nothing anyone is looking at: signing in, the device ping, push-token
  /// registration, personal display preferences, the audio player's saved settings. Refreshing
  /// the app after each of those would only cost calls.
  static bool isBackgroundWrite(String path) =>
      path.startsWith('/auth/') ||
      path.startsWith('/devices/') ||
      path.startsWith('/notifications/push-token') ||
      path.startsWith('/users/me/theme') ||
      path.startsWith('/users/me/language') ||
      path.startsWith('/users/me/notification-prefs') ||
      path.endsWith('/playback');

  void _afterSuccess(Response<dynamic> response) {
    final options = response.requestOptions;
    if (options.method == 'GET' || options.method == 'HEAD') return;
    cache.clear();
    if (!isBackgroundWrite(options.path)) _mutations.add(options.path);
  }

  /// Every repository call should route through this so DioException always becomes the same
  /// ApiException shape the UI knows how to render - no screen should ever catch a raw DioException.
  Future<T> call<T>(Future<Response<dynamic>> Function(Dio dio) request, T Function(dynamic data) parse) async {
    final Response<dynamic> response;
    try {
      response = await request(dio);
    } on DioException catch (e) {
      throw _mapError(e);
    }
    // Outside the try: the write happened even if reading its answer then fails.
    _afterSuccess(response);
    return parse(response.data);
  }

  /// For endpoints whose success response carries nothing worth parsing (204s, fire-and-forget
  /// POSTs) - avoids every caller writing `(_) => null` against a `Future<void>` return type.
  Future<void> callVoid(Future<Response<dynamic>> Function(Dio dio) request) async {
    try {
      _afterSuccess(await request(dio));
    } on DioException catch (e) {
      throw _mapError(e);
    }
  }

  ApiException _mapError(DioException e) {
    final data = e.response?.data;
    if (data is Map<String, dynamic>) {
      return ApiException.fromJson(data, status: e.response?.statusCode ?? 0);
    }
    final status = e.response?.statusCode;
    if (status != null) {
      // A response WAS received (so this isn't actually a connectivity problem) but its body
      // wasn't the JSON shape ErrorResponse expects - e.g. the backend hit an error path outside
      // its normal JSON error handler. Surface the status instead of a misleading "can't reach
      // the server", which sends debugging in entirely the wrong direction.
      return ApiException.network('Server returned an unexpected error (HTTP $status).');
    }
    if (e.type == DioExceptionType.connectionError || e.type == DioExceptionType.connectionTimeout) {
      return ApiException.network();
    }
    return ApiException.network(e.message);
  }
}
