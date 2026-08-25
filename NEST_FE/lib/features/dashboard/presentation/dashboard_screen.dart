import 'package:nest_fe/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:nest_fe/core/auth/session_controller.dart';
import 'package:nest_fe/features/curriculum/data/curriculum_api.dart';
import 'package:nest_fe/features/shell/domain/erp_action.dart';
import 'package:nest_fe/features/shell/presentation/app_shell.dart';

/// PRD 3.1: the ERP home screen is a grid of tiles scoped to the caller's role+feature grants -
/// same source list as the More sheet (features/shell/domain/erp_action.dart), just rendered
/// full-page instead of as an overlay.
class DashboardScreen extends ConsumerWidget {
  const DashboardScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user = ref.watch(sessionControllerProvider).user;
    final colorScheme = Theme.of(context).colorScheme;

    if (user == null) return const SizedBox.shrink();

    final membership = user.activeMembership;
    final visibleActions =
        kErpActions.where((a) => a.visibleFor(user) && (a.route != null || a.erpTabIndex != null)).toList();

    // A Student's "courses" means the ones THEY are enrolled in (membership.courseIds, already
    // scoped server-side to this one membership) - never the academy's whole catalog. Admin/
    // Trainer aren't personally "enrolled" in anything, so for them this still means "how many
    // courses does this academy offer" (activeCoursesProvider).
    final isStudent = membership?.roleType == 'STUDENT';
    final coursesAsync = ref.watch(activeCoursesProvider);
    final courseCountLabel = isStudent ? 'My courses' : 'Active courses';
    final courseCountValue =
        isStudent ? '${membership?.courseIds.length ?? 0}' : coursesAsync.maybeWhen(data: (c) => '${c.length}', orElse: () => '—');

    return RefreshIndicator(
      onRefresh: () => ref.refresh(activeCoursesProvider.future),
      child: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          Text(AppLocalizations.of(context).dashWelcomeBack, style: Theme.of(context).textTheme.bodyMedium),
          Text(user.fullName, style: Theme.of(context).textTheme.headlineSmall),
          if (membership?.academyName != null) ...[
            const SizedBox(height: 4),
            Text(membership!.academyName!, style: TextStyle(color: colorScheme.primary, fontWeight: FontWeight.w600)),
          ],
          const SizedBox(height: 20),
          Row(
            children: [
              Expanded(
                child: _StatCard(
                  icon: Icons.auto_stories_outlined,
                  label: courseCountLabel,
                  value: courseCountValue,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _StatCard(
                  icon: Icons.badge_outlined,
                  label: 'Your role',
                  value: (membership?.roleType ?? user.role).replaceAll('_', ' '),
                ),
              ),
            ],
          ),
          const SizedBox(height: 28),
          Text(AppLocalizations.of(context).dashQuickActions, style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 14),
          GridView.count(
            crossAxisCount: 4,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            mainAxisSpacing: 18,
            crossAxisSpacing: 8,
            childAspectRatio: 0.85,
            children: visibleActions.map((action) => _ActionTile(action: action)).toList(),
          ),
        ],
      ),
    );
  }
}

class _StatCard extends StatelessWidget {
  const _StatCard({required this.icon, required this.label, required this.value});

  final IconData icon;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, color: colorScheme.primary, size: 22),
            const SizedBox(height: 10),
            Text(value, style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 2),
            Text(label, style: Theme.of(context).textTheme.bodySmall),
          ],
        ),
      ),
    );
  }
}

class _ActionTile extends StatelessWidget {
  const _ActionTile({required this.action});
  final ErpAction action;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return InkWell(
      borderRadius: BorderRadius.circular(16),
      onTap: () {
        if (action.erpTabIndex != null) {
          context.findAncestorStateOfType<AppShellState>()?.goToErpTab(action.erpTabIndex!);
        } else if (action.route != null) {
          context.push(action.route!);
        }
      },
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 52,
            height: 52,
            decoration: BoxDecoration(
              color: colorScheme.primary.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(16),
            ),
            child: Icon(action.icon, color: colorScheme.primary, size: 22),
          ),
          const SizedBox(height: 8),
          Text(
            action.label,
            textAlign: TextAlign.center,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ],
      ),
    );
  }
}
