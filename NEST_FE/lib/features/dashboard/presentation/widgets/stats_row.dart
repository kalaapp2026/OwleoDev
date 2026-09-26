import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:nest_fe/app/theme/app_tokens.dart';
import 'package:nest_fe/app/theme/app_typography.dart';
import 'package:nest_fe/core/design/pressable.dart';
import 'package:nest_fe/features/curriculum/data/curriculum_api.dart';
import 'package:nest_fe/features/dashboard/data/dashboard_api.dart';

/// Courses / Batches / Students / Trainers, in that order to match the reference layout.
///
/// Courses reads from [activeCoursesProvider] - the count the rest of the app already shows -
/// rather than the new stats endpoint's own course count, so the two numbers can never disagree
/// on screen. Students/Trainers have no roster screen to drill into yet, so those two tiles are
/// informational only; Courses only navigates for an Academy Admin, since Course Creation itself
/// is admin-only.
class DashboardStatsRow extends ConsumerWidget {
  const DashboardStatsRow({super.key, required this.isAdmin});

  final bool isAdmin;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final coursesAsync = ref.watch(activeCoursesProvider);
    final statsAsync = ref.watch(dashboardStatsProvider);

    final courseCount = coursesAsync.maybeWhen(data: (c) => '${c.length}', orElse: () => '—');
    final batchCount = statsAsync.maybeWhen(data: (s) => '${s.activeBatches}', orElse: () => '—');
    final studentCount = statsAsync.maybeWhen(data: (s) => '${s.totalStudents}', orElse: () => '—');
    final trainerCount = statsAsync.maybeWhen(data: (s) => '${s.totalTrainers}', orElse: () => '—');

    final palette = context.palette;
    return Row(
      children: [
        Expanded(
          child: _StatTile(
            icon: Icons.people_alt_outlined,
            label: 'Students',
            value: studentCount,
            color: palette.primary,
            softColor: palette.primarySoft,
          ),
        ),
        const SizedBox(width: AppSpacing.sm),
        Expanded(
          child: _StatTile(
            icon: Icons.school_outlined,
            label: 'Trainers',
            value: trainerCount,
            color: palette.gold,
            softColor: palette.goldSoft,
          ),
        ),
        const SizedBox(width: AppSpacing.sm),
        Expanded(
          child: _StatTile(
            icon: Icons.auto_stories_outlined,
            label: 'Courses',
            value: courseCount,
            color: palette.violet,
            softColor: palette.violetSoft,
            onTap: isAdmin ? () => context.push('/erp/courses') : null,
          ),
        ),
        const SizedBox(width: AppSpacing.sm),
        Expanded(
          child: _StatTile(
            icon: Icons.groups_2_outlined,
            label: 'Batches',
            value: batchCount,
            color: palette.gateway,
            softColor: palette.gatewaySoft,
            onTap: () => context.push('/erp/batches'),
          ),
        ),
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
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm, vertical: AppSpacing.lg),
        decoration: BoxDecoration(
          color: palette.surfaceRaised,
          borderRadius: AppRadii.all(AppRadii.xl),
          border: Border.all(color: palette.border),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
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
