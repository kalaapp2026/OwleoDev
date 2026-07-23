/// Mirrors the backend's ErrorResponse shape (com.nest.common.dto.ErrorResponse) so every
/// screen can show a consistent, real message instead of a generic "something went wrong."
class ApiException implements Exception {
  final int status;
  final String error;
  final String code;
  final String message;
  final List<Map<String, String>>? validationErrors;

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
      validationErrors: (json['validationErrors'] as List?)
          ?.map((e) => Map<String, String>.from(e as Map))
          .toList(),
    );
  }

  factory ApiException.network([String? detail]) => ApiException(
        status: 0,
        error: 'Network Error',
        code: 'NETWORK_ERROR',
        message: detail ?? 'Could not reach the server - check your connection.',
      );

  bool get isUnauthorized => status == 401;
  bool get isForbidden => status == 403;
  bool get isValidation => code == 'VALIDATION_FAILED';

  /// First field-level message, handy for inline form errors.
  String? fieldError(String field) => validationErrors
      ?.firstWhere((e) => e['field'] == field, orElse: () => {})['message'];

  @override
  String toString() => message;
}
