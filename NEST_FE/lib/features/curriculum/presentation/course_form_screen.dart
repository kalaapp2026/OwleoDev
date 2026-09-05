import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:nest_fe/app/theme/app_tokens.dart';
import 'package:nest_fe/app/theme/app_typography.dart';
import 'package:nest_fe/core/design/attached_select.dart';
import 'package:nest_fe/core/design/buttons.dart';
import 'package:nest_fe/core/design/category_meta.dart';
import 'package:nest_fe/core/design/course_icons.dart';
import 'package:nest_fe/core/design/day_of_month_field.dart';
import 'package:nest_fe/core/design/pressable.dart';
import 'package:nest_fe/core/design/segmented_control.dart';
import 'package:nest_fe/core/format/money.dart';
import 'package:nest_fe/features/curriculum/data/course.dart';
import 'package:nest_fe/features/curriculum/data/curriculum_api.dart';

/// Cap borrowed from the prototype. A course description is a one-line orientation on a list row,
/// not a prospectus - the counter is shown so the limit is visible before it's hit.
const _descriptionLimit = 100;

/// Create or edit a course. Pops `true` when something was saved, so the list knows to refetch.
class CourseFormScreen extends ConsumerStatefulWidget {
  const CourseFormScreen({super.key, this.existing});

  final Course? existing;

  @override
  ConsumerState<CourseFormScreen> createState() => _CourseFormScreenState();
}

class _CourseFormScreenState extends ConsumerState<CourseFormScreen> {
  late final _nameController = TextEditingController(text: widget.existing?.name ?? '');
  late final _descriptionController =
      TextEditingController(text: widget.existing?.description ?? '');
  late final _feeController =
      TextEditingController(text: widget.existing?.defaultFee?.round().toString() ?? '');
  late final _feePerClassController =
      TextEditingController(text: widget.existing?.feePerClass?.round().toString() ?? '');
  late final _expectedClassesController = TextEditingController(
      text: widget.existing?.hybridExpectedClassesPerPeriod?.toString() ?? '');
  late final _thresholdController =
      TextEditingController(text: widget.existing?.hybridThresholdAttendance?.toString() ?? '');
  late final _belowPercentController = TextEditingController(
      text: widget.existing?.hybridFeeBelowThresholdPercent?.toString() ?? '');

  late CourseCategory _category = widget.existing?.category.let(
        (c) => c == CourseCategory.unknown ? CourseCategory.music : c,
      ) ??
      CourseCategory.music;

  late String _iconKey =
      resolveCourseIcon(iconKey: widget.existing?.iconKey, category: _category).key;

  late FeeModel _feeModel = widget.existing?.feeModel ?? FeeModel.fixed;
  late FeeCycle _feeCycle = widget.existing?.feeCycle ?? FeeCycle.monthly;
  late int? _billingDay = widget.existing?.billingDayOfMonth;
  late int? _dueDay = widget.existing?.dueDayOfMonth;
  // Mutated in place by the payment-method control, so it is a growable copy rather than the
  // model's own set.
  late final Set<PaymentMethod> _paymentMethods =
      widget.existing?.paymentMethods.toSet() ?? {PaymentMethod.cash};
  late bool _active = widget.existing?.isActive ?? true;

  bool _iconPickerOpen = false;
  bool _busy = false;

  bool get _isEditing => widget.existing != null;

  @override
  void dispose() {
    _nameController.dispose();
    _descriptionController.dispose();
    _feeController.dispose();
    _feePerClassController.dispose();
    _expectedClassesController.dispose();
    _thresholdController.dispose();
    _belowPercentController.dispose();
    super.dispose();
  }

  int? _intOf(TextEditingController c) => int.tryParse(c.text.trim());

  /// Mirrors the backend's per-model requirements, so the button disables rather than letting the
  /// admin submit into a 400 they then have to decode.
  bool get _billingValid => _feeModel == FeeModel.perClass
      ? (_intOf(_feePerClassController) ?? 0) > 0
      : (_intOf(_feeController) ?? 0) > 0;

  bool get _hybridValid => _feeModel != FeeModel.hybrid ||
      ((_intOf(_thresholdController) ?? 0) > 0 && (_intOf(_belowPercentController) ?? -1) >= 0);

  bool get _valid =>
      _nameController.text.trim().length > 1 &&
      _billingValid &&
      _hybridValid &&
      _billingDay != null &&
      _dueDay != null &&
      _paymentMethods.isNotEmpty;

  void _selectCategory(CourseCategory category) {
    setState(() {
      _category = category;
      // The chosen icon usually belongs to the old category's set. Snapping to the new
      // category's general icon is better than leaving a guitar on a Fine Arts course, and the
      // picker below is right there to choose something specific.
      if (!iconsForCategory(category).any((s) => s.key == _iconKey)) {
        _iconKey = iconsForCategory(category).first.key;
      }
    });
  }

  Future<void> _save() async {
    if (!_valid || _busy) return;
    setState(() => _busy = true);

    final api = ref.read(curriculumApiProvider);
    final description = _descriptionController.text.trim();

    try {
      if (_isEditing) {
        await api.updateCourse(
          widget.existing!.id,
          category: _category,
          name: _nameController.text.trim(),
          description: description.isEmpty ? null : description,
          durationLevel: widget.existing!.durationLevel,
          feeModel: _feeModel,
          defaultFee: _feeModel == FeeModel.perClass ? null : _intOf(_feeController),
          feePerClass: _feeModel == FeeModel.perClass ? _intOf(_feePerClassController) : null,
          hybridExpectedClassesPerPeriod:
              _feeModel == FeeModel.hybrid ? _intOf(_expectedClassesController) : null,
          hybridThresholdAttendance:
              _feeModel == FeeModel.hybrid ? _intOf(_thresholdController) : null,
          hybridFeeAboveThresholdPercent: _feeModel == FeeModel.hybrid ? 100 : null,
          hybridFeeBelowThresholdPercent:
              _feeModel == FeeModel.hybrid ? _intOf(_belowPercentController) : null,
          hybridMinFeeAmount: widget.existing!.hybridMinFeeAmount,
          thumbnailUrl: widget.existing!.thumbnailUrl,
          billingDayOfMonth: _billingDay,
          dueDayOfMonth: _dueDay,
          paymentMethods: _paymentMethods,
          iconKey: _iconKey,
        );
        // Status has its own endpoint, and only needs calling when it actually changed.
        if (_active != widget.existing!.isActive) {
          await api.setStatus(widget.existing!.id, _active ? 'ACTIVE' : 'INACTIVE');
        }
      } else {
        final created = await api.createCourse(
          category: _category,
          name: _nameController.text.trim(),
          description: description.isEmpty ? null : description,
          feeModel: _feeModel,
          defaultFee: _feeModel == FeeModel.perClass ? null : _intOf(_feeController),
          feePerClass: _feeModel == FeeModel.perClass ? _intOf(_feePerClassController) : null,
          hybridExpectedClassesPerPeriod:
              _feeModel == FeeModel.hybrid ? _intOf(_expectedClassesController) : null,
          hybridThresholdAttendance:
              _feeModel == FeeModel.hybrid ? _intOf(_thresholdController) : null,
          hybridFeeAboveThresholdPercent: _feeModel == FeeModel.hybrid ? 100 : null,
          hybridFeeBelowThresholdPercent:
              _feeModel == FeeModel.hybrid ? _intOf(_belowPercentController) : null,
          feeCycle: _feeCycle,
          billingDayOfMonth: _billingDay,
          dueDayOfMonth: _dueDay,
          paymentMethods: _paymentMethods,
          iconKey: _iconKey,
        );
        // A course created as Inactive is legitimate - setting it up ahead of a term start.
        if (!_active) await api.setStatus(created.id, 'INACTIVE');
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
    final meta = _category.meta(palette);

    return Scaffold(
      backgroundColor: palette.bg,
      appBar: AppBar(
        backgroundColor: palette.bg,
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              _isEditing ? 'Edit Course' : 'Add Course',
              style: TextStyle(
                  fontSize: 17, fontWeight: AppType.bold, color: palette.text),
            ),
            Text(
              _isEditing ? widget.existing!.name : 'Create a new course',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: AppType.smd, color: palette.textMuted),
            ),
          ],
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(
            AppSpacing.page, AppSpacing.xxl, AppSpacing.page, AppSpacing.x5l),
        children: [
          _Field(
            label: 'Course name',
            child: _textField(palette, _nameController, 'e.g. Guitar Beginner'),
          ),
          _Field(
            label: 'Category',
            child: AttachedSelect<CourseCategory>(
              label: 'Category',
              options: CourseCategory.selectable,
              labelOf: (c) => c.label,
              value: _category,
              searchable: true,
              searchHint: 'Search category',
              onSelected: _selectCategory,
              optionBuilder: (context, option, _) {
                final m = option.meta(palette);
                final selected = option == _category;
                return Row(
                  children: [
                    Container(
                      width: 9,
                      height: 9,
                      decoration: BoxDecoration(color: m.color, shape: BoxShape.circle),
                    ),
                    const SizedBox(width: AppSpacing.md),
                    Text(
                      option.label,
                      style: TextStyle(
                        fontSize: AppType.xl,
                        fontWeight: selected ? AppType.bold : AppType.regular,
                        color: selected ? m.color : palette.text,
                      ),
                    ),
                  ],
                );
              },
            ),
          ),
          _Field(
            label: 'Icon',
            child: _iconPicker(palette, meta),
          ),
          _Field(
            label: 'Description (optional)',
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                TextField(
                  controller: _descriptionController,
                  maxLines: 3,
                  maxLength: _descriptionLimit,
                  onChanged: (_) => setState(() {}),
                  buildCounter: (_, {required currentLength, required isFocused, maxLength}) =>
                      null,
                  style: TextStyle(
                    fontSize: AppType.lg,
                    fontWeight: AppType.regular,
                    height: 1.5,
                    color: palette.text,
                  ),
                  decoration: _decoration(
                      palette, 'Briefly describe this course (up to 100 characters)'),
                ),
                const SizedBox(height: AppSpacing.xxs),
                Text(
                  '${_descriptionController.text.length}/$_descriptionLimit characters',
                  style: TextStyle(
                    fontSize: AppType.xs,
                    color: _descriptionController.text.length >= _descriptionLimit
                        ? palette.notPaid
                        : palette.textFaint,
                  ),
                ),
              ],
            ),
          ),
          _Field(
            label: 'How is this course billed?',
            hint: feeModelHint(_feeModel),
            child: AppSegmentedControl<FeeModel>(
              options: FeeModel.values,
              labelOf: feeModelLabel,
              isSelected: (m) => m == _feeModel,
              onTap: (m) => setState(() => _feeModel = m),
            ),
          ),
          if (_feeModel == FeeModel.perClass)
            _Field(
              label: 'Fee per class',
              hint: 'The fee is calculated from actual attendance - classes attended x this rate.',
              child: _amountField(palette, _feePerClassController, 'e.g. 150'),
            )
          else
            _Field(
              label: _feeModel == FeeModel.hybrid
                  ? 'Base fee · per month'
                  : 'Fixed fee · per month',
              child: _amountField(palette, _feeController, 'e.g. 1000'),
            ),
          if (_feeModel == FeeModel.hybrid) ...[
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: _Field(
                    label: 'Expected classes',
                    child: _numberField(palette, _expectedClassesController, 'e.g. 8'),
                  ),
                ),
                const SizedBox(width: AppSpacing.md),
                Expanded(
                  child: _Field(
                    label: 'Min. classes',
                    child: _numberField(palette, _thresholdController, 'e.g. 6'),
                  ),
                ),
              ],
            ),
            _Field(
              label: 'Fee % if attendance is low',
              hint: 'e.g. 50 - the student pays the full fee if they attend at least the minimum '
                  'above; if not, only this % of the fee applies.',
              child: _numberField(palette, _belowPercentController, 'e.g. 50'),
            ),
          ],
          _Field(
            label: 'Fee issue date',
            hint: 'A fee slip is auto-generated on this day each cycle, covering attendance from '
                'the previous period to this one.',
            child: DayOfMonthField(
              value: _billingDay,
              onChanged: (d) => setState(() => _billingDay = d),
              accentColor: palette.primary,
            ),
          ),
          _Field(
            label: 'Payment due date',
            hint: 'Fees are marked overdue after this day, which triggers a payment-due reminder '
                'to the student automatically.',
            child: DayOfMonthField(
              value: _dueDay,
              onChanged: (d) => setState(() => _dueDay = d),
              accentColor: palette.gold,
            ),
          ),
          // A per-class course bills on attendance, so there is no cycle to choose and no fixed
          // per-cycle amount to preview.
          if (_feeModel != FeeModel.perClass) ...[
            _Field(
              label: 'Fee cycle',
              child: AttachedSelect<FeeCycle>(
                label: 'Fee cycle',
                options: FeeCycle.values,
                labelOf: (c) => c.label,
                value: _feeCycle,
                // Changing an existing course's cycle would silently re-scope fee slips already
                // raised against the old one, so it is fixed once the course exists.
                locked: _isEditing,
                onSelected: (c) => setState(() => _feeCycle = c),
              ),
            ),
            _cycleSummary(palette),
          ],
          _Field(
            label: 'Payment method',
            hint: 'Tap to select which methods are accepted for this course\'s fees - more than '
                'one is fine.',
            child: AppSegmentedControl<PaymentMethod>(
              options: PaymentMethod.values,
              labelOf: (m) => m.label,
              isSelected: _paymentMethods.contains,
              activeColorOf: (_, _) => palette.gold,
              activeTextColorOf: (_, _) => palette.onGold,
              onTap: (m) => setState(() {
                // Never let the last method be removed - a course with no accepted method is
                // uncollectable, and the backend would silently substitute cash anyway.
                if (_paymentMethods.contains(m)) {
                  if (_paymentMethods.length > 1) _paymentMethods.remove(m);
                } else {
                  _paymentMethods.add(m);
                }
              }),
            ),
          ),
          _Field(
            label: 'Status',
            hint: 'Inactive courses stay in history but drop off fee-collection lists.',
            child: AppSegmentedControl<bool>(
              options: const [true, false],
              labelOf: (a) => a ? 'Active' : 'Inactive',
              isSelected: (a) => a == _active,
              activeColorOf: (_, a) => a ? palette.paidManual : palette.surfaceHigh,
              activeTextColorOf: (_, a) => a ? palette.onPrimary : palette.textMuted,
              onTap: (a) => setState(() => _active = a),
            ),
          ),
          const SizedBox(height: AppSpacing.xs),
          AppPrimaryButton(
            label: _isEditing ? 'Save changes' : 'Create course',
            icon: Icons.check,
            busy: _busy,
            onPressed: _valid ? _save : null,
          ),
          if (!_valid) ...[
            const SizedBox(height: AppSpacing.sm),
            Text(
              _missingRequirement(),
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: AppType.sm, color: palette.textFaint),
            ),
          ],
        ],
      ),
    );
  }

  /// Names the one thing still blocking save. A disabled button with no explanation is the most
  /// common way a long form dead-ends.
  String _missingRequirement() {
    if (_nameController.text.trim().length <= 1) return 'Enter a course name to continue.';
    if (!_billingValid) {
      return _feeModel == FeeModel.perClass
          ? 'Enter the fee charged per class.'
          : 'Enter the fee for this course.';
    }
    if (!_hybridValid) return 'Hybrid courses need a minimum class count and a low-attendance %.';
    if (_billingDay == null) return 'Pick the day fee slips are issued on.';
    if (_dueDay == null) return 'Pick the day payment falls due.';
    return 'Select at least one payment method.';
  }

  Widget _iconPicker(AppPalette palette, CategoryMeta meta) {
    final icons = iconsForCategory(_category);
    final selected = icons.firstWhere((s) => s.key == _iconKey, orElse: () => icons.first);

    if (!_iconPickerOpen) {
      return Pressable(
        onTap: () => setState(() => _iconPickerOpen = true),
        child: Container(
          padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.xl, vertical: AppSpacing.md),
          decoration: BoxDecoration(
            color: palette.surfaceRaised,
            borderRadius: AppRadii.all(AppRadii.xl),
            border: Border.all(color: palette.border),
          ),
          child: Row(
            children: [
              Container(
                width: 32,
                height: 32,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: meta.soft,
                  borderRadius: AppRadii.all(AppRadii.md),
                ),
                child: CourseIcon(spec: selected, color: meta.color, size: 16),
              ),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: Text(
                  selected.label,
                  style: TextStyle(
                    fontSize: AppType.xxl,
                    fontWeight: AppType.medium,
                    color: palette.text,
                  ),
                ),
              ),
              Text(
                'Change',
                style: TextStyle(
                  fontSize: AppType.base,
                  fontWeight: AppType.bold,
                  color: palette.primary,
                ),
              ),
            ],
          ),
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        GridView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          padding: EdgeInsets.zero,
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 4,
            mainAxisSpacing: AppSpacing.sm,
            crossAxisSpacing: AppSpacing.sm,
            childAspectRatio: 1.15,
          ),
          itemCount: icons.length,
          itemBuilder: (context, i) {
            final spec = icons[i];
            final isSelected = spec.key == _iconKey;
            return Pressable(
              onTap: () => setState(() {
                _iconKey = spec.key;
                _iconPickerOpen = false;
              }),
              child: Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: AppSpacing.xxs, vertical: AppSpacing.md),
                decoration: BoxDecoration(
                  color: isSelected ? meta.soft : palette.surfaceRaised,
                  borderRadius: AppRadii.all(AppRadii.lg),
                  border: Border.all(
                    color: isSelected ? meta.color : palette.border,
                    width: 1.5,
                  ),
                ),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    CourseIcon(
                      spec: spec,
                      color: isSelected ? meta.color : palette.textMuted,
                      size: 18,
                    ),
                    const SizedBox(height: 5),
                    Text(
                      spec.label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: AppType.micro,
                        fontWeight: AppType.medium,
                        color: isSelected ? meta.color : palette.textFaint,
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        ),
        const SizedBox(height: AppSpacing.sm),
        Pressable(
          onTap: () => setState(() => _iconPickerOpen = false),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: AppSpacing.xxs),
            child: Text(
              'Collapse',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: AppType.base,
                fontWeight: AppType.medium,
                color: palette.textMuted,
              ),
            ),
          ),
        ),
      ],
    );
  }

  /// Restates the fee as the amount actually charged each time, because a quarterly course
  /// entered as "1000 per month" bills 3000 and that surprise is worth pre-empting.
  Widget _cycleSummary(AppPalette palette) {
    final base = _intOf(_feeController) ?? 0;
    if (base <= 0) return const SizedBox.shrink();
    final months = _feeCycle.months;

    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.x4l),
      child: Container(
        padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.xl, vertical: AppSpacing.lg),
        decoration: BoxDecoration(
          color: palette.primarySoft,
          borderRadius: AppRadii.all(AppRadii.xl),
          border: Border.all(color: palette.primaryDim),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('AMOUNT PER BILLING CYCLE',
                style: AppType.sectionLabel(palette.textMuted)),
            const SizedBox(height: AppSpacing.xxs),
            Text(
              months == 1
                  ? money(base)
                  : '${money(base)} x $months months = ${money(base * months)}',
              style: TextStyle(
                fontSize: AppType.x3l,
                fontWeight: AppType.heavy,
                color: palette.primary,
              ),
            ),
            const SizedBox(height: AppSpacing.xxs),
            Text(
              'Billed every ${months == 1 ? 'month' : '$months months'} '
              '(${_feeCycle.label} cycle).',
              style: TextStyle(fontSize: AppType.sm, color: palette.textFaint),
            ),
          ],
        ),
      ),
    );
  }

  Widget _textField(AppPalette palette, TextEditingController controller, String hint) {
    return TextField(
      controller: controller,
      onChanged: (_) => setState(() {}),
      style: TextStyle(
          fontSize: AppType.xxl, fontWeight: AppType.medium, color: palette.text),
      decoration: _decoration(palette, hint),
    );
  }

  Widget _numberField(AppPalette palette, TextEditingController controller, String hint) {
    return TextField(
      controller: controller,
      onChanged: (_) => setState(() {}),
      keyboardType: TextInputType.number,
      inputFormatters: [FilteringTextInputFormatter.digitsOnly],
      style: TextStyle(
          fontSize: AppType.xxl, fontWeight: AppType.medium, color: palette.text),
      decoration: _decoration(palette, hint),
    );
  }

  Widget _amountField(AppPalette palette, TextEditingController controller, String hint) {
    return TextField(
      controller: controller,
      onChanged: (_) => setState(() {}),
      keyboardType: TextInputType.number,
      inputFormatters: [FilteringTextInputFormatter.digitsOnly],
      style: TextStyle(
          fontSize: AppType.xxl, fontWeight: AppType.medium, color: palette.text),
      decoration: _decoration(palette, hint).copyWith(
        prefixIcon: Padding(
          padding: const EdgeInsets.only(left: AppSpacing.xl, right: AppSpacing.sm),
          child: Icon(Icons.currency_rupee, size: 15, color: palette.textFaint),
        ),
        prefixIconConstraints: const BoxConstraints(minWidth: 0, minHeight: 0),
      ),
    );
  }

  InputDecoration _decoration(AppPalette palette, String hint) => InputDecoration(
        isDense: true,
        hintText: hint,
        hintStyle: TextStyle(
            fontSize: AppType.lg, fontWeight: AppType.regular, color: palette.textFaint),
        filled: true,
        fillColor: palette.surfaceRaised,
        contentPadding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.xl, vertical: AppSpacing.lg),
        border: OutlineInputBorder(
          borderRadius: AppRadii.all(AppRadii.xl),
          borderSide: BorderSide(color: palette.border),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: AppRadii.all(AppRadii.xl),
          borderSide: BorderSide(color: palette.border),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: AppRadii.all(AppRadii.xl),
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
      padding: const EdgeInsets.only(bottom: AppSpacing.x4l),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(label.toUpperCase(), style: AppType.sectionLabel(palette.textMuted)),
          const SizedBox(height: AppSpacing.sm),
          child,
          if (hint != null) ...[
            const SizedBox(height: AppSpacing.xs),
            Text(
              hint!,
              style: TextStyle(fontSize: AppType.sm, color: palette.textFaint, height: 1.4),
            ),
          ],
        ],
      ),
    );
  }
}

extension _Let<T> on T {
  R let<R>(R Function(T) f) => f(this);
}
