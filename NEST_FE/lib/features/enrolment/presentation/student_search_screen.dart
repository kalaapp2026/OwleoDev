import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:nest_fe/app/theme/app_tokens.dart';
import 'package:nest_fe/app/theme/app_typography.dart';
import 'package:nest_fe/core/auth/feature_keys.dart';
import 'package:nest_fe/core/auth/session_controller.dart';
import 'package:nest_fe/core/design/app_top_bar.dart';
import 'package:nest_fe/core/design/avatar.dart';
import 'package:nest_fe/core/design/category_meta.dart';
import 'package:nest_fe/core/design/pressable.dart';
import 'package:nest_fe/core/error/api_exception.dart';
import 'package:nest_fe/features/curriculum/data/course.dart';
import 'package:nest_fe/features/curriculum/data/curriculum_api.dart';
import 'package:nest_fe/features/enrolment/data/enrolment_api.dart';
import 'package:nest_fe/features/enrolment/presentation/student_dashboard_screen.dart';

/// One student with every course of theirs this user can see.
class _Entry {
  _Entry(this.student);
  final StudentSummary student;
  final List<Course> courses = [];
}

/// Student Profiles: one flat, searchable list of students, each labelled with their course.
///
/// Still built from the per-course rosters rather than an academy-wide query, deliberately - like
/// every other roster picker here, a Trainer's courses are what [coursesForFeatureProvider]
/// already narrows to, so this list can never surface a student outside the courses that Trainer
/// actually manages.
class StudentSearchScreen extends ConsumerStatefulWidget {
  const StudentSearchScreen({super.key});

  @override
  ConsumerState<StudentSearchScreen> createState() => _StudentSearchScreenState();
}

class _StudentSearchScreenState extends ConsumerState<StudentSearchScreen> {
  String _query = '';
  final _searchController = TextEditingController();

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  /// Merges the rosters of every course into one entry per student. Null while any is loading.
  /// Throws the first roster error so the caller can show one message.
  List<_Entry>? _merge(List<Course> courses) {
    final byMembership = <String, _Entry>{};
    var loading = false;
    Object? error;
    for (final course in courses) {
      final roster = ref.watch(studentsForCourseProvider(course.id));
      roster.when(
        data: (students) {
          for (final s in students) {
            byMembership.putIfAbsent(s.membershipId, () => _Entry(s)).courses.add(course);
          }
        },
        loading: () => loading = true,
        error: (e, _) => error ??= e,
      );
    }
    if (error != null) throw error!;
    if (loading) return null;
    return byMembership.values.toList()
      ..sort((a, b) => a.student.fullName.toLowerCase().compareTo(b.student.fullName.toLowerCase()));
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final academyName = ref.watch(sessionControllerProvider).user?.activeMembership?.academyName;
    // BATCH_CREATION, not STUDENT_REGISTRATION: that's what /courses/{id}/students is actually
    // gated on server-side, so this never asks for a course the call would 403 on.
    final coursesAsync = ref.watch(coursesForFeatureProvider(FeatureKeys.batchCreation));

    return Scaffold(
      backgroundColor: palette.bg,
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            AppTopBar(title: 'Student Profiles', subtitle: academyName, actions: const [ThemeModeButton()]),
            Padding(
              padding: const EdgeInsets.fromLTRB(AppSpacing.x4l, AppSpacing.xxl, AppSpacing.x4l, AppSpacing.md),
              child: _searchField(palette),
            ),
            Expanded(
              child: coursesAsync.when(
                loading: () => const Center(child: CircularProgressIndicator()),
                error: (e, _) => _message('Could not load courses.'),
                data: (courses) {
                  if (courses.isEmpty) return _message('No courses available to you yet.');
                  final List<_Entry>? entries;
                  try {
                    entries = _merge(courses);
                  } catch (e) {
                    return _message(e is ApiException ? e.message : 'Could not load students.');
                  }
                  if (entries == null) return const Center(child: CircularProgressIndicator());
                  return _list(entries);
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _message(String text) => Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(text, textAlign: TextAlign.center, style: TextStyle(color: context.palette.textMuted)),
        ),
      );

  Widget _searchField(AppPalette palette) {
    OutlineInputBorder border(Color c) =>
        OutlineInputBorder(borderRadius: AppRadii.all(AppRadii.xl), borderSide: BorderSide(color: c));
    return TextField(
      controller: _searchController,
      onChanged: (v) => setState(() => _query = v.trim().toLowerCase()),
      style: TextStyle(color: palette.text, fontSize: AppType.xl),
      decoration: InputDecoration(
        hintText: 'Search students by name or username',
        hintStyle: TextStyle(color: palette.textFaint, fontSize: AppType.xl),
        prefixIcon: Icon(Icons.search, size: 18, color: palette.textFaint),
        filled: true,
        fillColor: palette.surfaceRaised,
        contentPadding: const EdgeInsets.symmetric(vertical: AppSpacing.xl),
        border: border(palette.border),
        enabledBorder: border(palette.border),
        focusedBorder: border(palette.primary),
      ),
    );
  }

  Widget _list(List<_Entry> all) {
    final palette = context.palette;
    final entries = _query.isEmpty
        ? all
        : all
            .where((e) =>
                e.student.fullName.toLowerCase().contains(_query) || e.student.username.toLowerCase().contains(_query))
            .toList();
    if (entries.isEmpty) {
      return _message(all.isEmpty ? 'No students enrolled yet.' : 'No student matches "$_query".');
    }
    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(AppSpacing.xl, 0, AppSpacing.xl, AppSpacing.listBottom),
      itemCount: entries.length,
      itemBuilder: (context, i) {
        final e = entries[i];
        final course = e.courses.first;
        final meta = course.category.meta(palette);
        return Pressable(
          onTap: () => Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => StudentDashboardScreen(membershipId: e.student.membershipId)),
          ),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md, vertical: AppSpacing.xl),
            decoration: BoxDecoration(border: Border(bottom: BorderSide(color: palette.borderSoft))),
            child: Row(
              children: [
                PersonAvatar(name: e.student.fullName, seed: e.student.membershipId, size: 48),
                const SizedBox(width: AppSpacing.xl),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(e.student.fullName,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(fontSize: AppType.x3l, fontWeight: AppType.bold, color: palette.text)),
                      const SizedBox(height: 3),
                      Row(
                        children: [
                          Container(width: 7, height: 7, decoration: BoxDecoration(color: meta.color, shape: BoxShape.circle)),
                          const SizedBox(width: AppSpacing.xs),
                          Flexible(
                            child: Text(
                              e.courses.length > 1 ? '${course.name} +${e.courses.length - 1}' : course.name,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(fontSize: AppType.smd, color: palette.textMuted),
                            ),
                          ),
                          if (!e.student.active) ...[
                            const SizedBox(width: AppSpacing.md),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm, vertical: 1),
                              decoration: BoxDecoration(
                                color: palette.textFaint.withValues(alpha: 0.13),
                                borderRadius: AppRadii.all(AppRadii.xs),
                              ),
                              child: Text('Inactive', style: TextStyle(fontSize: AppType.tiny, color: palette.textMuted)),
                            ),
                          ],
                        ],
                      ),
                    ],
                  ),
                ),
                Icon(Icons.chevron_right, size: 20, color: palette.textFaint),
              ],
            ),
          ),
        );
      },
    );
  }
}
