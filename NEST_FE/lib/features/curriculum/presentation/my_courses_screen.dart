import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:nest_fe/app/theme/app_tokens.dart';
import 'package:nest_fe/core/auth/session_controller.dart';
import 'package:nest_fe/core/design/app_top_bar.dart';
import 'package:nest_fe/core/design/category_meta.dart';
import 'package:nest_fe/core/design/charts.dart';
import 'package:nest_fe/core/design/course_icons.dart';
import 'package:nest_fe/core/design/gold_tabs.dart';
import 'package:nest_fe/core/design/status_badge.dart';
import 'package:nest_fe/core/design/toast.dart';
import 'package:nest_fe/core/format/money.dart';
import 'package:nest_fe/core/providers/core_providers.dart';
import 'package:nest_fe/core/widgets/async_value_view.dart';
import 'package:nest_fe/features/attendance/data/attendance_api.dart';
import 'package:nest_fe/features/attendance/data/student_attendance.dart';
import 'package:nest_fe/features/curriculum/data/course.dart';
import 'package:nest_fe/features/curriculum/data/curriculum_api.dart';
import 'package:nest_fe/features/enrolment/data/batch.dart';
import 'package:nest_fe/features/enrolment/data/enrolment_api.dart';

class _MyCourses {
  const _MyCourses(this.courses, this.batches);
  final List<Course> courses;
  final List<Batch> batches;
}

final _myCoursesProvider = FutureProvider.autoDispose<_MyCourses>((ref) async {
  final mid = ref.watch(activeMembershipIdProvider);
  if (mid == null) return const _MyCourses([], []);
  final courses = await ref.watch(curriculumApiProvider).listCoursesForMembership(mid);
  final batches = await ref.watch(enrolmentApiProvider).batchesForMembership(mid);
  courses.sort((a, b) => a.name.compareTo(b.name));
  return _MyCourses(courses, batches);
});

final _exploreProvider = FutureProvider.autoDispose<List<ExploreCourse>>((ref) {
  ref.watch(activeMembershipIdProvider);
  return ref.watch(curriculumApiProvider).exploreCourses();
});

enum _Tab { enrolled, explore }

/// The student's own enrolments: one card per course with its batch, trainer and attendance,
/// and a detail sheet with the fee structure. Read-only - a student changes none of this.
class MyCoursesScreen extends ConsumerStatefulWidget {
  const MyCoursesScreen({super.key});

  @override
  ConsumerState<MyCoursesScreen> createState() => _MyCoursesState();
}

class _MyCoursesState extends ConsumerState<MyCoursesScreen> {
  _Tab _tab = _Tab.enrolled;

  Future<void> _toggle(ExploreCourse c) async {
    try {
      await ref.read(curriculumApiProvider).setCourseInterest(c.id, !c.interested);
      ref.invalidate(_exploreProvider);
      if (mounted) {
        showAppToast(context, c.interested ? 'Interest withdrawn' : 'Interest sent - the academy will reach out soon');
      }
    } catch (_) {
      if (mounted) showAppToast(context, "Couldn't update - try again");
    }
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final mid = ref.watch(sessionControllerProvider).user?.activeMembership?.membershipId;
    final academy = ref.watch(sessionControllerProvider).user?.activeMembership?.academyName;
    final async = ref.watch(_myCoursesProvider);
    final attendance = mid == null ? null : ref.watch(studentAttendanceProvider(mid));

    return Scaffold(
      backgroundColor: palette.bg,
      body: SafeArea(
        child: Column(children: [
          AppTopBar(title: 'My Courses', subtitle: academy),
          Expanded(
            child: AsyncValueView<_MyCourses>(
              value: async,
              onRetry: () => ref.invalidate(_myCoursesProvider),
              data: (context, data) {
                final records = attendance?.valueOrNull ?? const <StudentAttendanceRecord>[];
                final present = records.where((r) => r.status == AttendanceStatus.present).length;
                final avg = records.isEmpty ? 0.0 : present / records.length * 100;
                final explore = ref.watch(_exploreProvider);
                return ListView(padding: const EdgeInsets.fromLTRB(20, 14, 20, 24), children: [
                  GoldTabs<_Tab>(
                    options: _Tab.values,
                    labelOf: (t) => t == _Tab.enrolled ? 'Enrolled' : 'Explore',
                    selected: _tab,
                    onTap: (t) => setState(() => _tab = t),
                  ),
                  const SizedBox(height: 14),
                  if (_tab == _Tab.explore) ..._exploreList(explore) else ...[
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: palette.surfaceRaised,
                      borderRadius: AppRadii.all(AppRadii.xxl),
                      border: Border.all(color: palette.border),
                    ),
                    child: Row(children: [
                      DonutChart(percent: avg, size: 64, strokeWidth: 7, color: palette.primary),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          Text('${data.courses.length} enrolled course${data.courses.length == 1 ? '' : 's'}',
                              style: TextStyle(fontSize: 15, fontWeight: FontWeight.w800, color: palette.text)),
                          const SizedBox(height: 4),
                          Text(records.isEmpty ? 'No classes marked yet' : '${avg.round()}% average attendance',
                              style: TextStyle(fontSize: 11, color: palette.textMuted)),
                        ]),
                      ),
                    ]),
                  ),
                  const SizedBox(height: 18),
                  Text('Your courses', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 13.5, color: palette.text)),
                  const SizedBox(height: 10),
                  if (data.courses.isEmpty)
                    Container(
                      padding: const EdgeInsets.symmetric(vertical: 22),
                      alignment: Alignment.center,
                      child: Text('No enrolments at this academy yet',
                          style: TextStyle(fontSize: 12, color: palette.textFaint)),
                    ),
                  for (final c in data.courses)
                    _CourseCard(
                      course: c,
                      batches: data.batches.where((b) => b.courseId == c.id).toList(),
                      records: records.where((r) => r.courseId == c.id).toList(),
                    ),
                  ],
                ]);
              },
            ),
          ),
        ]),
      ),
    );
  }
}

extension on _MyCoursesState {
  List<Widget> _exploreList(AsyncValue<List<ExploreCourse>> async) {
    final palette = context.palette;
    return [
      Text('Other courses at this academy',
          style: TextStyle(fontWeight: FontWeight.w800, fontSize: 13.5, color: palette.text)),
      const SizedBox(height: 10),
      ...async.when(
        loading: () => [const Center(child: Padding(padding: EdgeInsets.all(24), child: CircularProgressIndicator()))],
        error: (e, _) => [Text(e.toString().replaceFirst('Exception: ', ''), style: TextStyle(color: palette.textFaint))],
        data: (list) => list.isEmpty
            ? [
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 22),
                  child: Center(
                    child: Text("You're already enrolled in everything on offer here",
                        style: TextStyle(fontSize: 12, color: palette.textFaint)),
                  ),
                )
              ]
            : [
                for (final c in list)
                  Builder(builder: (context) {
                    final meta = context.categoryMeta(c.category);
                    return Container(
                      margin: const EdgeInsets.only(bottom: 10),
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: palette.surfaceRaised,
                        borderRadius: AppRadii.all(AppRadii.xxl),
                        border: Border.all(color: palette.border),
                      ),
                      child: Column(children: [
                        Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          Container(
                            width: 38,
                            height: 38,
                            decoration: BoxDecoration(color: meta.soft, borderRadius: AppRadii.all(AppRadii.lg)),
                            child: Center(
                              child: CourseIcon.forCourse(iconKey: c.iconKey, category: c.category, color: meta.color),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                              Text(c.name,
                                  style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13, color: palette.text)),
                              const SizedBox(height: 2),
                              Text(
                                [c.category.label, if ((c.durationLevel ?? '').isNotEmpty) c.durationLevel!].join(' · '),
                                style: TextStyle(fontSize: 10.5, color: palette.textFaint),
                              ),
                              if ((c.description ?? '').isNotEmpty) ...[
                                const SizedBox(height: 6),
                                Text(c.description!,
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(fontSize: 11, color: palette.textMuted)),
                              ],
                            ]),
                          ),
                        ]),
                        const SizedBox(height: 10),
                        SizedBox(
                          width: double.infinity,
                          child: c.interested
                              ? FilledButton.icon(
                                  onPressed: () => _toggle(c),
                                  icon: const Icon(Icons.check, size: 15),
                                  label: const Text('Interested'),
                                )
                              : OutlinedButton(onPressed: () => _toggle(c), child: const Text("I'm interested")),
                        ),
                      ]),
                    );
                  }),
              ],
      ),
    ];
  }
}

class _CourseCard extends StatelessWidget {
  const _CourseCard({required this.course, required this.batches, required this.records});
  final Course course;
  final List<Batch> batches;
  final List<StudentAttendanceRecord> records;

  double? get _pct => records.isEmpty
      ? null
      : records.where((r) => r.status == AttendanceStatus.present).length / records.length * 100;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final meta = context.categoryMeta(course.category);
    final pct = _pct;
    final pctColor = pct == null
        ? palette.textFaint
        : pct >= 85 ? palette.paidManual : pct >= 70 ? palette.partial : palette.notPaid;
    final trainers = {for (final b in batches) ...b.trainers.map((t) => t.name)}.where((n) => n.isNotEmpty);

    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: InkWell(
        borderRadius: AppRadii.all(AppRadii.xxl),
        onTap: () => _showDetail(context),
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: palette.surfaceRaised,
            borderRadius: AppRadii.all(AppRadii.xxl),
            border: Border.all(color: palette.border),
          ),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Container(
              width: 38,
              height: 38,
              decoration: BoxDecoration(color: meta.soft, borderRadius: AppRadii.all(AppRadii.lg)),
              child: Center(
                child: CourseIcon.forCourse(iconKey: course.iconKey, category: course.category, color: meta.color),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(course.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13, color: palette.text)),
                const SizedBox(height: 2),
                Text(
                  [if (trainers.isNotEmpty) trainers.join(', '), if (batches.isNotEmpty) batches.map((b) => b.name).join(', ')]
                      .join(' · '),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 10.5, color: palette.textFaint),
                ),
              ]),
            ),
            if (pct != null)
              StatusBadge(label: '${pct.round()}% present', color: pctColor),
            const SizedBox(width: 4),
            Icon(Icons.chevron_right, size: 16, color: palette.textFaint),
          ]),
        ),
      ),
    );
  }

  void _showDetail(BuildContext context) {
    final palette = context.palette;
    final meta = context.categoryMeta(course.category);
    final trainers = {for (final b in batches) ...b.trainers.map((t) => t.name)}.where((n) => n.isNotEmpty).toList();
    final present = records.where((r) => r.status == AttendanceStatus.present).length;

    Widget row(String k, String v) => Padding(
          padding: const EdgeInsets.symmetric(vertical: 5),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            SizedBox(width: 92, child: Text(k, style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.w600, color: palette.textFaint))),
            Expanded(child: Text(v, textAlign: TextAlign.right, style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w600, color: palette.text))),
          ]),
        );

    Widget box(List<Widget> children) => Container(
          width: double.infinity,
          padding: const EdgeInsets.all(12),
          margin: const EdgeInsets.only(top: 12),
          decoration: BoxDecoration(
            color: palette.surfaceHigh,
            borderRadius: AppRadii.all(AppRadii.xl),
            border: Border.all(color: palette.border),
          ),
          child: Column(children: children),
        );

    final feeLines = <Widget>[
      row('Billing', switch (course.feeModel) {
        FeeModel.perClass => 'Per class',
        FeeModel.fixed => 'Fixed',
        FeeModel.hybrid => 'Hybrid',
      }),
      row('Fee', course.feeSummary),
      if (course.feeModel == FeeModel.perClass)
        row('How it works', 'Classes attended × fee per class'),
      if (course.feeModel == FeeModel.hybrid && course.hybridThresholdAttendance != null)
        row('Threshold',
            'Full fee at ${course.hybridThresholdAttendance} of ${course.hybridExpectedClassesPerPeriod ?? '-'} classes'),
      if (course.billingDayOfMonth != null) row('Fee issued', ordinalDay(course.billingDayOfMonth!)),
      if (course.dueDayOfMonth != null) row('Payment due', ordinalDay(course.dueDayOfMonth!)),
    ];

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: palette.surface,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(22))),
      builder: (_) => DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.8,
        maxChildSize: 0.92,
        builder: (_, controller) => ListView(
          controller: controller,
          padding: const EdgeInsets.fromLTRB(18, 18, 18, 28),
          children: [
            Text(course.name, textAlign: TextAlign.center, style: TextStyle(fontSize: 15, fontWeight: FontWeight.w800, color: palette.text)),
            const SizedBox(height: 10),
            Row(children: [
              StatusBadge(label: course.category.label, color: meta.color, softColor: meta.soft),
              const SizedBox(width: 8),
              StatusBadge(label: 'Enrolled', color: palette.paidManual, softColor: palette.paidManualSoft),
            ]),
            if ((course.description ?? '').isNotEmpty) ...[
              const SizedBox(height: 12),
              Text(course.description!, style: TextStyle(fontSize: 11.5, height: 1.5, color: palette.textMuted)),
            ],
            if (trainers.isNotEmpty)
              box([row(trainers.length == 1 ? 'Trainer' : 'Trainers', trainers.join(', '))]),
            if (batches.isNotEmpty)
              box([for (final b in batches) row('Batch', b.name)]),
            box(feeLines),
            box([
              row('Attendance', records.isEmpty ? 'No classes yet' : '$present/${records.length} classes attended'),
            ]),
          ],
        ),
      ),
    );
  }
}
