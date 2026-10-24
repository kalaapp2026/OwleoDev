import 'package:flutter/material.dart';
import 'package:nest_fe/core/auth/feature_keys.dart';
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
import 'package:nest_fe/features/enrolment/data/enrolment_api.dart';
import 'package:nest_fe/features/fees/presentation/fee_format.dart';
import 'package:nest_fe/features/fees/data/fee_type.dart';
import 'package:nest_fe/features/fees/presentation/fees_screen.dart' show feesApiProvider;
import 'package:nest_fe/features/fees/presentation/widgets/payment_methods_field.dart';

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
  // Only courses the caller holds Fees entry on - the server refuses a fee type on any other.
  final courses = await ref.watch(coursesForFeatureProvider(FeatureKeys.feesEntry).future);
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

/// Create - or, given a [feeType], edit - a shared "Other" fee: costume, exam, annual day.
class AddFeeTypeScreen extends ConsumerStatefulWidget {
  const AddFeeTypeScreen({super.key, this.feeType, this.existingNames = const []});

  /// The fee being edited. Null creates a new one.
  final FeeType? feeType;

  /// Lower-cased names of the OTHER fees, so a duplicate is flagged as it is typed rather than after
  /// the server refuses it. Excludes the fee being edited - keeping its own name is not a clash.
  final List<String> existingNames;

  bool get isEdit => feeType != null;

  @override
  ConsumerState<AddFeeTypeScreen> createState() => _AddFeeTypeScreenState();
}

class _AddFeeTypeScreenState extends ConsumerState<AddFeeTypeScreen> {
  final _nameController = TextEditingController();
  final _amountController = TextEditingController();
  final List<_BatchOption> _batches = [];
  DateTime? _dueDate;
  // In the order they were switched on: the first is the fee's default method.
  final List<String> _methods = ['CASH'];
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    final fee = widget.feeType;
    if (fee == null) return;
    _nameController.text = fee.name;
    _amountController.text = fee.amount.round().toString();
    _dueDate = fee.dueDate;
    for (final b in fee.batches) {
      _batches.add(_BatchOption(id: b.batchId, label: b.label));
    }
    final methods = fee.paymentMethods.isNotEmpty
        ? fee.paymentMethods
        : [if (fee.defaultMode != null) fee.defaultMode!];
    if (methods.isNotEmpty) {
      _methods
        ..clear()
        ..addAll(methods);
    }
  }

  @override
  void dispose() {
    _nameController.dispose();
    _amountController.dispose();
    super.dispose();
  }

  /// At least one batch is required: a fee type bound to nothing applies to nobody, so it would
  /// sit in the catalogue looking real while charging no one.
  bool get _duplicate =>
      widget.existingNames.contains(_nameController.text.trim().toLowerCase());

  bool get _valid =>
      _nameController.text.trim().length > 1 &&
      (num.tryParse(_amountController.text.trim()) ?? 0) > 0 &&
      _batches.isNotEmpty &&
      !_duplicate &&
      _methods.isNotEmpty;

  void _toggleMethod(String method) => setState(() {
        _methods.contains(method) ? _methods.remove(method) : _methods.add(method);
      });

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
      final api = ref.read(feesApiProvider);
      final name = _nameController.text.trim();
      final amount = num.parse(_amountController.text.trim());
      final batchIds = _batches.map((b) => b.id).toList();
      if (widget.isEdit) {
        await api.updateFeeType(
          feeTypeId: widget.feeType!.id,
          name: name,
          amount: amount,
          batchIds: batchIds,
          dueDate: _dueDate,
          paymentMethods: List.of(_methods),
        );
      } else {
        await api.createFeeType(
          name: name,
          amount: amount,
          batchIds: batchIds,
          dueDate: _dueDate,
          defaultMode: _methods.first,
          paymentMethods: List.of(_methods),
        );
      }
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
        title: Text(widget.isEdit ? 'Edit Fee Type' : 'Add Fee Type'),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(
            AppSpacing.xl, AppSpacing.md, AppSpacing.xl, AppSpacing.x5l),
        children: [
          Text(widget.isEdit ? 'Changes apply to this fee type only' : 'Create a new other-fee category',
              style: TextStyle(fontSize: AppType.smd, color: palette.textMuted)),
          const SizedBox(height: AppSpacing.xl),
          _Field(
            label: 'Fee type name',
            hint: _duplicate ? 'A fee type with this name already exists' : null,
            hintColor: _duplicate ? palette.notPaid : null,
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
            label: 'Payment method',
            hint: 'Which methods are accepted for this fee type - more than one is fine',
            child: PaymentMethodsField(selected: _methods, onToggle: _toggleMethod),
          ),
          const SizedBox(height: AppSpacing.lg),
          AppPrimaryButton(
            label: widget.isEdit ? 'Save changes' : 'Create fee type',
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
  const _Field({required this.label, required this.child, this.hint, this.hintColor});

  final String label;
  final Widget child;
  final String? hint;
  final Color? hintColor;

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
            Text(hint!,
                style: TextStyle(fontSize: AppType.xs, color: hintColor ?? palette.textFaint)),
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
