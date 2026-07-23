import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Wraps flutter_secure_storage (Keychain on iOS, Keystore-backed EncryptedSharedPreferences on
/// Android, localStorage on web - there's no OS keychain in a browser, this is the accepted
/// trade-off every web app makes). This is the only place that touches raw tokens on disk.
class SecureTokenStorage {
  SecureTokenStorage._();

  static final SecureTokenStorage instance = SecureTokenStorage._();

  static const _accessTokenKey = 'nest.accessToken';
  static const _refreshTokenKey = 'nest.refreshToken';
  static const _ioTimeout = Duration(seconds: 5);

  final _storage = const FlutterSecureStorage(
    aOptions: AndroidOptions(encryptedSharedPreferences: true),
  );

  Future<void> saveTokens({required String accessToken, required String refreshToken}) async {
    await Future.wait([
      _write(_accessTokenKey, accessToken),
      _write(_refreshTokenKey, refreshToken),
    ]);
  }

  Future<void> saveAccessToken(String accessToken) => _write(_accessTokenKey, accessToken);

  Future<String?> readAccessToken() => _read(_accessTokenKey);

  Future<String?> readRefreshToken() => _read(_refreshTokenKey);

  Future<void> clear() async {
    await Future.wait([
      _delete(_accessTokenKey),
      _delete(_refreshTokenKey),
    ]);
  }

  /// On web this decrypts via the browser's Web Crypto API whenever something's already stored -
  /// a corrupted/unimportable key left over from an earlier build or session must never hang or
  /// crash the caller, since this runs on the hot path of every single API request (see
  /// AuthInterceptor.onRequest). A failed/timed-out read degrades to "no token", exactly like a
  /// signed-out user - never a stuck spinner or a misleading "can't reach the server".
  Future<String?> _read(String key) async {
    try {
      return await _storage.read(key: key).timeout(_ioTimeout);
    } catch (e) {
      debugPrint('SecureTokenStorage: read($key) failed, treating as absent - $e');
      return null;
    }
  }

  Future<void> _write(String key, String value) async {
    try {
      await _storage.write(key: key, value: value).timeout(_ioTimeout);
    } catch (e) {
      debugPrint('SecureTokenStorage: write($key) failed, value will not persist - $e');
    }
  }

  Future<void> _delete(String key) async {
    try {
      await _storage.delete(key: key).timeout(_ioTimeout);
    } catch (e) {
      debugPrint('SecureTokenStorage: delete($key) failed - $e');
    }
  }
}
