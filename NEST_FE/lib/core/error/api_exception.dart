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
    final validationErrors = (json['validationErrors'] as List?)
        ?.map((e) => Map<String, String>.from(e as Map))
        .toList();
    return ApiException(
      status: (json['status'] as num?)?.toInt() ?? status,
      error: json['error'] as String? ?? 'Error',
      code: json['code'] as String? ?? 'UNKNOWN',
      message: _messageFor(json['message'] as String?, validationErrors),
      validationErrors: validationErrors,
    );
  }

  /// A rejected form comes back as "Request failed validation" plus the real reasons per field.
  /// Every screen shows [message], so it carries the first reason (and says how many more there are)
  /// instead of that generic line.
  static String _messageFor(String? message, List<Map<String, String>>? errors) {
    if (errors == null || errors.isEmpty) return message ?? 'Something went wrong';
    final first = errors.first['message'];
    if (first == null || first.isEmpty) return message ?? 'Something went wrong';
    final more = errors.length - 1;
    return more > 0 ? '$first (and $more more to fix)' : first;
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
