import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:nest_fe/app/i18n/app_languages.dart';
import 'package:nest_fe/core/auth/session_controller.dart';
import 'package:nest_fe/core/providers/core_providers.dart';

final localeProvider = NotifierProvider<LocaleController, AppLanguage>(LocaleController.new);

/// UI language as a per-account preference synced to the backend (PATCH /users/me/language),
/// mirroring how theme already works - so it follows the person to their next device rather than
/// being stuck on whichever phone they set it on.
///
/// Before login there is no account to read from, so the app stays on English; the moment the
/// session resolves, the stored preference takes over.
class LocaleController extends Notifier<AppLanguage> {
  @override
  AppLanguage build() {
    ref.listen(sessionControllerProvider, (previous, next) {
      final tag = next.user?.languagePreference;
      if (tag != null) {
        state = AppLanguage.fromTag(tag);
      }
    });
    return AppLanguage.english;
  }

  Future<void> setLanguage(AppLanguage language) async {
    state = language;

    final session = ref.read(sessionControllerProvider);
    if (!session.isAuthenticated) return; // nothing to sync to yet

    // Fire-and-forget, same as theme: the UI has already switched, this only persists the choice.
    // A failure here means the language reverts on next login, which is recoverable - blocking the
    // UI on a network round-trip for a preference change is not worth it.
    unawaited(ref.read(authApiProvider).updateLanguage(language.tag));
  }
}

/// Convenience for widgets that need the raw Locale (MaterialApp, Directionality checks).
final localeValueProvider = Provider<Locale>((ref) => ref.watch(localeProvider).locale);
