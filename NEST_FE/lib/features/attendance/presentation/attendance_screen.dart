import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:nest_fe/core/error/api_exception.dart';
import 'package:nest_fe/core/providers/core_providers.dart';
import 'package:nest_fe/core/widgets/app_notice.dart';
import 'package:nest_fe/core/widgets/async_value_view.dart';
import 'package:nest_fe/core/widgets/avatar.dart';
import 'package:nest_fe/features/attendance/data/attendance_api.dart';
import 'package:nest_fe/features/attendance/data/class_instance.dart';
import 'package:nest_fe/features/curriculum/data/curriculum_api.dart';
import 'package:nest_fe/features/enrolment/presentation/batches_screen.dart';

final attendanceApiProvider = Provider((ref) => AttendanceApi(ref.watch(dioClientProvider)));

/// Looks up a batch via a Course -> Batch cascade (no "my batches today" convenience endpoint on
/// the backend yet - see the API reference's Scope gaps) then lets a Trainer/Admin mark each
/// class instance.
class AttendanceScreen extends ConsumerStatefulWidget {
  const AttendanceScreen({super.key});

  @override
  ConsumerState<AttendanceScreen> createState() => _AttendanceScreenState();
}

class _AttendanceScreenState extends ConsumerState<AttendanceScreen> {
  String? _selectedCourseId;
  String? _selectedBatchId;
  List<ClassInstance>? _instances;
  bool _isLoading = false;
  bool _isAddingClass = false;

  Future<void> _loadInstances() async {
    final batchId = _selectedBatchId;
    if (batchId == null) return;
    setState(() => _isLoading = true);
    try {
      final instances = await ref.read(attendanceApiProvider).classInstancesForBatch(batchId);
      setState(() => _instances = instances);
    } on ApiException catch (e) {
      if (mounted) AppNotice.error(context, e.message);
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _addClass() async {
    final batchId = _selectedBatchId;
    if (batchId == null) return;

    final picked = await _pickClassDateAndTime(context);
    if (picked == null) return;

    setState(() => _isAddingClass = true);
    try {
      await ref.read(attendanceApiProvider).addClassInstance(
            batchId: batchId,
            date: picked.date,
            startTime: picked.startTime,
            endTime: picked.endTime,
          );
      if (mounted) AppNotice.success(context, 'Class added.');
      await _loadInstances();
    } on ApiException catch (e) {
      if (mounted) AppNotice.error(context, e.message);
    } finally {
      if (mounted) setState(() => _isAddingClass = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final coursesAsync = ref.watch(activeCoursesProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Attendance')),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text('Load a batch\'s classes', style: Theme.of(context).textTheme.titleMedium),
                  const SizedBox(height: 12),
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
                          _instances = null;
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
                              onChanged: (id) => setState(() {
                                _selectedBatchId = id;
                                _instances = null;
                              }),
                            );
                          },
                          loading: () =>
                              const Center(child: SizedBox(height: 18, width: 18, child: CircularProgressIndicator(strokeWidth: 2))),
                          error: (err, stack) => Text(
                            err is ApiException ? err.message : 'Could not load batches',
                            style: TextStyle(color: Theme.of(context).colorScheme.error, fontSize: 13),
                          ),
                        );
                      },
                    ),
                  ],
                  const SizedBox(height: 14),
                  ElevatedButton(
                    onPressed: _isLoading || _selectedBatchId == null ? null : _loadInstances,
                    child: _isLoading
                        ? const SizedBox(height: 18, width: 18, child: CircularProgressIndicator(strokeWidth: 2))
                        : const Text('Load'),
                  ),
                ],
              ),
            ),
          ),
          if (_instances != null) ...[
            const SizedBox(height: 16),
            Align(
              alignment: Alignment.centerLeft,
              child: OutlinedButton.icon(
                onPressed: _isAddingClass ? null : _addClass,
                icon: _isAddingClass
                    ? const SizedBox(height: 16, width: 16, child: CircularProgressIndicator(strokeWidth: 2))
                    : const Icon(Icons.add, size: 18),
                label: const Text('Add a class'),
              ),
            ),
            const SizedBox(height: 8),
            if (_instances!.isEmpty)
              const EmptyState(icon: Icons.event_busy_outlined, message: 'No classes yet - add one above to start marking attendance.')
            else
              ..._instances!.map((instance) => Card(
                    child: ListTile(
                      leading: Icon(instance.status == 'SCHEDULED' ? Icons.event_available_outlined : Icons.event_busy_outlined),
                      title: Text('${instance.date} · ${instance.startTime}–${instance.endTime}'),
                      subtitle: Text(instance.status),
                      trailing: const Icon(Icons.chevron_right),
                      onTap: () => Navigator.of(context).push(MaterialPageRoute(
                        builder: (_) => _MarkAttendanceScreen(batchId: instance.batchId, classInstance: instance),
                      )),
                    ),
                  )),
          ],
        ],
      ),
    );
  }
}

class _PickedClassTime {
  const _PickedClassTime({required this.date, required this.startTime, required this.endTime});
  final String date;
  final String startTime;
  final String endTime;
}

Future<_PickedClassTime?> _pickClassDateAndTime(BuildContext context) async {
  final now = DateTime.now();
  final date = await showDatePicker(
    context: context,
    initialDate: now,
    firstDate: now.subtract(const Duration(days: 365)),
    lastDate: now.add(const Duration(days: 365)),
  );
  if (date == null || !context.mounted) return null;

  final startTime = await showTimePicker(context: context, initialTime: TimeOfDay.now());
  if (startTime == null || !context.mounted) return null;

  final defaultEnd = TimeOfDay(hour: (startTime.hour + 1) % 24, minute: startTime.minute);
  final endTime = await showTimePicker(context: context, initialTime: defaultEnd, helpText: 'SELECT END TIME');
  if (endTime == null) return null;

  String fmtDate(DateTime d) => '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
  String fmtTime(TimeOfDay t) => '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}:00';

  return _PickedClassTime(date: fmtDate(date), startTime: fmtTime(startTime), endTime: fmtTime(endTime));
}

class _MarkAttendanceScreen extends ConsumerStatefulWidget {
  const _MarkAttendanceScreen({required this.batchId, required this.classInstance});
  final String batchId;
  final ClassInstance classInstance;

  @override
  ConsumerState<_MarkAttendanceScreen> createState() => _MarkAttendanceScreenState();
}

class _MarkAttendanceScreenState extends ConsumerState<_MarkAttendanceScreen> {
  List<BatchMemberSummary>? _members;
  final Map<String, String> _statusByMember = {};
  bool _isSubmitting = false;
  String? _loadError;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      // Existing marks (if this class was already marked) are loaded alongside the roster so
      // reopening it to edit shows what's actually recorded, not a blank "everyone present" slate.
      final results = await Future.wait([
        ref.read(attendanceApiProvider).memberSummariesForBatch(widget.batchId),
        ref.read(attendanceApiProvider).forClassInstance(widget.classInstance.id),
      ]);
      final members = results[0] as List<BatchMemberSummary>;
      final existing = results[1] as List<AttendanceRecord>;
      final existingByMember = {for (final r in existing) r.membershipId: r.status};

      if (!mounted) return;
      setState(() {
        _members = members;
        for (final m in members) {
          _statusByMember[m.membershipId] = existingByMember[m.membershipId] ?? 'PRESENT';
        }
      });
    } on ApiException catch (e) {
      if (mounted) setState(() => _loadError = e.message);
    }
  }

  Future<void> _submit() async {
    setState(() => _isSubmitting = true);
    try {
      await ref.read(attendanceApiProvider).submitSheet(widget.classInstance.id, _statusByMember);
      if (mounted) {
        AppNotice.success(context, 'Attendance submitted.');
        Navigator.of(context).pop();
      }
    } on ApiException catch (e) {
      if (mounted) AppNotice.error(context, e.message);
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('${widget.classInstance.date} · ${widget.classInstance.startTime}')),
      body: _loadError != null
          ? Center(child: Text(_loadError!, style: TextStyle(color: Theme.of(context).colorScheme.error)))
          : _members == null
              ? const Center(child: CircularProgressIndicator())
              : _members!.isEmpty
                  ? const EmptyState(icon: Icons.people_outline, message: 'No students in this batch yet.')
                  : ListView(
                      padding: const EdgeInsets.all(16),
                      children: [
                        Text(
                          'Tap a student to toggle Present/Absent - everyone starts marked Present.',
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                        const SizedBox(height: 12),
                        ..._members!.map((member) => _AttendanceTile(
                              member: member,
                              isPresent: (_statusByMember[member.membershipId] ?? 'PRESENT') == 'PRESENT',
                              onToggle: () => setState(() {
                                final current = _statusByMember[member.membershipId] ?? 'PRESENT';
                                _statusByMember[member.membershipId] = current == 'PRESENT' ? 'ABSENT' : 'PRESENT';
                              }),
                            )),
                        const SizedBox(height: 12),
                        ElevatedButton(
                          onPressed: _isSubmitting ? null : _submit,
                          child: _isSubmitting
                              ? const SizedBox(height: 18, width: 18, child: CircularProgressIndicator(strokeWidth: 2))
                              : const Text('Submit attendance'),
                        ),
                      ],
                    ),
    );
  }
}

/// A single roster row rendered as a colour-filled tile (same visual language as the Trainer
/// feature-grant FilterChips) rather than a name + checkbox - tapping the whole tile toggles
/// Present/Absent, and the fill colour itself is the only status indicator needed.
class _AttendanceTile extends StatelessWidget {
  const _AttendanceTile({required this.member, required this.isPresent, required this.onToggle});

  final BatchMemberSummary member;
  final bool isPresent;
  final VoidCallback onToggle;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final fillColor = isPresent ? colorScheme.primaryContainer : colorScheme.errorContainer;
    final borderColor = isPresent ? colorScheme.primary : colorScheme.error;
    final onFillColor = isPresent ? colorScheme.onPrimaryContainer : colorScheme.onErrorContainer;

    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Material(
        color: fillColor,
        borderRadius: BorderRadius.circular(14),
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: onToggle,
          child: Container(
            decoration: BoxDecoration(borderRadius: BorderRadius.circular(14), border: Border.all(color: borderColor, width: 1.2)),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            child: Row(
              children: [
                Avatar(name: member.fullName, imageUrl: member.profileImageUrl, radius: 20),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(member.fullName, style: TextStyle(color: onFillColor, fontWeight: FontWeight.w600)),
                      Text('@${member.username}', style: TextStyle(color: onFillColor.withValues(alpha: 0.75), fontSize: 12)),
                    ],
                  ),
                ),
                Icon(isPresent ? Icons.check_circle : Icons.cancel, color: borderColor, size: 20),
                const SizedBox(width: 6),
                Text(
                  isPresent ? 'Present' : 'Absent',
                  style: TextStyle(color: onFillColor, fontWeight: FontWeight.w700, fontSize: 12.5),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
