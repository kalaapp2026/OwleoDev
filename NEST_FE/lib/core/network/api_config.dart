import 'dart:io' show Platform;
import 'package:flutter/foundation.dart' show kIsWeb;

/// Local-dev base URL resolution. Android's emulator can't resolve "localhost" as the host
/// machine - it uses the special alias 10.0.2.2 for that. Web and iOS simulator share the host's
/// network namespace, so plain localhost works there. Override with --dart-define=API_BASE_URL=...
/// for a real device on the same LAN, or a deployed environment.
class ApiConfig {
  ApiConfig._();

  static String get baseUrl {
    const override = String.fromEnvironment('API_BASE_URL');
    if (override.isNotEmpty) return override;

    if (kIsWeb) return 'http://localhost:8081';
    if (Platform.isAndroid) return 'http://10.0.2.2:8081';
    return 'http://localhost:8081';
  }

  /// Backend responses store uploaded media (profile pictures) as a relative path like
  /// "/uploads/profile-images/xyz.jpg" - resolve it against the same host the API calls go to,
  /// same reasoning as baseUrl itself (Android emulator can't reach "localhost").
  static String? resolveMediaUrl(String? path) {
    if (path == null || path.isEmpty) return null;
    if (path.startsWith('http://') || path.startsWith('https://')) return path;
    return '$baseUrl$path';
  }
}
