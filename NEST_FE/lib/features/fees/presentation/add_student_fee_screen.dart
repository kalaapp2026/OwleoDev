import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:nest_fe/app/theme/app_tokens.dart';
import 'package:nest_fe/app/theme/app_typography.dart';
import 'package:nest_fe/core/design/app_text_field.dart';
import 'package:nest_fe/core/design/buttons.dart';
import 'package:nest_fe/core/design/calendar_modal.dart';
import 'package:nest_fe/core/design/pressable.dart';
import 'package:nest_fe/features/fees/presentation/fee_format.dart';
import 'package:nest_fe/features/fees/data/fees_api.dart' show feesApiProvider;
import 'package:nest_fe/features/fees/presentation/widgets/payment_methods_field.dart';

/// A one-off charge for a single student - a replacement book, an extra costume.
///
/// Deliberately not a fee type with one batch: this belongs to a person, not a group, and
/// modelling it as a group of one would put it into every batch-level total.
class AddStudentFeeScreen extends ConsumerStatefulWidget {
  const AddStudentFeeScreen({
    super.key,
    required this.membershipId,
    required this.studentName,
  });

  final String membershipId;
  final String studentName;

  @override
  ConsumerState<AddStudentFeeScreen> createState() => _AddStudentFeeScreenState();
}

class _AddStudentFeeScreenState extends ConsumerState<AddStudentFeeScreen> {
  final _nameController = TextEditingController();
  final _amountController = TextEditingController();
  final _noteController = TextEditingController();
  DateTime? _dueDate;
  // In the order they were switched on: the first is the fee's default method.
  final List<String> _methods = ['CASH'];
  bool _busy = false;

  @override
  void dispose() {
    _nameController.dispose();
    _amountController.dispose();
    _noteController.dispose();
    super.dispose();
  }

  // The same rules the fields show under themselves, so the button and the messages agree.
  static final _nameRule = FieldPreset.title(label: 'fee name', max: 80);
  static final _amountRule = FieldPreset.wholeNumber(label: 'amount', min: 1, max: 1000000);
  static final _noteRule = FieldPreset.text(label: 'note', max: 300, required: false);

  bool get _valid =>
      _nameRule.check(_nameController.text) == null &&
      _amountRule.check(_amountController.text) == null &&
      _noteRule.check(_noteController.text) == null &&
      _methods.isNotEmpty;

  void _toggleMethod(String method) => setState(() {
        _methods.contains(method) ? _methods.remove(method) : _methods.add(method);
      });

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
      await ref.read(feesApiProvider).createStudentFee(
            membershipId: widget.membershipId,
            name: _nameController.text.trim(),
            amount: num.parse(_amountController.text.trim()),
            dueDate: _dueDate,
            defaultMode: _methods.first,
            paymentMethods: List.of(_methods),
            note: _noteController.text.trim().isEmpty ? null : _noteController.text.trim(),
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
        title: const Text('Add Fee'),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(
            AppSpacing.xl, AppSpacing.md, AppSpacing.xl, AppSpacing.x5l),
        children: [
          Container(
            padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.md, vertical: AppSpacing.md),
            decoration: BoxDecoration(
              color: palette.primarySoft,
              borderRadius: AppRadii.all(AppRadii.lg),
              border: Border.all(color: palette.primaryDim),
            ),
            child: Row(
              children: [
                Icon(Icons.person_outline, size: 15, color: palette.primary),
                const SizedBox(width: AppSpacing.sm),
                Expanded(
                  child: Text(
                    'This fee applies only to ${widget.studentName}, not the whole batch',
                    style: TextStyle(
                      fontSize: AppType.smd,
                      fontWeight: AppType.semi,
                      color: palette.primary,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: AppSpacing.xl),
          _Field(
            label: 'Fee name',
            child: CheckedField(
              controller: _nameController,
              preset: _nameRule,
              builder: (context, hasError) => TextField(
                controller: _nameController,
                onChanged: (_) => setState(() {}),
                textCapitalization: _nameRule.textCapitalization,
                inputFormatters: _nameRule.formatters,
                style: _inputStyle(palette),
                decoration: _decoration(palette, 'e.g. Extra costume, replacement book'),
              ),
            ),
          ),
          _Field(
            label: 'Amount',
            child: CheckedField(
              controller: _amountController,
              preset: _amountRule,
              builder: (context, hasError) => TextField(
              controller: _amountController,
              onChanged: (_) => setState(() {}),
              keyboardType: _amountRule.keyboardType,
              inputFormatters: _amountRule.formatters,
              style: _inputStyle(palette),
              decoration: _decoration(palette, 'e.g. 350').copyWith(
                prefixText: '₹',
                prefixStyle: TextStyle(fontSize: AppType.md, color: palette.textFaint),
              ),
              ),
            ),
          ),
          _Field(
            label: 'Last date to pay',
            hint: 'Optional. Unpaid after this date reads as "Due".',
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
            hint: 'Tap to select which methods are accepted for this fee - more than one is fine',
            child: PaymentMethodsField(selected: _methods, onToggle: _toggleMethod),
          ),
          _Field(
            label: 'Note',
            hint: 'Optional. Why this charge exists, for whoever reads it later.',
            child: CheckedField(
              controller: _noteController,
              preset: _noteRule,
              builder: (context, hasError) => TextField(
                controller: _noteController,
                maxLines: 2,
                onChanged: (_) => setState(() {}),
                textCapitalization: _noteRule.textCapitalization,
                inputFormatters: _noteRule.formatters,
                style: TextStyle(fontSize: AppType.lg, color: palette.text),
                decoration: _decoration(palette, 'e.g. Replaced a damaged costume'),
              ),
            ),
          ),
          const SizedBox(height: AppSpacing.sm),
          AppPrimaryButton(
            label: 'Add fee for ${widget.studentName}',
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
