/// Where the API lives. The HQ console talks to the SAME Spring Boot server as the academy app,
/// so the defaults match NEST_FE: port 8081 locally, and `--dart-define=API_BASE_URL=...` for a
/// deployed build (the value is compiled in, so changing it needs a rebuild, not a restart).
abstract final class ApiConfig {
  static const _override = String.fromEnvironment('API_BASE_URL');

  static String get baseUrl => _override.isNotEmpty ? _override : 'http://localhost:8081';
}
