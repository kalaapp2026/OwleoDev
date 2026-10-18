import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:nest_fe/core/auth/membership_summary.dart';
import 'package:nest_fe/core/auth/session_controller.dart';
import 'package:nest_fe/core/auth/user_profile.dart';
import 'package:nest_fe/core/design/toast.dart';

/// Bumped every time the person switches between their roles at one academy (student <-> trainer).
///
/// The app shell listens and returns to the Dashboard tab, so the switch reads as stepping into a
/// different role rather than the same screen quietly changing underneath. A signal like this
/// rather than a callback because the Profile tab that triggers it and the shell that reacts to it
/// import each other's files already - a direct reference would close that loop.
final roleSwitchTickProvider = StateProvider<int>((ref) => 0);

/// The roles this person holds at the academy they are currently in, student first. Only STUDENT and
/// TRAINER count: they are the two a person can hold side by side (an academy admin is not one of
/// them). Another academy's memberships are the academy switcher's job, not this.
List<MembershipSummary> rolesAtActiveAcademy(UserProfile user) {
  final active = user.activeMembership;
  if (active == null) return const [];
  final roles = user.activeMemberships
      .where((m) =>
          m.academyId == active.academyId && (m.roleType == 'STUDENT' || m.roleType == 'TRAINER'))
      .toList()
    ..sort((a, b) => (a.roleType == 'STUDENT' ? 0 : 1).compareTo(b.roleType == 'STUDENT' ? 0 : 1));
  return roles;
}

/// The other role this person can switch to right now, or null when they only hold one here.
MembershipSummary? otherRoleAtActiveAcademy(UserProfile user) {
  final active = user.activeMembership;
  final roles = rolesAtActiveAcademy(user);
  if (active == null || roles.length < 2) return null;
  for (final m in roles) {
    if (m.membershipId != active.membershipId) return m;
  }
  return null;
}

/// "Student" / "Trainer" - how a role is named wherever the person is told which one they are in.
String roleLabel(String roleType) => switch (roleType) {
      'TRAINER' => 'Trainer',
      'STUDENT' => 'Student',
      'ACADEMY_ADMIN' => 'Admin',
      _ => roleType.isEmpty
          ? ''
          : roleType[0] + roleType.substring(1).toLowerCase().replaceAll('_', ' '),
    };

/// Makes [target] the active membership and sends the app back to that role's Dashboard.
///
/// One function for every place that offers the switch (the avatar menu, the Profile card), so they
/// can't drift: the active membership decides the whole app - tabs, dashboard, More menu, the data
/// fetched, what the server allows - and this is the single step that changes it.
void switchToRole(WidgetRef ref, BuildContext context, MembershipSummary target) {
  final user = ref.read(sessionControllerProvider).user;
  if (user == null || user.activeMembershipId == target.membershipId) return;
  ref.read(sessionControllerProvider.notifier).switchActiveMembership(target.membershipId);
  ref.read(roleSwitchTickProvider.notifier).state++;
  showAppToast(context, 'Now using NEST as a ${roleLabel(target.roleType).toLowerCase()}.');
}
