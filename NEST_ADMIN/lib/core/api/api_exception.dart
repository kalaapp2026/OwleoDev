/// Mirrors the backend's ErrorResponse shape (`com.nest.common.dto.ErrorResponse`), the same one
/// NEST_FE parses, so every screen shows the server's real message instead of a generic failure.
class ApiException implements Exception {
  ApiException({
    required this.status,
    required this.error,
    required this.code,
    required this.message,
    this.validationErrors,
  });

  factory ApiException.fromJson(Map<String, dynamic> json, {int status = 0}) {
    return ApiException(
      status: (json['status'] as num?)?.toInt() ?? status,
      error: json['error'] as String? ?? 'Error',
      code: json['code'] as String? ?? 'UNKNOWN',
      message: json['message'] as String? ?? 'Something went wrong',
      validationErrors:
          (json['validationErrors'] as List?)?.map((e) => Map<String, String>.from(e as Map)).toList(),
    );
  }

  factory ApiException.network([String? detail]) => ApiException(
        status: 0,
        error: 'Network Error',
        code: 'NETWORK_ERROR',
        message: detail ?? 'Could not reach the server. Check your connection.',
      );

  final int status;
  final String error;
  final String code;
  final String message;
  final List<Map<String, String>>? validationErrors;

  bool get isUnauthorized => status == 401;
  bool get isForbidden => status == 403;

  @override
  String toString() => message;
}
