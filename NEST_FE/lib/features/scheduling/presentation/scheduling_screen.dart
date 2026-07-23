import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:nest_fe/core/error/api_exception.dart';
import 'package:nest_fe/core/providers/core_providers.dart';
import 'package:nest_fe/core/widgets/app_notice.dart';
import 'package:nest_fe/features/curriculum/data/curriculum_api.dart';
import 'package:nest_fe/features/enrolment/presentation/batches_screen.dart';
import 'package:nest_fe/features/scheduling/data/scheduling_api.dart';

final schedulingApiProvider = Provider((ref) => SchedulingApi(ref.watch(dioClientProvider)));

const _weekdays = ['MONDAY', 'TUESDAY', 'WEDNESDAY', 'THURSDAY', 'FRIDAY', 'SATURDAY', 'SUNDAY'];

/// PRD 3.7.1: setting a recurring weekly slot immediately materialises 8 weeks of class
/// instances on the backend - confirmed live when this was built (see the published API
/// reference's Scheduling section).
class SchedulingScreen extends ConsumerStatefulWidget {
  const SchedulingScreen({super.key});

  @override
  ConsumerState<SchedulingScreen> createState() => _SchedulingScreenState();
}

class _SchedulingScreenState extends ConsumerState<SchedulingScreen> {
  final _effectiveFromController = TextEditingController();
  String? _selectedCourseId;
  String? _selectedBatchId;
  String _dayOfWeek = _weekdays.first;
  TimeOfDay _startTime = const TimeOfDay(hour: 16, minute: 0);
  TimeOfDay _endTime = const TimeOfDay(hour: 17, minute: 0);
  bool _isSaving = false;

  String _fmtTime(TimeOfDay t) => '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}:00';

  Future<void> _pickTime(bool isStart) async {
    final picked = await showTimePicker(context: context, initialTime: isStart ? _startTime : _endTime);
    if (picked == null) return;
    setState(() => isStart ? _startTime = picked : _endTime = picked);
  }

  Future<void> _submit() async {
    if (_selectedBatchId == null) return;
    setState(() => _isSaving = true);
    try {
      await ref.read(schedulingApiProvider).setSchedule(
        batchId: _selectedBatchId!,
        slots: [
          {'dayOfWeek': _dayOfWeek, 'startTime': _fmtTime(_startTime), 'endTime': _fmtTime(_endTime)}
        ],
        effectiveFrom: _effectiveFromController.text.trim(),
      );
      if (mounted) AppNotice.success(context, 'Schedule set - 8 weeks of classes generated.');
    } on ApiException catch (e) {
      if (mounted) AppNotice.error(context, e.message);
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final coursesAsync = ref.watch(activeCoursesProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Set class schedule')),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          coursesAsync.when(
            data: (courses) {
              final validValue = courses.any((c) => c.id == _selectedCourseId) ? _selectedCourseId : null;
              return DropdownButtonFormField<String>(
                initialValue: validValue,
                decoration: const InputDecoration(labelText: 'Course'),
                items: courses.map((c) => DropdownMenuItem(value: c.id, child: Text(c.name))).toList(),
                onChanged: (id) => setState(() {
                  _selectedCourseId = id;
                  _selectedBatchId = null;
                }),
              );
            },
            loading: () => const Center(child: SizedBox(height: 18, width: 18, child: CircularProgressIndicator(strokeWidth: 2))),
            error: (err, stack) => Text(
              err is ApiException ? err.message : 'Could not load courses',
              style: TextStyle(color: Theme.of(context).colorScheme.error, fontSize: 13),
            ),
          ),
          if (_selectedCourseId != null) ...[
            const SizedBox(height: 12),
            Consumer(
              builder: (context, ref, _) {
                final batchesAsync = ref.watch(batchesForCourseProvider(_selectedCourseId!));
                return batchesAsync.when(
                  data: (batches) {
                    if (batches.isEmpty) {
                      return const Text('No batches under this course yet.', style: TextStyle(fontSize: 12.5));
                    }
                    final validValue = batches.any((b) => b.id == _selectedBatchId) ? _selectedBatchId : null;
                    return DropdownButtonFormField<String>(
                      initialValue: validValue,
                      decoration: const InputDecoration(labelText: 'Batch'),
                      items: batches.map((b) => DropdownMenuItem(value: b.id, child: Text(b.name))).toList(),
                      onChanged: (id) => setState(() => _selectedBatchId = id),
                    );
                  },
                  loading: () => const Center(child: SizedBox(height: 18, width: 18, child: CircularProgressIndicator(strokeWidth: 2))),
                  error: (err, stack) => Text(
                    err is ApiException ? err.message : 'Could not load batches',
                    style: TextStyle(color: Theme.of(context).colorScheme.error, fontSize: 13),
                  ),
                );
              },
            ),
          ],
          const SizedBox(height: 12),
          DropdownButtonFormField<String>(
            initialValue: _dayOfWeek,
            decoration: const InputDecoration(labelText: 'Day of week'),
            items: _weekdays.map((d) => DropdownMenuItem(value: d, child: Text(d))).toList(),
            onChanged: (v) => setState(() => _dayOfWeek = v!),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: () => _pickTime(true),
                  child: Text('Start ${_startTime.format(context)}'),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: OutlinedButton(
                  onPressed: () => _pickTime(false),
                  child: Text('End ${_endTime.format(context)}'),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _effectiveFromController,
            decoration: const InputDecoration(labelText: 'Effective from (YYYY-MM-DD)'),
          ),
          const SizedBox(height: 18),
          ElevatedButton(
            onPressed: _isSaving || _selectedBatchId == null ? null : _submit,
            child: _isSaving
                ? const SizedBox(height: 18, width: 18, child: CircularProgressIndicator(strokeWidth: 2))
                : const Text('Save schedule'),
          ),
        ],
      ),
    );
  }
}
