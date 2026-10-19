import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:nest_fe/app/theme/app_tokens.dart';
import 'package:nest_fe/app/theme/app_typography.dart';
import 'package:nest_fe/core/auth/session_controller.dart';
import 'package:nest_fe/core/design/app_date_picker.dart';
import 'package:nest_fe/core/design/category_meta.dart';
import 'package:nest_fe/core/design/charts.dart';
import 'package:nest_fe/core/design/course_icons.dart';
import 'package:nest_fe/core/design/gold_tabs.dart';
import 'package:nest_fe/core/design/month_grid_calendar.dart';
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
import 'package:nest_fe/features/enrolment/data/batch.dart';
import 'package:nest_fe/features/enrolment/data/enrolment_api.dart';
import 'package:nest_fe/features/scheduling/data/scheduling_api.dart';

/// The academy's minimum attendance, as in the reference. Below this the student sees a warning.
const _minAttendancePct = 75;

enum _Tab { overview, calendar, history }

typedef _BatchInfo = ({String? courseId, String courseName, String batchName, String? trainer, Set<Weekday> days});

/// Every batch the student is IN - not just the ones that already have a marked class - so the
/// switcher offers all of them (a batch whose first class has not happened yet still belongs here).
final _myBatchesProvider = FutureProvider.autoDispose<Map<String, _BatchInfo>>((ref) async {
  final mid = ref.watch(activeMembershipIdProvider);
  if (mid == null) return {};
  final batches = await ref.watch(enrolmentApiProvider).batchesForMembership(mid);
  final courses = await ref.watch(curriculumApiProvider).listCoursesForMembership(mid);
  final names = {for (final c in courses) c.id: c.name};
  return {
    for (final b in batches)
      b.id: (
        courseId: b.courseId,
        courseName: names[b.courseId] ?? 'Course',
        batchName: b.name,
        trainer: b.trainers.isEmpty ? null : b.trainers.map((t) => t.name).where((n) => n.isNotEmpty).join(', '),
        days: b.days.toSet(),
      ),
  };
});

final _myCoursesMetaProvider = FutureProvider.autoDispose<List<Course>>((ref) async {
  final mid = ref.watch(activeMembershipIdProvider);
  if (mid == null) return const <Course>[];
  return ref.watch(curriculumApiProvider).listCoursesForMembership(mid);
});

enum _Filter { all, present, absent, holiday }

DateTime _dateOnly(DateTime d) => DateTime(d.year, d.month, d.day);

/// "7:45 PM" from a local time.
String _clock12(DateTime t) => formatTimeOfDay('${t.hour}:${t.minute}');

/// A student's OWN attendance: Overview / Calendar / History for one batch at a time.
///
/// This is the student's Attendance tab. The Trainer's marking screen is a different screen
/// ([AttendanceHomeScreen]) - a student never reaches it. Everything here reads the caller's own
/// membership only, so there is nothing to scope.
class StudentAttendanceHomeScreen extends ConsumerStatefulWidget {
  const StudentAttendanceHomeScreen({super.key});

  @override
  ConsumerState<StudentAttendanceHomeScreen> createState() => _State();
}

class _State extends ConsumerState<StudentAttendanceHomeScreen> {
  _Tab _tab = _Tab.overview;
  String? _batchId;
  DateTime _selectedDay = _dateOnly(DateTime.now());
  late DateTime _calMonth = DateTime(DateTime.now().year, DateTime.now().month);
  DateTime? _openDay;
  _Filter _filter = _Filter.all;
  DateTime _to = _dateOnly(DateTime.now());
  late DateTime _from = DateTime(_to.year, _to.month - 6, _to.day);

  @override
  Widget build(BuildContext context) {
    final membershipId = ref.watch(sessionControllerProvider).user?.activeMembership?.membershipId;
    final palette = context.palette;
    if (membershipId == null) return const SizedBox.shrink();
    final async = ref.watch(studentAttendanceWithHolidaysProvider(membershipId));

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 14, 20, 0),
          child: AcademyPill(name: ref.watch(sessionControllerProvider).user?.activeMembership?.academyName ?? ''),
        ),
        Expanded(
          child: AsyncValueView<List<StudentAttendanceRecord>>(
            value: async,
            onRetry: () => ref.invalidate(studentAttendanceWithHolidaysProvider(membershipId)),
            data: (context, all) {
              final info = <String, _BatchInfo>{
                ...?ref.watch(_myBatchesProvider).valueOrNull,
              };
              for (final r in all) {
                info.putIfAbsent(
                    r.batchId,
                    () => (
                          courseId: r.courseId,
                          courseName: r.courseName ?? 'Course',
                          batchName: r.batchName ?? 'Batch',
                          trainer: null,
                          days: <Weekday>{},
                        ));
              }
              if (info.isEmpty) {
                return Center(
                  child: Text('No classes have been marked for you yet',
                      style: TextStyle(color: palette.textFaint, fontSize: AppType.sm)),
                );
              }
              final batchId = info.containsKey(_batchId) ? _batchId! : info.keys.first;
              final records = all.where((r) => r.batchId == batchId).toList()
                ..sort((a, b) => b.date.compareTo(a.date));
              return RefreshIndicator(
                onRefresh: () async => ref.invalidate(studentAttendanceWithHolidaysProvider(membershipId)),
                child: ListView(
                  padding: const EdgeInsets.fromLTRB(20, 14, 20, 24),
                  children: [
                    _batchCard(info, batchId),
                    const SizedBox(height: 16),
                    GoldTabs<_Tab>(
                      options: _Tab.values,
                      labelOf: (t) => switch (t) {
                        _Tab.overview => 'Overview',
                        _Tab.calendar => 'Calendar',
                        _Tab.history => 'History',
                      },
                      selected: _tab,
                      onTap: (t) => setState(() => _tab = t),
                    ),
                    const SizedBox(height: 16),
                    switch (_tab) {
                      _Tab.overview => _overview(records),
                      _Tab.calendar => _calendar(records, info[batchId]!, batchId),
                      _Tab.history => _history(records, info[batchId]!),
                    },
                  ],
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  /// The reference's batch card: category icon, course name, "batch · trainer", and a Switch menu
  /// when the student is in more than one batch.
  Widget _batchCard(Map<String, _BatchInfo> infos, String batchId) {
    final palette = context.palette;
    final batch = infos[batchId]!;
    final courses = ref.watch(_myCoursesMetaProvider).valueOrNull ?? const <Course>[];
    final course = courses.where((c) => c.id == batch.courseId).firstOrNull;
    final meta = course == null
        ? CategoryMeta(color: palette.gold, soft: palette.goldSoft, dim: palette.goldDim)
        : course.category.meta(palette);
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: palette.surfaceRaised,
        borderRadius: AppRadii.all(AppRadii.xxl),
        border: Border.all(color: palette.border),
      ),
      child: Row(children: [
        Container(
          width: 38,
          height: 38,
          decoration: BoxDecoration(color: meta.soft, borderRadius: AppRadii.all(11)),
          child: Center(
            child: course == null
                ? Icon(Icons.music_note_outlined, size: 17, color: meta.color)
                : CourseIcon.forCourse(iconKey: course.iconKey, category: course.category, color: meta.color),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(batch.courseName,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 13, fontWeight: AppType.bold, color: palette.text)),
            const SizedBox(height: 2),
            Text([batch.batchName, if ((batch.trainer ?? '').isNotEmpty) batch.trainer!].join(' · '),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 10.5, color: palette.textFaint)),
          ]),
        ),
        if (infos.length > 1)
          PopupMenuButton<String>(
            tooltip: 'Switch batch',
            color: palette.surface,
            elevation: 8,
            padding: EdgeInsets.zero,
            offset: const Offset(0, 40),
            shape: RoundedRectangleBorder(
                borderRadius: AppRadii.all(AppRadii.xl), side: BorderSide(color: palette.border)),
            onSelected: (id) => setState(() {
              _batchId = id;
              _openDay = null;
              _filter = _Filter.all;
            }),
            itemBuilder: (_) => [
              for (final e in infos.entries)
                PopupMenuItem(
                  value: e.key,
                  child: Row(children: [
                    Expanded(
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text(e.value.courseName,
                            style: TextStyle(
                                fontSize: 12.5,
                                fontWeight: e.key == batchId ? AppType.bold : AppType.regular,
                                color: e.key == batchId ? palette.gold : palette.text)),
                        Text(e.value.batchName, style: TextStyle(fontSize: 10, color: palette.textFaint)),
                      ]),
                    ),
                    if (e.key == batchId) Icon(Icons.check, size: 14, color: palette.gold),
                  ]),
                ),
            ],
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 7),
              decoration: BoxDecoration(
                color: palette.surfaceHigh,
                borderRadius: AppRadii.all(AppRadii.md),
                border: Border.all(color: palette.border),
              ),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                Text('Switch', style: TextStyle(fontSize: 10.5, fontWeight: AppType.bold, color: palette.textMuted)),
                const SizedBox(width: 4),
                Icon(Icons.expand_more, size: 12, color: palette.textFaint),
              ]),
            ),
          ),
      ]),
    );
  }

  /// Holidays are days off: they count towards neither side.
  ({int present, int absent, int denom, double pct}) _stats(List<StudentAttendanceRecord> r) {
    final present = r.where((e) => e.status == AttendanceStatus.present).length;
    final absent = r.where((e) => e.status == AttendanceStatus.absent).length;
    final denom = present + absent;
    return (present: present, absent: absent, denom: denom, pct: denom > 0 ? present / denom * 100 : 100);
  }

  Widget _overview(List<StudentAttendanceRecord> records) {
    final palette = context.palette;
    final s = _stats(records);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _card(
          Row(children: [
            DonutChart(
              percent: s.pct,
              size: 64,
              strokeWidth: 7,
              color: s.pct >= _minAttendancePct ? palette.paidManual : palette.notPaid,
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(children: [
                _legend('Present', s.present, palette.paidManual),
                const SizedBox(height: 6),
                _legend('Absent', s.absent, palette.notPaid),
              ]),
            ),
          ]),
        ),
        if (s.pct < _minAttendancePct) ...[
          const SizedBox(height: 16),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: palette.notPaidSoft,
              borderRadius: AppRadii.all(AppRadii.xl),
              border: Border.all(color: palette.notPaid.withValues(alpha: 0.27)),
            ),
            child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Icon(Icons.warning_amber_rounded, size: 16, color: palette.notPaid),
              const SizedBox(width: 10),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text('Attendance below requirement',
                      style: TextStyle(fontWeight: AppType.bold, fontSize: 12, color: palette.notPaid)),
                  const SizedBox(height: 2),
                  Text(
                    'Your attendance is ${s.pct.round()}%, under the $_minAttendancePct% minimum. '
                    "Reach out to your trainer if you think there's an error.",
                    style: TextStyle(fontSize: 10.5, height: 1.4, color: palette.textMuted),
                  ),
                ]),
              ),
            ]),
          ),
        ],
        const SizedBox(height: 16),
        Text('Recent classes', style: TextStyle(fontWeight: AppType.heavy, fontSize: 13.5, color: palette.text)),
        const SizedBox(height: 10),
        _rows(records.take(5).toList(), 'No classes yet'),
      ],
    );
  }

  Widget _legend(String label, int value, Color color) => Row(children: [
        Container(width: 7, height: 7, decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
        const SizedBox(width: 6),
        Expanded(child: Text(label, style: TextStyle(fontSize: 10.5, fontWeight: AppType.semi, color: context.palette.textMuted))),
        Text('$value', style: TextStyle(fontWeight: AppType.bold, fontSize: 12, color: context.palette.text)),
      ]);

  Widget _card(Widget child) {
    final palette = context.palette;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: palette.surfaceRaised,
        borderRadius: AppRadii.all(AppRadii.x3l),
        border: Border.all(color: palette.border),
      ),
      child: child,
    );
  }

  /// Rows grouped under a month rule, each with its status badge. The line under the date is the
  /// note (a holiday's reason) or who marked it.
  Widget _rows(List<StudentAttendanceRecord> list, String empty) {
    final palette = context.palette;
    if (list.isEmpty) {
      return Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(vertical: 22, horizontal: 10),
        decoration: BoxDecoration(
          color: palette.surfaceRaised,
          borderRadius: AppRadii.all(AppRadii.xl),
          border: Border.all(color: palette.border),
        ),
        child: Text(empty, textAlign: TextAlign.center, style: TextStyle(fontSize: 12, color: palette.textFaint)),
      );
    }
    String? lastMonth;
    final out = <Widget>[];
    for (final r in list) {
      final key = '${monthsFull[r.date.month - 1]} ${r.date.year}';
      if (key != lastMonth) {
        out.add(Padding(
          padding: const EdgeInsets.fromLTRB(2, 6, 2, 0),
          child: Row(children: [
            Text(key.toUpperCase(),
                style: TextStyle(fontSize: 9.5, fontWeight: AppType.bold, letterSpacing: 0.5, color: palette.textFaint)),
            const SizedBox(width: 8),
            Expanded(child: Container(height: 1, color: palette.borderSoft)),
          ]),
        ));
        lastMonth = key;
      }
      out.add(Padding(padding: const EdgeInsets.only(top: 8), child: _row(r)));
    }
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: out);
  }

  IconData _statusIcon(AttendanceStatus s) => switch (s) {
        AttendanceStatus.present => Icons.check_circle_outline,
        AttendanceStatus.absent => Icons.cancel_outlined,
        AttendanceStatus.holiday => Icons.calendar_today_outlined,
      };

  Widget _row(StudentAttendanceRecord r) {
    final palette = context.palette;
    return Container(
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
          child: Icon(_statusIcon(r.status), size: 15, color: r.status.color(palette)),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(formatFeeDate(r.date), style: TextStyle(fontWeight: AppType.bold, fontSize: 12, color: palette.text)),
            const SizedBox(height: 2),
            Text(r.note ?? r.markedByName ?? '—', style: TextStyle(fontSize: 10, color: palette.textFaint)),
          ]),
        ),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
          decoration: BoxDecoration(color: r.status.softColor(palette), borderRadius: AppRadii.all(AppRadii.sm)),
          child: Text(r.status.label,
              style: TextStyle(fontSize: 9.5, fontWeight: AppType.bold, color: r.status.color(palette))),
        ),
      ]),
    );
  }

  Widget _calendar(List<StudentAttendanceRecord> records, _BatchInfo batch, String batchId) {
    final palette = context.palette;
    final byDay = {for (final r in records) _dateOnly(r.date): r};
    final today = _dateOnly(DateTime.now());

    // The days a class is actually on, from the schedule for the month being looked at - which keeps
    // a batch whose weekdays changed part-way through showing the right days for each month. Until it
    // loads (or if it fails) the batch's current weekdays stand in.
    final feed = ref.watch(scheduleFeedProvider((
      from: DateTime(_calMonth.year, _calMonth.month, 1),
      to: DateTime(_calMonth.year, _calMonth.month + 1, 0),
      courseId: null,
    ))).valueOrNull;
    final classDays = feed == null
        ? null
        : {
            for (final e in feed)
              if (e.batchId == batchId && !e.status.isGhost) _dateOnly(e.date),
          };

    MonthCell cellFor(DateTime day) {
      final rec = byDay[day];
      final scheduled = classDays != null && day.year == _calMonth.year && day.month == _calMonth.month
          ? classDays.contains(day) || rec != null
          : batch.days.contains(Weekday.of(day));
      final isSelected = day == _selectedDay;
      final isToday = day == today;
      final isOpen = day == _openDay;
      return MonthCell(
        background: rec?.status.softColor(palette),
        borderColor: isOpen || (isToday && !isSelected)
            ? palette.gold
            : scheduled && rec == null
                ? palette.border
                : null,
        dashed: !(isOpen || (isToday && !isSelected)) && scheduled && rec == null,
        textColor: rec != null
            ? rec.status.color(palette)
            : isToday
                ? palette.gold
                : scheduled
                    ? palette.textFaint
                    : palette.text,
        bold: rec != null || isToday,
        opacity: scheduled ? 1 : 0.55,
        tappable: scheduled,
      );
    }

    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text('${batch.courseName} · ${batch.batchName}', style: TextStyle(fontSize: 11, color: palette.textFaint)),
      const SizedBox(height: 14),
      Wrap(spacing: 10, runSpacing: 4, children: [
        for (final s in AttendanceStatus.values) _legend2(s.label, s.color(palette)),
      ]),
      const SizedBox(height: 14),
      _card(MonthGridCalendar(
        initialMonth: _calMonth,
        onMonthChanged: (m) => setState(() {
          _calMonth = DateTime(m.year, m.month);
          _openDay = null;
        }),
        titleSize: 14.5,
        cellFor: cellFor,
        expandedDay: _openDay,
        expandedBuilder: (day) => _dayDetail(byDay[day]!),
        onDayTap: (day) => setState(() {
          _selectedDay = day;
          _openDay = byDay[day] == null ? null : (_openDay == day ? null : day);
        }),
      )),
    ]);
  }

  Widget _legend2(String l, Color c) => Row(mainAxisSize: MainAxisSize.min, children: [
        Container(width: 7, height: 7, decoration: BoxDecoration(color: c, shape: BoxShape.circle)),
        const SizedBox(width: 4),
        Text(l, style: TextStyle(fontSize: 9.5, fontWeight: AppType.semi, color: context.palette.textMuted)),
      ]);

  /// The panel under a tapped day: who marked it and when, or the holiday's reason.
  Widget _dayDetail(StudentAttendanceRecord r) {
    final palette = context.palette;
    final detail = r.note ??
        (r.markedByName != null
            ? 'Marked by ${r.markedByName}${r.markedAt != null ? ' · ${_clock12(r.markedAt!)}' : ''}'
            : 'No details');
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 4),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: palette.surfaceHigh,
        borderRadius: AppRadii.all(AppRadii.lg),
        border: Border.all(color: palette.border),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
          Text(formatFeeDate(r.date).toUpperCase(),
              style: TextStyle(fontSize: 10.5, fontWeight: AppType.bold, letterSpacing: 0.4, color: palette.textMuted)),
          Pressable(
            onTap: () => setState(() => _openDay = null),
            child: Container(
              width: 22,
              height: 22,
              decoration: BoxDecoration(
                color: palette.bg,
                borderRadius: AppRadii.all(7),
                border: Border.all(color: palette.border),
              ),
              child: Icon(Icons.close, size: 11, color: palette.textMuted),
            ),
          ),
        ]),
        const SizedBox(height: 8),
        Row(children: [
          Container(
            width: 34,
            height: 34,
            decoration: BoxDecoration(color: r.status.softColor(palette), borderRadius: AppRadii.all(AppRadii.md)),
            child: Icon(_statusIcon(r.status), size: 16, color: r.status.color(palette)),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(r.status.label,
                  style: TextStyle(fontSize: 12.5, fontWeight: AppType.bold, color: r.status.color(palette))),
              const SizedBox(height: 1),
              Text(detail, style: TextStyle(fontSize: 10.5, color: palette.textFaint)),
            ]),
          ),
        ]),
      ]),
    );
  }

  Widget _history(List<StudentAttendanceRecord> records, _BatchInfo batch) {
    final palette = context.palette;
    final inRange = records.where((r) => !r.date.isBefore(_from) && !r.date.isAfter(_to)).toList();
    final s = _stats(inRange);
    final shown = switch (_filter) {
      _Filter.all => inRange,
      _Filter.present => inRange.where((r) => r.status == AttendanceStatus.present).toList(),
      _Filter.absent => inRange.where((r) => r.status == AttendanceStatus.absent).toList(),
      _Filter.holiday => inRange.where((r) => r.status == AttendanceStatus.holiday).toList(),
    };

    Widget dateButton(String label, DateTime v, ValueChanged<DateTime> onPick, {DateTime? min, DateTime? max}) {
      return Expanded(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(label, style: TextStyle(fontSize: 10, fontWeight: AppType.semi, color: palette.textMuted)),
          const SizedBox(height: 4),
          Pressable(
            onTap: () async {
              final picked = await showAppDatePicker(
                  context: context, title: 'History $label'.toLowerCase(), value: v, minDate: min, maxDate: max);
              if (picked != null) onPick(_dateOnly(picked));
            },
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
              decoration: BoxDecoration(
                color: palette.surfaceRaised,
                borderRadius: AppRadii.all(AppRadii.md),
                border: Border.all(color: palette.border),
              ),
              child: Row(children: [
                Icon(Icons.calendar_today_outlined, size: 13, color: palette.textFaint),
                const SizedBox(width: 6),
                Text(formatFeeDate(v), style: TextStyle(fontSize: 12, fontWeight: AppType.semi, color: palette.text)),
              ]),
            ),
          ),
        ]),
      );
    }

    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(children: [
        dateButton('From', _from, (d) => _setFrom(d), max: _to),
        const SizedBox(width: 8),
        dateButton('To', _to, (d) => _setTo(d), min: _from, max: DateTime.now()),
      ]),
      const SizedBox(height: 8),
      Text('History can cover up to a 6-month range', style: TextStyle(fontSize: 9.5, color: palette.textFaint)),
      const SizedBox(height: 14),
      Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: palette.surfaceRaised,
          borderRadius: AppRadii.all(AppRadii.xl),
          border: Border.all(color: palette.border),
        ),
        child: Row(children: [
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('${s.denom} class${s.denom == 1 ? '' : 'es'} counted',
                  style: TextStyle(fontSize: 10.5, fontWeight: AppType.semi, color: palette.textMuted)),
              const SizedBox(height: 2),
              Text('${s.pct.round()}% attendance',
                  style: TextStyle(
                      fontSize: 16,
                      fontWeight: AppType.heavy,
                      color: s.pct >= _minAttendancePct ? palette.text : palette.notPaid)),
            ]),
          ),
          Pressable(
            onTap: shown.isEmpty ? null : () => _download(shown, batch, s.pct),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: BoxDecoration(
                color: shown.isEmpty ? palette.surfaceHigh : palette.primary,
                borderRadius: AppRadii.all(11),
              ),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                Icon(Icons.download_outlined, size: 14, color: shown.isEmpty ? palette.textFaint : palette.onPrimary),
                const SizedBox(width: 6),
                Text('Download',
                    style: TextStyle(
                        fontSize: 11.5,
                        fontWeight: AppType.bold,
                        color: shown.isEmpty ? palette.textFaint : palette.onPrimary)),
              ]),
            ),
          ),
        ]),
      ),
      const SizedBox(height: 14),
      SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(children: [
          for (final f in _Filter.values)
            Padding(
              padding: const EdgeInsets.only(right: 6),
              child: Pressable(
                onTap: () => setState(() => _filter = f),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
                  decoration: BoxDecoration(
                    color: _filter == f ? palette.gold : palette.surfaceRaised,
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: _filter == f ? palette.gold : palette.border),
                  ),
                  child: Text(f.name[0].toUpperCase() + f.name.substring(1),
                      style: TextStyle(
                          fontSize: 11,
                          fontWeight: AppType.bold,
                          color: _filter == f ? Colors.white : palette.textMuted)),
                ),
              ),
            ),
        ]),
      ),
      const SizedBox(height: 14),
      _rows(shown, 'No records match this filter'),
    ]);
  }

  void _setFrom(DateTime d) {
    setState(() {
      final from = d.isAfter(_to) ? _to : d;
      final limit = DateTime(_to.year, _to.month - 6, _to.day);
      if (from.isBefore(limit)) {
        // Whichever end the user just moved drags the other along rather than rejecting the pick.
        _from = from;
        _to = DateTime(from.year, from.month + 6, from.day);
        if (_to.isAfter(DateTime.now())) _to = _dateOnly(DateTime.now());
        showAppToast(context, 'History is limited to a 6-month range');
      } else {
        _from = from;
      }
    });
  }

  void _setTo(DateTime d) {
    setState(() {
      _to = d.isBefore(_from) ? _from : d;
      final limit = DateTime(_to.year, _to.month - 6, _to.day);
      if (_from.isBefore(limit)) {
        _from = limit;
        showAppToast(context, 'History is limited to a 6-month range');
      }
    });
  }

  /// The rows on screen - exactly the current range and filter - as a PDF or an Excel sheet, so the
  /// file matches what the student was looking at.
  Future<void> _download(List<StudentAttendanceRecord> rows, _BatchInfo batch, double pct) async {
    final format = await showDownloadFormatSheet(context, title: 'Download attendance as');
    if (format == null || !mounted) return;
    final user = ref.read(sessionControllerProvider).user;
    final academy = user?.activeMembership?.academyName ?? '';
    final table = ReportTable(
      title: 'Attendance History — ${user?.fullName ?? ''}',
      subtitle: '${batch.courseName} · ${batch.batchName} · $academy · ${formatFeeDate(_from)} – ${formatFeeDate(_to)}',
      headers: const ['Date', 'Course', 'Batch', 'Status', 'Marked by'],
      rows: [
        for (final r in rows)
          [formatFeeDate(r.date), batch.courseName, batch.batchName, r.status.label, r.markedByName ?? r.note ?? '—'],
      ],
      totalLabel: 'Attendance in range',
      totalValue: '${pct.round()}%',
      fileStem: '${user?.fullName ?? 'student'}_attendance_${_from.toIso8601String().substring(0, 10)}_to_${_to.toIso8601String().substring(0, 10)}',
      sheetName: 'Attendance',
    );
    try {
      await shareReport(table, format);
      if (mounted) {
        showAppToast(context, format == ReportFormat.pdf ? 'Attendance PDF ready to save' : 'Excel attendance file downloaded');
      }
    } catch (_) {
      if (mounted) {
        showAppToast(context, format == ReportFormat.pdf ? "Couldn't create the PDF" : "Couldn't generate the Excel file",
            error: true);
      }
    }
  }
}
