import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:nest_fe/app/i18n/app_languages.dart';
import 'package:nest_fe/app/i18n/locale_controller.dart';
import 'package:nest_fe/app/router/app_router.dart';
import 'package:nest_fe/l10n/app_localizations.dart';
import 'package:nest_fe/app/theme/app_theme.dart';
import 'package:nest_fe/app/theme/theme_controller.dart';
import 'package:nest_fe/core/providers/core_providers.dart';
import 'package:nest_fe/core/widgets/app_notice.dart';
import 'package:nest_fe/features/platform/data/device_install_service.dart';
import 'package:nest_fe/features/platform/data/platform_api.dart';

class OwleoNestApp extends ConsumerStatefulWidget {
  const OwleoNestApp({super.key});

  @override
  ConsumerState<OwleoNestApp> createState() => _OwleoNestAppState();
}

class _OwleoNestAppState extends ConsumerState<OwleoNestApp> {
  @override
  void initState() {
    super.initState();
    // Fire-and-forget install count for the Super Admin console. Deliberately not awaited and
    // never surfaced - analytics must not delay first paint or interrupt anyone if it fails.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      DeviceInstallService(PlatformApi(ref.read(dioClientProvider))).reportLaunch();
    });
  }

  @override
  Widget build(BuildContext context) {
    final router = ref.watch(routerProvider);
    final themeMode = ref.watch(themeModeProvider);
    final language = ref.watch(localeProvider);

    return MaterialApp.router(
      title: 'Owleo Nest',
      debugShowCheckedModeBanner: false,
      scaffoldMessengerKey: AppNotice.messengerKey,
      theme: AppTheme.light,
      darkTheme: AppTheme.dark,
      themeMode: themeMode,

      // Explicit locale rather than following the device: the language is a per-account
      // preference that has to survive moving between a phone and a shared desktop.
      locale: language.locale,
      supportedLocales: AppLanguage.supportedLocales,
      localizationsDelegates: const [
        AppLocalizations.delegate,
        // Translate Flutter's own widgets too - date pickers, "Cancel" in system dialogs, the
        // text-selection menu. Without these, half a screen would be translated and half not.
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      // Arabic flips the whole layout to RTL from here automatically - Flutter derives text
      // direction from the locale, so nothing downstream needs to special-case it.
      routerConfig: router,
    );
  }
}
