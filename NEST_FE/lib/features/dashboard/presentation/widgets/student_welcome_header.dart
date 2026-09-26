import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:nest_fe/app/theme/app_tokens.dart';
import 'package:nest_fe/app/theme/app_typography.dart';
import 'package:nest_fe/core/auth/session_controller.dart';
import 'package:nest_fe/core/auth/membership_summary.dart';
import 'package:nest_fe/core/auth/user_profile.dart';
import 'package:nest_fe/core/design/pressable.dart';

/// The reference's own hero gradient (`linear-gradient(135deg, #0F3D37 0%, #14544A 45%,
/// #1B8F7C 100%)`) - deliberately hardcoded rather than built from palette tokens, because it
/// ends at `palette.primaryDim` rather than starting there. Reusing tokens for a 2-stop gradient
/// landed one shade too bright/cyan across the whole hero.
const kDashboardHeroGradient = LinearGradient(
  begin: Alignment.topLeft,
  end: Alignment.bottomRight,
  colors: [Color(0xFF0F3D37), Color(0xFF14544A), Color(0xFF1B8F7C)],
  stops: [0.0, 0.45, 1.0],
);

/// The student dashboard's gradient hero: "Welcome back / {name} / academy chip", full-bleed
/// (edge to edge, no side margin) so it reads as a continuation of [AppShell]'s app bar, which is
/// tinted to this same gradient's start color for that screen - see its `isStudentDashboard`
/// check. This widget carries no bell, avatar or theme toggle of its own: those already live in
/// the app bar, and duplicating them here would be a second, inconsistent copy of the same
/// control. The academy chip reuses [AppShell]'s own `switchActiveMembership` call rather than
/// inventing a second switching path.
class StudentWelcomeHeader extends StatelessWidget {
  const StudentWelcomeHeader({super.key, required this.user, required this.membership});

  final UserProfile user;
  final MembershipSummary? membership;

  @override
  Widget build(BuildContext context) {
    final firstName = user.fullName.trim().split(RegExp(r'\s+')).firstOrNull ?? user.fullName;
    final academyName = membership?.academyName;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(20, 4, 20, AppSpacing.xxl),
      decoration: const BoxDecoration(gradient: kDashboardHeroGradient),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Welcome back',
            style: TextStyle(
              fontSize: AppType.sm,
              fontWeight: AppType.semi,
              color: Colors.white.withValues(alpha: 0.82),
            ),
          ),
          const SizedBox(height: 2),
          Text(
            '$firstName \u{1F44B}',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: AppType.x3l,
              fontWeight: AppType.heavy,
              letterSpacing: AppType.titleTracking,
              color: Colors.white,
            ),
          ),
          if (academyName != null) ...[
            const SizedBox(height: AppSpacing.md),
            _AcademyChip(user: user, membership: membership!, academyName: academyName),
          ],
        ],
      ),
    );
  }
}

class _AcademyChip extends ConsumerWidget {
  const _AcademyChip({required this.user, required this.membership, required this.academyName});

  final UserProfile user;
  final MembershipSummary membership;
  final String academyName;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final palette = context.palette;
    final chip = Container(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md, vertical: AppSpacing.xs),
      decoration: BoxDecoration(
        color: palette.goldSoft,
        borderRadius: AppRadii.all(AppRadii.pill),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.school_outlined, size: 14, color: palette.goldDim),
          const SizedBox(width: AppSpacing.xs),
          Flexible(
            child: Text(
              academyName,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: AppType.sm, fontWeight: AppType.bold, color: palette.goldDim),
            ),
          ),
          if (user.hasMultipleAcademies) ...[
            const SizedBox(width: AppSpacing.xxs),
            Icon(Icons.expand_more, size: 16, color: palette.goldDim),
          ],
        ],
      ),
    );

    if (!user.hasMultipleAcademies) return chip;

    return PopupMenuButton<String>(
      tooltip: 'Switch academy',
      padding: EdgeInsets.zero,
      onSelected: (membershipId) =>
          ref.read(sessionControllerProvider.notifier).switchActiveMembership(membershipId),
      itemBuilder: (context) => user.activeMemberships
          .map(
            (m) => PopupMenuItem<String>(
              value: m.membershipId,
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(m.academyName ?? m.academyId),
                        Text(m.roleType.replaceAll('_', ' '), style: Theme.of(context).textTheme.bodySmall),
                      ],
                    ),
                  ),
                  if (m.membershipId == user.activeMembershipId)
                    Icon(Icons.check_circle, color: Theme.of(context).colorScheme.primary, size: 18),
                ],
              ),
            ),
          )
          .toList(),
      child: Pressable(borderRadius: AppRadii.all(AppRadii.pill), child: chip),
    );
  }
}
