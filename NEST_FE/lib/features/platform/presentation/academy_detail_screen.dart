import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:nest_fe/core/error/api_exception.dart';
import 'package:nest_fe/core/widgets/app_notice.dart';
import 'package:nest_fe/core/widgets/async_value_view.dart';
import 'package:nest_fe/features/academy/presentation/academy_onboarding_screen.dart';
import 'package:nest_fe/features/platform/data/platform_api.dart';
import 'package:nest_fe/features/platform/presentation/academy_stats_screen.dart';
import 'package:nest_fe/features/platform/presentation/console_layout.dart';
import 'package:nest_fe/features/platform/presentation/super_admin_dashboard_screen.dart';

final academyDetailProvider = FutureProvider.autoDispose
    .family<AcademySummary, String>((ref, id) => ref.watch(platformApiProvider).academy(id));

/// One tenant in full. Read-only for operational data by design: the console can see everything
/// about an academy, but its students, fees and attendance are the academy's own business records
/// and stay theirs to edit. The only writes offered here are lifecycle ones (suspend/reactivate),
/// which are the platform operator's legitimate call.
class AcademyDetailScreen extends ConsumerWidget {
  const AcademyDetailScreen({super.key, required this.academyId, this.initial});

  final String academyId;

  /// Row already loaded by the table - lets the page paint instantly instead of flashing a
  /// spinner for data the caller is holding, while the fresh copy loads behind it.
  final AcademySummary? initial;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(academyDetailProvider(academyId));
    final academy = async.valueOrNull ?? initial;

    return Scaffold(
      appBar: AppBar(
        title: Text(academy?.name ?? 'Academy'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: 'Refresh',
            onPressed: () => ref.invalidate(academyDetailProvider(academyId)),
          ),
        ],
      ),
      body: academy == null
          ? AsyncValueView<AcademySummary>(
              value: async,
              onRetry: () => ref.invalidate(academyDetailProvider(academyId)),
              data: (context, data) => _Body(academy: data),
            )
          : _Body(academy: academy),
    );
  }
}

class _Body extends ConsumerWidget {
  const _Body({required this.academy});

  final AcademySummary academy;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colorScheme = Theme.of(context).colorScheme;
    return ConsolePage(
      maxWidth: 1100,
      children: [
        Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(academy.name, style: Theme.of(context).textTheme.headlineSmall),
                  const SizedBox(height: 4),
                  Text(
                    [
                      if (academy.city != null) academy.city!,
                      if (academy.plan != null) 'Plan: ${academy.plan}',
                      if (academy.createdAt != null) 'Since ${_monthYear(academy.createdAt!)}',
                    ].join('  ·  '),
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ],
              ),
            ),
            ConsoleStatusChip(status: academy.status),
          ],
        ),
        const SizedBox(height: 24),

        const ConsoleSectionTitle('People'),
        ConsoleStatGrid(stats: [
          ConsoleStat('Students', '${academy.students}', Icons.school_outlined),
          ConsoleStat('Trainers', '${academy.trainers}', Icons.badge_outlined),
          ConsoleStat('Admins', '${academy.admins}', Icons.admin_panel_settings_outlined),
          ConsoleStat('Total people', '${academy.people}', Icons.people_outline),
        ]),
        const SizedBox(height: 24),

        const ConsoleSectionTitle('Teaching'),
        ConsoleStatGrid(stats: [
          ConsoleStat('Courses', '${academy.courses}', Icons.auto_stories_outlined),
          ConsoleStat('Batches', '${academy.batches}', Icons.groups_2_outlined),
          ConsoleStat('Events', '${academy.events}', Icons.celebration_outlined),
          ConsoleStat('Posts', '${academy.posts}', Icons.dynamic_feed_outlined),
        ]),
        const SizedBox(height: 24),

        const ConsoleSectionTitle('Money & activity'),
        ConsoleStatGrid(stats: [
          ConsoleStat(
            'Fees collected',
            formatCurrency(academy.feesCollected),
            Icons.payments_outlined,
            footnote: 'from its own students',
          ),
          ConsoleStat(
            'Last active',
            formatRelative(academy.lastActivityAt),
            Icons.bolt_outlined,
            tone: academy.lastActivityAt == null ? colorScheme.error : null,
            footnote: academy.lastActivityAt == null ? 'no activity recorded' : null,
          ),
        ]),
        const SizedBox(height: 28),

        const ConsoleSectionTitle('Operator actions'),
        Card(
          margin: EdgeInsets.zero,
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  academy.isSuspended
                      ? 'This academy is suspended - nobody in it can log in.'
                      : 'Suspending locks out everyone in this academy until you reactivate it.',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
                const SizedBox(height: 12),
                _SuspendButton(academy: academy),
                const SizedBox(height: 16),
                Text(
                  "Students, fees and attendance are the academy's own records and aren't editable "
                  'from here - that keeps their audit trail trustworthy in a dispute.',
                  style: TextStyle(fontSize: 11, color: colorScheme.onSurface.withValues(alpha: 0.5)),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  static String _monthYear(DateTime date) {
    const months = [
      'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
    ];
    return '${months[date.month - 1]} ${date.year}';
  }
}

class _SuspendButton extends ConsumerStatefulWidget {
  const _SuspendButton({required this.academy});

  final AcademySummary academy;

  @override
  ConsumerState<_SuspendButton> createState() => _SuspendButtonState();
}

class _SuspendButtonState extends ConsumerState<_SuspendButton> {
  bool _busy = false;

  Future<void> _toggle() async {
    final academy = widget.academy;
    final reactivating = academy.isSuspended;

    if (!reactivating) {
      final ok = await AppNotice.confirm(
        context,
        title: 'Suspend ${academy.name}?',
        message: 'Everyone in this academy - students, trainers and its admin - loses access until '
            'you reactivate it.',
        confirmLabel: 'Suspend',
      );
      if (!ok) return;
    }

    setState(() => _busy = true);
    try {
      await ref
          .read(academyOnboardingApiProvider)
          .setStatus(academy.id, reactivating ? 'ACTIVE' : 'SUSPENDED');
      if (mounted) {
        AppNotice.success(context, reactivating ? '${academy.name} reactivated.' : '${academy.name} suspended.');
        ref.invalidate(academyDetailProvider(academy.id));
        ref.invalidate(academyStatsProvider);
        ref.invalidate(platformOverviewProvider);
      }
    } on ApiException catch (e) {
      if (mounted) AppNotice.error(context, e.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final reactivating = widget.academy.isSuspended;
    if (_busy) {
      return const SizedBox(height: 20, width: 20, child: CircularProgressIndicator(strokeWidth: 2));
    }
    return OutlinedButton.icon(
      onPressed: _toggle,
      icon: Icon(reactivating ? Icons.play_circle_outline : Icons.pause_circle_outline,
          color: reactivating ? Colors.green.shade600 : colorScheme.error),
      label: Text(
        reactivating ? 'Reactivate academy' : 'Suspend academy',
        style: TextStyle(color: reactivating ? Colors.green.shade600 : colorScheme.error),
      ),
      style: OutlinedButton.styleFrom(
        side: BorderSide(
          color: (reactivating ? Colors.green.shade600 : colorScheme.error).withValues(alpha: 0.4),
        ),
      ),
    );
  }
}
