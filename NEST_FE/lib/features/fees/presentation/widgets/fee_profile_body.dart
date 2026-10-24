import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:nest_fe/app/theme/app_tokens.dart';
import 'package:nest_fe/app/theme/app_typography.dart';
import 'package:nest_fe/core/design/buttons.dart';
import 'package:nest_fe/core/design/pressable.dart';
import 'package:nest_fe/core/design/sheets.dart';
import 'package:nest_fe/core/design/status_badge.dart';
import 'package:nest_fe/core/design/toast.dart';
import 'package:nest_fe/features/fees/data/fee_roster.dart';
import 'package:nest_fe/features/fees/presentation/fee_format.dart';

/// One thing a student owes - a course for their regular fee, a fee type or one-off for an Other
/// fee. The profile's two halves look and behave the same, so they share this shape and one body
/// instead of two copies that drift apart.
class FeeLine {
  const FeeLine({
    required this.id,
    required this.title,
    required this.agreedFee,
    required this.paid,
    required this.balance,
    required this.status,
    this.context,
    this.paidOn,
    this.tag,
  });

  /// Stable across refreshes - selection and the inline editor are keyed by it.
  final String id;
  final String title;
  final num agreedFee;
  final num paid;
  final num balance;
  final PaymentStatus status;

  /// A second line of context ("Guitar Beginner · Batch A"), shown when there is only one line.
  final String? context;
  final DateTime? paidOn;

  /// A small label beside the title, e.g. INDIVIDUAL for a charge that is theirs alone.
  final String? tag;

  bool get isSettled => status.isSettled;

  /// What a "mark as paid" would collect. Never negative, so an overpaid line never offers to take
  /// money back.
  num get outstanding => balance > 0 ? balance : 0;
}

/// Records what was collected. [partial] is set when the admin typed an amount rather than settling
/// in full, and is only ever offered against a single line. Throws to report a failure; the body
/// shows it and leaves the selection as it was.
typedef FeePayCallback = Future<void> Function(
    List<FeeLine> targets, String mode, String? reference, num? partial);

typedef FeeEditCallback = Future<void> Function(FeeLine line, num amount);

/// A student's fee position and the recorder for taking a payment, for either half of the profile.
///
/// Stats, the overdue notice, the expandable breakdown (select, edit a line's amount), and the
/// recorder: Cash or UPI, settle in full or record a partial amount. Callers put it at the top of a
/// list and append their own slips and history beneath.
class FeeProfileBody extends StatefulWidget {
  const FeeProfileBody({
    super.key,
    required this.lines,
    required this.noun,
    required this.selectPrompt,
    required this.selectHint,
    required this.settledText,
    required this.onPay,
    required this.onEdit,
    this.overdueText,
    this.onAddFee,
    this.addFeeLabel,
  });

  final List<FeeLine> lines;

  /// "courses" / "fee types" - how the breakdown counts its lines.
  final String noun;

  /// Above the selectable lines: "Select which course you're collecting payment for:".
  final String selectPrompt;

  /// In the recorder before anything is chosen: "Select a course above to record a payment".
  final String selectHint;

  /// When there is nothing left to collect.
  final String settledText;

  final FeePayCallback onPay;
  final FeeEditCallback onEdit;
  final String? overdueText;

  /// Other fees only: raises a new one-off charge for this student.
  final VoidCallback? onAddFee;
  final String? addFeeLabel;

  @override
  State<FeeProfileBody> createState() => _FeeProfileBodyState();
}

class _FeeProfileBodyState extends State<FeeProfileBody> {
  /// Which lines the admin is collecting for.
  ///
  /// Starts empty and is never auto-populated. Pre-selecting the line they arrived from reads as a
  /// suggestion but behaves as a selection: tapping a second line then quietly makes it a
  /// multi-select and marks something paid that nobody chose.
  final Set<String> _selected = {};

  final _amountController = TextEditingController();
  final _referenceController = TextEditingController();
  final _feeController = TextEditingController();
  String _mode = 'CASH';
  bool _open = false;
  bool _busy = false;
  String? _editingId;

  @override
  void dispose() {
    _amountController.dispose();
    _referenceController.dispose();
    _feeController.dispose();
    super.dispose();
  }

  bool get _hasBreakdown => widget.lines.length > 1;

  List<FeeLine> get _selectedLines =>
      widget.lines.where((l) => _selected.contains(l.id)).toList();

  /// The lines a payment would apply to. With one line there is nothing to choose, so it is the
  /// target whether or not it was ticked - making the admin tick a single row first is friction
  /// with no decision behind it.
  List<FeeLine> get _targets => _hasBreakdown ? _selectedLines : widget.lines;

  @override
  void didUpdateWidget(FeeProfileBody old) {
    super.didUpdateWidget(old);
    // After a combined payment the lines it settled would sit selected but un-payable.
    final settled = widget.lines.where((l) => l.isSettled).map((l) => l.id).toSet();
    if (_selected.intersection(settled).isNotEmpty) {
      _selected.removeAll(settled);
    }
    final live = widget.lines.map((l) => l.id).toSet();
    _selected.retainAll(live);
  }

  void _toast(Object error) {
    if (!mounted) return;
    showAppToast(context, error.toString().replaceFirst('Exception: ', ''), error: true);
  }

  Future<void> _pay({num? partial}) async {
    final targets = _targets.where((l) => !l.isSettled).toList();
    if (targets.isEmpty || _busy) return;
    setState(() => _busy = true);
    try {
      final ref = _mode == 'UPI' && _referenceController.text.trim().isNotEmpty
          ? _referenceController.text.trim()
          : null;
      await widget.onPay(targets, _mode, ref, partial);
      if (!mounted) return;
      _amountController.clear();
      _referenceController.clear();
      setState(() => _selected.clear());
    } catch (e) {
      _toast(e);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _saveEdit(FeeLine line) async {
    final value = num.tryParse(_feeController.text.trim());
    if (value == null || value <= 0) return;
    setState(() => _busy = true);
    try {
      await widget.onEdit(line, value);
      if (mounted) setState(() => _editingId = null);
    } catch (e) {
      _toast(e);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _startEdit(FeeLine line) => setState(() {
        _editingId = line.id;
        _feeController.text = line.agreedFee.round().toString();
      });

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final lines = widget.lines;

    if (lines.isEmpty) {
      // Nothing owed. For Other fees that is a normal state with a way forward (add the first one);
      // for a regular fee it just means no active enrolment this period.
      return widget.onAddFee == null
          ? _Banner(
              icon: Icons.info_outline,
              text: 'No active enrolment for this period',
              color: palette.textMuted,
              soft: palette.surfaceHigh,
            )
          : _EmptyOther(onAddFee: widget.onAddFee, label: widget.addFeeLabel);
    }

    final totalFee = lines.fold<num>(0, (a, l) => a + l.agreedFee);
    final totalPaid = lines.fold<num>(0, (a, l) => a + l.paid);
    final totalBalance = lines.fold<num>(0, (a, l) => a + l.outstanding);
    final targets = _targets.where((l) => !l.isSettled).toList();
    final targetTotal = targets.fold<num>(0, (a, l) => a + l.outstanding);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            StatBox(
              label: _hasBreakdown ? 'Agreed fee (all ${widget.noun})' : 'Agreed fee',
              value: money(totalFee),
            ),
            const SizedBox(width: AppSpacing.sm),
            StatBox(
              label: _hasBreakdown ? 'Paid (all ${widget.noun})' : 'Paid',
              value: money(totalPaid),
              accent: palette.paidManual,
            ),
            const SizedBox(width: AppSpacing.sm),
            StatBox(
              label: _hasBreakdown ? 'Balance (all ${widget.noun})' : 'Balance',
              value: money(totalBalance),
              accent: totalBalance > 0 ? palette.notPaid : palette.textFaint,
            ),
          ],
        ),
        if (widget.overdueText != null) ...[
          const SizedBox(height: AppSpacing.lg),
          _Banner(
            icon: Icons.event_busy_outlined,
            text: widget.overdueText!,
            color: palette.due,
            soft: palette.dueSoft,
          ),
        ],
        const SizedBox(height: AppSpacing.lg),
        _FeeCard(
          lines: lines,
          noun: widget.noun,
          selectPrompt: widget.selectPrompt,
          selected: _selected,
          open: _open,
          editingId: _editingId,
          feeController: _feeController,
          busy: _busy,
          contextLine: lines.length == 1 ? lines.first.context : null,
          totalBalance: totalBalance,
          totalFee: totalFee,
          selectedTotal: _selectedLines.fold<num>(0, (a, l) => a + l.outstanding),
          selectedCount: _selectedLines.length,
          onToggleOpen: () => setState(() => _open = !_open),
          onToggleLine: (line) => setState(() {
            _selected.contains(line.id) ? _selected.remove(line.id) : _selected.add(line.id);
            _amountController.clear();
          }),
          onStartEdit: _startEdit,
          onCancelEdit: () => setState(() => _editingId = null),
          onSaveEdit: _saveEdit,
          onAddFee: widget.onAddFee,
          addFeeLabel: widget.addFeeLabel,
        ),
        const SizedBox(height: AppSpacing.lg),
        if (_hasBreakdown && _selected.isNotEmpty && targetTotal <= 0)
          _Banner(
            icon: Icons.check_circle_outline,
            text: 'All selected ${widget.noun} are already paid',
            color: palette.paidManual,
            soft: palette.paidManualSoft,
          )
        else if (totalBalance > 0)
          _Recorder(
            targets: targets,
            total: targetTotal,
            hasBreakdown: _hasBreakdown,
            noun: widget.noun,
            selectHint: widget.selectHint,
            mode: _mode,
            busy: _busy,
            amountController: _amountController,
            referenceController: _referenceController,
            onModeChanged: (m) => setState(() => _mode = m),
            onClear: () => setState(() {
              _selected.clear();
              _amountController.clear();
            }),
            onMarkPaid: () => _pay(),
            onPartial: (amount) => _pay(partial: amount),
          )
        else
          _Banner(
            icon: Icons.check_circle_outline,
            text: widget.settledText,
            color: palette.paidManual,
            soft: palette.paidManualSoft,
          ),
      ],
    );
  }
}

/// The agreed-fee card, which becomes an expandable breakdown once there is more than one line.
class _FeeCard extends StatelessWidget {
  const _FeeCard({
    required this.lines,
    required this.noun,
    required this.selectPrompt,
    required this.selected,
    required this.open,
    required this.editingId,
    required this.feeController,
    required this.busy,
    required this.contextLine,
    required this.totalBalance,
    required this.totalFee,
    required this.selectedTotal,
    required this.selectedCount,
    required this.onToggleOpen,
    required this.onToggleLine,
    required this.onStartEdit,
    required this.onCancelEdit,
    required this.onSaveEdit,
    required this.onAddFee,
    required this.addFeeLabel,
  });

  final List<FeeLine> lines;
  final String noun;
  final String selectPrompt;
  final Set<String> selected;
  final bool open;
  final String? editingId;
  final TextEditingController feeController;
  final bool busy;
  final String? contextLine;
  final num totalBalance;
  final num totalFee;
  final num selectedTotal;
  final int selectedCount;
  final VoidCallback onToggleOpen;
  final ValueChanged<FeeLine> onToggleLine;
  final ValueChanged<FeeLine> onStartEdit;
  final VoidCallback onCancelEdit;
  final ValueChanged<FeeLine> onSaveEdit;
  final VoidCallback? onAddFee;
  final String? addFeeLabel;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final hasBreakdown = lines.length > 1;
    final single = lines.length == 1 ? lines.first : null;
    final headline = hasBreakdown ? (selectedCount > 0 ? selectedTotal : totalBalance) : totalFee;

    return Container(
      padding: const EdgeInsets.all(AppSpacing.lg),
      decoration: BoxDecoration(
        color: palette.surfaceRaised,
        borderRadius: AppRadii.all(AppRadii.x3l),
        border: Border.all(color: editingId != null && single != null ? palette.primary : palette.border),
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
                                  ? (selectedCount > 0
                                      ? 'Selected amount to be paid'
                                      : 'Balance still to be collected')
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
                      if (editingId != null && single != null)
                        _FeeEditor(
                          controller: feeController,
                          busy: busy,
                          onSave: () => onSaveEdit(single),
                          onCancel: onCancelEdit,
                        )
                      else ...[
                        Text(
                          money(headline),
                          style: TextStyle(
                            fontSize: AppType.x3l,
                            fontWeight: AppType.heavy,
                            color: hasBreakdown
                                ? (headline > 0 ? palette.notPaid : palette.paidManual)
                                : palette.text,
                          ),
                        ),
                        const SizedBox(height: 2),
                        if (hasBreakdown)
                          Text(
                            selectedCount > 0
                                ? '$selectedCount of ${lines.length} $noun selected'
                                : 'of ${money(totalFee)} across ${lines.length} $noun',
                            style: TextStyle(fontSize: AppType.tiny, color: palette.textFaint),
                          )
                        else if (single != null) ...[
                          Text.rich(
                            TextSpan(
                              text: money(single.outstanding),
                              style: TextStyle(
                                fontWeight: AppType.bold,
                                color: single.outstanding > 0 ? palette.notPaid : palette.paidManual,
                              ),
                              children: [
                                TextSpan(
                                  text: ' / ${money(single.agreedFee)} to be paid',
                                  style: TextStyle(
                                      fontWeight: AppType.regular, color: palette.textFaint),
                                ),
                              ],
                            ),
                            style: TextStyle(fontSize: AppType.xs),
                          ),
                          if (contextLine != null)
                            Text(contextLine!,
                                style: TextStyle(fontSize: AppType.tiny, color: palette.textFaint)),
                        ],
                      ],
                    ],
                  ),
                ),
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  if (!hasBreakdown && single != null && editingId == null)
                    _EditButton(onTap: () => onStartEdit(single)),
                  if (onAddFee != null) ...[
                    if (!hasBreakdown && single != null && editingId == null)
                      const SizedBox(height: AppSpacing.xs),
                    _AddFeeButton(onTap: onAddFee!, label: addFeeLabel),
                  ],
                ],
              ),
            ],
          ),
          if (hasBreakdown && open) ...[
            const SizedBox(height: AppSpacing.md),
            Divider(height: 1, color: palette.borderSoft),
            const SizedBox(height: AppSpacing.md),
            Text(selectPrompt, style: TextStyle(fontSize: AppType.xs, color: palette.textMuted)),
            const SizedBox(height: AppSpacing.sm),
            for (final line in lines)
              Padding(
                padding: const EdgeInsets.only(bottom: AppSpacing.xs),
                child: _BreakdownRow(
                  line: line,
                  selected: selected.contains(line.id),
                  editing: editingId == line.id,
                  feeController: feeController,
                  busy: busy,
                  onToggle: () => onToggleLine(line),
                  onStartEdit: () => onStartEdit(line),
                  onCancelEdit: onCancelEdit,
                  onSaveEdit: () => onSaveEdit(line),
                ),
              ),
            const SizedBox(height: AppSpacing.xs),
            Divider(height: 1, color: palette.borderSoft),
            const SizedBox(height: AppSpacing.sm),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text('Total across all $noun',
                    style: TextStyle(
                        fontSize: AppType.smd,
                        fontWeight: AppType.bold,
                        color: palette.textMuted)),
                Text(money(totalFee),
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
    required this.line,
    required this.selected,
    required this.editing,
    required this.feeController,
    required this.busy,
    required this.onToggle,
    required this.onStartEdit,
    required this.onCancelEdit,
    required this.onSaveEdit,
  });

  final FeeLine line;
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
    // A settled line can still have its amount edited - that is how a mistaken figure gets
    // corrected - but it cannot be selected for payment, because there is nothing left to collect.
    final selectable = !line.isSettled && !editing;

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
              opacity: line.isSettled && !editing ? 0.55 : 1,
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
                          Row(
                            children: [
                              Flexible(
                                child: Text(
                                  line.title,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    fontSize: AppType.smd,
                                    fontWeight: AppType.medium,
                                    color: palette.text,
                                  ),
                                ),
                              ),
                              if (line.tag != null) ...[
                                const SizedBox(width: AppSpacing.xs),
                                StatusBadge(
                                  label: line.tag!,
                                  color: palette.gold,
                                  softColor: palette.goldSoft,
                                  dense: true,
                                ),
                              ],
                            ],
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
                          else if (line.isSettled)
                            Text(money(line.agreedFee),
                                style: TextStyle(fontSize: AppType.xs, color: palette.textFaint))
                          else
                            Text.rich(TextSpan(
                              text: money(line.outstanding),
                              style: TextStyle(
                                fontSize: AppType.xs,
                                fontWeight: AppType.heavy,
                                color: line.status == PaymentStatus.partial
                                    ? palette.partial
                                    : palette.notPaid,
                              ),
                              children: [
                                TextSpan(
                                  text: '/${money(line.agreedFee)}',
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
              label: statusLabel(line.status),
              color: line.status.color(palette),
              softColor: line.status.softColor(palette),
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
/// Not save-on-blur: the agreed fee is what a family is charged, and a stray tap elsewhere must not
/// be able to commit a half-typed number.
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
                    fontSize: AppType.smd, fontWeight: AppType.bold, color: palette.primary)),
          ],
        ),
      ),
    );
  }
}

class _AddFeeButton extends StatelessWidget {
  const _AddFeeButton({required this.onTap, this.label});

  final VoidCallback onTap;
  final String? label;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return Pressable(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md, vertical: AppSpacing.sm),
        decoration: BoxDecoration(
          borderRadius: AppRadii.all(AppRadii.md),
          border: Border.all(color: palette.border),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.add_rounded, size: 13, color: palette.textMuted),
            const SizedBox(width: AppSpacing.xxs),
            Text(label ?? 'Add fee',
                style: TextStyle(
                    fontSize: AppType.xs, fontWeight: AppType.bold, color: palette.textMuted)),
          ],
        ),
      ),
    );
  }
}

/// A student with no Other fees at all - a newly joined one. The tab still has to open, or there is
/// nowhere to add their first one-off charge from.
class _EmptyOther extends StatelessWidget {
  const _EmptyOther({required this.onAddFee, this.label});

  final VoidCallback? onAddFee;
  final String? label;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return Container(
      padding: const EdgeInsets.all(AppSpacing.x4l),
      decoration: BoxDecoration(
        color: palette.surfaceRaised,
        borderRadius: AppRadii.all(AppRadii.x3l),
        border: Border.all(color: palette.border),
      ),
      child: Column(
        children: [
          Icon(Icons.receipt_long_outlined, size: 28, color: palette.textFaint),
          const SizedBox(height: AppSpacing.md),
          Text(
            'No fees yet',
            textAlign: TextAlign.center,
            style: TextStyle(
                fontSize: AppType.lg, fontWeight: AppType.bold, color: palette.text),
          ),
          const SizedBox(height: AppSpacing.xs),
          Text(
            "This student isn't linked to any Other Fees record - maybe they just joined. Add one "
            'below, like a uniform or book fee, just for them.',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: AppType.smd, color: palette.textMuted, height: 1.5),
          ),
          if (onAddFee != null) ...[
            const SizedBox(height: AppSpacing.lg),
            AppPrimaryButton(label: label ?? 'Add fee', icon: Icons.add, onPressed: onAddFee),
          ],
        ],
      ),
    );
  }
}

/// The payment recorder: Cash or UPI, then either settle in full or record a partial amount.
///
/// Only Cash and UPI. A gateway payment is the student paying online, which this screen cannot
/// take on their behalf.
class _Recorder extends StatelessWidget {
  const _Recorder({
    required this.targets,
    required this.total,
    required this.hasBreakdown,
    required this.noun,
    required this.selectHint,
    required this.mode,
    required this.busy,
    required this.amountController,
    required this.referenceController,
    required this.onModeChanged,
    required this.onClear,
    required this.onMarkPaid,
    required this.onPartial,
  });

  final List<FeeLine> targets;
  final num total;
  final bool hasBreakdown;
  final String noun;
  final String selectHint;
  final String mode;
  final bool busy;
  final TextEditingController amountController;
  final TextEditingController referenceController;
  final ValueChanged<String> onModeChanged;
  final VoidCallback onClear;
  final VoidCallback onMarkPaid;
  final ValueChanged<num> onPartial;

  static const _modes = [('CASH', 'Cash'), ('UPI', 'UPI')];

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final needsSelection = hasBreakdown && targets.isEmpty;
    final multi = targets.length > 1;
    // A partial against several lines at once needs a split rule nobody has decided, so it is
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
                    if (targets.length == 1 && hasBreakdown)
                      TextSpan(
                        text: ' · ${targets.first.title}',
                        style: TextStyle(color: palette.primary),
                      )
                    else if (multi)
                      TextSpan(
                        text: ' · ${targets.length} $noun',
                        style: TextStyle(color: palette.primary),
                      ),
                  ],
                )),
              ),
              if (hasBreakdown && targets.isNotEmpty)
                Pressable(
                  onTap: onClear,
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
                      child: Text(t.title,
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
          if (mode == 'UPI') ...[
            const SizedBox(height: AppSpacing.sm),
            TextField(
              controller: referenceController,
              style: TextStyle(fontSize: AppType.md, color: palette.text),
              decoration: _fieldDecoration(palette, 'UPI transaction ID (optional)'),
            ),
          ],
          if (needsSelection) ...[
            const SizedBox(height: AppSpacing.md),
            Text(
              selectHint,
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
                  : 'Select a single ${noun == 'courses' ? 'course' : 'fee'} to pay part of it',
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
