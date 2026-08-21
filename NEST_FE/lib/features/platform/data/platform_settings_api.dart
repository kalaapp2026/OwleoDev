import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:nest_fe/core/network/dio_client.dart';
import 'package:nest_fe/core/providers/core_providers.dart';

/// Which half of the app people get, set platform-wide by the Super Admin. Rollout is ERP-first,
/// so an academy being onboarded isn't shown a Social side that isn't ready for them.
enum AppModeSetting {
  erpFirst('ERP_FIRST', 'ERP first', 'Both sides available. The app opens on ERP.'),
  socialFirst('SOCIAL_FIRST', 'Social first', 'Both sides available. The app opens on Social.'),
  erpOnly('ERP_ONLY', 'ERP only', 'Social is hidden completely and the centre toggle disappears.'),
  socialOnly('SOCIAL_ONLY', 'Social only', 'ERP is hidden completely and the centre toggle disappears.');

  const AppModeSetting(this.wire, this.label, this.description);

  final String wire;
  final String label;
  final String description;

  static AppModeSetting fromWire(String? value) => AppModeSetting.values.firstWhere(
        (m) => m.wire == value,
        orElse: () => AppModeSetting.erpFirst,
      );
}

class PlatformSettings {
  final AppModeSetting appMode;
  final bool allowsErp;
  final bool allowsSocial;

  /// False means one half is hidden entirely - the nav's centre toggle should not be shown at all.
  final bool allowsBoth;
  final bool startsOnErp;

  const PlatformSettings({
    required this.appMode,
    required this.allowsErp,
    required this.allowsSocial,
    required this.allowsBoth,
    required this.startsOnErp,
  });

  /// Used before the real settings arrive and if the call fails. ERP-first matches the backend
  /// default, and showing both halves is the non-destructive guess: briefly showing a toggle that
  /// then disappears is better than hiding a side the user is entitled to.
  static const fallback = PlatformSettings(
    appMode: AppModeSetting.erpFirst,
    allowsErp: true,
    allowsSocial: true,
    allowsBoth: true,
    startsOnErp: true,
  );

  factory PlatformSettings.fromJson(Map<String, dynamic> json) {
    final mode = AppModeSetting.fromWire(json['appMode'] as String?);
    return PlatformSettings(
      appMode: mode,
      // Prefer the server's booleans - it owns what a mode means, so every client agrees rather
      // than each re-deriving the rules. Fall back to the enum if an older backend omits them.
      allowsErp: json['allowsErp'] as bool? ?? mode != AppModeSetting.socialOnly,
      allowsSocial: json['allowsSocial'] as bool? ?? mode != AppModeSetting.erpOnly,
      allowsBoth: json['allowsBoth'] as bool? ??
          (mode == AppModeSetting.erpFirst || mode == AppModeSetting.socialFirst),
      startsOnErp: json['startsOnErp'] as bool? ??
          (mode == AppModeSetting.erpFirst || mode == AppModeSetting.erpOnly),
    );
  }
}

class PlatformSettingsApi {
  PlatformSettingsApi(this._client);
  final DioClient _client;

  /// Readable by any signed-in user - the shell needs it to know which side to open.
  Future<PlatformSettings> fetch() => _client.call(
        (dio) => dio.get('/platform/settings'),
        (data) => PlatformSettings.fromJson(data as Map<String, dynamic>),
      );

  Future<PlatformSettings> update(AppModeSetting mode) => _client.call(
        (dio) => dio.put('/admin/platform/settings', data: {'appMode': mode.wire}),
        (data) => PlatformSettings.fromJson(data as Map<String, dynamic>),
      );
}

final platformSettingsApiProvider =
    Provider((ref) => PlatformSettingsApi(ref.watch(dioClientProvider)));

/// Deliberately NOT autoDispose: the shell reads this on every rebuild, and letting it dispose
/// would refetch (and flash the fallback) every time the widget tree settles.
final platformSettingsProvider = FutureProvider<PlatformSettings>(
  (ref) => ref.watch(platformSettingsApiProvider).fetch(),
);
