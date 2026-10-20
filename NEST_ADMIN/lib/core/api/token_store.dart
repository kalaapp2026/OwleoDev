import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// The only place that touches the raw tokens. On web this is browser storage (there is no OS
/// keychain in a browser), the same trade-off NEST_FE makes. Every read degrades to "absent" on
/// failure so a corrupted entry shows the login screen rather than a stuck spinner.
class TokenStore {
  TokenStore._();
  static final TokenStore instance = TokenStore._();

  // A different key prefix from the academy app, so the two apps never read each other's tokens
  // if they are ever served from the same origin.
  static const _accessKey = 'hq.accessToken';
  static const _refreshKey = 'hq.refreshToken';
  static const _timeout = Duration(seconds: 5);

  final _storage = const FlutterSecureStorage();

  Future<void> save({required String access, required String refresh}) async {
    await Future.wait([_write(_accessKey, access), _write(_refreshKey, refresh)]);
  }

  Future<String?> readAccess() => _read(_accessKey);
  Future<String?> readRefresh() => _read(_refreshKey);

  Future<void> clear() async {
    await Future.wait([_delete(_accessKey), _delete(_refreshKey)]);
  }

  Future<String?> _read(String key) async {
    try {
      return await _storage.read(key: key).timeout(_timeout);
    } catch (e) {
      debugPrint('TokenStore: read($key) failed, treating as absent - $e');
      return null;
    }
  }

  Future<void> _write(String key, String value) async {
    try {
      await _storage.write(key: key, value: value).timeout(_timeout);
    } catch (e) {
      debugPrint('TokenStore: write($key) failed - $e');
    }
  }

  Future<void> _delete(String key) async {
    try {
      await _storage.delete(key: key).timeout(_timeout);
    } catch (e) {
      debugPrint('TokenStore: delete($key) failed - $e');
    }
  }
}
