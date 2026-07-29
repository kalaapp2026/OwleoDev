import 'dart:io' show Platform;
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:nest_fe/features/platform/data/platform_api.dart';

/// Bump alongside pubspec.yaml's version. Kept as a plain constant rather than pulling in
/// package_info_plus for one string - it only feeds a dashboard breakdown, so a stale value is
/// cosmetic, never functional.
const String kAppVersion = '1.0.0';

/// Reports this device to the backend once per launch so the Super Admin console can show an
/// "installs seen" figure. The id is generated here and stored locally - it is NOT a hardware
/// identifier, so it carries no PII and can't be correlated with anything outside NEST.
class DeviceInstallService {
  DeviceInstallService(this._api);

  final PlatformApi _api;

  static const _deviceIdKey = 'nest.deviceId';
  static const _storage = FlutterSecureStorage(
    aOptions: AndroidOptions(encryptedSharedPreferences: true),
  );

  /// Best-effort by design: this is analytics, so a failure here must never surface to the user
  /// or block startup. Callers fire it and ignore the result.
  Future<void> reportLaunch() async {
    try {
      await _api.pingDevice(
        deviceId: await _deviceId(),
        platform: _platformName(),
        appVersion: kAppVersion,
      );
    } catch (e) {
      debugPrint('DeviceInstallService: install ping failed (ignored) - $e');
    }
  }

  Future<String> _deviceId() async {
    final existing = await _storage.read(key: _deviceIdKey);
    if (existing != null && existing.isNotEmpty) return existing;

    final generated = _randomId();
    await _storage.write(key: _deviceIdKey, value: generated);
    return generated;
  }

  /// 32 hex chars from a cryptographic source - enough that collisions across installs aren't a
  /// practical concern, without pulling in a uuid package for one call site.
  String _randomId() {
    final random = Random.secure();
    return List.generate(16, (_) => random.nextInt(256).toRadixString(16).padLeft(2, '0')).join();
  }

  String _platformName() {
    if (kIsWeb) return 'web';
    return Platform.operatingSystem;
  }
}
