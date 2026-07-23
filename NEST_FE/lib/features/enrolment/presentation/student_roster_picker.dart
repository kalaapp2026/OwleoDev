import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:nest_fe/core/providers/core_providers.dart';
import 'package:nest_fe/core/widgets/async_value_view.dart';
import 'package:nest_fe/features/enrolment/data/enrolment_api.dart';
import 'package:nest_fe/features/enrolment/presentation/batches_screen.dart';

/// Every active Student enrolled in a course - the roster picker source shared by batch creation
/// (pre-selecting members) and batch editing (mapping/unmapping members).
final studentsForCourseProvider = FutureProvider.autoDispose.family<List<StudentSummary>, String>((ref, courseId) {
  ref.watch(activeMembershipIdProvider);
  return ref.watch(enrolmentApiProvider).studentsForCourse(courseId);
});

/// Checkbox list of a course's enrolled students - the caller owns selection state (and thus
/// decides what "checking" a row actually does: stage it for a new batch, or immediately
/// map/unmap it on an existing one).
class StudentRosterPicker extends ConsumerWidget {
  const StudentRosterPicker({super.key, required this.courseId, required this.selectedMembershipIds, required this.onToggle});

  final String courseId;
  final Set<String> selectedMembershipIds;
  final void Function(String membershipId, bool selected) onToggle;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final studentsAsync = ref.watch(studentsForCourseProvider(courseId));
    return AsyncValueView<List<StudentSummary>>(
      value: studentsAsync,
      onRetry: () => ref.invalidate(studentsForCourseProvider(courseId)),
      data: (context, students) {
        if (students.isEmpty) {
          return const Text('No students enrolled in this course yet.', style: TextStyle(fontSize: 12.5));
        }
        return Column(
          children: students
              .map((s) => CheckboxListTile(
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                    controlAffinity: ListTileControlAffinity.leading,
                    title: Text(s.fullName),
                    subtitle: Text('@${s.username}', style: const TextStyle(fontSize: 12)),
                    value: selectedMembershipIds.contains(s.membershipId),
                    onChanged: (v) => onToggle(s.membershipId, v ?? false),
                  ))
              .toList(),
        );
      },
    );
  }
}
