import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:nest_fe/core/error/api_exception.dart';
import 'package:nest_fe/core/widgets/app_notice.dart';
import 'package:nest_fe/features/enrolment/presentation/batches_screen.dart';
import 'package:nest_fe/features/enrolment/presentation/student_roster_picker.dart';
import 'package:nest_fe/features/enrolment/presentation/trainer_picker.dart';
import 'package:nest_fe/features/scheduling/presentation/schedule_slot_editor.dart';
import 'package:nest_fe/features/scheduling/presentation/scheduling_screen.dart' show schedulingApiProvider;

Future<void> showBatchFormSheet(BuildContext context, WidgetRef ref, {required String courseId}) {
  return showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    builder: (_) => _BatchFormSheet(courseId: courseId),
  );
}

class _BatchFormSheet extends ConsumerStatefulWidget {
  const _BatchFormSheet({required this.courseId});
  final String courseId;

  @override
  ConsumerState<_BatchFormSheet> createState() => _BatchFormSheetState();
}

class _BatchFormSheetState extends ConsumerState<_BatchFormSheet> {
  final _nameController = TextEditingController();
  String _batchType = 'REGULAR';
  bool _isSaving = false;

  DateTime _effectiveFrom = DateTime.now();
  List<ScheduleSlot> _slots = [];
  final Set<String> _selectedStudentIds = {};
  String? _selectedTrainerId;

  String _fmtDate(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  Future<void> _pickEffectiveFrom() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _effectiveFrom,
      firstDate: DateTime.now().subtract(const Duration(days: 1)),
      lastDate: DateTime.now().add(const Duration(days: 365)),
    );
    if (picked != null) setState(() => _effectiveFrom = picked);
  }

  Future<void> _submit() async {
    setState(() => _isSaving = true);
    try {
      final batch = await ref.read(enrolmentApiProvider).createBatch(
            courseId: widget.courseId,
            name: _nameController.text.trim(),
            batchType: _batchType,
            trainerMembershipId: _selectedTrainerId,
          );

      // The batch itself is already created at this point - a schedule or roster hiccup below
      // must never look like the whole thing failed, since it didn't. Each step is independent
      // and any that fails is reported specifically; the rest (and Class Schedule/Edit batch
      // afterwards) can still fix it up.
      final warnings = <String>[];
      final successes = <String>[];

      if (_slots.isNotEmpty) {
        try {
          await ref.read(schedulingApiProvider).setSchedule(
                batchId: batch.id,
                slots: _slots.map((s) => s.toApiSlot()).toList(),
                effectiveFrom: _fmtDate(_effectiveFrom),
              );
          successes.add('${_slots.length} weekly class(es) scheduled');
        } on ApiException catch (e) {
          warnings.add('schedule could not be set (${e.message})');
        }
      }

      var addedCount = 0;
      for (final membershipId in _selectedStudentIds) {
        try {
          await ref.read(enrolmentApiProvider).addMember(batch.id, membershipId);
          addedCount++;
        } on ApiException {
          // A single student's "already in another Regular batch for this course" conflict
          // shouldn't block the rest of the roster from being added - they can be mapped
          // individually later from Edit batch.
        }
      }
      if (addedCount > 0) successes.add('$addedCount student(s) added');
      if (addedCount < _selectedStudentIds.length) {
        warnings.add('${_selectedStudentIds.length - addedCount} student(s) could not be added');
      }

      ref.invalidate(batchesForCourseProvider(widget.courseId));
      if (mounted) {
        final summary = successes.isEmpty ? 'Batch created.' : 'Batch created - ${successes.join(', ')}.';
        if (warnings.isEmpty) {
          AppNotice.success(context, summary);
        } else {
          AppNotice.error(context, '$summary ${warnings.join('; ')}.');
        }
        Navigator.of(context).pop();
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
      padding: EdgeInsets.only(left: 20, right: 20, top: 20, bottom: MediaQuery.of(context).viewInsets.bottom + 20),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('New batch', style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 18),
            TextField(controller: _nameController, decoration: const InputDecoration(labelText: 'Batch name (e.g. Batch A - Evening)')),
            const SizedBox(height: 12),
            SegmentedButton<String>(
              segments: const [
                ButtonSegment(value: 'REGULAR', label: Text('Regular')),
                ButtonSegment(value: 'TEMPORARY', label: Text('Temporary')),
              ],
              selected: {_batchType},
              onSelectionChanged: (s) => setState(() => _batchType = s.first),
            ),
            const SizedBox(height: 16),
            Text('Default trainer', style: Theme.of(context).textTheme.titleSmall),
            const SizedBox(height: 4),
            Text(
              'Shown to students so they know who is taking the class - can be left unset.',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: 8),
            TrainerPicker(
              courseId: widget.courseId,
              selectedMembershipId: _selectedTrainerId,
              onChanged: (id) => setState(() => _selectedTrainerId = id),
            ),
            if (_batchType == 'REGULAR') ...[
              const SizedBox(height: 20),
              Text('Weekly schedule (optional)', style: Theme.of(context).textTheme.titleSmall),
              const SizedBox(height: 4),
              Text(
                'Add every day this batch meets - e.g. Monday and Wednesday, 4-5pm. Can also be set later from Class Schedule.',
                style: Theme.of(context).textTheme.bodySmall,
              ),
              const SizedBox(height: 10),
              ScheduleSlotEditor(slots: _slots, onChanged: (s) => setState(() => _slots = s)),
              if (_slots.isNotEmpty) ...[
                const SizedBox(height: 8),
                OutlinedButton.icon(
                  onPressed: _pickEffectiveFrom,
                  icon: const Icon(Icons.event_outlined, size: 18),
                  label: Text('Starting from ${_fmtDate(_effectiveFrom)}'),
                ),
              ],
            ],
            const SizedBox(height: 20),
            Text('Students (optional)', style: Theme.of(context).textTheme.titleSmall),
            const SizedBox(height: 4),
            Text(
              'Pick who from this course starts in this batch - more can be added later from Edit batch.',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: 8),
            StudentRosterPicker(
              courseId: widget.courseId,
              selectedMembershipIds: _selectedStudentIds,
              onToggle: (id, selected) => setState(() => selected ? _selectedStudentIds.add(id) : _selectedStudentIds.remove(id)),
            ),
            const SizedBox(height: 18),
            ElevatedButton(
              onPressed: _isSaving ? null : _submit,
              child: _isSaving
                  ? const SizedBox(height: 18, width: 18, child: CircularProgressIndicator(strokeWidth: 2))
                  : const Text('Create batch'),
            ),
          ],
        ),
      ),
    );
  }
}
