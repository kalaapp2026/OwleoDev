import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:nest_fe/app/theme/app_tokens.dart';
import 'package:nest_fe/app/theme/app_typography.dart';
import 'package:nest_fe/core/design/pressable.dart';
import 'package:nest_fe/core/auth/feature_keys.dart';
import 'package:nest_fe/core/auth/session_controller.dart';
import 'package:nest_fe/features/dashboard/data/dashboard_api.dart';
import 'package:nest_fe/features/dashboard/data/dashboard_stats.dart';

/// Students / Trainers / Courses / Batches.
///
/// Every figure comes from [myDashboardStatsProvider], which the server narrows to the courses the
/// caller holds a feature on - a trainer granted Attendance on Guitar sees Guitar's headcount, not
/// the academy's. Which tiles appear is narrowed the same way: a count of people or batches the
/// caller's features never touch is noise. Courses only navigates for an Academy Admin, since
/// Course Creation itself is admin-only.
class DashboardStatsRow extends ConsumerWidget {
  const DashboardStatsRow({super.key, required this.isAdmin});

  final bool isAdmin;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user = ref.watch(sessionControllerProvider).user;
    final statsAsync = ref.watch(myDashboardStatsProvider);
    bool holdsAny(List<String> keys) => isAdmin || (user != null && keys.any(user.hasFeature));
    String stat(int Function(DashboardStats) pick) =>
        statsAsync.maybeWhen(data: (s) => '${pick(s)}', orElse: () => '—');

    final palette = context.palette;
    final tiles = <Widget>[
      if (holdsAny([
        FeatureKeys.attendance,
        FeatureKeys.feesEntry,
        FeatureKeys.feesDashboard,
        FeatureKeys.studentRegistration,
        FeatureKeys.batchCreation,
      ]))
        _StatTile(
          icon: Icons.people_alt_outlined,
          label: 'Students',
          value: stat((s) => s.totalStudents),
          color: palette.primary,
          softColor: palette.primarySoft,
          // The people list for whoever may register students; the fees/attendance student search for
          // someone who only works with them.
          onTap: holdsAny([FeatureKeys.studentRegistration])
              ? () => context.push('/erp/students/new')
              : () => context.push('/erp/students'),
        ),
      if (holdsAny([
        FeatureKeys.trainerRegistration,
        FeatureKeys.batchCreation,
        FeatureKeys.batchScheduling,
        FeatureKeys.reschedule,
      ]))
        _StatTile(
          icon: Icons.school_outlined,
          label: 'Trainers',
          value: stat((s) => s.totalTrainers),
          color: palette.gold,
          softColor: palette.goldSoft,
          onTap: holdsAny([FeatureKeys.trainerRegistration]) ? () => context.push('/erp/students/new?tab=trainer') : null,
        ),
      _StatTile(
        icon: Icons.auto_stories_outlined,
        label: 'Courses',
        value: stat((s) => s.activeCourses),
        color: palette.violet,
        softColor: palette.violetSoft,
        onTap: isAdmin ? () => context.push('/erp/courses') : null,
      ),
      if (holdsAny([
        FeatureKeys.batchCreation,
        FeatureKeys.batchScheduling,
        FeatureKeys.reschedule,
        FeatureKeys.attendance,
      ]))
        _StatTile(
          icon: Icons.groups_2_outlined,
          label: 'Batches',
          value: stat((s) => s.activeBatches),
          color: palette.gateway,
          softColor: palette.gatewaySoft,
          onTap: holdsAny([FeatureKeys.batchCreation]) ? () => context.push('/erp/batches') : null,
        ),
    ];

    return Row(
      children: [
        for (var i = 0; i < tiles.length; i++) ...[
          if (i > 0) const SizedBox(width: AppSpacing.sm),
          Expanded(child: tiles[i]),
        ],
      ],
    );
  }
}

class _StatTile extends StatelessWidget {
  const _StatTile({
    required this.icon,
    required this.label,
    required this.value,
    required this.color,
    required this.softColor,
    this.onTap,
  });

  final IconData icon;
  final String label;
  final String value;
  final Color color;
  final Color softColor;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return Pressable(
      onTap: onTap,
      borderRadius: AppRadii.all(AppRadii.xl),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md, vertical: AppSpacing.lg),
        decoration: BoxDecoration(
          color: palette.surfaceRaised,
          borderRadius: AppRadii.all(AppRadii.xl),
          border: Border.all(color: palette.border),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 24,
              height: 24,
              alignment: Alignment.center,
              decoration: BoxDecoration(color: softColor, borderRadius: AppRadii.all(AppRadii.sm)),
              child: Icon(icon, size: 13, color: color),
            ),
            const SizedBox(height: AppSpacing.xs),
            Text(
              value,
              style: TextStyle(fontSize: AppType.x4l, fontWeight: AppType.heavy, color: palette.text),
            ),
            const SizedBox(height: 2),
            Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: AppType.tiny, fontWeight: AppType.semi, color: palette.textMuted),
            ),
          ],
        ),
      ),
    );
  }
}
