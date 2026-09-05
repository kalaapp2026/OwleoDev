import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
// trainersForCourseProvider lives with the API it calls - see the note in student_roster_picker.
import 'package:nest_fe/features/enrolment/data/enrolment_api.dart';

/// Single-select dropdown of a course's mapped trainers, with a "No default trainer" option -
/// unlike the student roster this is always optional (a batch can be created before a trainer is
/// assigned), so there's no empty-state block, just a note when the course has no trainers yet.
class TrainerPicker extends ConsumerWidget {
  const TrainerPicker({super.key, required this.courseId, required this.selectedMembershipId, required this.onChanged});

  final String courseId;
  final String? selectedMembershipId;
  final void Function(String? membershipId) onChanged;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final trainersAsync = ref.watch(trainersForCourseProvider(courseId));
    return trainersAsync.when(
      data: (trainers) {
        if (trainers.isEmpty) {
          return const Text(
            'No trainers or admins available yet.',
            style: TextStyle(fontSize: 12.5),
          );
        }
        final validValue = trainers.any((t) => t.membershipId == selectedMembershipId) ? selectedMembershipId : null;
        return DropdownButtonFormField<String?>(
          initialValue: validValue,
          decoration: const InputDecoration(labelText: 'Trainer (optional)'),
          items: [
            const DropdownMenuItem<String?>(value: null, child: Text('No default trainer')),
            ...trainers.map((t) => DropdownMenuItem<String?>(value: t.membershipId, child: Text(t.fullName))),
          ],
          onChanged: onChanged,
        );
      },
      loading: () => const Padding(
        padding: EdgeInsets.symmetric(vertical: 8),
        child: Center(child: SizedBox(height: 18, width: 18, child: CircularProgressIndicator(strokeWidth: 2))),
      ),
      error: (err, stack) => const Text('Could not load trainers for this course.', style: TextStyle(fontSize: 12.5)),
    );
  }
}
