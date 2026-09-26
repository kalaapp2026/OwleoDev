import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:nest_fe/core/auth/session_controller.dart';
import 'package:nest_fe/core/auth/session_state.dart';
import 'package:nest_fe/core/widgets/owleo_wordmark.dart';
import 'package:nest_fe/features/academy/presentation/academy_info_screen.dart';
import 'package:nest_fe/features/academy/presentation/academy_onboarding_screen.dart';
import 'package:nest_fe/features/academy/presentation/academy_settings_screen.dart';
import 'package:nest_fe/features/attendance/presentation/attendance_home_screen.dart';
import 'package:nest_fe/features/auth/presentation/become_artist_screen.dart';
import 'package:nest_fe/features/auth/presentation/login_screen.dart';
import 'package:nest_fe/features/curriculum/presentation/course_list_screen.dart';
import 'package:nest_fe/features/curriculum/presentation/study_material_home_screen.dart';
import 'package:nest_fe/features/enrolment/presentation/batch_list_screen.dart';
import 'package:nest_fe/features/enrolment/presentation/student_search_screen.dart';
import 'package:nest_fe/features/enrolment/presentation/user_list_screen.dart';
import 'package:nest_fe/features/messages/presentation/messages_home_screen.dart';
import 'package:nest_fe/features/events/presentation/event_form_screen.dart';
import 'package:nest_fe/features/events/presentation/event_list_screen.dart';
import 'package:nest_fe/features/profile/presentation/profile_screen.dart';
import 'package:nest_fe/features/scheduling/presentation/calendar_screen.dart';
import 'package:nest_fe/features/scheduling/presentation/schedule_screen.dart';
import 'package:nest_fe/features/shell/presentation/app_shell.dart';
import 'package:nest_fe/features/shell/presentation/more_menu_sheet.dart';

/// AppShell isn't torn down when one of these routes is pushed on top of it - go_router's `.push`
/// keeps the previous page in the Navigator stack, just visually covered - but the pushed page is
/// a Navigator SIBLING of AppShell, not a descendant, so `findAncestorStateOfType` can't reach it
/// from there (that's the same trap More sheet hit, see its own comment). A GlobalKey reaches the
/// still-live AppShellState directly instead.
final appShellKey = GlobalKey<AppShellState>();

/// Wraps a pushed "More"-destination screen with its own copy of the real bottom nav bar, in a
/// genuine `bottomNavigationBar` slot rather than an overlay - the outer Scaffold's own layout
/// then gives the inner screen's body correctly-reduced height, so a screen's own bottom-anchored
/// content (an "Add trainer" button, say) naturally lands above the bar instead of under it. These
/// routes are full-screen go_router pages with no AppShell of their own, which is why the nav bar
/// disappears on them without this - see CLAUDE.md's "Navigation bar" note on this being deferred
/// architecture work; this is the bounded fix rather than a full ShellRoute rewrite.
class _WithNavBar extends StatelessWidget {
  const _WithNavBar({required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final shellState = appShellKey.currentState;
    // Not expected once logged in (AppShell mounts for the session's whole lifetime), but a
    // pushed screen still works standalone rather than crashing if it's ever somehow null.
    if (shellState == null) return child;
    return Scaffold(
      body: child,
      bottomNavigationBar: shellState.buildOverlayBottomNav(
        onNavigate: () => Navigator.of(context).pop(),
        // Reusing onNavigate (pop) here would just close this screen and reveal whatever tab
        // AppShell was last on - not open the menu, which is what tapping More actually means.
        // Opening it directly on this screen's own Navigator (the same single Navigator AppShell
        // uses) needs no pop first.
        onMoreTap: () => showMoreMenu(context, shellState.ref, shellState),
      ),
    );
  }
}

final routerProvider = Provider<GoRouter>((ref) {
  return GoRouter(
    initialLocation: '/home',
    refreshListenable: _SessionRefreshListenable(ref),
    redirect: (context, state) {
      final session = ref.read(sessionControllerProvider);
      final loc = state.matchedLocation;
      final goingToLogin = loc == '/login';
      // /signup is public like /login, but - unlike /login - a freshly-authenticated user must be
      // allowed to stay on it (or move on to /become-artist) instead of being bounced to /home,
      // since signup flips the session to authenticated mid-flow, before the artist prompt runs.
      final isPublicAuthRoute = goingToLogin || loc == '/signup';

      if (session.isBootstrapping) return null; // splash handles this path
      if (!session.isAuthenticated && !isPublicAuthRoute) return '/login';
      if (session.isAuthenticated && goingToLogin) return '/home';
      return null;
    },
    routes: [
      GoRoute(path: '/login', builder: (context, state) => const LoginScreen()),
      GoRoute(path: '/signup', builder: (context, state) => const SignupScreen()),
      GoRoute(path: '/become-artist', builder: (context, state) => const BecomeArtistScreen()),
      GoRoute(path: '/home', builder: (context, state) => const _RootGate()),
      GoRoute(
        path: '/profile',
        builder: (context, state) => Scaffold(appBar: AppBar(title: const Text('Profile')), body: const ProfileScreen()),
      ),
      GoRoute(path: '/erp/students/new', builder: (context, state) => const _WithNavBar(child: UserListScreen())),
      GoRoute(path: '/erp/students', builder: (context, state) => const _WithNavBar(child: StudentSearchScreen())),
      GoRoute(path: '/erp/messages', builder: (context, state) => const _WithNavBar(child: MessagesHomeScreen())),
      GoRoute(path: '/erp/courses', builder: (context, state) => const _WithNavBar(child: CourseListScreen())),
      GoRoute(path: '/erp/events', builder: (context, state) => const _WithNavBar(child: EventListScreen())),
      GoRoute(path: '/erp/events/new', builder: (context, state) => const EventFormScreen()),
      // Study Material is separate from Syllabus: one is a file drop for a batch, the other is
      // the course's curriculum structure.
      GoRoute(path: '/erp/study-materials', builder: (context, state) => const _WithNavBar(child: StudyMaterialHomeScreen())),
      GoRoute(path: '/erp/academy', builder: (context, state) => const _WithNavBar(child: AcademyInfoScreen())),
      GoRoute(path: '/erp/academy-settings', builder: (context, state) => const _WithNavBar(child: AcademySettingsScreen())),
      GoRoute(path: '/erp/academies/new', builder: (context, state) => const AcademyOnboardingScreen()),
      // Reschedule is no longer its own route - it is a sheet on the schedule feed, reached from
      // the class it applies to rather than from a screen that then asks which class you meant.
      GoRoute(path: '/erp/scheduling', builder: (context, state) => const _WithNavBar(child: ScheduleScreen())),
      GoRoute(path: '/erp/attendance', builder: (context, state) => const _WithNavBar(child: AttendanceHomeScreen())),
      GoRoute(path: '/erp/calendar', builder: (context, state) => const CalendarScreen()),
      // Batches moved off the bottom tab bar (that slot is now Attendance, matching the
      // reference nav bar) - reachable from the More grid and the Dashboard's own Batches stat.
      GoRoute(path: '/erp/batches', builder: (context, state) => const _WithNavBar(child: BatchListScreen())),
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
    return AppShell(key: appShellKey);
  }
}
