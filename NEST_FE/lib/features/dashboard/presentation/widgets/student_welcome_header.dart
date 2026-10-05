import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:nest_fe/app/theme/app_tokens.dart';
import 'package:nest_fe/app/theme/app_typography.dart';
import 'package:nest_fe/core/auth/session_controller.dart';
import 'package:nest_fe/core/auth/membership_summary.dart';
import 'package:nest_fe/core/auth/user_profile.dart';
import 'package:nest_fe/core/design/pressable.dart';
import 'package:nest_fe/features/academy/presentation/academy_profile_shared.dart' show AcademyCover, academyProfileProvider;

/// The dashboard hero's background for every role: the active academy's cover photo, else the
/// preset style the Admin picked on the Academy Profile (teal by default, which is the hero's
/// original gradient). The app bar's white icons float over the top of it, so a photo gets a dark
/// scrim - a bright photo would otherwise swallow them. [fullScrim] also darkens the rest, for a
/// hero that carries white text of its own.
class DashboardCoverBackdrop extends StatelessWidget {
  const DashboardCoverBackdrop({super.key, required this.imageUrl, required this.styleKey, required this.height, this.fullScrim = false});

  final String? imageUrl;
  final String? styleKey;
  final double height;
  final bool fullScrim;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: height,
      width: double.infinity,
      child: Stack(
        fit: StackFit.expand,
        children: [
          AcademyCover(imageUrl: imageUrl, styleKey: styleKey, height: height),
          if (imageUrl != null)
            DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    Colors.black.withValues(alpha: 0.5),
                    Colors.black.withValues(alpha: fullScrim ? 0.45 : 0),
                  ],
                  stops: const [0, 0.6],
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// The student dashboard's hero: "Welcome back / {name} / academy chip" over the academy's cover,
/// full-bleed so it reads as a continuation of [AppShell]'s transparent app bar. This widget
/// carries no bell, avatar or theme toggle of its own: those already live in the app bar, and
/// duplicating them here would be a second, inconsistent copy of the same control. The academy
/// chip reuses [AppShell]'s own `switchActiveMembership` call rather than inventing a second
/// switching path.
class StudentWelcomeHeader extends ConsumerWidget {
  const StudentWelcomeHeader({super.key, required this.user, required this.membership});

  final UserProfile user;
  final MembershipSummary? membership;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final firstName = user.fullName.trim().split(RegExp(r'\s+')).firstOrNull ?? user.fullName;
    final academyName = membership?.academyName;
    final profile = ref.watch(academyProfileProvider).valueOrNull;

    return Stack(
      children: [
        Positioned.fill(
          child: DashboardCoverBackdrop(
            imageUrl: profile?.coverImageUrl,
            styleKey: profile?.coverStyle,
            height: double.infinity,
            fullScrim: true,
          ),
        ),
        _content(firstName, academyName),
      ],
    );
  }

  Widget _content(String firstName, String? academyName) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(20, 4, 20, AppSpacing.xxl),
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
