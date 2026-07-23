import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:nest_fe/core/error/api_exception.dart';
import 'package:nest_fe/core/widgets/app_notice.dart';
import 'package:nest_fe/features/scheduling/presentation/scheduling_screen.dart';

/// PRD 3.7.2: the original class instance is marked Cancelled-Rescheduled (never deleted) and a
/// new linked instance is created - a mandatory reason is required, matching the backend's
/// RESCHEDULE feature gate.
class RescheduleScreen extends ConsumerStatefulWidget {
  const RescheduleScreen({super.key});

  @override
  ConsumerState<RescheduleScreen> createState() => _RescheduleScreenState();
}

class _RescheduleScreenState extends ConsumerState<RescheduleScreen> {
  final _instanceIdController = TextEditingController();
  final _newDateController = TextEditingController();
  final _reasonController = TextEditingController();
  TimeOfDay _newStart = const TimeOfDay(hour: 17, minute: 0);
  TimeOfDay _newEnd = const TimeOfDay(hour: 18, minute: 0);
  bool _isSaving = false;

  String _fmtTime(TimeOfDay t) => '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}:00';

  Future<void> _submit() async {
    setState(() => _isSaving = true);
    try {
      await ref.read(schedulingApiProvider).reschedule(
            classInstanceId: _instanceIdController.text.trim(),
            newDate: _newDateController.text.trim(),
            newStartTime: _fmtTime(_newStart),
            newEndTime: _fmtTime(_newEnd),
            reason: _reasonController.text.trim(),
          );
      if (mounted) AppNotice.success(context, 'Rescheduled - affected students see the update immediately.');
    } on ApiException catch (e) {
      if (mounted) AppNotice.error(context, e.message);
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Reschedule a class')),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          TextField(controller: _instanceIdController, decoration: const InputDecoration(labelText: 'Class instance ID')),
          const SizedBox(height: 12),
          TextField(controller: _newDateController, decoration: const InputDecoration(labelText: 'New date (YYYY-MM-DD)')),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: () async {
                    final picked = await showTimePicker(context: context, initialTime: _newStart);
                    if (picked != null) setState(() => _newStart = picked);
                  },
                  child: Text('Start ${_newStart.format(context)}'),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: OutlinedButton(
                  onPressed: () async {
                    final picked = await showTimePicker(context: context, initialTime: _newEnd);
                    if (picked != null) setState(() => _newEnd = picked);
                  },
                  child: Text('End ${_newEnd.format(context)}'),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _reasonController,
            decoration: const InputDecoration(labelText: 'Reason (required)', hintText: 'Trainer unavailable / Hall unavailable / ...'),
          ),
          const SizedBox(height: 18),
          ElevatedButton(
            onPressed: _isSaving ? null : _submit,
            child: _isSaving
                ? const SizedBox(height: 18, width: 18, child: CircularProgressIndicator(strokeWidth: 2))
                : const Text('Reschedule'),
          ),
        ],
      ),
    );
  }
}
