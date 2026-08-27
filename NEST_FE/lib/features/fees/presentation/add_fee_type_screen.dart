import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:nest_fe/app/theme/app_tokens.dart';
import 'package:nest_fe/app/theme/app_typography.dart';
import 'package:nest_fe/core/design/buttons.dart';
import 'package:nest_fe/core/design/calendar_modal.dart';
import 'package:nest_fe/core/design/pressable.dart';
import 'package:nest_fe/core/design/sheets.dart';
import 'package:nest_fe/features/curriculum/data/curriculum_api.dart';
import 'package:nest_fe/features/enrolment/data/batch.dart';
import 'package:nest_fe/features/enrolment/presentation/batches_screen.dart';
import 'package:nest_fe/features/fees/presentation/fee_format.dart';
import 'package:nest_fe/features/fees/presentation/fees_screen.dart' show feesApiProvider;

/// A batch of one course, labelled so it reads unambiguously in a picker.
///
/// "Batch A" alone is useless when every course has one, so the option carries its course.
class _BatchOption {
  const _BatchOption({required this.id, required this.label});

  final String id;
  final String label;

  @override
  bool operator ==(Object other) => other is _BatchOption && other.id == id;

  @override
  int get hashCode => id.hashCode;
}

/// Every active batch across every course, for the fee type's batch picker.
final _allBatchesProvider = FutureProvider.autoDispose<List<_BatchOption>>((ref) async {
  final courses = await ref.watch(activeCoursesProvider.future);
  final api = ref.watch(enrolmentApiProvider);
  final options = <_BatchOption>[];
  for (final course in courses) {
    final batches = await api.batchesForCourse(course.id);
    for (final Batch batch in batches.where((b) => b.status == 'ACTIVE')) {
      options.add(_BatchOption(id: batch.id, label: '${course.name} · ${batch.name}'));
    }
  }
  options.sort((a, b) => a.label.toLowerCase().compareTo(b.label.toLowerCase()));
  return options;
});

/// Create a shared "Other" fee - costume, exam, annual day.
class AddFeeTypeScreen extends ConsumerStatefulWidget {
  const AddFeeTypeScreen({super.key});

  @override
  ConsumerState<AddFeeTypeScreen> createState() => _AddFeeTypeScreenState();
}

class _AddFeeTypeScreenState extends ConsumerState<AddFeeTypeScreen> {
  final _nameController = TextEditingController();
  final _amountController = TextEditingController();
  final List<_BatchOption> _batches = [];
  DateTime? _dueDate;
  String _mode = 'CASH';
  bool _busy = false;

  @override
  void dispose() {
    _nameController.dispose();
    _amountController.dispose();
    super.dispose();
  }

  /// At least one batch is required: a fee type bound to nothing applies to nobody, so it would
  /// sit in the catalogue looking real while charging no one.
  bool get _valid =>
      _nameController.text.trim().length > 1 &&
      (num.tryParse(_amountController.text.trim()) ?? 0) > 0 &&
      _batches.isNotEmpty;

  Future<void> _pickBatches() async {
    final all = await ref.read(_allBatchesProvider.future);
    if (!mounted) return;
    final picked = await showAppMultiSelectSheet<_BatchOption>(
      context: context,
      title: 'Select batches',
      options: all,
      labelOf: (b) => b.label,
      initialSelection: _batches,
    );
    if (picked != null) setState(() => _batches..clear()..addAll(picked));
  }

  Future<void> _pickDueDate() async {
    final picked = await showAppCalendar(
      context: context,
      month: _dueDate ?? DateTime.now(),
      selectedDay: _dueDate?.day,
    );
    if (picked != null) setState(() => _dueDate = picked);
  }

  Future<void> _create() async {
    if (!_valid || _busy) return;
    setState(() => _busy = true);
    try {
      await ref.read(feesApiProvider).createFeeType(
            name: _nameController.text.trim(),
            amount: num.parse(_amountController.text.trim()),
            batchIds: _batches.map((b) => b.id).toList(),
            dueDate: _dueDate,
            defaultMode: _mode,
          );
      if (mounted) Navigator.of(context).pop(true);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(e.toString().replaceFirst('Exception: ', ''))),
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;

    return Scaffold(
      backgroundColor: palette.bg,
      appBar: AppBar(
        backgroundColor: palette.bg,
        title: const Text('Add Fee Type'),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(
            AppSpacing.xl, AppSpacing.md, AppSpacing.xl, AppSpacing.x5l),
        children: [
          Text('Create a new other-fee category',
              style: TextStyle(fontSize: AppType.smd, color: palette.textMuted)),
          const SizedBox(height: AppSpacing.xl),
          _Field(
            label: 'Fee type name',
            child: TextField(
              controller: _nameController,
              onChanged: (_) => setState(() {}),
              style: _inputStyle(palette),
              decoration: _decoration(palette, 'e.g. Recital Fee'),
            ),
          ),
          _Field(
            label: 'Amount',
            child: TextField(
              controller: _amountController,
              onChanged: (_) => setState(() {}),
              keyboardType: TextInputType.number,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              style: _inputStyle(palette),
              decoration: _decoration(palette, 'e.g. 600').copyWith(
                prefixText: '₹',
                prefixStyle: TextStyle(fontSize: AppType.md, color: palette.textFaint),
              ),
            ),
          ),
          _Field(
            label: 'Batches',
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Pressable(
                  onTap: _pickBatches,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: AppSpacing.lg, vertical: AppSpacing.md),
                    decoration: BoxDecoration(
                      color: palette.surfaceRaised,
                      borderRadius: AppRadii.all(AppRadii.lg),
                      border: Border.all(color: palette.border),
                    ),
                    child: Row(
                      children: [
                        Expanded(
                          child: Text(
                            _batches.isEmpty
                                ? 'Select one or more batches'
                                : _batches.length <= 2
                                    ? _batches.map((b) => b.label).join(', ')
                                    : '${_batches.length} batches selected',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: AppType.lg,
                              fontWeight:
                                  _batches.isEmpty ? AppType.regular : AppType.semi,
                              color: _batches.isEmpty ? palette.textMuted : palette.text,
                            ),
                          ),
                        ),
                        Icon(Icons.keyboard_arrow_down_rounded,
                            size: 18, color: palette.textMuted),
                      ],
                    ),
                  ),
                ),
                if (_batches.isNotEmpty) ...[
                  const SizedBox(height: AppSpacing.sm),
                  Wrap(
                    spacing: AppSpacing.xs,
                    runSpacing: AppSpacing.xs,
                    children: [
                      for (final batch in _batches)
                        _RemovableChip(
                          label: batch.label,
                          onRemove: () => setState(() => _batches.remove(batch)),
                        ),
                    ],
                  ),
                ],
              ],
            ),
          ),
          _Field(
            label: 'Last date to pay',
            hint: 'Students unpaid after this date are marked "Due"',
            child: Pressable(
              onTap: _pickDueDate,
              child: Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: AppSpacing.lg, vertical: AppSpacing.md),
                decoration: BoxDecoration(
                  color: palette.surfaceRaised,
                  borderRadius: AppRadii.all(AppRadii.lg),
                  border: Border.all(color: palette.border),
                ),
                child: Row(
                  children: [
                    Icon(Icons.calendar_today_outlined, size: 15, color: palette.primary),
                    const SizedBox(width: AppSpacing.sm),
                    Expanded(
                      child: Text(
                        // Optional: an open-ended charge, like a shop purchase, has no last date.
                        _dueDate == null ? 'Optional' : formatFeeDate(_dueDate!),
                        style: TextStyle(
                          fontSize: AppType.lg,
                          fontWeight: _dueDate == null ? AppType.regular : AppType.semi,
                          color: _dueDate == null ? palette.textMuted : palette.text,
                        ),
                      ),
                    ),
                    if (_dueDate != null)
                      Pressable(
                        onTap: () => setState(() => _dueDate = null),
                        child: Icon(Icons.close_rounded, size: 15, color: palette.textFaint),
                      ),
                  ],
                ),
              ),
            ),
          ),
          _Field(
            label: 'Default payment method',
            hint: 'Pre-selects the mode when collecting. Not a restriction.',
            child: Row(
              children: [
                for (final (value, label) in const [
                  ('CASH', 'Cash'),
                  ('UPI', 'UPI'),
                  ('GATEWAY', 'Gateway')
                ]) ...[
                  Expanded(
                    child: _ModeButton(
                      label: label,
                      selected: _mode == value,
                      onTap: () => setState(() => _mode = value),
                    ),
                  ),
                  if (value != 'GATEWAY') const SizedBox(width: AppSpacing.xs),
                ],
              ],
            ),
          ),
          const SizedBox(height: AppSpacing.lg),
          AppPrimaryButton(
            label: 'Create fee type',
            icon: Icons.check,
            busy: _busy,
            onPressed: _valid ? _create : null,
          ),
        ],
      ),
    );
  }

  TextStyle _inputStyle(AppPalette palette) => TextStyle(
        fontSize: AppType.xxl,
        fontWeight: AppType.semi,
        color: palette.text,
      );

  InputDecoration _decoration(AppPalette palette, String hint) => InputDecoration(
        isDense: true,
        hintText: hint,
        hintStyle: TextStyle(
            fontSize: AppType.lg, fontWeight: AppType.regular, color: palette.textFaint),
        filled: true,
        fillColor: palette.surfaceRaised,
        contentPadding:
            const EdgeInsets.symmetric(horizontal: AppSpacing.lg, vertical: AppSpacing.md),
        border: OutlineInputBorder(
          borderRadius: AppRadii.all(AppRadii.lg),
          borderSide: BorderSide(color: palette.border),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: AppRadii.all(AppRadii.lg),
          borderSide: BorderSide(color: palette.border),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: AppRadii.all(AppRadii.lg),
          borderSide: BorderSide(color: palette.primary),
        ),
      );
}

class _Field extends StatelessWidget {
  const _Field({required this.label, required this.child, this.hint});

  final String label;
  final Widget child;
  final String? hint;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.xl),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(label.toUpperCase(), style: AppType.sectionLabel(palette.textMuted)),
          const SizedBox(height: AppSpacing.sm),
          child,
          if (hint != null) ...[
            const SizedBox(height: AppSpacing.xs),
            Text(hint!, style: TextStyle(fontSize: AppType.xs, color: palette.textFaint)),
          ],
        ],
      ),
    );
  }
}

class _RemovableChip extends StatelessWidget {
  const _RemovableChip({required this.label, required this.onRemove});

  final String label;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm, vertical: 4),
      decoration: BoxDecoration(
        color: palette.primarySoft,
        borderRadius: AppRadii.all(AppRadii.sm),
        border: Border.all(color: palette.primaryDim),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(label,
              style: TextStyle(
                  fontSize: AppType.smd,
                  fontWeight: AppType.semi,
                  color: palette.primary)),
          const SizedBox(width: AppSpacing.xxs),
          Pressable(
            onTap: onRemove,
            child: Icon(Icons.close_rounded, size: 12, color: palette.primary),
          ),
        ],
      ),
    );
  }
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
        padding: const EdgeInsets.symmetric(vertical: AppSpacing.md),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: selected ? palette.goldSoft : Colors.transparent,
          borderRadius: AppRadii.all(AppRadii.md),
          border: Border.all(color: selected ? palette.gold : palette.border),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (selected) ...[
              Icon(Icons.check_rounded, size: 13, color: palette.gold),
              const SizedBox(width: AppSpacing.xxs),
            ],
            Text(
              label,
              style: TextStyle(
                fontSize: AppType.md,
                fontWeight: AppType.bold,
                color: selected ? palette.gold : palette.textMuted,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
