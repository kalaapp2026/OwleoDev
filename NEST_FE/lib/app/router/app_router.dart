import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:nest_fe/core/auth/session_controller.dart';
import 'package:nest_fe/core/auth/session_state.dart';
import 'package:nest_fe/core/widgets/owleo_wordmark.dart';
import 'package:nest_fe/features/academy/presentation/academy_info_screen.dart';
import 'package:nest_fe/features/academy/presentation/academy_onboarding_screen.dart';
import 'package:nest_fe/features/attendance/presentation/attendance_screen.dart';
import 'package:nest_fe/features/auth/presentation/login_screen.dart';
import 'package:nest_fe/features/curriculum/presentation/course_management_screen.dart';
import 'package:nest_fe/features/curriculum/presentation/syllabus_screen.dart';
import 'package:nest_fe/features/enrolment/presentation/user_creation_screen.dart';
import 'package:nest_fe/features/events/presentation/event_create_screen.dart';
import 'package:nest_fe/features/profile/presentation/profile_screen.dart';
import 'package:nest_fe/features/scheduling/presentation/calendar_screen.dart';
import 'package:nest_fe/features/scheduling/presentation/reschedule_screen.dart';
import 'package:nest_fe/features/scheduling/presentation/scheduling_screen.dart';
import 'package:nest_fe/features/shell/presentation/app_shell.dart';

final routerProvider = Provider<GoRouter>((ref) {
  return GoRouter(
    initialLocation: '/home',
    refreshListenable: _SessionRefreshListenable(ref),
    redirect: (context, state) {
      final session = ref.read(sessionControllerProvider);
      final goingToLogin = state.matchedLocation == '/login';

      if (session.isBootstrapping) return null; // splash handles this path
      if (!session.isAuthenticated && !goingToLogin) return '/login';
      if (session.isAuthenticated && goingToLogin) return '/home';
      return null;
    },
    routes: [
      GoRoute(path: '/login', builder: (context, state) => const LoginScreen()),
      GoRoute(path: '/home', builder: (context, state) => const _RootGate()),
      GoRoute(path: '/profile', builder: (context, state) => const Scaffold(body: ProfileScreen())),
      GoRoute(path: '/erp/students/new', builder: (context, state) => const UserCreationScreen()),
      GoRoute(path: '/erp/courses', builder: (context, state) => const CourseManagementScreen()),
      GoRoute(path: '/erp/events/new', builder: (context, state) => const EventCreateScreen()),
      GoRoute(path: '/erp/syllabus', builder: (context, state) => const SyllabusScreen()),
      GoRoute(path: '/erp/academy', builder: (context, state) => const AcademyInfoScreen()),
      GoRoute(path: '/erp/academies/new', builder: (context, state) => const AcademyOnboardingScreen()),
      GoRoute(path: '/erp/scheduling', builder: (context, state) => const SchedulingScreen()),
      GoRoute(path: '/erp/scheduling/reschedule', builder: (context, state) => const RescheduleScreen()),
      GoRoute(path: '/erp/attendance', builder: (context, state) => const AttendanceScreen()),
      GoRoute(path: '/erp/calendar', builder: (context, state) => const CalendarScreen()),
    ],
  );
});

/// go_router only re-evaluates `redirect` when this notifies - bridges Riverpod's SessionState
/// changes into the ChangeNotifier go_router expects.
class _SessionRefreshListenable extends ChangeNotifier {
  _SessionRefreshListenable(Ref ref) {
    ref.listen(sessionControllerProvider, (previous, next) {
      if (previous?.status != next.status) notifyListeners();
    });
  }
}

/// Splash while the session bootstraps (checking for a stored token), then either the shell or
/// login - never a blank frame or a flash of the wrong screen.
class _RootGate extends ConsumerWidget {
  const _RootGate();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final session = ref.watch(sessionControllerProvider);

    if (session.status == SessionStatus.bootstrapping) {
      return const Scaffold(body: Center(child: OwleoWordmark(size: OwleoWordmarkSize.large)));
    }
    if (!session.isAuthenticated) {
      return const LoginScreen();
    }
    return const AppShell();
  }
}
