import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:nest_fe/core/auth/session_controller.dart';
import 'package:nest_fe/core/auth/user_profile.dart';
import 'package:nest_fe/core/providers/core_providers.dart';

final themeModeProvider = NotifierProvider<ThemeModeController, ThemeMode>(ThemeModeController.new);

/// Phase 6 of the PRD: theme is a per-account preference synced to the backend
/// (PATCH /users/me/theme), not just a local device setting - so it follows the user across
/// devices. Falls back to the OS setting for anyone not logged in yet.
class ThemeModeController extends Notifier<ThemeMode> {
  @override
  ThemeMode build() {
    ref.listen(sessionControllerProvider, (previous, next) {
      final pref = next.user?.themePreference;
      if (pref != null) {
        state = _toFlutterThemeMode(pref);
      }
    });
    return ThemeMode.system;
  }

  Future<void> setThemeMode(ThemeMode mode) async {
    state = mode;
    final session = ref.read(sessionControllerProvider);
    if (!session.isAuthenticated) return; // nothing to sync yet

    final pref = switch (mode) {
      ThemeMode.light => ThemePreference.light,
      ThemeMode.dark => ThemePreference.dark,
      ThemeMode.system => ThemePreference.system,
    };
    // Fire-and-forget: the UI has already switched locally, this just persists the choice so it
    // follows the user to their next device/session.
    unawaited(ref.read(authApiProvider).updateTheme(pref));
  }

  ThemeMode _toFlutterThemeMode(ThemePreference pref) => switch (pref) {
        ThemePreference.light => ThemeMode.light,
        ThemePreference.dark => ThemeMode.dark,
        ThemePreference.system => ThemeMode.system,
      };
}
