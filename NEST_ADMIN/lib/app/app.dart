import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/ui/controls.dart';
import 'router.dart';
import 'theme.dart';

class HqApp extends ConsumerWidget {
  const HqApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return MaterialApp.router(
      title: 'Owleo HQ',
      debugShowCheckedModeBanner: false,
      theme: hqTheme(),
      darkTheme: hqTheme(),
      themeMode: ThemeMode.dark,
      scrollBehavior: const HqScrollBehavior(),
      routerConfig: ref.watch(routerProvider),
    );
  }
}
