import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:nest_fe/app/theme/app_tokens.dart';
import 'package:nest_fe/app/theme/app_typography.dart';
import 'package:nest_fe/core/auth/membership_summary.dart';
import 'package:nest_fe/core/auth/role_switch.dart';
import 'package:nest_fe/core/auth/session_controller.dart';
import 'package:nest_fe/core/design/segmented_control.dart';

/// "Switch role: Student | Trainer" - shown on the Profile tab only for someone who holds both roles
/// at the academy they are in (a student in one course, a trainer for another).
///
/// The same switch as the avatar menu in the top bar, via [switchToRole]; this is the version that
/// shows both options side by side.
class RoleSwitchCard extends ConsumerWidget {
  const RoleSwitchCard({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user = ref.watch(sessionControllerProvider).user;
    final active = user?.activeMembership;
    if (user == null || active == null) return const SizedBox.shrink();

    final roles = rolesAtActiveAcademy(user);
    if (roles.length < 2) return const SizedBox.shrink();

    final palette = context.palette;

    return Container(
      margin: const EdgeInsets.fromLTRB(AppSpacing.page, AppSpacing.md, AppSpacing.page, AppSpacing.md),
      padding: const EdgeInsets.all(AppSpacing.xl),
      decoration: BoxDecoration(
        color: palette.surfaceRaised,
        borderRadius: AppRadii.all(AppRadii.xxl),
        border: Border.all(color: palette.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.swap_horiz_rounded, size: 18, color: palette.textMuted),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: Text('Switch role',
                    style: TextStyle(
                        fontSize: AppType.lg, fontWeight: AppType.bold, color: palette.text)),
              ),
            ],
          ),
          const SizedBox(height: 2),
          Padding(
            padding: const EdgeInsets.only(left: 26),
            child: Text(
              'You are both at ${active.academyName ?? 'this academy'}. '
              'Pick which one you want to use right now.',
              style: TextStyle(fontSize: AppType.sm, color: palette.textMuted, height: 1.4),
            ),
          ),
          const SizedBox(height: AppSpacing.lg),
          AppSegmentedControl<MembershipSummary>(
            options: roles,
            labelOf: (m) => roleLabel(m.roleType),
            isSelected: (m) => m.membershipId == active.membershipId,
            // Trainer in the gold used everywhere for the staff side, student in the app's teal.
            activeColorOf: (context, m) => m.roleType == 'TRAINER' ? palette.gold : palette.primary,
            activeTextColorOf: (context, m) =>
                m.roleType == 'TRAINER' ? palette.onGold : palette.onPrimary,
            onTap: (m) => switchToRole(ref, context, m),
          ),
        ],
      ),
    );
  }
}
