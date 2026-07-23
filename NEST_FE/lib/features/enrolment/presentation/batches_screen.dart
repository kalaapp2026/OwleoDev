import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:nest_fe/core/auth/feature_keys.dart';
import 'package:nest_fe/core/auth/session_controller.dart';
import 'package:nest_fe/core/auth/user_profile.dart';
import 'package:nest_fe/core/providers/core_providers.dart';
import 'package:nest_fe/core/widgets/async_value_view.dart';
import 'package:nest_fe/features/curriculum/data/course.dart';
import 'package:nest_fe/features/curriculum/data/curriculum_api.dart';
import 'package:nest_fe/features/enrolment/data/batch.dart';
import 'package:nest_fe/features/enrolment/data/enrolment_api.dart';
import 'package:nest_fe/features/enrolment/presentation/batch_edit_sheet.dart';
import 'package:nest_fe/features/enrolment/presentation/batch_form_sheet.dart';

final enrolmentApiProvider = Provider((ref) => EnrolmentApi(ref.watch(dioClientProvider)));
final batchesForCourseProvider = FutureProvider.autoDispose.family<List<Batch>, String>((ref, courseId) {
  ref.watch(activeMembershipIdProvider);
  return ref.watch(enrolmentApiProvider).batchesForCourse(courseId);
});

/// A Student's "my batches" - just the batch(es) THEY belong to, across every course. Never a
/// course's full roster of batches (other students' batches aren't theirs to see).
final batchesForMembershipProvider = FutureProvider.autoDispose.family<List<Batch>, String>((ref, membershipId) {
  ref.watch(activeMembershipIdProvider);
  return ref.watch(enrolmentApiProvider).batchesForMembership(membershipId);
});

bool _canCreateBatches(UserProfile? user) =>
    user != null && (user.isSuperAdmin || user.isActiveAcademyAdmin || user.hasFeature(FeatureKeys.batchCreation));

/// Batches only - course management (create/edit/deactivate a course) lives on its own screen
/// now (Course Creation tile). For a Trainer/Admin, Course is a filter dimension over the
/// academy's batches. For a Student, there's no filter at all: they only ever see the specific
/// batch(es) they're actually mapped into - a course they're enrolled in but not yet assigned a
/// batch for simply doesn't appear, rather than showing an empty/misleading entry for it.
class BatchesScreen extends ConsumerStatefulWidget {
  const BatchesScreen({super.key});

  @override
  ConsumerState<BatchesScreen> createState() => _BatchesScreenState();
}

class _BatchesScreenState extends ConsumerState<BatchesScreen> {
  /// null until the course list first loads, at which point it's seeded with a sensible default
  /// (see _seedFilterIfNeeded) - null also doubles as "no filter applied yet".
  Set<String>? _selectedCourseIds;

  void _seedFilterIfNeeded(List<Course> courses, UserProfile? user) {
    if (_selectedCourseIds != null) return;
    final ownCourseIds = user?.activeMembership?.courseIds ?? const <String>{};
    final ownAvailable = courses.where((c) => ownCourseIds.contains(c.id)).map((c) => c.id).toSet();
    // A Trainer mapped to specific courses starts filtered to just those; an Admin (who isn't
    // personally mapped to any course) or a Trainer with no mappings yet starts unfiltered.
    _selectedCourseIds = ownAvailable.isNotEmpty ? ownAvailable : courses.map((c) => c.id).toSet();
  }

  @override
  Widget build(BuildContext context) {
    final user = ref.watch(sessionControllerProvider).user;
    final isStudent = user?.activeMembership?.roleType == 'STUDENT';

    // No own Scaffold/AppBar - this is rendered inside AppShell's IndexedStack as the Batches
    // tab, which already supplies the surrounding Scaffold and AppBar (title comes from
    // _erpTitles there, not from this widget).
    if (isStudent) {
      final membershipId = user?.activeMembershipId;
      if (membershipId == null) return const SizedBox.shrink();
      return _MyBatchesView(membershipId: membershipId);
    }

    final canCreate = _canCreateBatches(user);
    final coursesAsync = ref.watch(activeCoursesProvider);

    return AsyncValueView<List<Course>>(
      value: coursesAsync,
      onRetry: () => ref.invalidate(activeCoursesProvider),
      data: (context, courses) {
        if (courses.isEmpty) {
          return const EmptyState(icon: Icons.groups_2_outlined, message: 'Create a course first, then batches can be added under it.');
        }

        Widget filterRow = const SizedBox.shrink();
        List<Course> visibleCourses = courses;
        if (courses.length > 1) {
          _seedFilterIfNeeded(courses, user);
          final selected = _selectedCourseIds!;
          visibleCourses = courses.where((c) => selected.contains(c.id)).toList();
          filterRow = Padding(
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 4),
            child: Wrap(
              spacing: 8,
              runSpacing: 4,
              children: courses.map((c) {
                final isSelected = selected.contains(c.id);
                return FilterChip(
                  label: Text(c.name),
                  selected: isSelected,
                  onSelected: (v) => setState(() {
                    v ? selected.add(c.id) : selected.remove(c.id);
                  }),
                );
              }).toList(),
            ),
          );
        }

        return Column(
          children: [
            filterRow,
            Expanded(
              child: visibleCourses.isEmpty
                  ? const EmptyState(icon: Icons.filter_alt_off_outlined, message: 'No courses match the current filter.')
                  : ListView(
                      padding: const EdgeInsets.all(12),
                      children: visibleCourses.map((course) => _CourseBatchList(course: course, canCreate: canCreate)).toList(),
                    ),
            ),
          ],
        );
      },
    );
  }
}

/// A Student sees exactly the batch(es) they're mapped into - grouped by course, but a course
/// they're enrolled in with no batch assignment yet just isn't shown (there's nothing they could
/// do about it, and an empty entry would read as a bug rather than as "nothing to see here").
class _MyBatchesView extends ConsumerWidget {
  const _MyBatchesView({required this.membershipId});
  final String membershipId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final batchesAsync = ref.watch(batchesForMembershipProvider(membershipId));
    final coursesAsync = ref.watch(activeCoursesProvider);

    return AsyncValueView<List<Batch>>(
      value: batchesAsync,
      onRetry: () => ref.invalidate(batchesForMembershipProvider(membershipId)),
      data: (context, batches) {
        if (batches.isEmpty) {
          return const EmptyState(
            icon: Icons.groups_2_outlined,
            message: "You haven't been assigned to a batch yet - check with your academy.",
          );
        }
        return coursesAsync.when(
          data: (courses) {
            final courseNames = {for (final c in courses) c.id: c.name};
            final byCourse = <String, List<Batch>>{};
            for (final b in batches) {
              (byCourse[b.courseId] ??= []).add(b);
            }
            return ListView(
              padding: const EdgeInsets.all(12),
              children: byCourse.entries
                  .map((entry) => Card(
                        margin: const EdgeInsets.only(bottom: 10),
                        child: Padding(
                          padding: const EdgeInsets.all(12),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(courseNames[entry.key] ?? 'Course', style: Theme.of(context).textTheme.titleMedium),
                              const SizedBox(height: 4),
                              ...entry.value.map((b) => ListTile(
                                    dense: true,
                                    contentPadding: EdgeInsets.zero,
                                    leading: Icon(b.batchType == 'REGULAR' ? Icons.repeat : Icons.event_repeat_outlined, size: 20),
                                    title: Text(b.name),
                                    subtitle: Text([
                                      b.batchType,
                                      b.status,
                                      if (b.trainerName != null) 'Trainer: ${b.trainerName}',
                                    ].join(' · ')),
                                  )),
                            ],
                          ),
                        ),
                      ))
                  .toList(),
            );
          },
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (err, stack) => const Center(child: Text('Could not load your courses')),
        );
      },
    );
  }
}

class _CourseBatchList extends ConsumerWidget {
  const _CourseBatchList({required this.course, required this.canCreate});
  final Course course;
  final bool canCreate;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final batchesAsync = ref.watch(batchesForCourseProvider(course.id));

    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: ExpansionTile(
        title: Text(course.name),
        subtitle: Text(course.category),
        childrenPadding: const EdgeInsets.only(bottom: 8),
        children: [
          batchesAsync.when(
            data: (batches) {
              if (batches.isEmpty) {
                return const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  child: Text('No batches yet', style: TextStyle(fontSize: 13)),
                );
              }
              return Column(
                children: batches
                    .map((b) => ListTile(
                          dense: true,
                          leading: Icon(b.batchType == 'REGULAR' ? Icons.repeat : Icons.event_repeat_outlined, size: 20),
                          title: Text(b.name),
                          subtitle: Text([
                            b.batchType,
                            b.status,
                            if (b.trainerName != null) 'Trainer: ${b.trainerName}',
                          ].join(' · ')),
                          trailing: canCreate ? const Icon(Icons.chevron_right) : null,
                          onTap: canCreate ? () => showBatchEditSheet(context, ref, batch: b) : null,
                        ))
                    .toList(),
              );
            },
            loading: () => const Padding(
              padding: EdgeInsets.all(16),
              child: Center(child: SizedBox(height: 18, width: 18, child: CircularProgressIndicator(strokeWidth: 2))),
            ),
            error: (err, stack) => const Padding(
              padding: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Text('Could not load batches', style: TextStyle(fontSize: 13)),
            ),
          ),
          if (canCreate)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: Align(
                alignment: Alignment.centerLeft,
                child: TextButton.icon(
                  onPressed: () => showBatchFormSheet(context, ref, courseId: course.id),
                  icon: const Icon(Icons.add, size: 18),
                  label: const Text('Add batch'),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
