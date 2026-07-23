import 'package:flutter/material.dart';

const scheduleWeekdays = ['MONDAY', 'TUESDAY', 'WEDNESDAY', 'THURSDAY', 'FRIDAY', 'SATURDAY', 'SUNDAY'];

/// One weekly (day, start, end) slot being edited - mutable on purpose so ScheduleSlotEditor can
/// tweak a row in place and just report the list back via onChanged, rather than rebuilding
/// immutable copies on every keystroke/time pick.
class ScheduleSlot {
  ScheduleSlot({String? dayOfWeek, TimeOfDay? startTime, TimeOfDay? endTime})
      : dayOfWeek = dayOfWeek ?? scheduleWeekdays.first,
        startTime = startTime ?? const TimeOfDay(hour: 16, minute: 0),
        endTime = endTime ?? const TimeOfDay(hour: 17, minute: 0);

  String dayOfWeek;
  TimeOfDay startTime;
  TimeOfDay endTime;

  static String _fmt(TimeOfDay t) => '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}:00';

  Map<String, String> toApiSlot() => {'dayOfWeek': dayOfWeek, 'startTime': _fmt(startTime), 'endTime': _fmt(endTime)};
}

/// Editable list of weekly schedule slots - shared by batch creation and Edit batch, so "add a
/// day", the day/time pickers, and remove-row all look and behave identically in both places.
class ScheduleSlotEditor extends StatelessWidget {
  const ScheduleSlotEditor({super.key, required this.slots, required this.onChanged});

  final List<ScheduleSlot> slots;
  final ValueChanged<List<ScheduleSlot>> onChanged;

  Future<void> _pickTime(BuildContext context, ScheduleSlot slot, bool isStart) async {
    final picked = await showTimePicker(context: context, initialTime: isStart ? slot.startTime : slot.endTime);
    if (picked == null) return;
    isStart ? slot.startTime = picked : slot.endTime = picked;
    onChanged(List.of(slots));
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ...slots.map((slot) => _SlotRow(
              slot: slot,
              onChangeDay: (d) {
                slot.dayOfWeek = d;
                onChanged(List.of(slots));
              },
              onPickStart: () => _pickTime(context, slot, true),
              onPickEnd: () => _pickTime(context, slot, false),
              onRemove: () => onChanged(slots.where((s) => s != slot).toList()),
            )),
        Align(
          alignment: Alignment.centerLeft,
          child: TextButton.icon(
            onPressed: () => onChanged([...slots, ScheduleSlot()]),
            icon: const Icon(Icons.add, size: 18),
            label: const Text('Add a day'),
          ),
        ),
      ],
    );
  }
}

class _SlotRow extends StatelessWidget {
  const _SlotRow({
    required this.slot,
    required this.onChangeDay,
    required this.onPickStart,
    required this.onPickEnd,
    required this.onRemove,
  });

  final ScheduleSlot slot;
  final ValueChanged<String> onChangeDay;
  final VoidCallback onPickStart;
  final VoidCallback onPickEnd;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        children: [
          Expanded(
            flex: 3,
            child: DropdownButtonFormField<String>(
              initialValue: slot.dayOfWeek,
              isExpanded: true,
              decoration: const InputDecoration(labelText: 'Day', isDense: true),
              items: scheduleWeekdays.map((d) => DropdownMenuItem(value: d, child: Text(d.substring(0, 3)))).toList(),
              onChanged: (v) => onChangeDay(v!),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            flex: 2,
            child: OutlinedButton(onPressed: onPickStart, child: Text(slot.startTime.format(context))),
          ),
          const SizedBox(width: 6),
          Expanded(
            flex: 2,
            child: OutlinedButton(onPressed: onPickEnd, child: Text(slot.endTime.format(context))),
          ),
          IconButton(
            onPressed: onRemove,
            icon: const Icon(Icons.close, size: 18),
            tooltip: 'Remove',
            visualDensity: VisualDensity.compact,
          ),
        ],
      ),
    );
  }
}
