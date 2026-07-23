import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:nest_fe/core/auth/feature_keys.dart';
import 'package:nest_fe/core/auth/session_controller.dart';
import 'package:nest_fe/core/error/api_exception.dart';
import 'package:nest_fe/core/widgets/app_notice.dart';
import 'package:nest_fe/core/widgets/async_value_view.dart';
import 'package:nest_fe/features/curriculum/data/course.dart';
import 'package:nest_fe/features/curriculum/data/curriculum_api.dart';
import 'package:nest_fe/features/enrolment/data/enrolment_api.dart';
import 'package:nest_fe/features/enrolment/presentation/batches_screen.dart';
import 'package:nest_fe/features/enrolment/presentation/profile_image_picker.dart';
import 'package:nest_fe/features/enrolment/presentation/student_roster_picker.dart';

/// PRD 3.4/3.5: manual registration for both Students and Trainers - the two account types the
/// backend actually supports self-service creation for (Flow B WhatsApp self-registration isn't
/// built yet, see Scope gaps). The Student tab opens on a roster (who's already registered,
/// course-filtered), not straight into a blank form - "Add" is a deliberate action below the list.
class UserCreationScreen extends StatefulWidget {
  const UserCreationScreen({super.key});

  @override
  State<UserCreationScreen> createState() => _UserCreationScreenState();
}

class _UserCreationScreenState extends State<UserCreationScreen> with SingleTickerProviderStateMixin {
  late final TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Users'),
        bottom: TabBar(controller: _tabController, tabs: const [Tab(text: 'Students'), Tab(text: 'Trainers')]),
      ),
      body: TabBarView(controller: _tabController, children: const [_StudentRoster(), _TrainerForm()]),
    );
  }
}

/// Reusable multi-select course picker (Wrap of FilterChip) - a student can enrol in several
/// courses from the same academy in one registration, and a person already known to NEST (from
/// another academy) picks the course(s) they're joining THIS academy for the same way.
class _CoursesPicker extends ConsumerWidget {
  const _CoursesPicker({required this.selectedCourseIds, required this.onToggle});

  final Set<String> selectedCourseIds;
  final void Function(String courseId, bool selected) onToggle;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final coursesAsync = ref.watch(activeCoursesProvider);
    return AsyncValueView<List<Course>>(
      value: coursesAsync,
      onRetry: () => ref.invalidate(activeCoursesProvider),
      data: (context, courses) {
        if (courses.isEmpty) {
          return const Text('No active courses in this academy yet - create one first.', style: TextStyle(fontSize: 12.5));
        }
        return Wrap(
          spacing: 8,
          runSpacing: 4,
          children: courses.map((c) {
            final selected = selectedCourseIds.contains(c.id);
            return FilterChip(
              label: Text(c.name),
              selected: selected,
              onSelected: (v) => onToggle(c.id, v),
            );
          }).toList(),
        );
      },
    );
  }
}

/// Entry point for the Student tab: a course-filtered roster of who's already registered, with
/// "Add student" below it - not a blank form on open. Admin must pick a course (their view spans
/// the whole academy, so a course is the only sane way to narrow it down); a Trainer's dropdown is
/// pre-scoped to just the courses they're mapped to and auto-selects the first one.
class _StudentRoster extends ConsumerStatefulWidget {
  const _StudentRoster();

  @override
  ConsumerState<_StudentRoster> createState() => _StudentRosterState();
}

class _StudentRosterState extends ConsumerState<_StudentRoster> {
  String? _selectedCourseId;

  @override
  Widget build(BuildContext context) {
    final user = ref.watch(sessionControllerProvider).user;
    final isAdmin = user != null && (user.isSuperAdmin || user.isActiveAcademyAdmin);

    final coursesAsync = isAdmin || user?.activeMembershipId == null
        ? ref.watch(activeCoursesProvider)
        : ref.watch(coursesForMembershipProvider(user!.activeMembershipId!));

    return AsyncValueView<List<Course>>(
      value: coursesAsync,
      onRetry: () => ref.invalidate(activeCoursesProvider),
      data: (context, courses) {
        if (courses.isEmpty) {
          return const EmptyState(
            icon: Icons.school_outlined,
            message: 'No courses to show students for yet.',
          );
        }
        // A Trainer mapped to exactly the courses they teach doesn't need to make a choice to see
        // anyone - default to the first one; an Admin's dropdown starts unset (mandatory pick).
        if (!isAdmin && _selectedCourseId == null) {
          _selectedCourseId = courses.first.id;
        }
        final selectedCourseId = _selectedCourseId;

        return Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
              child: DropdownButtonFormField<String>(
                initialValue: selectedCourseId != null && courses.any((c) => c.id == selectedCourseId) ? selectedCourseId : null,
                decoration: InputDecoration(
                  labelText: isAdmin ? 'Course (required)' : 'Course',
                  prefixIcon: const Icon(Icons.school_outlined),
                ),
                items: courses.map((c) => DropdownMenuItem(value: c.id, child: Text(c.name))).toList(),
                onChanged: (v) => setState(() => _selectedCourseId = v),
              ),
            ),
            Expanded(
              child: selectedCourseId == null
                  ? const EmptyState(icon: Icons.filter_list_outlined, message: 'Pick a course to see its students.')
                  : _RosterList(courseId: selectedCourseId),
            ),
            SafeArea(
              top: false,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                child: OutlinedButton.icon(
                  icon: const Icon(Icons.person_add_alt_outlined),
                  label: const Text('Add student'),
                  onPressed: () async {
                    await Navigator.of(context).push(MaterialPageRoute(builder: (_) => const _AddStudentScreen()));
                    ref.invalidate(studentsForCourseProvider);
                  },
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}

class _RosterList extends ConsumerWidget {
  const _RosterList({required this.courseId});
  final String courseId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final studentsAsync = ref.watch(studentsForCourseProvider(courseId));
    return AsyncValueView<List<StudentSummary>>(
      value: studentsAsync,
      onRetry: () => ref.invalidate(studentsForCourseProvider(courseId)),
      data: (context, students) {
        if (students.isEmpty) {
          return const EmptyState(icon: Icons.people_outline, message: 'No students registered for this course yet.');
        }
        return ListView.builder(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          itemCount: students.length,
          itemBuilder: (context, i) {
            final s = students[i];
            return Card(
              margin: const EdgeInsets.symmetric(vertical: 4),
              child: ListTile(
                leading: CircleAvatar(child: Text(s.fullName.isNotEmpty ? s.fullName[0].toUpperCase() : '?')),
                title: Text(s.fullName),
                subtitle: Text('@${s.username}'),
              ),
            );
          },
        );
      },
    );
  }
}

class _AddStudentScreen extends StatelessWidget {
  const _AddStudentScreen();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Add student')),
      body: const _StudentForm(),
    );
  }
}

class _StudentForm extends ConsumerStatefulWidget {
  const _StudentForm();

  @override
  ConsumerState<_StudentForm> createState() => _StudentFormState();
}

class _StudentFormState extends ConsumerState<_StudentForm> {
  final _usernameController = TextEditingController();
  final _fullNameController = TextEditingController();
  final _phoneController = TextEditingController();
  final _dobController = TextEditingController();
  final _emailController = TextEditingController();
  final _codeController = TextEditingController();
  final _selectedCourseIds = <String>{};
  bool _isSaving = false;
  Uint8List? _photoBytes;
  String? _photoFilename;

  /// Set once registerStudent() comes back pendingConfirmation=true (PRD 7.4: this email already
  /// has a NEST account, and it's not already visible to whoever's registering it) - the form
  /// switches to asking for the OTP the person was sent to their app's Notifications tab.
  bool _pendingConfirmation = false;
  String? _existingMembershipId;
  String? _existingFullName;

  Future<void> _submit() async {
    if (_selectedCourseIds.isEmpty) {
      AppNotice.error(context, 'Pick at least one course to enrol this student in.');
      return;
    }
    setState(() => _isSaving = true);
    try {
      final result = await ref.read(enrolmentApiProvider).registerStudent(
            username: _usernameController.text.trim(),
            fullName: _fullNameController.text.trim(),
            phone: _phoneController.text.trim(),
            dob: _dobController.text.trim(),
            email: _emailController.text.trim().isEmpty ? null : _emailController.text.trim(),
            courses: _selectedCourseIds.map((id) => {'courseId': id, 'fee': null}).toList(),
          );
      if (!mounted) return;

      // The photo upload is a best-effort follow-up call, not part of registration itself - a
      // failure here shouldn't read as "registration failed" when the person was created fine.
      String? photoWarning;
      if (!result.pendingConfirmation && _photoBytes != null) {
        try {
          await ref.read(enrolmentApiProvider).uploadProfileImage(result.userId, _photoBytes!, _photoFilename!);
        } on ApiException catch (e) {
          photoWarning = ' (photo upload failed: ${e.message})';
        }
      }
      if (!mounted) return;

      if (result.pendingConfirmation) {
        setState(() {
          _pendingConfirmation = true;
          _existingMembershipId = result.membershipId;
          _existingFullName = result.fullName;
        });
      } else {
        AppNotice.success(context, '${result.fullName} was registered successfully.${photoWarning ?? ''}');
        Navigator.of(context).pop();
      }
    } on ApiException catch (e) {
      if (mounted) AppNotice.error(context, e.message);
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  Future<void> _confirm() async {
    setState(() => _isSaving = true);
    try {
      final result = await ref.read(enrolmentApiProvider).confirmMembership(
            membershipId: _existingMembershipId!,
            code: _codeController.text.trim(),
          );
      if (mounted) {
        AppNotice.success(context, 'Confirmed - ${result.fullName} is now enrolled.');
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
    if (_pendingConfirmation) {
      return ListView(
        padding: const EdgeInsets.all(20),
        children: [
          Card(
            color: Theme.of(context).colorScheme.primaryContainer.withValues(alpha: 0.35),
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Row(
                children: [
                  const Icon(Icons.info_outline),
                  const SizedBox(width: 10),
                  Expanded(child: Text('A NEST account for $_existingFullName already exists.')),
                ],
              ),
            ),
          ),
          const SizedBox(height: 14),
          Text('Confirm', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 6),
          Text(
            'They were sent a code in their app\'s Notifications tab. Ask them to read it out to confirm '
            'they approve this enrolment.',
            style: Theme.of(context).textTheme.bodySmall,
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _codeController,
            autofocus: true,
            keyboardType: TextInputType.number,
            decoration: const InputDecoration(labelText: 'Code', prefixIcon: Icon(Icons.pin_outlined)),
          ),
          const SizedBox(height: 18),
          ElevatedButton(
            onPressed: _isSaving ? null : _confirm,
            child: _isSaving
                ? const SizedBox(height: 18, width: 18, child: CircularProgressIndicator(strokeWidth: 2))
                : const Text('Confirm'),
          ),
        ],
      );
    }

    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        TextField(controller: _usernameController, decoration: const InputDecoration(labelText: 'Username')),
        const SizedBox(height: 12),
        TextField(controller: _fullNameController, decoration: const InputDecoration(labelText: 'Full name')),
        const SizedBox(height: 12),
        TextField(controller: _phoneController, decoration: const InputDecoration(labelText: 'Phone')),
        const SizedBox(height: 12),
        TextField(controller: _dobController, decoration: const InputDecoration(labelText: 'Date of birth (YYYY-MM-DD)')),
        const SizedBox(height: 12),
        TextField(
          controller: _emailController,
          decoration: const InputDecoration(
            labelText: 'Email',
            helperText: 'Used to detect if this person already has a NEST account elsewhere.',
          ),
        ),
        const SizedBox(height: 12),
        ProfileImagePicker(
          onPicked: (file, bytes) => setState(() {
            _photoBytes = bytes;
            _photoFilename = file?.name;
          }),
        ),
        const SizedBox(height: 16),
        Text('Courses to enrol in', style: Theme.of(context).textTheme.titleMedium),
        Text(
          'Pick every course this student is joining - if they already have a NEST account (even at another '
          'academy), these get mapped to that same person once confirmed.',
          style: Theme.of(context).textTheme.bodySmall,
        ),
        const SizedBox(height: 8),
        _CoursesPicker(
          selectedCourseIds: _selectedCourseIds,
          onToggle: (id, selected) => setState(() => selected ? _selectedCourseIds.add(id) : _selectedCourseIds.remove(id)),
        ),
        const SizedBox(height: 18),
        ElevatedButton(
          onPressed: _isSaving ? null : _submit,
          child: _isSaving
              ? const SizedBox(height: 18, width: 18, child: CircularProgressIndicator(strokeWidth: 2))
              : const Text('Register student'),
        ),
      ],
    );
  }
}

class _TrainerForm extends ConsumerStatefulWidget {
  const _TrainerForm();

  @override
  ConsumerState<_TrainerForm> createState() => _TrainerFormState();
}

class _TrainerFormState extends ConsumerState<_TrainerForm> {
  final _usernameController = TextEditingController();
  final _fullNameController = TextEditingController();
  final _phoneController = TextEditingController();
  final _selectedFeatures = <String>{};
  final _selectedCourseIds = <String>{};
  bool _isSaving = false;
  Uint8List? _photoBytes;
  String? _photoFilename;

  static const _allFeatures = [
    FeatureKeys.attendance,
    FeatureKeys.batchScheduling,
    FeatureKeys.reschedule,
    FeatureKeys.feesEntry,
    FeatureKeys.syllabusEdit,
    FeatureKeys.eventManagement,
    FeatureKeys.studentRegistration,
    FeatureKeys.batchCreation,
  ];

  Future<void> _submit() async {
    setState(() => _isSaving = true);
    try {
      final result = await ref.read(enrolmentApiProvider).registerTrainer(
            username: _usernameController.text.trim(),
            fullName: _fullNameController.text.trim(),
            phone: _phoneController.text.trim(),
            features: _selectedFeatures,
            courseIds: _selectedCourseIds,
          );
      if (!mounted) return;

      String? photoWarning;
      if (_photoBytes != null) {
        try {
          await ref.read(enrolmentApiProvider).uploadProfileImage(result.userId, _photoBytes!, _photoFilename!);
        } on ApiException catch (e) {
          photoWarning = ' (photo upload failed: ${e.message})';
        }
      }
      if (!mounted) return;
      AppNotice.success(context, 'Registered - temp password: ${result.temporaryPassword}${photoWarning ?? ''}');
    } on ApiException catch (e) {
      if (mounted) AppNotice.error(context, e.message);
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        TextField(controller: _usernameController, decoration: const InputDecoration(labelText: 'Username')),
        const SizedBox(height: 12),
        TextField(controller: _fullNameController, decoration: const InputDecoration(labelText: 'Full name')),
        const SizedBox(height: 12),
        TextField(controller: _phoneController, decoration: const InputDecoration(labelText: 'Phone')),
        const SizedBox(height: 12),
        ProfileImagePicker(
          onPicked: (file, bytes) => setState(() {
            _photoBytes = bytes;
            _photoFilename = file?.name;
          }),
        ),
        const SizedBox(height: 16),
        Text('Courses to map', style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 4),
        Text(
          'Optional - can be assigned later once batches are set up.',
          style: Theme.of(context).textTheme.bodySmall,
        ),
        const SizedBox(height: 8),
        _CoursesPicker(
          selectedCourseIds: _selectedCourseIds,
          onToggle: (id, selected) => setState(() => selected ? _selectedCourseIds.add(id) : _selectedCourseIds.remove(id)),
        ),
        const SizedBox(height: 16),
        Text('Features to grant', style: Theme.of(context).textTheme.titleMedium),
        Text(
          'Capped to whatever features you yourself hold - the backend rejects anything beyond that (PRD §3.5).',
          style: Theme.of(context).textTheme.bodySmall,
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 4,
          children: _allFeatures.map((f) {
            final selected = _selectedFeatures.contains(f);
            return FilterChip(
              label: Text(f.replaceAll('_', ' ')),
              selected: selected,
              onSelected: (v) => setState(() => v ? _selectedFeatures.add(f) : _selectedFeatures.remove(f)),
            );
          }).toList(),
        ),
        const SizedBox(height: 18),
        ElevatedButton(
          onPressed: _isSaving ? null : _submit,
          child: _isSaving
              ? const SizedBox(height: 18, width: 18, child: CircularProgressIndicator(strokeWidth: 2))
              : const Text('Register trainer'),
        ),
      ],
    );
  }
}
