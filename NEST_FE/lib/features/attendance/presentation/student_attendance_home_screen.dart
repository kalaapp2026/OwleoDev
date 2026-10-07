import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:nest_fe/app/theme/app_tokens.dart';
import 'package:nest_fe/app/theme/app_typography.dart';
import 'package:nest_fe/core/auth/session_controller.dart';
import 'package:nest_fe/core/design/app_date_picker.dart';
import 'package:nest_fe/core/providers/core_providers.dart';
import 'package:nest_fe/core/design/charts.dart';
import 'package:nest_fe/core/design/gold_tabs.dart';
import 'package:nest_fe/core/design/category_meta.dart';
import 'package:nest_fe/core/design/course_icons.dart';
import 'package:nest_fe/features/curriculum/data/course.dart';
import 'package:nest_fe/features/curriculum/data/curriculum_api.dart';
import 'package:nest_fe/features/enrolment/data/enrolment_api.dart';
import 'package:nest_fe/core/design/status_badge.dart';
import 'package:nest_fe/core/format/money.dart';
import 'package:nest_fe/core/widgets/async_value_view.dart';
import 'package:nest_fe/features/attendance/data/attendance_api.dart';
import 'package:nest_fe/features/attendance/data/student_attendance.dart';
import 'package:share_plus/share_plus.dart';

/// The academy's minimum attendance, as in the reference. Below this the student sees a warning.
const _minAttendancePct = 75;

enum _Tab { overview, calendar, history }

typedef _BatchInfo = ({String? courseId, String courseName, String batchName});

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
      b.id: (courseId: b.courseId, courseName: names[b.courseId] ?? 'Course', batchName: b.name),
  };
});

final _myCoursesMetaProvider = FutureProvider.autoDispose<List<Course>>((ref) async {
  final mid = ref.watch(activeMembershipIdProvider);
  if (mid == null) return const <Course>[];
  return ref.watch(curriculumApiProvider).listCoursesForMembership(mid);
});

enum _Filter { all, present, absent }

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
  DateTime _month = DateTime(DateTime.now().year, DateTime.now().month);
  DateTime? _selectedDay;
  _Filter _filter = _Filter.all;
  DateTime _to = _dateOnly(DateTime.now());
  late DateTime _from = DateTime(_to.year, _to.month - 6, _to.day);

  static DateTime _dateOnly(DateTime d) => DateTime(d.year, d.month, d.day);

  @override
  Widget build(BuildContext context) {
    final membershipId = ref.watch(sessionControllerProvider).user?.activeMembership?.membershipId;
    final palette = context.palette;
    if (membershipId == null) return const SizedBox.shrink();
    final async = ref.watch(studentAttendanceProvider(membershipId));

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 14, 20, 0),
          child: AcademyPill(name: ref.watch(sessionControllerProvider).user?.activeMembership?.academyName ?? ''),
        ),
        Expanded(
          child: AsyncValueView<List<StudentAttendanceRecord>>(
            value: async,
            onRetry: () => ref.invalidate(studentAttendanceProvider(membershipId)),
            data: (context, all) {
              final info = <String, _BatchInfo>{
                ...?ref.watch(_myBatchesProvider).valueOrNull,
              };
              for (final r in all) {
                info.putIfAbsent(
                    r.batchId,
                    () => (courseId: r.courseId, courseName: r.courseName ?? 'Course', batchName: r.batchName ?? 'Batch'));
              }
              final batches = {for (final e in info.entries) e.key: '${e.value.courseName} · ${e.value.batchName}'};
              if (batches.isEmpty) {
                return Center(
                  child: Text('No classes have been marked for you yet',
                      style: TextStyle(color: palette.textFaint, fontSize: AppType.sm)),
                );
              }
              final batchId = batches.containsKey(_batchId) ? _batchId! : batches.keys.first;
              final records = all.where((r) => r.batchId == batchId).toList()
                ..sort((a, b) => b.date.compareTo(a.date));
              return RefreshIndicator(
                onRefresh: () async => ref.invalidate(studentAttendanceProvider(membershipId)),
                child: ListView(
                  padding: const EdgeInsets.fromLTRB(20, 14, 20, 24),
                  children: [
                    _batchCard(batches, batchId, info[batchId]!),
                    const SizedBox(height: 14),
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
                      _Tab.calendar => _calendar(records),
                      _Tab.history => _history(records),
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

  /// "20:00:00" -> "8:00 PM".
  static String _clock(String t) {
    final parts = t.split(':');
    if (parts.length < 2) return t;
    final h = int.tryParse(parts[0]) ?? 0;
    return '${h % 12 == 0 ? 12 : h % 12}:${parts[1]} ${h >= 12 ? 'PM' : 'AM'}';
  }

  /// The reference's batch card: category icon, course name, batch, and a Switch menu when the
  /// student is in more than one batch.
  Widget _batchCard(Map<String, String> batches, String batchId, _BatchInfo batch) {
    final palette = context.palette;
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
          decoration: BoxDecoration(color: meta.soft, borderRadius: AppRadii.all(AppRadii.lg)),
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
                style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: palette.text)),
            const SizedBox(height: 2),
            Text(batch.batchName, style: TextStyle(fontSize: 10.5, color: palette.textFaint)),
          ]),
        ),
        if (batches.length > 1)
          PopupMenuButton<String>(
            tooltip: 'Switch batch',
            onSelected: (id) => setState(() {
              _batchId = id;
              _selectedDay = null;
            }),
            itemBuilder: (_) => [
              for (final e in batches.entries)
                PopupMenuItem(
                  value: e.key,
                  child: Text(e.value, style: TextStyle(fontWeight: e.key == batchId ? FontWeight.w700 : FontWeight.w500)),
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
                Text('Switch', style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.w700, color: palette.textMuted)),
                Icon(Icons.expand_more, size: 13, color: palette.textFaint),
              ]),
            ),
          ),
      ]),
    );
  }

  ({int present, int absent, double pct}) _stats(List<StudentAttendanceRecord> r) {
    final present = r.where((e) => e.status == AttendanceStatus.present).length;
    final absent = r.length - present;
    return (present: present, absent: absent, pct: r.isEmpty ? 100 : present / r.length * 100);
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
                      style: TextStyle(fontWeight: FontWeight.w700, fontSize: 12, color: palette.notPaid)),
                  const SizedBox(height: 2),
                  Text(
                    'Your attendance is ${s.pct.round()}%, under the $_minAttendancePct% minimum. '
                    "Reach out to your trainer if you think there's an error.",
                    style: TextStyle(fontSize: 10.5, color: palette.textMuted),
                  ),
                ]),
              ),
            ]),
          ),
        ],
        const SizedBox(height: 20),
        Text('Recent classes', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 13.5, color: palette.text)),
        const SizedBox(height: 10),
        ..._rows(records.take(5).toList(), 'No classes yet'),
      ],
    );
  }

  Widget _legend(String label, int value, Color color) => Row(children: [
        Container(width: 7, height: 7, decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
        const SizedBox(width: 6),
        Expanded(child: Text(label, style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.w600, color: context.palette.textMuted))),
        Text('$value', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 12, color: context.palette.text)),
      ]);

  Widget _card(Widget child) {
    final palette = context.palette;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: palette.surfaceRaised,
        borderRadius: AppRadii.all(AppRadii.xxl),
        border: Border.all(color: palette.border),
      ),
      child: child,
    );
  }

  List<Widget> _rows(List<StudentAttendanceRecord> list, String empty) {
    final palette = context.palette;
    if (list.isEmpty) {
      return [
        Container(
          padding: const EdgeInsets.symmetric(vertical: 22),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: palette.surfaceRaised,
            borderRadius: AppRadii.all(AppRadii.xl),
            border: Border.all(color: palette.border),
          ),
          child: Text(empty, style: TextStyle(fontSize: 12, color: palette.textFaint)),
        ),
      ];
    }
    String? lastMonth;
    final out = <Widget>[];
    for (final r in list) {
      final key = '${monthsFull[r.date.month - 1]} ${r.date.year}';
      if (key != lastMonth) {
        out.add(Padding(
          padding: const EdgeInsets.only(top: 6, bottom: 6),
          child: Text(key.toUpperCase(),
              style: TextStyle(fontSize: 9.5, fontWeight: FontWeight.w700, letterSpacing: 0.5, color: palette.textFaint)),
        ));
        lastMonth = key;
      }
      final present = r.status == AttendanceStatus.present;
      out.add(Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Container(
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
              child: Icon(present ? Icons.check_circle_outline : Icons.cancel_outlined, size: 15, color: r.status.color(palette)),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(formatFeeDate(r.date), style: TextStyle(fontWeight: FontWeight.w700, fontSize: 12, color: palette.text)),
                const SizedBox(height: 2),
                Text(r.note ?? '${_clock(r.startTime)}–${_clock(r.endTime)}', style: TextStyle(fontSize: 10, color: palette.textFaint)),
              ]),
            ),
            StatusBadge(label: r.status.label, color: r.status.color(palette), softColor: r.status.softColor(palette), dense: true),
          ]),
        ),
      ));
    }
    return out;
  }

  Widget _calendar(List<StudentAttendanceRecord> records) {
    final palette = context.palette;
    final byDay = <String, StudentAttendanceRecord>{};
    for (final r in records) {
      byDay['${r.date.year}-${r.date.month}-${r.date.day}'] = r;
    }
    final first = DateTime(_month.year, _month.month, 1);
    final days = DateTime(_month.year, _month.month + 1, 0).day;
    final lead = first.weekday % 7; // Sunday first, as in the reference.
    final cells = <Widget>[
      for (final d in const ['S', 'M', 'T', 'W', 'T', 'F', 'S'])
        Center(child: Text(d, style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.w700, color: palette.textFaint))),
      for (var i = 0; i < lead; i++) const SizedBox.shrink(),
      for (var d = 1; d <= days; d++) _dayCell(DateTime(_month.year, _month.month, d), byDay),
    ];
    final selected = _selectedDay == null
        ? null
        : byDay['${_selectedDay!.year}-${_selectedDay!.month}-${_selectedDay!.day}'];
    return Column(children: [
      Row(children: [
        IconButton(
            onPressed: () => setState(() => _month = DateTime(_month.year, _month.month - 1)),
            icon: const Icon(Icons.chevron_left)),
        Expanded(
          child: Center(
            child: Text('${monthsFull[_month.month - 1]} ${_month.year}',
                style: TextStyle(fontWeight: FontWeight.w800, fontSize: 14.5, color: palette.text)),
          ),
        ),
        IconButton(
            onPressed: () => setState(() => _month = DateTime(_month.year, _month.month + 1)),
            icon: const Icon(Icons.chevron_right)),
      ]),
      _card(GridView.count(
        crossAxisCount: 7,
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        mainAxisSpacing: 4,
        crossAxisSpacing: 4,
        children: cells,
      )),
      if (selected != null) ...[const SizedBox(height: 12), ..._rows([selected], '')],
      const SizedBox(height: 12),
      Wrap(spacing: 14, children: [
        _legend2('Present', palette.paidManual),
        _legend2('Absent', palette.notPaid),
      ]),
    ]);
  }

  Widget _legend2(String l, Color c) => Row(mainAxisSize: MainAxisSize.min, children: [
        Container(width: 7, height: 7, decoration: BoxDecoration(color: c, shape: BoxShape.circle)),
        const SizedBox(width: 4),
        Text(l, style: TextStyle(fontSize: 9.5, fontWeight: FontWeight.w600, color: context.palette.textMuted)),
      ]);

  Widget _dayCell(DateTime d, Map<String, StudentAttendanceRecord> byDay) {
    final palette = context.palette;
    final rec = byDay['${d.year}-${d.month}-${d.day}'];
    final isToday = _dateOnly(DateTime.now()) == d;
    final selected = _selectedDay == d;
    return GestureDetector(
      onTap: rec == null ? null : () => setState(() => _selectedDay = selected ? null : d),
      child: Container(
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: rec?.status.softColor(palette),
          borderRadius: AppRadii.all(AppRadii.md),
          border: selected || (isToday && rec == null)
              ? Border.all(color: palette.gold, width: 1.5)
              : null,
        ),
        child: Text('${d.day}',
            style: TextStyle(
              fontSize: 12.5,
              fontWeight: rec != null || isToday ? FontWeight.w800 : FontWeight.w500,
              color: rec?.status.color(palette) ?? (isToday ? palette.gold : palette.text),
            )),
      ),
    );
  }

  Widget _history(List<StudentAttendanceRecord> records) {
    final palette = context.palette;
    final inRange = records
        .where((r) => !r.date.isBefore(_from) && !r.date.isAfter(_to))
        .toList();
    final s = _stats(inRange);
    final shown = switch (_filter) {
      _Filter.all => inRange,
      _Filter.present => inRange.where((r) => r.status == AttendanceStatus.present).toList(),
      _Filter.absent => inRange.where((r) => r.status == AttendanceStatus.absent).toList(),
    };

    Widget dateButton(String label, DateTime v, ValueChanged<DateTime> onPick, {DateTime? min, DateTime? max}) {
      return Expanded(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(label, style: TextStyle(fontSize: 10, fontWeight: FontWeight.w600, color: palette.textMuted)),
          const SizedBox(height: 4),
          InkWell(
            borderRadius: AppRadii.all(AppRadii.md),
            onTap: () async {
              final picked = await showAppDatePicker(
                  context: context, title: 'History $label'.toLowerCase(), value: v, minDate: min, maxDate: max);
              if (picked != null) onPick(_dateOnly(picked));
            },
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
              decoration: BoxDecoration(
                color: palette.surfaceRaised,
                borderRadius: AppRadii.all(AppRadii.md),
                border: Border.all(color: palette.border),
              ),
              child: Row(children: [
                Icon(Icons.calendar_today_outlined, size: 13, color: palette.textFaint),
                const SizedBox(width: 6),
                Text(formatFeeDate(v), style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: palette.text)),
              ]),
            ),
          ),
        ]),
      );
    }

    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(children: [
        dateButton('From', _from, (d) => setState(() {
              _from = d.isAfter(_to) ? _to : d;
              _clampRange(fromChanged: true);
            }), max: _to),
        const SizedBox(width: 8),
        dateButton('To', _to, (d) => setState(() {
              _to = d.isBefore(_from) ? _from : d;
              _clampRange(fromChanged: false);
            }), min: _from, max: DateTime.now()),
      ]),
      const SizedBox(height: 6),
      Text('History can cover up to a 6-month range',
          style: TextStyle(fontSize: 9.5, color: palette.textFaint)),
      const SizedBox(height: 12),
      _card(Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('${s.present + s.absent} class${s.present + s.absent == 1 ? '' : 'es'} counted',
            style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.w600, color: palette.textMuted)),
        const SizedBox(height: 2),
        Text('${s.pct.round()}% attendance',
            style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w800,
                color: s.pct >= _minAttendancePct ? palette.text : palette.notPaid)),
        const SizedBox(height: 8),
        OutlinedButton.icon(
          onPressed: shown.isEmpty ? null : () => _export(shown),
          icon: const Icon(Icons.download, size: 15),
          label: const Text('Download'),
        ),
      ])),
      const SizedBox(height: 12),
      SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(children: [
          for (final f in _Filter.values)
            Padding(
              padding: const EdgeInsets.only(right: 6),
              child: GestureDetector(
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
                          fontWeight: FontWeight.w700,
                          color: _filter == f ? Colors.white : palette.textMuted)),
                ),
              ),
            ),
        ]),
      ),
      const SizedBox(height: 10),
      ..._rows(shown, 'No records match this filter'),
    ]);
  }

  /// The rows on screen as a CSV - exactly the current range and filter, so the file matches what
  /// the student was looking at.
  Future<void> _export(List<StudentAttendanceRecord> rows) async {
    String cell(String v) => '"${v.replaceAll('"', '""')}"';
    final csv = StringBuffer('Date,Course,Batch,Status\n');
    for (final r in rows) {
      csv.writeln([formatFeeDate(r.date), r.courseName ?? '', r.batchName ?? '', r.status.label].map(cell).join(','));
    }
    await Share.shareXFiles([
      XFile.fromData(Uint8List.fromList(utf8.encode(csv.toString())),
          name: 'attendance_history.csv', mimeType: 'text/csv'),
    ], text: 'My attendance history');
  }

  /// The reference caps a history window at six months; whichever end the user just moved drags
  /// the other along rather than rejecting the pick.
  void _clampRange({required bool fromChanged}) {
    final limit = DateTime(_to.year, _to.month - 6, _to.day);
    if (_from.isBefore(limit)) {
      if (fromChanged) {
        _to = DateTime(_from.year, _from.month + 6, _from.day);
        if (_to.isAfter(DateTime.now())) _to = _dateOnly(DateTime.now());
      } else {
        _from = limit;
      }
    }
  }
}
