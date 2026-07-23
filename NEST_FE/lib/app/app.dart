import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:nest_fe/app/router/app_router.dart';
import 'package:nest_fe/app/theme/app_theme.dart';
import 'package:nest_fe/app/theme/theme_controller.dart';
import 'package:nest_fe/core/widgets/app_notice.dart';

class OwleoNestApp extends ConsumerWidget {
  const OwleoNestApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
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
