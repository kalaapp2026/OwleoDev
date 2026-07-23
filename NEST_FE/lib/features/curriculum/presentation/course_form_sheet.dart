import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:nest_fe/core/error/api_exception.dart';
import 'package:nest_fe/core/widgets/app_notice.dart';
import 'package:nest_fe/features/curriculum/data/course.dart';
import 'package:nest_fe/features/curriculum/data/curriculum_api.dart';

const _categories = ['DANCE', 'MUSIC_VOCAL', 'MUSIC_INSTRUMENTAL', 'FITNESS', 'OTHER'];
const _feeCycles = ['MONTHLY', 'QUARTERLY', 'YEARLY', 'TERM_BASED', 'ONE_TIME'];

/// Pass [existing] to edit a course in place; omit it to create a new one. Category and fee
/// cycle are only ever set at creation time - the backend's update endpoint doesn't accept them
/// (PRD 3.3: a course's cycle/category is fixed once students start enrolling against it).
Future<void> showCourseFormSheet(BuildContext context, WidgetRef ref, {Course? existing}) {
  return showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    builder: (_) => _CourseFormSheet(existing: existing),
  );
}

class _CourseFormSheet extends ConsumerStatefulWidget {
  const _CourseFormSheet({this.existing});
  final Course? existing;

  @override
  ConsumerState<_CourseFormSheet> createState() => _CourseFormSheetState();
}

class _CourseFormSheetState extends ConsumerState<_CourseFormSheet> {
  late final _nameController = TextEditingController(text: widget.existing?.name);
  late final _descriptionController = TextEditingController(text: widget.existing?.description);
  late final _feeController = TextEditingController(text: widget.existing?.defaultFee?.toString());
  late final _feePerClassController = TextEditingController(text: widget.existing?.feePerClass?.toString());
  late final _hybridClassesController =
      TextEditingController(text: widget.existing?.hybridExpectedClassesPerPeriod?.toString());
  late final _hybridThresholdController = TextEditingController(text: widget.existing?.hybridThresholdAttendance?.toString());
  late final _hybridBelowPercentController =
      TextEditingController(text: widget.existing?.hybridFeeBelowThresholdPercent?.toString());

  late String _category = _categories.first;
  late String _feeCycle = widget.existing?.feeCycle ?? _feeCycles.first;
  late FeeModel _feeModel = widget.existing?.feeModel ?? FeeModel.fixed;
  late int? _billingDayOfMonth = widget.existing?.billingDayOfMonth;
  bool _isSaving = false;

  bool get _isEditing => widget.existing != null;

  Future<void> _submit() async {
    setState(() => _isSaving = true);
    try {
      if (_isEditing) {
        await ref.read(curriculumApiProvider).updateCourse(
              widget.existing!.id,
              name: _nameController.text.trim(),
              description: _descriptionController.text.trim().isEmpty ? null : _descriptionController.text.trim(),
              feeModel: _feeModel,
              defaultFee: num.tryParse(_feeController.text.trim()),
              feePerClass: num.tryParse(_feePerClassController.text.trim()),
              hybridExpectedClassesPerPeriod: int.tryParse(_hybridClassesController.text.trim()),
              hybridThresholdAttendance: int.tryParse(_hybridThresholdController.text.trim()),
              hybridFeeBelowThresholdPercent: int.tryParse(_hybridBelowPercentController.text.trim()),
              billingDayOfMonth: _billingDayOfMonth,
            );
        ref.invalidate(activeCoursesProvider);
        ref.invalidate(allCoursesProvider);
        if (mounted) {
          AppNotice.success(context, 'Course updated.');
          Navigator.of(context).pop();
        }
      } else {
        await ref.read(curriculumApiProvider).createCourse(
              category: _category,
              name: _nameController.text.trim(),
              description: _descriptionController.text.trim().isEmpty ? null : _descriptionController.text.trim(),
              feeModel: _feeModel,
              defaultFee: num.tryParse(_feeController.text.trim()),
              feePerClass: num.tryParse(_feePerClassController.text.trim()),
              hybridExpectedClassesPerPeriod: int.tryParse(_hybridClassesController.text.trim()),
              hybridThresholdAttendance: int.tryParse(_hybridThresholdController.text.trim()),
              hybridFeeBelowThresholdPercent: int.tryParse(_hybridBelowPercentController.text.trim()),
              feeCycle: _feeCycle,
              billingDayOfMonth: _billingDayOfMonth,
            );
        ref.invalidate(activeCoursesProvider);
        ref.invalidate(allCoursesProvider);
        if (mounted) {
          AppNotice.success(context, 'Course created.');
          Navigator.of(context).pop();
        }
      }
    } on ApiException catch (e) {
      if (mounted) AppNotice.error(context, e.message);
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(
        left: 20,
        right: 20,
        top: 20,
        bottom: MediaQuery.of(context).viewInsets.bottom + 20,
      ),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(_isEditing ? 'Edit course' : 'New course', style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 18),
            if (!_isEditing) ...[
              DropdownButtonFormField<String>(
                initialValue: _category,
                decoration: const InputDecoration(labelText: 'Category'),
                items: _categories.map((c) => DropdownMenuItem(value: c, child: Text(c.replaceAll('_', ' ')))).toList(),
                onChanged: (v) => setState(() => _category = v!),
              ),
              const SizedBox(height: 12),
            ],
            TextField(controller: _nameController, decoration: const InputDecoration(labelText: 'Course name')),
            const SizedBox(height: 12),
            TextField(
              controller: _descriptionController,
              decoration: const InputDecoration(labelText: 'Description (optional)'),
              maxLines: 2,
            ),
            const SizedBox(height: 16),
            Text('How is this course billed?', style: Theme.of(context).textTheme.titleSmall),
            const SizedBox(height: 8),
            SegmentedButton<FeeModel>(
              segments: const [
                ButtonSegment(value: FeeModel.perClass, label: Text('Per-class')),
                ButtonSegment(value: FeeModel.fixed, label: Text('Fixed')),
                ButtonSegment(value: FeeModel.hybrid, label: Text('Hybrid')),
              ],
              selected: {_feeModel},
              onSelectionChanged: (s) => setState(() => _feeModel = s.first),
            ),
            const SizedBox(height: 12),
            ..._feeModelFields(),
            const SizedBox(height: 16),
            Text('Fee issue date (optional)', style: Theme.of(context).textTheme.titleSmall),
            const SizedBox(height: 4),
            Text(
              'A fee slip is auto-generated on this day each month, covering attendance from '
              'the previous month\'s date to this one.',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: 8),
            InkWell(
              borderRadius: BorderRadius.circular(12),
              onTap: () => _pickBillingDay(context),
              child: InputDecorator(
                decoration: InputDecoration(
                  labelText: 'Day of month',
                  suffixIcon: _billingDayOfMonth == null
                      ? const Icon(Icons.event_outlined)
                      : IconButton(
                          icon: const Icon(Icons.clear, size: 18),
                          tooltip: 'Clear',
                          onPressed: () => setState(() => _billingDayOfMonth = null),
                        ),
                ),
                child: Text(
                  _billingDayOfMonth == null ? 'Not set' : Course.ordinalDay(_billingDayOfMonth!),
                ),
              ),
            ),
            if (!_isEditing) ...[
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                initialValue: _feeCycle,
                decoration: const InputDecoration(labelText: 'Fee cycle'),
                items: _feeCycles.map((f) => DropdownMenuItem(value: f, child: Text(f.replaceAll('_', ' ')))).toList(),
                onChanged: (v) => setState(() => _feeCycle = v!),
              ),
            ],
            const SizedBox(height: 20),
            ElevatedButton(
              onPressed: _isSaving ? null : _submit,
              child: _isSaving
                  ? const SizedBox(height: 18, width: 18, child: CircularProgressIndicator(strokeWidth: 2))
                  : Text(_isEditing ? 'Save changes' : 'Create course'),
            ),
          ],
        ),
      ),
    );
  }

  /// A 1-31 day grid instead of free-text entry - there's no real calendar date to pick (this
  /// repeats every month), so a compact grid reads faster than scrolling a full date picker and
  /// can't produce an invalid value the way a text field could.
  Future<void> _pickBillingDay(BuildContext context) async {
    final selected = await showDialog<int?>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Fee issue date'),
        content: SizedBox(
          width: 320,
          child: GridView.count(
            crossAxisCount: 7,
            shrinkWrap: true,
            mainAxisSpacing: 6,
            crossAxisSpacing: 6,
            children: List.generate(31, (i) {
              final day = i + 1;
              final isSelected = day == _billingDayOfMonth;
              return InkWell(
                borderRadius: BorderRadius.circular(8),
                onTap: () => Navigator.of(dialogContext).pop(day),
                child: Container(
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: isSelected ? Theme.of(context).colorScheme.primary : null,
                    border: Border.all(color: Theme.of(context).colorScheme.outlineVariant),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    '$day',
                    style: TextStyle(
                      color: isSelected ? Theme.of(context).colorScheme.onPrimary : null,
                      fontWeight: isSelected ? FontWeight.w700 : null,
                    ),
                  ),
                ),
              );
            }),
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.of(dialogContext).pop(), child: const Text('Not set')),
          TextButton(onPressed: () => Navigator.of(dialogContext).pop(_billingDayOfMonth), child: const Text('Cancel')),
        ],
      ),
    );
    setState(() => _billingDayOfMonth = selected);
  }

  /// NEST Course Fee Calculation Spec §5.2 - each model asks for a different subset of fields.
  List<Widget> _feeModelFields() {
    switch (_feeModel) {
      case FeeModel.perClass:
        return [
          TextField(
            controller: _feePerClassController,
            keyboardType: TextInputType.number,
            decoration: const InputDecoration(labelText: 'Fee per class (₹)'),
          ),
        ];
      case FeeModel.fixed:
        return [
          TextField(
            controller: _feeController,
            keyboardType: TextInputType.number,
            decoration: const InputDecoration(labelText: 'Fee (₹)'),
          ),
        ];
      case FeeModel.hybrid:
        return [
          TextField(
            controller: _feeController,
            keyboardType: TextInputType.number,
            decoration: const InputDecoration(labelText: 'Base fee (₹)'),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _hybridClassesController,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(labelText: 'Expected classes/period'),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: TextField(
                  controller: _hybridThresholdController,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(labelText: 'Threshold attendance'),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _hybridBelowPercentController,
            keyboardType: TextInputType.number,
            decoration: const InputDecoration(
              labelText: 'Fee % if below threshold',
              helperText: 'e.g. 50 - full fee always applies once attendance meets the threshold',
            ),
          ),
        ];
    }
  }
}
