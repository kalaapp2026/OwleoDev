import 'package:flutter/widgets.dart';

import '../../core/ui/primitives.dart';
import '../academies/academies_screen.dart';
import '../alerts/alerts_screen.dart';
import '../approvals/approvals_screen.dart';
import '../finance/finance_screen.dart';
import '../growth/growth_screen.dart';
import '../collections/collections_screen.dart';
import '../dashboard/dashboard_screen.dart';
import '../onboarding/onboarding_screen.dart';
import '../plans/plans_screen.dart';
import '../artists/artists_screen.dart';
import '../events/events_screen.dart';
import '../marketing/marketing_screen.dart';
import '../invoicing/invoicing_screen.dart';
import '../payments/payments_screen.dart';
import '../notifications/notifications_screen.dart';
import '../providers/providers_screen.dart';
import '../settings/settings_screen.dart';
import '../social/social_screens.dart';
import '../transfers/transfers_screen.dart';
import '../courses/courses_screen.dart';
import '../exits/exits_screen.dart';
import '../master/master_screen.dart';
import '../reports/reports_screen.dart';
import '../support/support_screen.dart';
import '../users/users_screen.dart';
import 'modules.dart';

/// Maps a module id to its screen. Modules are added here as they are built; anything not yet
/// built shows a "being built" card so the whole console is navigable from day one.
Widget screenFor(String id) {
  switch (id) {
    case 'overview':
      return const DashboardScreen();
    case 'academies':
      return const AcademiesScreen();
    case 'onboarding':
      return const OnboardingScreen();
    case 'approvals':
      return const ApprovalsScreen();
    case 'collections':
      return const CollectionsScreen();
    case 'alerts':
      return const AlertsScreen();
    case 'growth':
      return const GrowthScreen();
    case 'finance':
      return const FinanceScreen();
    case 'plans':
      return const PlansScreen();
    case 'users':
      return const UsersScreen();
    case 'master':
      return const MasterScreen();
    case 'courses':
      return const CoursesScreen();
    case 'exits':
      return const ExitsScreen();
    case 'reports':
      return const ReportsScreen();
    case 'support':
      return const SupportScreen();
    case 'artists':
      return const ArtistsScreen();
    case 'events':
      return const EventsScreen();
    case 'transfers':
      return const TransfersScreen();
    case 'providers':
      return const ProvidersScreen();
    case 'marketing':
      return const MarketingScreen();
    case 'payments':
      return const PaymentsScreen();
    case 'notifs':
      return const NotificationsScreen();
    case 'invoicing':
      return const InvoicingScreen();
    case 'settings':
      return const SettingsScreen();
    case 'students':
      return const UsersScreen();
    default:
      return ComingSoon(hqModules[id]?.title ?? id);
  }
}

Widget socialScreenFor(String tab) {
  return switch (tab) {
    'event' => const SocialEventScreen(),
    'search' => const SocialSearchScreen(),
    'profile' => const SocialProfileScreen(),
    _ => const SocialPostScreen(),
  };
}
