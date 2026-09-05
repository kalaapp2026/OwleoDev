import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:nest_fe/app/theme/app_tokens.dart';
import 'package:nest_fe/app/theme/app_typography.dart';
import 'package:nest_fe/core/design/avatar.dart';
import 'package:nest_fe/core/design/buttons.dart';
import 'package:nest_fe/core/design/category_meta.dart';
import 'package:nest_fe/core/design/pressable.dart';
import 'package:nest_fe/core/design/toast.dart';
import 'package:nest_fe/core/format/money.dart';
import 'package:nest_fe/features/attendance/data/attendance_api.dart';
import 'package:nest_fe/features/attendance/data/class_instance.dart';
import 'package:nest_fe/features/attendance/data/student_attendance.dart';
import 'package:nest_fe/features/attendance/presentation/student_attendance_screen.dart';
import 'package:nest_fe/features/scheduling/data/schedule_entry.dart';

/// Marks one class. Everyone starts Present; tapping a row flips them to Absent.
///
/// That default is deliberate and matches how attendance is actually taken - the trainer looks
/// for empty chairs, not full ones. Starting everyone unmarked would mean N taps instead of the
/// two or three an average class needs.
///
/// Pops `true` when a sheet was submitted.
class MarkAttendanceScreen extends ConsumerStatefulWidget {
  const MarkAttendanceScreen({super.key, required this.entry});

  final ScheduleEntry entry;

  @override
  ConsumerState<MarkAttendanceScreen> createState() => _MarkAttendanceScreenState();
}

class _MarkAttendanceScreenState extends ConsumerState<MarkAttendanceScreen> {
  final _searchController = TextEditingController();
  final Set<String> _absentIds = {};

  String _query = '';
  bool _seeded = false;
  bool _busy = false;

  ScheduleEntry get entry => widget.entry;

  bool get _canMark => entry.canMarkAttendance(DateTime.now());

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  /// Seeds from whatever was already marked, so reopening a class shows the previous answers
  /// rather than silently resetting everyone to present.
  void _seedFrom(List<AttendanceRecord> existing) {
    if (_seeded) return;
    _seeded = true;
    for (final record in existing) {
      if (record.status == 'ABSENT') _absentIds.add(record.membershipId);
    }
  }

  Future<void> _submit(List<BatchMemberSummary> roster) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await ref.read(attendanceApiProvider).submitSheet(
            entry.classInstanceId,
            {
              for (final student in roster)
                student.membershipId:
                    _absentIds.contains(student.membershipId) ? 'ABSENT' : 'PRESENT',
            },
          );
      if (mounted) {
        showAppToast(context, 'Attendance saved');
        Navigator.of(context).pop(true);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(e.toString().replaceFirst('Exception: ', ''))),
        );
        setState(() => _busy = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final meta = entry.courseCategory.meta(palette);
    final rosterAsync = ref.watch(batchRosterProvider(entry.batchId));
    final existingAsync = ref.watch(classAttendanceProvider(entry.classInstanceId));

    return Scaffold(
      backgroundColor: palette.bg,
      appBar: AppBar(
        backgroundColor: palette.bg,
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Flexible(
                  child: Text(entry.batchName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                          fontSize: 17,
                          fontWeight: AppType.bold,
                          color: palette.text)),
                ),
                if (entry.isTemporary) ...[
                  const SizedBox(width: AppSpacing.sm),
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: AppSpacing.sm, vertical: 3),
                    decoration: BoxDecoration(
                      color: palette.gold,
                      borderRadius: AppRadii.all(AppRadii.xs),
                    ),
                    child: Text('TEMPORARY',
                        style: TextStyle(
                          fontSize: 9,
                          fontWeight: AppType.heavy,
                          letterSpacing: 0.4,
                          color: palette.onGold,
                        )),
                  ),
                ],
              ],
            ),
            Text('${entry.courseName ?? ''} · ${formatFeeDate(entry.date)}',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: AppType.smd, color: palette.textMuted)),
          ],
        ),
      ),
      body: rosterAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => _error(palette, e),
        data: (roster) => existingAsync.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (e, _) => _error(palette, e),
          data: (existing) {
            _seedFrom(existing);

            final q = _query.trim().toLowerCase();
            final visible = q.isEmpty
                ? roster
                : roster.where((s) => s.fullName.toLowerCase().contains(q)).toList();
            final presentCount = roster.length - _absentIds.length;

            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(
                  child: ListView(
                    padding: const EdgeInsets.fromLTRB(
                        AppSpacing.page, AppSpacing.xxl, AppSpacing.page, AppSpacing.x4l),
                    children: [
                      if (!_canMark) _futureNotice(palette),
                      Row(
                        children: [
                          Expanded(
                            child: _StatPill(
                              icon: Icons.check_circle_outline,
                              color: palette.paidManual,
                              soft: palette.paidManualSoft,
                              count: presentCount,
                              label: 'Present',
                            ),
                          ),
                          const SizedBox(width: AppSpacing.sm),
                          Expanded(
                            child: _StatPill(
                              icon: Icons.cancel_outlined,
                              color: palette.notPaid,
                              soft: palette.notPaidSoft,
                              count: _absentIds.length,
                              label: 'Absent',
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: AppSpacing.xl),
                      if (roster.isEmpty)
                        Padding(
                          padding: const EdgeInsets.symmetric(vertical: AppSpacing.x5l),
                          child: Text(
                            'This batch has no students yet. Add them from Batches.',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                                fontSize: AppType.lg, color: palette.textFaint),
                          ),
                        )
                      else ...[
                        Text(_canMark ? 'TAP TO MARK ABSENT' : 'ROSTER',
                            style: AppType.sectionLabel(palette.textMuted)),
                        const SizedBox(height: AppSpacing.sm),
                        _search(palette),
                        const SizedBox(height: AppSpacing.md),
                        if (visible.isEmpty)
                          Padding(
                            padding: const EdgeInsets.symmetric(vertical: AppSpacing.x4l),
                            child: Text('No students match "$_query".',
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                    fontSize: AppType.base, color: palette.textFaint)),
                          )
                        else
                          for (final student in visible)
                            Padding(
                              padding: const EdgeInsets.only(bottom: AppSpacing.sm),
                              child: _StudentRow(
                                student: student,
                                isAbsent: _absentIds.contains(student.membershipId),
                                enabled: _canMark,
                                accent: meta.color,
                                onToggle: () => setState(() {
                                  if (!_absentIds.remove(student.membershipId)) {
                                    _absentIds.add(student.membershipId);
                                  }
                                }),
                                onOpenProfile: () =>
                                    Navigator.of(context).push(MaterialPageRoute(
                                  builder: (_) => StudentAttendanceScreen(
                                    membershipId: student.membershipId,
                                    studentName: student.fullName,
                                  ),
                                )),
                              ),
                            ),
                      ],
                    ],
                  ),
                ),
                if (_canMark && roster.isNotEmpty)
                  Container(
                    padding: EdgeInsets.fromLTRB(AppSpacing.page, AppSpacing.lg,
                        AppSpacing.page, AppSpacing.xxl + MediaQuery.paddingOf(context).bottom),
                    decoration: BoxDecoration(
                      border: Border(top: BorderSide(color: palette.borderSoft)),
                    ),
                    child: AppPrimaryButton(
                      label: 'Submit attendance',
                      icon: Icons.check,
                      busy: _busy,
                      onPressed: () => _submit(roster),
                    ),
                  ),
              ],
            );
          },
        ),
      ),
    );
  }

  Widget _futureNotice(AppPalette palette) {
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.xl),
      child: Container(
        padding: const EdgeInsets.all(AppSpacing.xl),
        decoration: BoxDecoration(
          color: palette.primarySoft,
          borderRadius: AppRadii.all(AppRadii.xl),
          border: Border.all(color: palette.primary.withValues(alpha: 0.25)),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(Icons.calendar_today_outlined, size: 15, color: palette.primary),
            const SizedBox(width: AppSpacing.md),
            Expanded(
              child: Text(
                "This class hasn't happened yet. You can see who's on the roster, but attendance "
                'can only be marked from the day of the class onward.',
                style: TextStyle(
                    fontSize: AppType.smd, color: palette.textMuted, height: 1.5),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _search(AppPalette palette) {
    return Container(
      padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.lg, vertical: AppSpacing.md),
      decoration: BoxDecoration(
        color: palette.surfaceRaised,
        borderRadius: AppRadii.all(AppRadii.lg),
        border: Border.all(color: palette.border),
      ),
      child: Row(
        children: [
          Icon(Icons.search, size: 14, color: palette.textFaint),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: TextField(
              controller: _searchController,
              onChanged: (v) => setState(() => _query = v),
              style: TextStyle(
                  fontSize: AppType.lg,
                  fontWeight: AppType.regular,
                  color: palette.text),
              decoration: InputDecoration(
                isDense: true,
                border: InputBorder.none,
                contentPadding: EdgeInsets.zero,
                hintText: 'Search student',
                hintStyle: TextStyle(fontSize: AppType.lg, color: palette.textFaint),
              ),
            ),
          ),
          if (_query.isNotEmpty)
            Pressable(
              onTap: () {
                _searchController.clear();
                setState(() => _query = '');
              },
              child: Icon(Icons.close_rounded, size: 13, color: palette.textFaint),
            ),
        ],
      ),
    );
  }

  Widget _error(AppPalette palette, Object e) => Center(
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.x4l),
          child: Text(e.toString().replaceFirst('Exception: ', ''),
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: AppType.lg, color: palette.textMuted)),
        ),
      );
}

class _StatPill extends StatelessWidget {
  const _StatPill({
    required this.icon,
    required this.color,
    required this.soft,
    required this.count,
    required this.label,
  });

  final IconData icon;
  final Color color;
  final Color soft;
  final int count;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.lg, vertical: AppSpacing.lg),
      decoration: BoxDecoration(
        color: soft,
        borderRadius: AppRadii.all(AppRadii.lg),
        border: Border.all(color: color.withValues(alpha: 0.27)),
      ),
      child: Row(
        children: [
          Icon(icon, size: 15, color: color),
          const SizedBox(width: AppSpacing.sm),
          Text('$count',
              style: TextStyle(
                  fontSize: AppType.x3l,
                  fontWeight: AppType.heavy,
                  height: 1,
                  color: color)),
          const SizedBox(width: AppSpacing.xs),
          Flexible(
            child: Text(label.toUpperCase(),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: AppType.base,
                  fontWeight: AppType.bold,
                  letterSpacing: 0.3,
                  height: 1,
                  color: color,
                )),
          ),
        ],
      ),
    );
  }
}

/// One student. The background crossfades between the present and absent tints rather than
/// snapping, so a mis-tap is visible as a change rather than just a different colour.
class _StudentRow extends StatelessWidget {
  const _StudentRow({
    required this.student,
    required this.isAbsent,
    required this.enabled,
    required this.accent,
    required this.onToggle,
    required this.onOpenProfile,
  });

  final BatchMemberSummary student;
  final bool isAbsent;
  final bool enabled;
  final Color accent;
  final VoidCallback onToggle;
  final VoidCallback onOpenProfile;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final status = isAbsent ? AttendanceStatus.absent : AttendanceStatus.present;

    return Pressable(
      onTap: enabled ? onToggle : null,
      child: AnimatedContainer(
        duration: AppMotion.flipColor,
        curve: AppMotion.enter,
        padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.xl, vertical: AppSpacing.lg),
        decoration: BoxDecoration(
          color: status.softColor(palette),
          borderRadius: AppRadii.all(AppRadii.xl),
          border: Border.all(color: status.color(palette).withValues(alpha: 0.33)),
        ),
        child: Row(
          children: [
            PersonAvatar(
                name: student.fullName, seed: student.membershipId, size: 34),
            const SizedBox(width: AppSpacing.md),
            Expanded(
              child: Text(student.fullName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                      fontSize: AppType.xxl,
                      fontWeight: AppType.semi,
                      color: palette.text)),
            ),
            const SizedBox(width: AppSpacing.sm),
            Icon(
              isAbsent ? Icons.cancel_outlined : Icons.check_circle_outline,
              size: 17,
              color: status.color(palette),
            ),
            const SizedBox(width: 5),
            Text(status.label,
                style: TextStyle(
                  fontSize: AppType.sm,
                  fontWeight: AppType.bold,
                  color: status.color(palette),
                )),
            const SizedBox(width: AppSpacing.sm),
            // Its own tap target, so opening a student's history never risks flipping their
            // status by accident.
            Pressable(
              onTap: onOpenProfile,
              child: Container(
                width: 26,
                height: 26,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: const Color(0x2E000000),
                  borderRadius: AppRadii.all(AppRadii.sm),
                ),
                child: Icon(Icons.chevron_right, size: 16, color: palette.text),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
