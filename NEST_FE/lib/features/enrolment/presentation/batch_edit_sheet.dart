import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:nest_fe/core/error/api_exception.dart';
import 'package:nest_fe/core/widgets/app_notice.dart';
import 'package:nest_fe/features/attendance/data/class_instance.dart';
import 'package:nest_fe/features/enrolment/data/batch.dart';
import 'package:nest_fe/features/enrolment/presentation/batches_screen.dart';
import 'package:nest_fe/features/enrolment/presentation/student_roster_picker.dart';
import 'package:nest_fe/features/scheduling/presentation/schedule_slot_editor.dart';
import 'package:nest_fe/features/scheduling/presentation/scheduling_screen.dart' show schedulingApiProvider;

/// Map/unmap students, change the weekly schedule, reschedule an individual class (makeup
/// class), or delete the batch entirely once it's empty.
Future<void> showBatchEditSheet(BuildContext context, WidgetRef ref, {required Batch batch}) {
  return showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    builder: (_) => _BatchEditSheet(batch: batch),
  );
}

class _BatchEditSheet extends ConsumerStatefulWidget {
  const _BatchEditSheet({required this.batch});
  final Batch batch;

  @override
  ConsumerState<_BatchEditSheet> createState() => _BatchEditSheetState();
}

class _BatchEditSheetState extends ConsumerState<_BatchEditSheet> {
  Set<String>? _memberIds;
  String? _memberLoadError;

  List<ScheduleSlot> _slots = [];
  DateTime _effectiveFrom = DateTime.now();
  bool _scheduleLoaded = false;
  bool _isSavingSchedule = false;

  List<ClassInstance>? _upcoming;
  String? _upcomingLoadError;

  bool _isDeleting = false;

  String _fmtDate(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  @override
  void initState() {
    super.initState();
    _loadMembers();
    if (widget.batch.batchType == 'REGULAR') {
      _loadCurrentSchedule();
      _loadUpcoming();
    }
  }

  Future<void> _loadMembers() async {
    try {
      final members = await ref.read(enrolmentApiProvider).members(widget.batch.id);
      if (mounted) setState(() => _memberIds = members.toSet());
    } on ApiException catch (e) {
      if (mounted) setState(() => _memberLoadError = e.message);
    }
  }

  Future<void> _loadCurrentSchedule() async {
    try {
      final current = await ref.read(schedulingApiProvider).currentSchedule(widget.batch.id);
      if (!mounted) return;
      setState(() {
        _slots = current
            .map((s) => ScheduleSlot(dayOfWeek: s.dayOfWeek, startTime: _parseTime(s.startTime), endTime: _parseTime(s.endTime)))
            .toList();
        _scheduleLoaded = true;
      });
    } on ApiException catch (e) {
      if (mounted) AppNotice.error(context, 'Could not load current schedule: ${e.message}');
    }
  }

  TimeOfDay _parseTime(String hhmmss) {
    final parts = hhmmss.split(':');
    return TimeOfDay(hour: int.parse(parts[0]), minute: int.parse(parts[1]));
  }

  Future<void> _loadUpcoming() async {
    try {
      final instances = await ref.read(schedulingApiProvider).upcomingClassInstances(widget.batch.id);
      if (mounted) setState(() => _upcoming = instances);
    } on ApiException catch (e) {
      if (mounted) setState(() => _upcomingLoadError = e.message);
    }
  }

  Future<void> _pickEffectiveFrom() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _effectiveFrom,
      firstDate: DateTime.now(),
      lastDate: DateTime.now().add(const Duration(days: 365)),
    );
    if (picked != null) setState(() => _effectiveFrom = picked);
  }

  Future<void> _saveSchedule() async {
    if (_slots.isEmpty) {
      AppNotice.error(context, 'Add at least one day, or remove all of them via Class Schedule instead.');
      return;
    }
    setState(() => _isSavingSchedule = true);
    try {
      await ref.read(schedulingApiProvider).setSchedule(
            batchId: widget.batch.id,
            slots: _slots.map((s) => s.toApiSlot()).toList(),
            effectiveFrom: _fmtDate(_effectiveFrom),
          );
      if (mounted) {
        AppNotice.success(context, 'Schedule updated - new timing applies from ${_fmtDate(_effectiveFrom)} onward.');
      }
      await _loadUpcoming();
    } on ApiException catch (e) {
      if (mounted) AppNotice.error(context, e.message);
    } finally {
      if (mounted) setState(() => _isSavingSchedule = false);
    }
  }

  Future<void> _toggleMember(String membershipId, bool selected) async {
    final previous = Set<String>.from(_memberIds ?? {});
    setState(() => selected ? _memberIds!.add(membershipId) : _memberIds!.remove(membershipId));
    try {
      if (selected) {
        await ref.read(enrolmentApiProvider).addMember(widget.batch.id, membershipId);
      } else {
        await ref.read(enrolmentApiProvider).removeMember(widget.batch.id, membershipId);
      }
    } on ApiException catch (e) {
      // Roll back the optimistic checkbox change if the backend actually rejected it (e.g. the
      // "already in another Regular batch for this course" conflict).
      if (mounted) {
        setState(() => _memberIds = previous);
        AppNotice.error(context, e.message);
      }
    }
  }

  Future<void> _openReschedule(ClassInstance instance) async {
    final result = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => _RescheduleDialog(instance: instance),
    );
    if (result == true) await _loadUpcoming();
  }

  Future<void> _delete() async {
    final memberCount = _memberIds?.length ?? 0;
    if (memberCount > 0) {
      AppNotice.error(context, 'Please de-link the $memberCount student(s) from this batch first.');
      return;
    }
    final confirmed = await AppNotice.confirm(
      context,
      title: 'Delete batch',
      message: 'This removes "${widget.batch.name}" and its schedule permanently. This cannot be undone.',
      confirmLabel: 'Delete',
    );
    if (!confirmed) return;

    setState(() => _isDeleting = true);
    try {
      await ref.read(enrolmentApiProvider).deleteBatch(widget.batch.id);
      ref.invalidate(batchesForCourseProvider(widget.batch.courseId));
      if (mounted) {
        AppNotice.success(context, 'Batch deleted.');
        Navigator.of(context).pop();
      }
    } on ApiException catch (e) {
      if (mounted) AppNotice.error(context, e.message);
    } finally {
      if (mounted) setState(() => _isDeleting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Padding(
      padding: EdgeInsets.only(left: 20, right: 20, top: 20, bottom: MediaQuery.of(context).viewInsets.bottom + 20),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('Edit batch', style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 2),
            Text(widget.batch.name, style: Theme.of(context).textTheme.bodyMedium),
            if (widget.batch.batchType == 'REGULAR') ...[
              const SizedBox(height: 20),
              Text('Weekly schedule', style: Theme.of(context).textTheme.titleSmall),
              const SizedBox(height: 4),
              Text(
                'Changes apply from the date below onward - classes already held keep their original timing.',
                style: Theme.of(context).textTheme.bodySmall,
              ),
              const SizedBox(height: 10),
              if (!_scheduleLoaded)
                const Center(child: Padding(padding: EdgeInsets.all(12), child: CircularProgressIndicator()))
              else ...[
                ScheduleSlotEditor(slots: _slots, onChanged: (s) => setState(() => _slots = s)),
                const SizedBox(height: 4),
                OutlinedButton.icon(
                  onPressed: _pickEffectiveFrom,
                  icon: const Icon(Icons.event_outlined, size: 18),
                  label: Text('Starting from ${_fmtDate(_effectiveFrom)}'),
                ),
                const SizedBox(height: 10),
                ElevatedButton(
                  onPressed: _isSavingSchedule ? null : _saveSchedule,
                  child: _isSavingSchedule
                      ? const SizedBox(height: 18, width: 18, child: CircularProgressIndicator(strokeWidth: 2))
                      : const Text('Save schedule'),
                ),
              ],
              const SizedBox(height: 20),
              Text('Upcoming classes', style: Theme.of(context).textTheme.titleSmall),
              const SizedBox(height: 4),
              Text('Tap a class to reschedule just that one occurrence (a makeup class).', style: Theme.of(context).textTheme.bodySmall),
              const SizedBox(height: 8),
              if (_upcomingLoadError != null)
                Text(_upcomingLoadError!, style: TextStyle(color: colorScheme.error, fontSize: 13))
              else if (_upcoming == null)
                const Center(child: Padding(padding: EdgeInsets.all(12), child: CircularProgressIndicator()))
              else if (_upcoming!.isEmpty)
                const Text('No upcoming classes scheduled.', style: TextStyle(fontSize: 12.5))
              else
                ..._upcoming!.map((ci) => ListTile(
                      dense: true,
                      contentPadding: EdgeInsets.zero,
                      leading: const Icon(Icons.event_outlined, size: 20),
                      title: Text('${ci.date} · ${ci.startTime}–${ci.endTime}'),
                      subtitle: Text(ci.status),
                      trailing: ci.status == 'SCHEDULED' ? const Icon(Icons.chevron_right) : null,
                      onTap: ci.status == 'SCHEDULED' ? () => _openReschedule(ci) : null,
                    )),
            ],
            const SizedBox(height: 20),
            Text('Students', style: Theme.of(context).textTheme.titleSmall),
            const SizedBox(height: 4),
            Text(
              'Check to add a student to this batch, uncheck to remove them.',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: 8),
            if (_memberLoadError != null)
              Text(_memberLoadError!, style: TextStyle(color: colorScheme.error, fontSize: 13))
            else if (_memberIds == null)
              const Center(child: Padding(padding: EdgeInsets.all(16), child: CircularProgressIndicator()))
            else
              StudentRosterPicker(
                courseId: widget.batch.courseId,
                selectedMembershipIds: _memberIds!,
                onToggle: _toggleMember,
              ),
            const SizedBox(height: 24),
            OutlinedButton.icon(
              onPressed: _isDeleting ? null : _delete,
              icon: Icon(Icons.delete_outline, color: colorScheme.error),
              label: _isDeleting
                  ? const SizedBox(height: 18, width: 18, child: CircularProgressIndicator(strokeWidth: 2))
                  : Text('Delete batch', style: TextStyle(color: colorScheme.error)),
              style: OutlinedButton.styleFrom(side: BorderSide(color: colorScheme.error.withValues(alpha: 0.4))),
            ),
            const SizedBox(height: 10),
            OutlinedButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Done')),
          ],
        ),
      ),
    );
  }
}

/// Reschedule ONE upcoming class instance - a makeup class, distinct from changing the batch's
/// ongoing weekly pattern. The original stays on record as CANCELLED (rescheduled) for audit.
class _RescheduleDialog extends ConsumerStatefulWidget {
  const _RescheduleDialog({required this.instance});
  final ClassInstance instance;

  @override
  ConsumerState<_RescheduleDialog> createState() => _RescheduleDialogState();
}

class _RescheduleDialogState extends ConsumerState<_RescheduleDialog> {
  late DateTime _newDate = DateTime.tryParse(widget.instance.date) ?? DateTime.now();
  late TimeOfDay _newStart = _parseTime(widget.instance.startTime);
  late TimeOfDay _newEnd = _parseTime(widget.instance.endTime);
  final _reasonController = TextEditingController();
  bool _isSaving = false;

  TimeOfDay _parseTime(String hhmmss) {
    final parts = hhmmss.split(':');
    return TimeOfDay(hour: int.parse(parts[0]), minute: int.parse(parts[1]));
  }

  String _fmtDate(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
  String _fmtTime(TimeOfDay t) => '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}:00';

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _newDate,
      firstDate: DateTime.now(),
      lastDate: DateTime.now().add(const Duration(days: 365)),
    );
    if (picked != null) setState(() => _newDate = picked);
  }

  Future<void> _pickTime(bool isStart) async {
    final picked = await showTimePicker(context: context, initialTime: isStart ? _newStart : _newEnd);
    if (picked == null) return;
    setState(() => isStart ? _newStart = picked : _newEnd = picked);
  }

  Future<void> _submit() async {
    if (_reasonController.text.trim().isEmpty) {
      AppNotice.error(context, 'A reason is required (e.g. trainer unavailable, venue clash).');
      return;
    }
    setState(() => _isSaving = true);
    try {
      await ref.read(schedulingApiProvider).reschedule(
            classInstanceId: widget.instance.id,
            newDate: _fmtDate(_newDate),
            newStartTime: _fmtTime(_newStart),
            newEndTime: _fmtTime(_newEnd),
            reason: _reasonController.text.trim(),
          );
      if (mounted) {
        AppNotice.success(context, 'Class rescheduled.');
        Navigator.of(context).pop(true);
      }
    } on ApiException catch (e) {
      if (mounted) AppNotice.error(context, e.message);
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Reschedule this class'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('Originally ${widget.instance.date} · ${widget.instance.startTime}–${widget.instance.endTime}',
              style: Theme.of(context).textTheme.bodySmall),
          const SizedBox(height: 12),
          OutlinedButton.icon(
            onPressed: _pickDate,
            icon: const Icon(Icons.event_outlined, size: 18),
            label: Text('New date: ${_fmtDate(_newDate)}'),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(child: OutlinedButton(onPressed: () => _pickTime(true), child: Text('Start ${_newStart.format(context)}'))),
              const SizedBox(width: 8),
              Expanded(child: OutlinedButton(onPressed: () => _pickTime(false), child: Text('End ${_newEnd.format(context)}'))),
            ],
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _reasonController,
            decoration: const InputDecoration(labelText: 'Reason', hintText: 'Trainer unavailable / Venue clash / ...'),
          ),
        ],
      ),
      actions: [
        TextButton(onPressed: () => Navigator.of(context).pop(false), child: const Text('Cancel')),
        FilledButton(
          onPressed: _isSaving ? null : _submit,
          child: _isSaving
              ? const SizedBox(height: 18, width: 18, child: CircularProgressIndicator(strokeWidth: 2))
              : const Text('Reschedule'),
        ),
      ],
    );
  }
}
