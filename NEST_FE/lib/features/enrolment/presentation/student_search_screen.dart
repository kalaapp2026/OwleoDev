import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:nest_fe/app/theme/app_tokens.dart';
import 'package:nest_fe/app/theme/app_typography.dart';
import 'package:nest_fe/core/auth/feature_keys.dart';
import 'package:nest_fe/core/design/attached_select.dart';
import 'package:nest_fe/core/design/avatar.dart';
import 'package:nest_fe/core/design/category_meta.dart';
import 'package:nest_fe/core/design/pressable.dart';
import 'package:nest_fe/core/widgets/async_value_view.dart';
import 'package:nest_fe/features/curriculum/data/course.dart';
import 'package:nest_fe/features/curriculum/data/curriculum_api.dart';
import 'package:nest_fe/features/enrolment/data/enrolment_api.dart';
import 'package:nest_fe/features/enrolment/presentation/student_dashboard_screen.dart';

/// Course-scoped student search: pick a course, then find someone in its roster to open their
/// profile. Course-scoped rather than academy-wide by design - like every other roster picker in
/// this app, a Trainer's list is what [coursesForFeatureProvider] already narrows it to, so this
/// screen can never surface a student outside the courses that Trainer actually manages.
class StudentSearchScreen extends ConsumerStatefulWidget {
  const StudentSearchScreen({super.key});

  @override
  ConsumerState<StudentSearchScreen> createState() => _StudentSearchScreenState();
}

class _StudentSearchScreenState extends ConsumerState<StudentSearchScreen> {
  String? _courseId;
  String _query = '';
  final _searchController = TextEditingController();

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    // BATCH_CREATION, not STUDENT_REGISTRATION: that's what /courses/{id}/students is actually
    // gated on server-side, so this is the picker that never offers a course the call would 403 on.
    final coursesAsync = ref.watch(coursesForFeatureProvider(FeatureKeys.batchCreation));

    return Scaffold(
      backgroundColor: palette.bg,
      appBar: AppBar(title: const Text('Students')),
      body: coursesAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Text('Could not load courses.', style: TextStyle(color: palette.textMuted)),
          ),
        ),
        data: (courses) {
          if (courses.isEmpty) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Text('No courses available to you yet.', style: TextStyle(color: palette.textMuted)),
              ),
            );
          }
          _courseId ??= courses.first.id;
          final course = courses.firstWhere((c) => c.id == _courseId, orElse: () => courses.first);

          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(AppSpacing.page, AppSpacing.xl, AppSpacing.page, 0),
                child: Column(
                  children: [
                    _coursePicker(palette, courses, course),
                    const SizedBox(height: AppSpacing.lg),
                    _searchField(palette),
                    const SizedBox(height: AppSpacing.lg),
                  ],
                ),
              ),
              Expanded(child: _roster(course.id)),
            ],
          );
        },
      ),
    );
  }

  Widget _coursePicker(AppPalette palette, List<Course> courses, Course course) {
    return AttachedSelect<Course>(
      label: 'Course',
      options: courses,
      labelOf: (c) => c.name,
      value: course,
      searchable: true,
      searchHint: 'Search course',
      onSelected: (c) => setState(() => _courseId = c.id),
      optionBuilder: (context, option, _) {
        final meta = option.category.meta(palette);
        final selected = option.id == _courseId;
        return Row(
          children: [
            Container(height: 9, width: 9, decoration: BoxDecoration(color: meta.color, shape: BoxShape.circle)),
            const SizedBox(width: AppSpacing.md),
            Expanded(
              child: Text(option.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: AppType.xl,
                    fontWeight: selected ? AppType.bold : AppType.regular,
                    color: selected ? meta.color : palette.text,
                  )),
            ),
          ],
        );
      },
    );
  }

  Widget _searchField(AppPalette palette) {
    return TextField(
      controller: _searchController,
      onChanged: (v) => setState(() => _query = v.trim().toLowerCase()),
      decoration: InputDecoration(
        hintText: 'Search by name',
        prefixIcon: const Icon(Icons.search),
        filled: true,
        fillColor: palette.surface,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppRadii.lg),
          borderSide: BorderSide(color: palette.borderSoft),
        ),
      ),
    );
  }

  Widget _roster(String courseId) {
    final palette = context.palette;
    final studentsAsync = ref.watch(studentsForCourseProvider(courseId));
    return AsyncValueView<List<StudentSummary>>(
      value: studentsAsync,
      onRetry: () => ref.invalidate(studentsForCourseProvider(courseId)),
      data: (context, students) {
        final filtered = _query.isEmpty
            ? students
            : students.where((s) => s.fullName.toLowerCase().contains(_query)).toList();
        if (filtered.isEmpty) {
          return Center(
            child: Text(
              students.isEmpty ? 'No students enrolled in this course yet.' : 'No student matches "$_query".',
              style: TextStyle(color: palette.textMuted),
            ),
          );
        }
        return ListView.builder(
          padding: const EdgeInsets.fromLTRB(AppSpacing.page, 0, AppSpacing.page, AppSpacing.listBottom),
          itemCount: filtered.length,
          itemBuilder: (context, i) {
            final student = filtered[i];
            return Pressable(
              onTap: () => Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => StudentDashboardScreen(membershipId: student.membershipId)),
              ),
              borderRadius: BorderRadius.circular(AppRadii.lg),
              child: Container(
                margin: const EdgeInsets.only(bottom: AppSpacing.sm),
                padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xl, vertical: AppSpacing.lg),
                decoration: BoxDecoration(
                  color: palette.surfaceRaised,
                  borderRadius: BorderRadius.circular(AppRadii.lg),
                  border: Border.all(color: palette.borderSoft),
                ),
                child: Row(
                  children: [
                    PersonAvatar(name: student.fullName, seed: student.membershipId, size: 40),
                    const SizedBox(width: AppSpacing.lg),
                    Expanded(
                      child: Text(student.fullName,
                          style: TextStyle(fontSize: AppType.xl, fontWeight: AppType.medium, color: palette.text)),
                    ),
                    if (!student.active)
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm, vertical: 2),
                        decoration: BoxDecoration(
                          color: palette.textFaint.withValues(alpha: 0.13),
                          borderRadius: BorderRadius.circular(AppRadii.sm),
                        ),
                        child: Text('Inactive', style: TextStyle(fontSize: AppType.tiny, color: palette.textMuted)),
                      ),
                    const SizedBox(width: AppSpacing.sm),
                    Icon(Icons.chevron_right, color: palette.textFaint),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }
}
