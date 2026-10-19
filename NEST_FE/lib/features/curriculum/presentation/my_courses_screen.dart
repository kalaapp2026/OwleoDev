import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:nest_fe/app/theme/app_tokens.dart';
import 'package:nest_fe/app/theme/app_typography.dart';
import 'package:nest_fe/core/auth/session_controller.dart';
import 'package:nest_fe/core/design/app_top_bar.dart';
import 'package:nest_fe/core/design/avatar.dart';
import 'package:nest_fe/core/design/category_meta.dart';
import 'package:nest_fe/core/design/charts.dart';
import 'package:nest_fe/core/design/course_icons.dart';
import 'package:nest_fe/core/design/gold_tabs.dart';
import 'package:nest_fe/core/design/pressable.dart';
import 'package:nest_fe/core/design/toast.dart';
import 'package:nest_fe/core/export/report_export.dart';
import 'package:nest_fe/core/format/money.dart';
import 'package:nest_fe/core/providers/core_providers.dart';
import 'package:nest_fe/core/widgets/async_value_view.dart';
import 'package:nest_fe/features/attendance/data/attendance_api.dart';
import 'package:nest_fe/features/attendance/data/student_attendance.dart';
import 'package:nest_fe/features/curriculum/data/course.dart';
import 'package:nest_fe/features/curriculum/data/curriculum_api.dart';
import 'package:nest_fe/features/curriculum/data/study_material.dart';
import 'package:nest_fe/features/curriculum/data/study_material_api.dart';
import 'package:nest_fe/features/enrolment/data/batch.dart';
import 'package:nest_fe/features/enrolment/data/enrolment_api.dart';
import 'package:nest_fe/features/profile/data/self_profile_api.dart' show selfProfileProvider;
import 'package:nest_fe/features/shell/presentation/header_actions.dart';

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

/// "Mon, Wed, Fri · 6:00 PM–6:45 PM" for one batch, or null while it has no weekly schedule.
String? _scheduleLine(Batch b) {
  if (b.days.isEmpty && b.timeRange == null) return null;
  return [
    if (b.days.isNotEmpty) formatDays(b.days),
    if (b.timeRange != null) b.timeRange!.replaceAll(' - ', '–'),
  ].join(' · ');
}

/// The student's own enrolments: one card per course with its trainer, batch and attendance, a
/// detail sheet with the fee structure, and an Explore tab for what else the academy teaches.
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
      if (mounted) showAppToast(context, "Couldn't update - try again", error: true);
    }
  }

  Future<void> _export(_MyCourses data, List<StudentAttendanceRecord> records, DateTime? joined) async {
    final format = await showDownloadFormatSheet(context, title: 'Export courses as');
    if (format == null || !mounted) return;
    final user = ref.read(sessionControllerProvider).user;
    final academy = user?.activeMembership?.academyName ?? '';
    final table = ReportTable(
      title: 'My Courses — ${user?.fullName ?? ''}',
      subtitle: academy,
      headers: const ['Course', 'Batch & Schedule', 'Enrolled since', 'Attendance'],
      rows: [
        for (final c in data.courses)
          () {
            final batches = data.batches.where((b) => b.courseId == c.id).toList();
            final marked = records.where((r) => r.courseId == c.id).toList();
            final present = marked.where((r) => r.status == AttendanceStatus.present).length;
            return [
              c.name,
              batches.map((b) => [b.name, _scheduleLine(b)].whereType<String>().join(' · ')).join('; '),
              joined == null ? '—' : formatFeeDate(joined),
              marked.isEmpty ? '—' : '${(present / marked.length * 100).round()}%',
            ];
          }(),
      ],
      fileStem: '${user?.fullName ?? 'student'}_courses',
      sheetName: 'Courses',
    );
    try {
      await shareReport(table, format);
      if (mounted) showAppToast(context, format == ReportFormat.pdf ? 'Courses PDF ready to save' : 'Excel file downloaded');
    } catch (_) {
      if (mounted) showAppToast(context, "Couldn't create the file", error: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final user = ref.watch(sessionControllerProvider).user;
    final mid = user?.activeMembership?.membershipId;
    final academy = user?.activeMembership?.academyName;
    final async = ref.watch(_myCoursesProvider);
    final attendance = mid == null ? null : ref.watch(studentAttendanceProvider(mid));
    final explore = ref.watch(_exploreProvider);
    final joined = ref
        .watch(selfProfileProvider)
        .valueOrNull
        ?.academies
        .where((a) => a.academyId == user?.activeMembership?.academyId)
        .firstOrNull
        ?.joiningDate;

    return Scaffold(
      backgroundColor: palette.bg,
      body: SafeArea(
        child: Column(children: [
          AppTopBar(title: 'My Courses', subtitle: user?.fullName, actions: kStudentTopBarActions),
          Expanded(
            child: AsyncValueView<_MyCourses>(
              value: async,
              onRetry: () => ref.invalidate(_myCoursesProvider),
              data: (context, data) {
                final records = attendance?.valueOrNull ?? const <StudentAttendanceRecord>[];
                final present = records.where((r) => r.status == AttendanceStatus.present).length;
                final avg = records.isEmpty ? 0.0 : present / records.length * 100;
                final exploreCount = explore.valueOrNull?.length ?? 0;
                return ListView(padding: const EdgeInsets.fromLTRB(20, 14, 20, 24), children: [
                  AcademyPill(name: academy ?? ''),
                  const SizedBox(height: 14),
                  GoldTabs<_Tab>(
                    options: _Tab.values,
                    labelOf: (t) => t == _Tab.enrolled ? 'Enrolled' : 'Explore',
                    badgeOf: (t) => t == _Tab.enrolled ? data.courses.length : exploreCount,
                    selected: _tab,
                    onTap: (t) => setState(() => _tab = t),
                  ),
                  const SizedBox(height: 14),
                  if (_tab == _Tab.explore)
                    ..._exploreList(explore)
                  else ...[
                    _summary(academy ?? 'your academy', data, avg, () => _export(data, records, joined)),
                    const SizedBox(height: 20),
                    Text('Your courses', style: TextStyle(fontWeight: AppType.heavy, fontSize: 13.5, color: palette.text)),
                    const SizedBox(height: 10),
                    if (data.courses.isEmpty)
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.symmetric(vertical: 22),
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          color: palette.surfaceRaised,
                          borderRadius: AppRadii.all(AppRadii.xl),
                          border: Border.all(color: palette.border),
                        ),
                        child: Text('No enrolments at this academy yet',
                            style: TextStyle(fontSize: 12, color: palette.textFaint)),
                      ),
                    for (final c in data.courses)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 12),
                        child: _CourseCard(
                          course: c,
                          batches: data.batches.where((b) => b.courseId == c.id).toList(),
                          records: records.where((r) => r.courseId == c.id).toList(),
                          joined: joined,
                        ),
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

  Widget _summary(String academy, _MyCourses data, double avg, VoidCallback onExport) {
    final palette = context.palette;
    final n = data.courses.length;
    final empty = n == 0;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: palette.surfaceRaised,
        borderRadius: AppRadii.all(AppRadii.x3l),
        border: Border.all(color: palette.border),
      ),
      child: Column(children: [
        Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Expanded(
            child: Text('Your courses at $academy',
                style: TextStyle(fontSize: 12.5, fontWeight: AppType.bold, color: palette.text)),
          ),
          const SizedBox(width: 8),
          Pressable(
            onTap: empty ? null : onExport,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 7),
              decoration: BoxDecoration(
                color: empty ? palette.surfaceHigh : palette.primary,
                borderRadius: AppRadii.all(AppRadii.md),
              ),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                Icon(Icons.download_outlined, size: 12, color: empty ? palette.textFaint : palette.onPrimary),
                const SizedBox(width: 5),
                Text('Export',
                    style: TextStyle(
                        fontSize: 10.5, fontWeight: AppType.bold, color: empty ? palette.textFaint : palette.onPrimary)),
              ]),
            ),
          ),
        ]),
        const SizedBox(height: 14),
        Row(children: [
          DonutChart(percent: avg, size: 64, strokeWidth: 7, color: palette.primary),
          const SizedBox(width: 14),
          Expanded(
            child: Column(children: [
              _kv('Enrolled courses', '$n', big: true),
              const SizedBox(height: 6),
              _kv('Average attendance', '${avg.round()}%'),
              const SizedBox(height: 4),
              Align(
                alignment: Alignment.centerLeft,
                child: Text(empty ? 'No active enrollments here yet' : 'Across ${data.batches.length} batch${data.batches.length == 1 ? '' : 'es'}',
                    style: TextStyle(fontSize: 9.5, color: palette.textFaint)),
              ),
            ]),
          ),
        ]),
      ]),
    );
  }

  Widget _kv(String k, String v, {bool big = false}) {
    final palette = context.palette;
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      crossAxisAlignment: CrossAxisAlignment.baseline,
      textBaseline: TextBaseline.alphabetic,
      children: [
        Text(k, style: TextStyle(fontSize: 10.5, fontWeight: AppType.semi, color: palette.textMuted)),
        Text(v, style: TextStyle(fontSize: big ? 15 : 12.5, fontWeight: big ? AppType.heavy : AppType.bold, color: palette.text)),
      ],
    );
  }

  List<Widget> _exploreList(AsyncValue<List<ExploreCourse>> async) {
    final palette = context.palette;
    return [
      Text('Other courses at this academy',
          style: TextStyle(fontWeight: AppType.heavy, fontSize: 13.5, color: palette.text)),
      const SizedBox(height: 10),
      ...async.when(
        loading: () => [const Center(child: Padding(padding: EdgeInsets.all(24), child: CircularProgressIndicator()))],
        error: (e, _) => [Text(e.toString().replaceFirst('Exception: ', ''), style: TextStyle(color: palette.textFaint))],
        data: (list) => list.isEmpty
            ? [
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(vertical: 22),
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: palette.surfaceRaised,
                    borderRadius: AppRadii.all(AppRadii.xl),
                    border: Border.all(color: palette.border),
                  ),
                  child: Text("You're already enrolled in everything on offer here",
                      style: TextStyle(fontSize: 12, color: palette.textFaint)),
                )
              ]
            : [
                for (final c in list)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: _exploreCard(c),
                  ),
              ],
      ),
    ];
  }

  Widget _exploreCard(ExploreCourse c) {
    final palette = context.palette;
    final meta = c.category.meta(palette);
    return Container(
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
            decoration: BoxDecoration(color: meta.soft, borderRadius: AppRadii.all(11)),
            child: Center(child: CourseIcon.forCourse(iconKey: c.iconKey, category: c.category, color: meta.color)),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(c.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontWeight: AppType.bold, fontSize: 13, color: palette.text)),
              const SizedBox(height: 2),
              Text(
                [
                  if ((c.trainerName ?? '').isNotEmpty) c.trainerName!,
                  c.category.label,
                  if ((c.durationLevel ?? '').isNotEmpty) c.durationLevel!,
                ].join(' · '),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 10.5, color: palette.textFaint),
              ),
            ]),
          ),
        ]),
        const SizedBox(height: 10),
        _DashedRule(color: palette.borderSoft),
        const SizedBox(height: 10),
        Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
          Expanded(
            child: Row(children: [
              Icon(Icons.schedule, size: 11, color: palette.textFaint),
              const SizedBox(width: 5),
              Flexible(
                child: Text(c.schedule ?? 'Schedule to be announced',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 10.5, color: palette.textFaint)),
              ),
            ]),
          ),
          const SizedBox(width: 8),
          Pressable(
            onTap: () => _toggle(c),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
              decoration: BoxDecoration(
                color: c.interested ? palette.primarySoft : palette.primary,
                borderRadius: AppRadii.all(AppRadii.md),
                border: c.interested ? Border.all(color: palette.primary) : null,
                boxShadow: c.interested
                    ? null
                    : [BoxShadow(color: palette.primary.withValues(alpha: 0.25), blurRadius: 16, offset: const Offset(0, 6))],
              ),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                if (c.interested) ...[
                  Icon(Icons.check, size: 12, color: palette.primary),
                  const SizedBox(width: 4),
                ],
                Text(c.interested ? 'Interested' : "I'm interested",
                    style: TextStyle(
                        fontSize: 11,
                        fontWeight: AppType.bold,
                        color: c.interested ? palette.primary : palette.onPrimary)),
              ]),
            ),
          ),
        ]),
      ]),
    );
  }
}

class _DashedRule extends StatelessWidget {
  const _DashedRule({required this.color});
  final Color color;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, c) {
      final count = (c.maxWidth / 6).floor();
      return Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [for (var i = 0; i < count; i++) Container(width: 3, height: 1, color: color)],
      );
    });
  }
}

class _CourseCard extends StatelessWidget {
  const _CourseCard({required this.course, required this.batches, required this.records, required this.joined});
  final Course course;
  final List<Batch> batches;
  final List<StudentAttendanceRecord> records;
  final DateTime? joined;

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
        : pct >= 85
            ? palette.paidManual
            : pct >= 70
                ? palette.partial
                : palette.notPaid;
    final pctSoft = pct == null
        ? palette.surfaceHigh
        : pct >= 85
            ? palette.paidManualSoft
            : pct >= 70
                ? palette.partialSoft
                : palette.notPaidSoft;
    final trainers = {for (final b in batches) ...b.trainers.map((t) => t.name)}.where((n) => n.isNotEmpty);
    final schedule = [for (final b in batches) _scheduleLine(b)].whereType<String>().toList();

    return Container(
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
            decoration: BoxDecoration(color: meta.soft, borderRadius: AppRadii.all(11)),
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
                  style: TextStyle(fontWeight: AppType.bold, fontSize: 13, color: palette.text)),
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
          if (pct != null) ...[
            const SizedBox(width: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(color: pctSoft, borderRadius: AppRadii.all(AppRadii.sm)),
              child: Text('${pct.round()}% present',
                  style: TextStyle(fontSize: 9.5, fontWeight: AppType.bold, color: pctColor)),
            ),
          ],
        ]),
        const SizedBox(height: 10),
        _DashedRule(color: palette.borderSoft),
        const SizedBox(height: 10),
        Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
          Expanded(
            child: Row(children: [
              Icon(Icons.schedule, size: 11, color: palette.textFaint),
              const SizedBox(width: 5),
              Flexible(
                child: Text(schedule.isEmpty ? 'No schedule set' : schedule.join('  |  '),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 10.5, color: palette.textFaint)),
              ),
            ]),
          ),
          const SizedBox(width: 8),
          Pressable(
            onTap: () => _showDetail(context),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              decoration: BoxDecoration(
                borderRadius: AppRadii.all(AppRadii.md),
                border: Border.all(color: palette.border),
              ),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                Text('View', style: TextStyle(fontSize: 11, fontWeight: AppType.bold, color: palette.textMuted)),
                const SizedBox(width: 4),
                Icon(Icons.chevron_right, size: 12, color: palette.textMuted),
              ]),
            ),
          ),
        ]),
      ]),
    );
  }

  void _showDetail(BuildContext context) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: context.palette.surface,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(22))),
      builder: (_) => _CourseDetail(course: course, batches: batches, records: records, joined: joined),
    );
  }
}

class _CourseDetail extends ConsumerStatefulWidget {
  const _CourseDetail({required this.course, required this.batches, required this.records, required this.joined});
  final Course course;
  final List<Batch> batches;
  final List<StudentAttendanceRecord> records;
  final DateTime? joined;

  @override
  ConsumerState<_CourseDetail> createState() => _CourseDetailState();
}

class _CourseDetailState extends ConsumerState<_CourseDetail> {
  bool _showLog = false;

  Widget _box(List<Widget> children, {EdgeInsets? padding}) {
    final palette = context.palette;
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(top: 12),
      padding: padding ?? const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: palette.surfaceHigh,
        borderRadius: AppRadii.all(AppRadii.xl),
        border: Border.all(color: palette.border),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: children),
    );
  }

  Widget _row(IconData icon, String k, String v) {
    final palette = context.palette;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Icon(icon, size: 13, color: palette.textFaint),
        const SizedBox(width: 8),
        Text(k, style: TextStyle(fontSize: 10.5, fontWeight: AppType.semi, color: palette.textFaint)),
        const SizedBox(width: 12),
        Expanded(
          child: Text(v,
              textAlign: TextAlign.right,
              style: TextStyle(fontSize: 11.5, fontWeight: AppType.bold, color: palette.text)),
        ),
      ]),
    );
  }

  Widget _closeTile(VoidCallback onTap, {IconData icon = Icons.close}) {
    final palette = context.palette;
    return Pressable(
      onTap: onTap,
      child: Container(
        width: 32,
        height: 32,
        decoration: BoxDecoration(
          color: palette.surfaceRaised,
          borderRadius: AppRadii.all(AppRadii.lg),
          border: Border.all(color: palette.border),
        ),
        child: Icon(icon, size: 15, color: palette.text),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final course = widget.course;
    final meta = course.category.meta(palette);
    final trainers = {for (final b in widget.batches) ...b.trainers.map((t) => t.name)}.where((n) => n.isNotEmpty).toList();
    final present = widget.records.where((r) => r.status == AttendanceStatus.present).length;
    final total = widget.records.length;
    final pct = total == 0 ? 0.0 : present / total * 100;
    final ringColor = pct >= 85 ? palette.paidManual : pct >= 70 ? palette.partial : palette.notPaid;
    final materials = ref.watch(materialBatchesProvider).valueOrNull ?? const <BatchMaterialSummary>[];
    final batchIds = widget.batches.map((b) => b.id).toSet();
    final fileCount = materials.where((m) => batchIds.contains(m.batchId)).fold<int>(0, (a, m) => a + m.fileCount);

    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.86,
      maxChildSize: 0.95,
      builder: (_, controller) => ListView(
        controller: controller,
        padding: const EdgeInsets.fromLTRB(18, 16, 18, 28),
        children: _showLog ? _log(palette, course) : _detail(palette, course, meta, trainers, pct, ringColor, present, total, fileCount),
      ),
    );
  }

  List<Widget> _detail(AppPalette palette, Course course, CategoryMeta meta, List<String> trainers, double pct,
      Color ringColor, int present, int total, int fileCount) {
    return [
      Row(children: [
        const SizedBox(width: 32),
        Expanded(
          child: Text(course.name,
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 15, fontWeight: AppType.heavy, color: palette.text)),
        ),
        _closeTile(() => Navigator.of(context).pop()),
      ]),
      const SizedBox(height: 12),
      Row(children: [
        _tag(course.category.label, meta.color, meta.soft),
        const SizedBox(width: 8),
        _tag(course.isActive ? 'Active' : 'Inactive', palette.paidManual, palette.paidManualSoft),
      ]),
      if ((course.description ?? '').isNotEmpty) ...[
        const SizedBox(height: 12),
        Text(course.description!, style: TextStyle(fontSize: 11.5, height: 1.5, color: palette.textMuted)),
      ],
      if (trainers.isNotEmpty)
        _box([
          for (final t in trainers)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 2),
              child: Row(children: [
                PersonAvatar(name: t, seed: t, size: 34),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text('Trainer', style: TextStyle(fontSize: 9.5, fontWeight: AppType.semi, color: palette.textFaint)),
                    Text(t,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(fontSize: 12.5, fontWeight: AppType.bold, color: palette.text)),
                  ]),
                ),
              ]),
            ),
        ]),
      if (widget.batches.isNotEmpty)
        _box([
          for (final b in widget.batches) ...[
            _row(Icons.layers_outlined, 'Batch', b.name),
            if (_scheduleLine(b) != null) _row(Icons.schedule, 'Schedule', _scheduleLine(b)!),
          ],
          if (widget.joined != null) _row(Icons.school_outlined, 'Enrolled since', formatFeeDate(widget.joined!)),
          if ((course.durationLevel ?? '').isNotEmpty) _row(Icons.timelapse, 'Duration', course.durationLevel!),
        ]),
      _box(_fees(palette, course)),
      _box(padding: const EdgeInsets.all(12), [
        Row(children: [
          DonutChart(percent: pct, size: 48, strokeWidth: 5, color: ringColor),
          const SizedBox(width: 14),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('$present/$total classes attended',
                  style: TextStyle(fontSize: 12, fontWeight: AppType.bold, color: palette.text)),
              const SizedBox(height: 1),
              Text('Since enrollment', style: TextStyle(fontSize: 9.5, color: palette.textFaint)),
            ]),
          ),
          Pressable(
            onTap: () => setState(() => _showLog = true),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              decoration: BoxDecoration(
                borderRadius: AppRadii.all(AppRadii.md),
                border: Border.all(color: palette.border),
              ),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                Text('Log', style: TextStyle(fontSize: 10.5, fontWeight: AppType.bold, color: palette.textMuted)),
                const SizedBox(width: 4),
                Icon(Icons.chevron_right, size: 12, color: palette.textMuted),
              ]),
            ),
          ),
        ]),
      ]),
      Pressable(
        onTap: () {
          Navigator.of(context).pop();
          context.push('/erp/study-materials');
        },
        child: Container(
          margin: const EdgeInsets.only(top: 12),
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: palette.surfaceHigh,
            borderRadius: AppRadii.all(AppRadii.xl),
            border: Border.all(color: palette.border),
          ),
          child: Row(children: [
            Container(
              width: 32,
              height: 32,
              decoration: BoxDecoration(color: palette.violetSoft, borderRadius: AppRadii.all(AppRadii.md)),
              child: Icon(Icons.description_outlined, size: 15, color: palette.violet),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('$fileCount study material${fileCount == 1 ? '' : 's'} shared',
                    style: TextStyle(fontSize: 12, fontWeight: AppType.bold, color: palette.text)),
                const SizedBox(height: 1),
                Text('Tap to open Study Material', style: TextStyle(fontSize: 9.5, color: palette.textFaint)),
              ]),
            ),
            Icon(Icons.chevron_right, size: 13, color: palette.textFaint),
          ]),
        ),
      ),
      const SizedBox(height: 12),
      Pressable(
        onTap: () => Navigator.of(context).pop(),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 12),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            borderRadius: AppRadii.all(13),
            border: Border.all(color: palette.border),
          ),
          child: Text('Close', style: TextStyle(fontSize: 13, fontWeight: AppType.bold, color: palette.text)),
        ),
      ),
    ];
  }

  Widget _tag(String label, Color color, Color soft) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(color: soft, borderRadius: AppRadii.all(AppRadii.sm)),
        child: Text(label, style: TextStyle(fontSize: 9.5, fontWeight: AppType.bold, color: color)),
      );

  /// The fee box: how the course bills, what a cycle costs, and when slips are issued and due.
  List<Widget> _fees(AppPalette palette, Course course) {
    final cycleMonths = course.feeCycle.months;
    final billing = switch (course.feeModel) {
      FeeModel.perClass => 'Per class',
      FeeModel.fixed => 'Fixed',
      FeeModel.hybrid => 'Hybrid',
    };
    final lines = <Widget>[
      Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
        Row(children: [
          Icon(Icons.account_balance_wallet_outlined, size: 13, color: palette.textFaint),
          const SizedBox(width: 6),
          Text('Fees', style: TextStyle(fontSize: 10.5, fontWeight: AppType.semi, color: palette.textFaint)),
        ]),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
          decoration: BoxDecoration(
            color: palette.surfaceRaised,
            borderRadius: AppRadii.all(AppRadii.sm),
            border: Border.all(color: palette.border),
          ),
          child: Text(billing, style: TextStyle(fontSize: 9.5, fontWeight: AppType.bold, color: palette.textMuted)),
        ),
      ]),
      const SizedBox(height: 8),
    ];
    if (course.feeModel == FeeModel.perClass) {
      lines.addAll([
        Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, crossAxisAlignment: CrossAxisAlignment.baseline, textBaseline: TextBaseline.alphabetic, children: [
          Text('Per class', style: TextStyle(fontSize: 11.5, fontWeight: AppType.semi, color: palette.textMuted)),
          Text(money(course.feePerClass ?? 0), style: TextStyle(fontSize: 15, fontWeight: AppType.heavy, color: palette.text)),
        ]),
        const SizedBox(height: 8),
        Text('Calculated from attendance — classes attended × fee per class.',
            style: TextStyle(fontSize: 10, height: 1.4, color: palette.textFaint)),
      ]);
    } else {
      lines.addAll([
        Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, crossAxisAlignment: CrossAxisAlignment.baseline, textBaseline: TextBaseline.alphabetic, children: [
          Text('Per ${course.feeCycle.label.toLowerCase()} cycle',
              style: TextStyle(fontSize: 11.5, fontWeight: AppType.semi, color: palette.textMuted)),
          Text(money((course.defaultFee ?? 0) * cycleMonths),
              style: TextStyle(fontSize: 15, fontWeight: AppType.heavy, color: palette.text)),
        ]),
        if (cycleMonths > 1) ...[
          const SizedBox(height: 4),
          Text('${money(course.defaultFee ?? 0)} per month × $cycleMonths months',
              style: TextStyle(fontSize: 10, color: palette.textFaint)),
        ],
        if (course.feeModel == FeeModel.hybrid && course.hybridThresholdAttendance != null) ...[
          const SizedBox(height: 8),
          Text(
            'Full fee if at least ${course.hybridThresholdAttendance} of ${course.hybridExpectedClassesPerPeriod ?? '-'} expected '
            'classes are attended — otherwise ${course.hybridFeeBelowThresholdPercent ?? 0}% of the fee applies.',
            style: TextStyle(fontSize: 10, height: 1.4, color: palette.textFaint),
          ),
        ],
      ]);
    }
    lines.addAll([
      const SizedBox(height: 6),
      Container(height: 1, color: palette.borderSoft),
      if (course.billingDayOfMonth != null) _row(Icons.calendar_today_outlined, 'Fee issued', '${ordinalDay(course.billingDayOfMonth!)} of cycle'),
      if (course.dueDayOfMonth != null) _row(Icons.schedule, 'Payment due', '${ordinalDay(course.dueDayOfMonth!)} of cycle'),
    ]);
    return lines;
  }

  /// The course's attendance, newest first - the prototype's "Log".
  List<Widget> _log(AppPalette palette, Course course) {
    final rows = [...widget.records]..sort((a, b) => b.date.compareTo(a.date));
    return [
      Row(children: [
        _closeTile(() => setState(() => _showLog = false), icon: Icons.arrow_back),
        const SizedBox(width: 12),
        Expanded(
          child: Text('${course.name} · Attendance',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: 14, fontWeight: AppType.heavy, color: palette.text)),
        ),
      ]),
      const SizedBox(height: 14),
      if (rows.isEmpty)
        Container(
          padding: const EdgeInsets.symmetric(vertical: 22),
          alignment: Alignment.center,
          child: Text('No classes marked yet', style: TextStyle(fontSize: 12, color: palette.textFaint)),
        ),
      for (final r in rows)
        Container(
          margin: const EdgeInsets.only(bottom: 8),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(
            color: palette.surfaceRaised,
            borderRadius: AppRadii.all(AppRadii.xl),
            border: Border.all(color: palette.border),
          ),
          child: Row(children: [
            Container(
              width: 32,
              height: 32,
              decoration: BoxDecoration(color: r.status.softColor(palette), borderRadius: AppRadii.all(AppRadii.md)),
              child: Icon(r.status == AttendanceStatus.present ? Icons.check_circle_outline : Icons.cancel_outlined,
                  size: 15, color: r.status.color(palette)),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(formatFeeDate(r.date), style: TextStyle(fontSize: 12, fontWeight: AppType.bold, color: palette.text)),
                const SizedBox(height: 2),
                Text(r.markedByName ?? r.note ?? '—', style: TextStyle(fontSize: 10, color: palette.textFaint)),
              ]),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(color: r.status.softColor(palette), borderRadius: AppRadii.all(AppRadii.sm)),
              child: Text(r.status.label, style: TextStyle(fontSize: 9.5, fontWeight: AppType.bold, color: r.status.color(palette))),
            ),
          ]),
        ),
    ];
  }
}
