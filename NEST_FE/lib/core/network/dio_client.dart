import 'package:dio/dio.dart';
import 'package:nest_fe/core/error/api_exception.dart';
import 'package:nest_fe/core/network/api_config.dart';
import 'package:nest_fe/core/network/auth_interceptor.dart';

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

    authInterceptor = AuthInterceptor();
    dio.interceptors.add(authInterceptor);
  }

  late final Dio dio;
  late final AuthInterceptor authInterceptor;

  /// Every repository call should route through this so DioException always becomes the same
  /// ApiException shape the UI knows how to render - no screen should ever catch a raw DioException.
  Future<T> call<T>(Future<Response<dynamic>> Function(Dio dio) request, T Function(dynamic data) parse) async {
    try {
      final response = await request(dio);
      return parse(response.data);
    } on DioException catch (e) {
      throw _mapError(e);
    }
  }

  /// For endpoints whose success response carries nothing worth parsing (204s, fire-and-forget
  /// POSTs) - avoids every caller writing `(_) => null` against a `Future<void>` return type.
  Future<void> callVoid(Future<Response<dynamic>> Function(Dio dio) request) async {
    try {
      await request(dio);
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
