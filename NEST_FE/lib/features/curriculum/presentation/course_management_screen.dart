import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:nest_fe/core/error/api_exception.dart';
import 'package:nest_fe/core/widgets/app_notice.dart';
import 'package:nest_fe/core/widgets/async_value_view.dart';
import 'package:nest_fe/features/curriculum/data/course.dart';
import 'package:nest_fe/features/curriculum/data/curriculum_api.dart';
import 'package:nest_fe/features/curriculum/presentation/course_form_sheet.dart';
import 'package:nest_fe/features/fees/presentation/fees_screen.dart' show feesApiProvider;

/// Course catalog management - create, edit, activate/deactivate. Separate from the Batches
/// screen on purpose: that screen is for browsing/running batches, this one is for defining what
/// courses exist in the first place. Reached only via the admin-only "Course Creation" tile.
class CourseManagementScreen extends ConsumerWidget {
  const CourseManagementScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final coursesAsync = ref.watch(allCoursesProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Courses')),
      body: AsyncValueView<List<Course>>(
        value: coursesAsync,
        onRetry: () => ref.invalidate(allCoursesProvider),
        data: (context, courses) {
          if (courses.isEmpty) {
            return const EmptyState(icon: Icons.auto_stories_outlined, message: 'No courses yet - create the first one.');
          }
          return ListView.builder(
            padding: const EdgeInsets.all(12),
            itemCount: courses.length,
            itemBuilder: (context, index) => _CourseTile(course: courses[index]),
          );
        },
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => showCourseFormSheet(context, ref),
        icon: const Icon(Icons.add),
        label: const Text('New course'),
      ),
    );
  }
}

class _CourseTile extends ConsumerWidget {
  const _CourseTile({required this.course});
  final Course course;

  Future<void> _toggleStatus(BuildContext context, WidgetRef ref) async {
    final activating = !course.isActive;
    try {
      await ref.read(curriculumApiProvider).setStatus(course.id, activating ? 'ACTIVE' : 'INACTIVE');
      ref.invalidate(activeCoursesProvider);
      ref.invalidate(allCoursesProvider);
      if (context.mounted) {
        AppNotice.success(context, activating ? '${course.name} reactivated.' : '${course.name} deactivated.');
      }
    } on ApiException catch (e) {
      if (context.mounted) AppNotice.error(context, e.message);
    }
  }

  /// Manual trigger for the same calculation the billing-day cron runs - lets an Admin test the
  /// setup, or catch up a course whose billing day already passed this month, without waiting.
  Future<void> _generateFeeSlips(BuildContext context, WidgetRef ref) async {
    try {
      final slips = await ref.read(feesApiProvider).generateFeeSlips(course.id);
      if (context.mounted) {
        AppNotice.success(
          context,
          slips.isEmpty ? 'No new fee slips to generate - already up to date.' : 'Generated ${slips.length} fee slip(s).',
        );
      }
    } on ApiException catch (e) {
      if (context.mounted) AppNotice.error(context, e.message);
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colorScheme = Theme.of(context).colorScheme;

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: Opacity(
        opacity: course.isActive ? 1 : 0.6,
        child: ListTile(
          title: Row(
            children: [
              Flexible(child: Text(course.name)),
              if (!course.isActive) ...[
                const SizedBox(width: 8),
                Chip(
                  label: const Text('Inactive', style: TextStyle(fontSize: 11)),
                  visualDensity: VisualDensity.compact,
                  materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  backgroundColor: colorScheme.errorContainer,
                  labelStyle: TextStyle(color: colorScheme.onErrorContainer),
                ),
              ],
            ],
          ),
          subtitle: Text([
            course.category,
            course.feeSummary,
            if (course.billingSummary != null) course.billingSummary!,
          ].join(' · ')),
          trailing: PopupMenuButton<String>(
            onSelected: (action) {
              if (action == 'edit') {
                showCourseFormSheet(context, ref, existing: course);
              } else if (action == 'toggle') {
                _toggleStatus(context, ref);
              } else if (action == 'generateSlips') {
                _generateFeeSlips(context, ref);
              }
            },
            itemBuilder: (_) => [
              const PopupMenuItem(value: 'edit', child: Text('Edit')),
              PopupMenuItem(value: 'toggle', child: Text(course.isActive ? 'Deactivate' : 'Reactivate')),
              if (course.billingDayOfMonth != null)
                const PopupMenuItem(value: 'generateSlips', child: Text('Generate fee slips now')),
            ],
          ),
        ),
      ),
    );
  }
}
