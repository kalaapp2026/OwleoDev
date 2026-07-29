import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:nest_fe/app/router/app_router.dart';
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

    return MaterialApp.router(
      title: 'Owleo Nest',
      debugShowCheckedModeBanner: false,
      scaffoldMessengerKey: AppNotice.messengerKey,
      theme: AppTheme.light,
      darkTheme: AppTheme.dark,
      themeMode: themeMode,
      routerConfig: router,
    );
  }
}
