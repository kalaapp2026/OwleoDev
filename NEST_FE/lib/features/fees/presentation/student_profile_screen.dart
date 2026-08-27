import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:nest_fe/app/theme/app_tokens.dart';
import 'package:nest_fe/app/theme/app_typography.dart';
import 'package:nest_fe/core/design/buttons.dart';
import 'package:nest_fe/core/design/pressable.dart';
import 'package:nest_fe/core/design/sheets.dart';
import 'package:nest_fe/core/design/status_badge.dart';
import 'package:nest_fe/core/design/toast.dart';
import 'package:nest_fe/features/fees/data/fee_roster.dart';
import 'package:nest_fe/features/fees/data/student_fee_profile.dart';
import 'package:nest_fe/features/fees/presentation/fee_format.dart';
import 'package:nest_fe/features/fees/presentation/statement_screen.dart';
import 'package:nest_fe/features/fees/presentation/fees_screen.dart' show feesApiProvider;

typedef _ProfileKey = ({String membershipId, String period});

final _profileProvider =
    FutureProvider.autoDispose.family<StudentFeeProfile, _ProfileKey>((ref, key) {
  return ref.watch(feesApiProvider).feeProfile(
        membershipId: key.membershipId,
        period: key.period,
      );
});

/// A student's fee detail for one period: what they owe across their courses, and the recorder
/// for taking a payment against one or several of them.
class StudentProfileScreen extends ConsumerStatefulWidget {
  const StudentProfileScreen({
    super.key,
    required this.membershipId,
    required this.period,
  });

  final String membershipId;
  final String period;

  @override
  ConsumerState<StudentProfileScreen> createState() => _StudentProfileScreenState();
}

class _StudentProfileScreenState extends ConsumerState<StudentProfileScreen> {
  /// Which course rows the admin is collecting for.
  ///
  /// Starts empty and is never auto-populated. Pre-selecting the course the admin arrived from
  /// reads as a suggestion but behaves as a selection: tapping a second row then quietly makes it
  /// a multi-select and marks a course paid that nobody chose.
  final Set<String> _selected = {};

  final _amountController = TextEditingController();
  final _gatewayRefController = TextEditingController();
  String _mode = 'CASH';
  bool _breakdownOpen = false;
  bool _busy = false;
  String? _editingCourseId;
  final _feeController = TextEditingController();

  _ProfileKey get _key => (membershipId: widget.membershipId, period: widget.period);

  @override
  void dispose() {
    _amountController.dispose();
    _gatewayRefController.dispose();
    _feeController.dispose();
    super.dispose();
  }

  void _refresh() => ref.invalidate(_profileProvider(_key));

  void _showError(Object error) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(error.toString().replaceFirst('Exception: ', ''))),
    );
  }

  /// Drops any selected row that is now fully paid.
  ///
  /// After a combined payment the rows it settled would otherwise sit selected but un-payable,
  /// with the recorder showing a zero total and no obvious way to clear them.
  void _dropSettled(StudentFeeProfile profile) {
    final settled = profile.courses.where((c) => c.isSettled).map((c) => c.courseId).toSet();
    if (_selected.intersection(settled).isEmpty) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) setState(() => _selected.removeAll(settled));
    });
  }

  List<CourseFeeRow> _selectedRows(StudentFeeProfile profile) =>
      profile.courses.where((c) => _selected.contains(c.courseId)).toList();

  /// The rows a payment would actually apply to, and what it would collect.
  ///
  /// With one course there is nothing to choose, so it is the target whether or not it was
  /// ticked - making the admin tick a single row before they can collect is friction with no
  /// decision behind it.
  List<CourseFeeRow> _targets(StudentFeeProfile profile) {
    if (!profile.hasBreakdown) return profile.courses;
    return _selectedRows(profile);
  }

  Future<void> _recordPayment(StudentFeeProfile profile, {num? partialAmount}) async {
    final targets = _targets(profile).where((c) => !c.isSettled).toList();
    if (targets.isEmpty || _busy) return;

    setState(() => _busy = true);
    try {
      final api = ref.read(feesApiProvider);
      if (partialAmount != null) {
        // A partial only ever applies to one course. Splitting an arbitrary amount across several
        // needs a rule nobody has decided, and guessing one would put money against the wrong
        // course silently.
        final target = targets.first;
        await api.recordEntry(
          membershipId: widget.membershipId,
          courseId: target.courseId,
          period: widget.period,
          amountPaid: partialAmount,
          mode: _mode,
          gatewayRef: _gatewayRefController.text.trim().isEmpty
              ? null
              : _gatewayRefController.text.trim(),
        );
      } else {
        for (final target in targets) {
          await api.recordEntry(
            membershipId: widget.membershipId,
            courseId: target.courseId,
            period: widget.period,
            amountPaid: target.outstanding,
            mode: _mode,
            gatewayRef: _gatewayRefController.text.trim().isEmpty
                ? null
                : _gatewayRefController.text.trim(),
          );
        }
      }
      _amountController.clear();
      _gatewayRefController.clear();
      setState(() => _selected.clear());
      _refresh();
      if (mounted) {
        showAppToast(
            context,
            partialAmount != null
                ? 'Partial payment recorded'
                : targets.length == 1
                    ? 'Payment recorded'
                    : '${targets.length} courses marked as paid');
      }
    } catch (e) {
      _showError(e);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _saveAgreedFee(CourseFeeRow row) async {
    final value = num.tryParse(_feeController.text.trim());
    if (value == null || value < 0) return;
    setState(() => _busy = true);
    try {
      await ref.read(feesApiProvider).updateAgreedFee(
            membershipId: widget.membershipId,
            courseId: row.courseId,
            agreedFee: value,
          );
      setState(() => _editingCourseId = null);
      _refresh();
      if (mounted) showAppToast(context, 'Agreed fee updated to ${money(value)}');
    } catch (e) {
      _showError(e);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final async = ref.watch(_profileProvider(_key));

    return Scaffold(
      backgroundColor: palette.bg,
      appBar: AppBar(
        backgroundColor: palette.bg,
        title: Text(async.valueOrNull?.studentName ?? 'Student'),
      ),
      body: async.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(
          child: Padding(
            padding: const EdgeInsets.all(AppSpacing.x4l),
            child: Text(
              e.toString().replaceFirst('Exception: ', ''),
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: AppType.md, color: palette.textMuted),
            ),
          ),
        ),
        data: (profile) {
          _dropSettled(profile);
          return _body(profile, palette);
        },
      ),
    );
  }

  Widget _body(StudentFeeProfile profile, AppPalette palette) {
    final targets = _targets(profile).where((c) => !c.isSettled).toList();
    final targetTotal = targets.fold<num>(0, (sum, c) => sum + c.outstanding);
    final overdue = profile.courses.any((c) => c.status == PaymentStatus.due);

    return ListView(
      padding: const EdgeInsets.fromLTRB(AppSpacing.xl, AppSpacing.md, AppSpacing.xl, AppSpacing.x5l),
      children: [
        Text(
          'Student fee profile · ${_periodLabel(profile.period)}',
          style: TextStyle(fontSize: AppType.smd, color: palette.textMuted),
        ),
        const SizedBox(height: AppSpacing.lg),
        Row(
          children: [
            StatBox(
              label: profile.hasBreakdown ? 'Agreed fee (all courses)' : 'Agreed fee',
              value: money(profile.totalAgreedFee),
            ),
            const SizedBox(width: AppSpacing.sm),
            StatBox(
              label: profile.hasBreakdown ? 'Paid (all courses)' : 'Paid',
              value: money(profile.totalPaid),
              accent: palette.paidManual,
            ),
            const SizedBox(width: AppSpacing.sm),
            StatBox(
              label: profile.hasBreakdown ? 'Balance (all courses)' : 'Balance',
              value: money(profile.outstanding),
              accent: profile.outstanding > 0 ? palette.notPaid : palette.textFaint,
            ),
          ],
        ),
        if (overdue) ...[
          const SizedBox(height: AppSpacing.lg),
          _Banner(
            icon: Icons.event_busy_outlined,
            text: 'Overdue - the billing period for at least one course has closed',
            color: palette.due,
            soft: palette.dueSoft,
          ),
        ],
        const SizedBox(height: AppSpacing.lg),
        _FeeCard(
          profile: profile,
          selected: _selected,
          open: _breakdownOpen,
          editingCourseId: _editingCourseId,
          feeController: _feeController,
          busy: _busy,
          onToggleOpen: () => setState(() => _breakdownOpen = !_breakdownOpen),
          onToggleRow: (row) => setState(() {
            _selected.contains(row.courseId)
                ? _selected.remove(row.courseId)
                : _selected.add(row.courseId);
            _amountController.clear();
          }),
          onStartEdit: (row) => setState(() {
            _editingCourseId = row.courseId;
            _feeController.text = row.agreedFee.round().toString();
          }),
          onCancelEdit: () => setState(() => _editingCourseId = null),
          onSaveEdit: _saveAgreedFee,
        ),
        const SizedBox(height: AppSpacing.lg),
        if (targetTotal > 0)
          _Recorder(
            profile: profile,
            targets: targets,
            total: targetTotal,
            mode: _mode,
            busy: _busy,
            amountController: _amountController,
            gatewayRefController: _gatewayRefController,
            onModeChanged: (m) => setState(() => _mode = m),
            onClearSelection: () => setState(() {
              _selected.clear();
              _amountController.clear();
            }),
            onMarkPaid: () => _recordPayment(profile),
            onPartial: (amount) => _recordPayment(profile, partialAmount: amount),
          )
        else
          _Banner(
            icon: Icons.check_circle_outline,
            text: profile.hasBreakdown && _selected.isNotEmpty
                ? 'The selected courses are already paid'
                : 'Fully paid for this period',
            color: palette.paidManual,
            soft: palette.paidManualSoft,
          ),
        const SizedBox(height: AppSpacing.xxl),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text('Fee slips & history',
                style: TextStyle(
                    fontSize: AppType.md, fontWeight: AppType.bold, color: palette.text)),
            Pressable(
              onTap: () => Navigator.of(context).push(MaterialPageRoute(
                builder: (_) => StatementScreen(membershipId: widget.membershipId),
              )),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.download_outlined, size: 13, color: palette.primary),
                  const SizedBox(width: AppSpacing.xxs),
                  Text('Statement',
                      style: TextStyle(
                          fontSize: AppType.smd,
                          fontWeight: AppType.bold,
                          color: palette.primary)),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.sm),
        for (final row in profile.courses)
          Padding(
            padding: const EdgeInsets.only(bottom: AppSpacing.xs),
            child: _SlipRow(row: row),
          ),
      ],
    );
  }

  String _periodLabel(String period) {
    final parts = period.split('-');
    if (parts.length != 2) return period;
    final month = int.tryParse(parts[1]);
    if (month == null || month < 1 || month > 12) return period;
    const names = [
      'January', 'February', 'March', 'April', 'May', 'June',
      'July', 'August', 'September', 'October', 'November', 'December'
    ];
    return '${names[month - 1]} ${parts[0]}';
  }
}

/// The agreed-fee card, which becomes an expandable breakdown once there is more than one course.
class _FeeCard extends StatelessWidget {
  const _FeeCard({
    required this.profile,
    required this.selected,
    required this.open,
    required this.editingCourseId,
    required this.feeController,
    required this.busy,
    required this.onToggleOpen,
    required this.onToggleRow,
    required this.onStartEdit,
    required this.onCancelEdit,
    required this.onSaveEdit,
  });

  final StudentFeeProfile profile;
  final Set<String> selected;
  final bool open;
  final String? editingCourseId;
  final TextEditingController feeController;
  final bool busy;
  final VoidCallback onToggleOpen;
  final ValueChanged<CourseFeeRow> onToggleRow;
  final ValueChanged<CourseFeeRow> onStartEdit;
  final VoidCallback onCancelEdit;
  final ValueChanged<CourseFeeRow> onSaveEdit;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final hasBreakdown = profile.hasBreakdown;
    final single = profile.courses.length == 1 ? profile.courses.first : null;

    return Container(
      padding: const EdgeInsets.all(AppSpacing.lg),
      decoration: BoxDecoration(
        color: palette.surfaceRaised,
        borderRadius: AppRadii.all(AppRadii.x3l),
        border: Border.all(color: palette.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Pressable(
                  onTap: hasBreakdown ? onToggleOpen : null,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Row(
                        children: [
                          Flexible(
                            child: Text(
                              hasBreakdown
                                  ? 'Balance still to be collected'
                                  : 'Agreed fee to be collected',
                              style: TextStyle(fontSize: AppType.xs, color: palette.textMuted),
                            ),
                          ),
                          if (hasBreakdown) ...[
                            const SizedBox(width: AppSpacing.xxs),
                            AnimatedRotation(
                              turns: open ? 0.5 : 0,
                              duration: AppMotion.chevron,
                              child: Icon(Icons.keyboard_arrow_down_rounded,
                                  size: 14, color: palette.textFaint),
                            ),
                          ],
                        ],
                      ),
                      const SizedBox(height: AppSpacing.xxs),
                      if (editingCourseId != null && single != null)
                        _FeeEditor(
                          controller: feeController,
                          busy: busy,
                          onSave: () => onSaveEdit(single),
                          onCancel: onCancelEdit,
                        )
                      else ...[
                        Text(
                          money(hasBreakdown ? profile.outstanding : profile.totalAgreedFee),
                          style: TextStyle(
                            fontSize: AppType.x3l,
                            fontWeight: AppType.heavy,
                            color: hasBreakdown
                                ? (profile.outstanding > 0 ? palette.notPaid : palette.paidManual)
                                : palette.text,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          hasBreakdown
                              ? 'of ${money(profile.totalAgreedFee)} across ${profile.courses.length} courses'
                              : single == null
                                  ? 'No active enrolment for this period'
                                  : '${money(single.outstanding)} of ${money(single.agreedFee)} to be paid',
                          style: TextStyle(fontSize: AppType.tiny, color: palette.textFaint),
                        ),
                        if (!hasBreakdown && single?.batchName != null)
                          Text(
                            '${single!.courseName} · ${single.batchName}',
                            style: TextStyle(fontSize: AppType.tiny, color: palette.textFaint),
                          ),
                      ],
                    ],
                  ),
                ),
              ),
              if (!hasBreakdown && single != null && editingCourseId == null) ...[
                const SizedBox(width: AppSpacing.sm),
                _EditButton(onTap: () => onStartEdit(single)),
              ],
            ],
          ),
          if (hasBreakdown && open) ...[
            const SizedBox(height: AppSpacing.md),
            Divider(height: 1, color: palette.borderSoft),
            const SizedBox(height: AppSpacing.md),
            Text(
              "Select which course you're collecting payment for:",
              style: TextStyle(fontSize: AppType.xs, color: palette.textMuted),
            ),
            const SizedBox(height: AppSpacing.sm),
            for (final row in profile.courses)
              Padding(
                padding: const EdgeInsets.only(bottom: AppSpacing.xs),
                child: _BreakdownRow(
                  row: row,
                  selected: selected.contains(row.courseId),
                  editing: editingCourseId == row.courseId,
                  feeController: feeController,
                  busy: busy,
                  onToggle: () => onToggleRow(row),
                  onStartEdit: () => onStartEdit(row),
                  onCancelEdit: onCancelEdit,
                  onSaveEdit: () => onSaveEdit(row),
                ),
              ),
            const SizedBox(height: AppSpacing.xs),
            Divider(height: 1, color: palette.borderSoft),
            const SizedBox(height: AppSpacing.sm),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text('Total across all courses',
                    style: TextStyle(
                        fontSize: AppType.smd,
                        fontWeight: AppType.bold,
                        color: palette.textMuted)),
                Text(money(profile.totalAgreedFee),
                    style: TextStyle(
                        fontSize: AppType.md,
                        fontWeight: AppType.heavy,
                        color: palette.revenue)),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

class _BreakdownRow extends StatelessWidget {
  const _BreakdownRow({
    required this.row,
    required this.selected,
    required this.editing,
    required this.feeController,
    required this.busy,
    required this.onToggle,
    required this.onStartEdit,
    required this.onCancelEdit,
    required this.onSaveEdit,
  });

  final CourseFeeRow row;
  final bool selected;
  final bool editing;
  final TextEditingController feeController;
  final bool busy;
  final VoidCallback onToggle;
  final VoidCallback onStartEdit;
  final VoidCallback onCancelEdit;
  final VoidCallback onSaveEdit;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    // A settled row can still have its fee edited - that is how a mistaken amount gets corrected -
    // but it cannot be selected for payment, because there is nothing left to collect.
    final selectable = !row.isSettled && !editing;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md, vertical: AppSpacing.sm),
      decoration: BoxDecoration(
        color: selected ? palette.primarySoft : Colors.transparent,
        borderRadius: AppRadii.all(AppRadii.lg),
        border: Border.all(color: selected ? palette.primary : palette.borderSoft),
      ),
      child: Row(
        children: [
          Expanded(
            child: Opacity(
              opacity: row.isSettled && !editing ? 0.55 : 1,
              child: Pressable(
                onTap: selectable ? onToggle : null,
                child: Row(
                  children: [
                    AppCheckbox(checked: selected, size: 16),
                    const SizedBox(width: AppSpacing.sm),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            row.batchName == null
                                ? row.courseName
                                : '${row.courseName} · ${row.batchName}',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: AppType.smd,
                              fontWeight: AppType.medium,
                              color: palette.text,
                            ),
                          ),
                          const SizedBox(height: 2),
                          if (editing)
                            _FeeEditor(
                              controller: feeController,
                              busy: busy,
                              dense: true,
                              onSave: onSaveEdit,
                              onCancel: onCancelEdit,
                            )
                          else if (row.isSettled)
                            Text(money(row.agreedFee),
                                style: TextStyle(fontSize: AppType.xs, color: palette.textFaint))
                          else
                            Text.rich(TextSpan(
                              text: money(row.outstanding),
                              style: TextStyle(
                                fontSize: AppType.xs,
                                fontWeight: AppType.heavy,
                                color: row.status == PaymentStatus.partial
                                    ? palette.partial
                                    : palette.notPaid,
                              ),
                              children: [
                                TextSpan(
                                  text: '/${money(row.agreedFee)}',
                                  style: TextStyle(
                                      fontWeight: AppType.regular, color: palette.textFaint),
                                ),
                              ],
                            )),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          if (!editing) ...[
            const SizedBox(width: AppSpacing.xs),
            Pressable(
              onTap: onStartEdit,
              child: Padding(
                padding: const EdgeInsets.all(3),
                child: Icon(Icons.edit_outlined, size: 13, color: palette.gold),
              ),
            ),
            const SizedBox(width: AppSpacing.xxs),
            StatusBadge(
              label: statusLabel(row.status),
              color: row.status.color(palette),
              softColor: row.status.softColor(palette),
              dense: true,
            ),
          ],
        ],
      ),
    );
  }
}

/// Inline amount editor with explicit save/cancel.
///
/// Not save-on-blur: the agreed fee is what a family is charged, and a stray tap elsewhere must
/// not be able to commit a half-typed number.
class _FeeEditor extends StatelessWidget {
  const _FeeEditor({
    required this.controller,
    required this.busy,
    required this.onSave,
    required this.onCancel,
    this.dense = false,
  });

  final TextEditingController controller;
  final bool busy;
  final VoidCallback onSave;
  final VoidCallback onCancel;
  final bool dense;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return Row(
      children: [
        SizedBox(
          width: dense ? 84 : 120,
          child: TextField(
            controller: controller,
            autofocus: true,
            keyboardType: TextInputType.number,
            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
            style: TextStyle(
              fontSize: dense ? AppType.smd : AppType.md,
              fontWeight: AppType.bold,
              color: palette.text,
            ),
            decoration: InputDecoration(
              isDense: true,
              prefixText: '₹',
              prefixStyle: TextStyle(fontSize: AppType.smd, color: palette.textFaint),
              filled: true,
              fillColor: palette.surfaceHigh,
              contentPadding: EdgeInsets.symmetric(
                  horizontal: AppSpacing.sm, vertical: dense ? 4 : AppSpacing.sm),
              border: OutlineInputBorder(
                borderRadius: AppRadii.all(AppRadii.sm),
                borderSide: BorderSide(color: palette.primary),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: AppRadii.all(AppRadii.sm),
                borderSide: BorderSide(color: palette.primary),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: AppRadii.all(AppRadii.sm),
                borderSide: BorderSide(color: palette.primary),
              ),
            ),
          ),
        ),
        const SizedBox(width: AppSpacing.xs),
        _MiniButton(
          icon: Icons.check_rounded,
          background: palette.primary,
          foreground: palette.onPrimary,
          onTap: busy ? null : onSave,
        ),
        const SizedBox(width: AppSpacing.xxs),
        _MiniButton(
          icon: Icons.close_rounded,
          background: Colors.transparent,
          foreground: palette.textMuted,
          border: palette.border,
          onTap: busy ? null : onCancel,
        ),
      ],
    );
  }
}

class _MiniButton extends StatelessWidget {
  const _MiniButton({
    required this.icon,
    required this.background,
    required this.foreground,
    required this.onTap,
    this.border,
  });

  final IconData icon;
  final Color background;
  final Color foreground;
  final VoidCallback? onTap;
  final Color? border;

  @override
  Widget build(BuildContext context) {
    return Pressable(
      onTap: onTap,
      child: Container(
        width: 26,
        height: 26,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: background,
          borderRadius: AppRadii.all(AppRadii.sm),
          border: border == null ? null : Border.all(color: border!),
        ),
        child: Icon(icon, size: 14, color: foreground),
      ),
    );
  }
}

class _EditButton extends StatelessWidget {
  const _EditButton({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return Pressable(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md, vertical: AppSpacing.sm),
        decoration: BoxDecoration(
          color: palette.primarySoft,
          borderRadius: AppRadii.all(AppRadii.md),
          border: Border.all(color: palette.primaryDim),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.edit_outlined, size: 13, color: palette.primary),
            const SizedBox(width: AppSpacing.xxs),
            Text('Edit',
                style: TextStyle(
                    fontSize: AppType.smd,
                    fontWeight: AppType.bold,
                    color: palette.primary)),
          ],
        ),
      ),
    );
  }
}

/// The payment recorder: mode, then either settle in full or record a partial amount.
class _Recorder extends StatelessWidget {
  const _Recorder({
    required this.profile,
    required this.targets,
    required this.total,
    required this.mode,
    required this.busy,
    required this.amountController,
    required this.gatewayRefController,
    required this.onModeChanged,
    required this.onClearSelection,
    required this.onMarkPaid,
    required this.onPartial,
  });

  final StudentFeeProfile profile;
  final List<CourseFeeRow> targets;
  final num total;
  final String mode;
  final bool busy;
  final TextEditingController amountController;
  final TextEditingController gatewayRefController;
  final ValueChanged<String> onModeChanged;
  final VoidCallback onClearSelection;
  final VoidCallback onMarkPaid;
  final ValueChanged<num> onPartial;

  static const _modes = [('CASH', 'Cash'), ('UPI', 'UPI'), ('GATEWAY', 'Gateway')];

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final needsSelection = profile.hasBreakdown && targets.isEmpty;
    final multi = targets.length > 1;
    // A partial against several courses at once needs a split rule nobody has decided, so it is
    // offered only when the target is unambiguous.
    final canPartial = targets.length == 1;

    return Container(
      padding: const EdgeInsets.all(AppSpacing.lg),
      decoration: BoxDecoration(
        color: palette.surfaceRaised,
        borderRadius: AppRadii.all(AppRadii.x3l),
        border: Border.all(color: targets.isEmpty ? palette.border : palette.primary),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Text.rich(TextSpan(
                  text: 'Record a payment',
                  style: TextStyle(
                    fontSize: AppType.md,
                    fontWeight: AppType.bold,
                    color: palette.text,
                  ),
                  children: [
                    if (targets.length == 1 && profile.hasBreakdown)
                      TextSpan(
                        text: ' · ${targets.first.courseName}',
                        style: TextStyle(color: palette.primary),
                      )
                    else if (multi)
                      TextSpan(
                        text: ' · ${targets.length} courses',
                        style: TextStyle(color: palette.primary),
                      ),
                  ],
                )),
              ),
              if (profile.hasBreakdown && targets.isNotEmpty)
                Pressable(
                  onTap: onClearSelection,
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.close_rounded, size: 11, color: palette.textFaint),
                      const SizedBox(width: 2),
                      Text('Clear',
                          style: TextStyle(fontSize: AppType.xs, color: palette.textFaint)),
                    ],
                  ),
                ),
            ],
          ),
          if (multi) ...[
            const SizedBox(height: AppSpacing.sm),
            for (final t in targets)
              Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Flexible(
                      child: Text(t.courseName,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(fontSize: AppType.smd, color: palette.textMuted)),
                    ),
                    Text(money(t.outstanding),
                        style: TextStyle(
                            fontSize: AppType.smd,
                            fontWeight: AppType.bold,
                            color: palette.text)),
                  ],
                ),
              ),
            const SizedBox(height: AppSpacing.xs),
            Divider(height: 1, color: palette.borderSoft),
          ],
          const SizedBox(height: AppSpacing.md),
          Row(
            children: [
              for (final (value, label) in _modes) ...[
                Expanded(
                  child: _ModeButton(
                    label: label,
                    selected: mode == value,
                    onTap: () => onModeChanged(value),
                  ),
                ),
                if (value != _modes.last.$1) const SizedBox(width: AppSpacing.xs),
              ],
            ],
          ),
          if (mode != 'CASH') ...[
            const SizedBox(height: AppSpacing.sm),
            TextField(
              controller: gatewayRefController,
              style: TextStyle(fontSize: AppType.md, color: palette.text),
              decoration: _fieldDecoration(
                  palette, mode == 'UPI' ? 'UPI transaction ID (optional)' : 'Gateway reference'),
            ),
          ],
          if (needsSelection) ...[
            const SizedBox(height: AppSpacing.md),
            Text(
              'Select a course above to record a payment',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: AppType.smd, color: palette.textFaint),
            ),
          ],
          const SizedBox(height: AppSpacing.md),
          AppPrimaryButton(
            label: multi
                ? 'Mark ${targets.length} as paid (${money(total)})'
                : 'Mark as paid (${money(total)})',
            icon: Icons.check,
            busy: busy,
            onPressed: needsSelection ? null : onMarkPaid,
          ),
          const SizedBox(height: AppSpacing.md),
          Row(
            children: [
              Expanded(child: Divider(color: palette.border)),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm),
                child: Text('OR RECORD PARTIAL AMOUNT',
                    style: AppType.sectionLabel(palette.textFaint)),
              ),
              Expanded(child: Divider(color: palette.border)),
            ],
          ),
          const SizedBox(height: AppSpacing.sm),
          TextField(
            controller: amountController,
            enabled: canPartial && !busy,
            keyboardType: TextInputType.number,
            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
            style: TextStyle(fontSize: AppType.md, color: palette.text),
            decoration: _fieldDecoration(
              palette,
              canPartial
                  ? 'Amount up to ${money(targets.first.outstanding)}'
                  : 'Select a single course to pay part of it',
            ),
          ),
          const SizedBox(height: AppSpacing.sm),
          ValueListenableBuilder<TextEditingValue>(
            valueListenable: amountController,
            builder: (context, value, _) {
              final amount = num.tryParse(value.text.trim());
              final valid = canPartial &&
                  amount != null &&
                  amount > 0 &&
                  amount <= targets.first.outstanding;
              return Pressable(
                onTap: valid && !busy ? () => onPartial(amount) : null,
                child: Container(
                  padding: const EdgeInsets.symmetric(vertical: AppSpacing.md),
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: valid ? palette.partialSoft : palette.surfaceHigh,
                    borderRadius: AppRadii.all(AppRadii.lg),
                    border: Border.all(color: valid ? palette.partial : palette.border),
                  ),
                  child: Text(
                    'Record partial payment',
                    style: TextStyle(
                      fontSize: AppType.md,
                      fontWeight: AppType.bold,
                      color: valid ? palette.partial : palette.textFaint,
                    ),
                  ),
                ),
              );
            },
          ),
        ],
      ),
    );
  }

  InputDecoration _fieldDecoration(AppPalette palette, String hint) => InputDecoration(
        isDense: true,
        hintText: hint,
        hintStyle: TextStyle(fontSize: AppType.md, color: palette.textFaint),
        filled: true,
        fillColor: palette.surfaceHigh,
        contentPadding:
            const EdgeInsets.symmetric(horizontal: AppSpacing.md, vertical: AppSpacing.md),
        border: OutlineInputBorder(
          borderRadius: AppRadii.all(AppRadii.lg),
          borderSide: BorderSide(color: palette.border),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: AppRadii.all(AppRadii.lg),
          borderSide: BorderSide(color: palette.border),
        ),
        disabledBorder: OutlineInputBorder(
          borderRadius: AppRadii.all(AppRadii.lg),
          borderSide: BorderSide(color: palette.borderSoft),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: AppRadii.all(AppRadii.lg),
          borderSide: BorderSide(color: palette.primary),
        ),
      );
}

class _ModeButton extends StatelessWidget {
  const _ModeButton({required this.label, required this.selected, required this.onTap});

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return Pressable(
      onTap: onTap,
      child: AnimatedContainer(
        duration: AppMotion.fade,
        padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: selected ? palette.primarySoft : Colors.transparent,
          borderRadius: AppRadii.all(AppRadii.md),
          border: Border.all(color: selected ? palette.primary : palette.border),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: AppType.md,
            fontWeight: AppType.bold,
            color: selected ? palette.primary : palette.textMuted,
          ),
        ),
      ),
    );
  }
}

class _SlipRow extends StatelessWidget {
  const _SlipRow({required this.row});

  final CourseFeeRow row;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md, vertical: 11),
      decoration: BoxDecoration(
        color: palette.surfaceRaised,
        borderRadius: AppRadii.all(AppRadii.lg),
        border: Border.all(color: palette.borderSoft),
      ),
      child: Row(
        children: [
          Icon(Icons.receipt_long_outlined, size: 15, color: palette.textFaint),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(row.courseName,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                        fontSize: AppType.smd,
                        fontWeight: AppType.semi,
                        color: palette.text)),
                const SizedBox(height: 2),
                Text(
                  '${money(row.totalPaid)} of ${money(row.agreedFee)}'
                  '${row.lastPaidOn == null ? '' : ' (${formatFeeDate(row.lastPaidOn!)})'}',
                  style: TextStyle(fontSize: AppType.xs, color: palette.textFaint),
                ),
              ],
            ),
          ),
          const SizedBox(width: AppSpacing.xs),
          StatusBadge(
            label: statusLabel(row.status),
            color: row.status.color(palette),
            softColor: row.status.softColor(palette),
            dense: true,
          ),
        ],
      ),
    );
  }
}

class _Banner extends StatelessWidget {
  const _Banner({
    required this.icon,
    required this.text,
    required this.color,
    required this.soft,
  });

  final IconData icon;
  final String text;
  final Color color;
  final Color soft;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md, vertical: AppSpacing.md),
      decoration: BoxDecoration(
        color: soft,
        borderRadius: AppRadii.all(AppRadii.lg),
        border: Border.all(color: color),
      ),
      child: Row(
        children: [
          Icon(icon, size: 16, color: color),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Text(
              text,
              style: TextStyle(
                fontSize: AppType.smd,
                fontWeight: AppType.bold,
                color: color,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
