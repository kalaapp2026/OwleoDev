import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../core/auth/session.dart';
import '../features/auth/login_screen.dart';
import '../features/shell/hq_shell.dart';
import '../features/shell/module_gate.dart';
import '../features/shell/modules.dart';
import '../features/shell/screens.dart';

final routerProvider = Provider<GoRouter>((ref) {
  // go_router re-evaluates `redirect` whenever this changes: sign in, sign out, session restored.
  final refresh = ValueNotifier<int>(0);
  ref.listen(sessionProvider, (_, _) => refresh.value++);
  ref.onDispose(refresh.dispose);

  return GoRouter(
    initialLocation: '/overview',
    refreshListenable: refresh,
    redirect: (context, state) {
      final status = ref.read(sessionProvider).status;
      final path = state.uri.path;
      switch (status) {
        case SessionStatus.bootstrapping:
          return path == '/splash' ? null : '/splash';
        case SessionStatus.signedOut:
          return path == '/login' ? null : '/login';
        case SessionStatus.signedIn:
          if (path == '/login' || path == '/splash' || path == '/') return '/overview';
          return null;
      }
    },
    routes: [
      GoRoute(path: '/splash', builder: (_, _) => const SplashScreen()),
      GoRoute(path: '/login', builder: (_, _) => const LoginScreen()),
      ShellRoute(
        builder: (context, state, child) => HqShell(location: state.uri.toString(), child: child),
        routes: [
          for (final id in hqModules.keys)
            GoRoute(
              path: '/$id',
              pageBuilder: (context, state) => NoTransitionPage(key: ValueKey('hq-$id'), child: ModuleGate(id)),
            ),
          // The prototype also reaches Students through its own route; it is a tab of Users now.
          GoRoute(path: '/students', redirect: (_, _) => '/users?tab=students'),
          for (final t in socialTabs)
            GoRoute(
              path: t.path,
              pageBuilder: (context, state) => NoTransitionPage(key: ValueKey('soc-${t.id}'), child: socialScreenFor(t.id)),
            ),
        ],
      ),
    ],
  );
});
