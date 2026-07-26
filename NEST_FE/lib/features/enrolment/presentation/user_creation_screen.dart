import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
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
import 'package:nest_fe/features/enrolment/presentation/user_edit_screens.dart';

/// Shows a student's login details (new registration or a password reset) in a dialog with copy
/// buttons - a snackbar would vanish before the admin can note them down. Both values are
/// selectable and copyable so they can be handed over reliably.
Future<void> showLoginCredentialsDialog(
  BuildContext context, {
  required String username,
  required String temporaryPassword,
  String title = 'Login details',
}) {
  return showDialog(
    context: context,
    builder: (dialogContext) => AlertDialog(
      title: Text(title),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Share these with the student - they change the password on first login.'),
          const SizedBox(height: 14),
          _CredentialRow(label: 'Username', value: username),
          const SizedBox(height: 8),
          _CredentialRow(label: 'Temporary password', value: temporaryPassword),
        ],
      ),
      actions: [TextButton(onPressed: () => Navigator.of(dialogContext).pop(), child: const Text('Done'))],
    ),
  );
}

class _CredentialRow extends StatelessWidget {
  const _CredentialRow({required this.label, required this.value});
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label, style: Theme.of(context).textTheme.bodySmall),
              SelectableText(value, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
            ],
          ),
        ),
        IconButton(
          icon: const Icon(Icons.copy_outlined, size: 18),
          tooltip: 'Copy',
          onPressed: () {
            Clipboard.setData(ClipboardData(text: value));
            AppNotice.success(context, '$label copied.');
          },
        ),
      ],
    );
  }
}

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
      body: TabBarView(controller: _tabController, children: const [_StudentRoster(), _TrainerRoster()]),
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
                    ref.invalidate(courseStudentsManageProvider);
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

/// Management rosters (includeInactive: true) - distinct from the batch-picker's active-only
/// studentsForCourseProvider, because here an admin needs to see AND reactivate deactivated people.
final courseStudentsManageProvider =
    FutureProvider.autoDispose.family<List<StudentSummary>, String>((ref, courseId) {
  return ref.watch(enrolmentApiProvider).studentsForCourse(courseId, includeInactive: true);
});

final courseTrainersManageProvider =
    FutureProvider.autoDispose.family<List<TrainerSummary>, String>((ref, courseId) {
  return ref.watch(enrolmentApiProvider).trainersForCourse(courseId, includeInactive: true);
});

class _RosterList extends ConsumerWidget {
  const _RosterList({required this.courseId});
  final String courseId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final studentsAsync = ref.watch(courseStudentsManageProvider(courseId));
    return AsyncValueView<List<StudentSummary>>(
      value: studentsAsync,
      onRetry: () => ref.invalidate(courseStudentsManageProvider(courseId)),
      data: (context, students) {
        if (students.isEmpty) {
          return const EmptyState(icon: Icons.people_outline, message: 'No students registered for this course yet.');
        }
        return ListView.builder(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          itemCount: students.length,
          itemBuilder: (context, i) {
            final s = students[i];
            return _MemberRosterTile(
              fullName: s.fullName,
              username: s.username,
              active: s.active,
              onToggle: (active) async {
                await ref.read(enrolmentApiProvider).setCourseMemberActive(courseId, s.membershipId, active);
                ref.invalidate(courseStudentsManageProvider(courseId));
                ref.invalidate(studentsForCourseProvider(courseId)); // keep the batch picker in sync
              },
              onResetPassword: () async {
                final temp = await ref.read(enrolmentApiProvider).resetStudentPassword(s.membershipId);
                if (context.mounted) {
                  await showLoginCredentialsDialog(context,
                      username: s.username, temporaryPassword: temp, title: 'New password');
                }
              },
              onEdit: () async {
                final saved = await Navigator.of(context).push<bool>(
                  MaterialPageRoute(builder: (_) => EditStudentScreen(membershipId: s.membershipId)),
                );
                if (saved == true) {
                  ref.invalidate(courseStudentsManageProvider(courseId));
                  ref.invalidate(studentsForCourseProvider(courseId));
                }
              },
            );
          },
        );
      },
    );
  }
}

/// One roster row with an active/inactive switch. Deactivating removes the course from that
/// person's app and drops them from batch pickers; the row stays so it can be flipped back.
class _MemberRosterTile extends StatefulWidget {
  const _MemberRosterTile({
    required this.fullName,
    required this.username,
    required this.active,
    required this.onToggle,
    this.onResetPassword,
    this.onEdit,
  });

  final String fullName;
  final String username;
  final bool active;
  final Future<void> Function(bool active) onToggle;

  /// When set (students), a key button offers a password reset. Omitted for trainers.
  final Future<void> Function()? onResetPassword;

  /// Opens the edit form for this person.
  final VoidCallback? onEdit;

  @override
  State<_MemberRosterTile> createState() => _MemberRosterTileState();
}

class _MemberRosterTileState extends State<_MemberRosterTile> {
  bool _busy = false;

  Future<void> _run(Future<void> Function() action) async {
    setState(() => _busy = true);
    try {
      await action();
    } on ApiException catch (e) {
      if (mounted) AppNotice.error(context, e.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final active = widget.active;
    return Card(
      margin: const EdgeInsets.symmetric(vertical: 4),
      child: ListTile(
        leading: CircleAvatar(
          child: Text(widget.fullName.isNotEmpty ? widget.fullName[0].toUpperCase() : '?'),
        ),
        title: Text(widget.fullName),
        subtitle: Text(active ? '@${widget.username}' : '@${widget.username} · inactive'),
        enabled: active,
        trailing: _busy
            ? const SizedBox(height: 20, width: 20, child: CircularProgressIndicator(strokeWidth: 2))
            : Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (widget.onEdit != null)
                    IconButton(
                      icon: const Icon(Icons.edit_outlined, size: 20),
                      tooltip: 'Edit',
                      onPressed: widget.onEdit,
                    ),
                  if (widget.onResetPassword != null)
                    IconButton(
                      icon: const Icon(Icons.key_outlined, size: 20),
                      tooltip: 'Reset password',
                      onPressed: () => _run(widget.onResetPassword!),
                    ),
                  Switch(value: active, onChanged: (v) => _run(() => widget.onToggle(v))),
                ],
              ),
      ),
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
        if (photoWarning != null) AppNotice.error(context, 'Registered, but$photoWarning');
        // Students log in with a password now - surface the generated temp one so it can be handed
        // over (a snackbar would vanish before it's noted down).
        await showLoginCredentialsDialog(
          context,
          username: result.username,
          temporaryPassword: result.temporaryPassword ?? '(unavailable)',
        );
        if (mounted) Navigator.of(context).pop();
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

/// Trainer tab, roster-first (mirrors _StudentRoster): pick a course, see its trainers with an
/// active/inactive switch, "Add trainer" below. Only actual course-mapped Trainers appear here -
/// an Academy Admin is not a Trainer and is never listed as one.
class _TrainerRoster extends ConsumerStatefulWidget {
  const _TrainerRoster();

  @override
  ConsumerState<_TrainerRoster> createState() => _TrainerRosterState();
}

class _TrainerRosterState extends ConsumerState<_TrainerRoster> {
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
          return const EmptyState(icon: Icons.school_outlined, message: 'No courses to show trainers for yet.');
        }
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
                  ? const EmptyState(icon: Icons.filter_list_outlined, message: 'Pick a course to see its trainers.')
                  : _TrainerRosterList(courseId: selectedCourseId),
            ),
            SafeArea(
              top: false,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                child: OutlinedButton.icon(
                  icon: const Icon(Icons.badge_outlined),
                  label: const Text('Add trainer'),
                  onPressed: () async {
                    await Navigator.of(context).push(MaterialPageRoute(builder: (_) => const _AddTrainerScreen()));
                    if (selectedCourseId != null) ref.invalidate(courseTrainersManageProvider(selectedCourseId));
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

class _TrainerRosterList extends ConsumerWidget {
  const _TrainerRosterList({required this.courseId});
  final String courseId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final trainersAsync = ref.watch(courseTrainersManageProvider(courseId));
    return AsyncValueView<List<TrainerSummary>>(
      value: trainersAsync,
      onRetry: () => ref.invalidate(courseTrainersManageProvider(courseId)),
      data: (context, trainers) {
        if (trainers.isEmpty) {
          return const EmptyState(icon: Icons.people_outline, message: 'No trainers mapped to this course yet.');
        }
        return ListView.builder(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          itemCount: trainers.length,
          itemBuilder: (context, i) {
            final t = trainers[i];
            return _MemberRosterTile(
              fullName: t.fullName,
              username: t.username,
              active: t.active,
              onToggle: (active) async {
                await ref.read(enrolmentApiProvider).setCourseMemberActive(courseId, t.membershipId, active);
                ref.invalidate(courseTrainersManageProvider(courseId));
              },
              onEdit: () async {
                final saved = await Navigator.of(context).push<bool>(
                  MaterialPageRoute(builder: (_) => EditTrainerScreen(membershipId: t.membershipId)),
                );
                if (saved == true) ref.invalidate(courseTrainersManageProvider(courseId));
              },
            );
          },
        );
      },
    );
  }
}

class _AddTrainerScreen extends StatelessWidget {
  const _AddTrainerScreen();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Add trainer')),
      body: const _TrainerForm(),
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
  final _emailController = TextEditingController();
  final _dobController = TextEditingController();
  final _addressController = TextEditingController();
  final _cityController = TextEditingController();
  final _stateController = TextEditingController();
  final _yearsOfExperienceController = TextEditingController();
  final _selectedCourseIds = <String>{};

  /// ON (default): one shared feature set applied to every selected course. OFF: each course gets
  /// its own set from [_perCourseFeatures].
  bool _sameForAll = true;
  final _sharedFeatures = <String>{};
  final _perCourseFeatures = <String, Set<String>>{};

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

  /// courseId -> features to grant, exactly what the backend's courseFeatures map expects.
  Map<String, Set<String>> _buildCourseFeatures() {
    return {
      for (final courseId in _selectedCourseIds)
        courseId: _sameForAll ? {..._sharedFeatures} : {...?_perCourseFeatures[courseId]},
    };
  }

  @override
  void dispose() {
    _usernameController.dispose();
    _fullNameController.dispose();
    _phoneController.dispose();
    _emailController.dispose();
    _dobController.dispose();
    _addressController.dispose();
    _cityController.dispose();
    _stateController.dispose();
    _yearsOfExperienceController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_selectedCourseIds.isEmpty) {
      AppNotice.error(context, 'Assign the trainer to at least one course.');
      return;
    }
    if (_emailController.text.trim().isEmpty || _dobController.text.trim().isEmpty) {
      AppNotice.error(context, 'Email and date of birth are required.');
      return;
    }
    setState(() => _isSaving = true);
    try {
      final result = await ref.read(enrolmentApiProvider).registerTrainer(
            username: _usernameController.text.trim(),
            fullName: _fullNameController.text.trim(),
            phone: _phoneController.text.trim(),
            email: _emailController.text.trim(),
            dob: _dobController.text.trim(),
            address: _addressController.text.trim().isEmpty ? null : _addressController.text.trim(),
            city: _cityController.text.trim().isEmpty ? null : _cityController.text.trim(),
            state: _stateController.text.trim().isEmpty ? null : _stateController.text.trim(),
            yearsOfExperience: int.tryParse(_yearsOfExperienceController.text.trim()),
            courseFeatures: _buildCourseFeatures(),
          );
      if (!mounted) return;

      if (_photoBytes != null) {
        try {
          await ref.read(enrolmentApiProvider).uploadProfileImage(result.userId, _photoBytes!, _photoFilename!);
        } on ApiException catch (e) {
          if (mounted) AppNotice.error(context, 'Registered, but photo upload failed: ${e.message}');
        }
      }
      if (!mounted) return;
      await showLoginCredentialsDialog(context,
          username: result.username, temporaryPassword: result.temporaryPassword);
      if (mounted) Navigator.of(context).pop();
    } on ApiException catch (e) {
      if (mounted) AppNotice.error(context, e.message);
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  Widget _featureWrap(Set<String> selected, void Function(String feature, bool on) onToggle) {
    return Wrap(
      spacing: 8,
      runSpacing: 4,
      children: _allFeatures.map((f) {
        return FilterChip(
          label: Text(f.replaceAll('_', ' ')),
          selected: selected.contains(f),
          onSelected: (v) => setState(() => onToggle(f, v)),
        );
      }).toList(),
    );
  }

  /// One labelled feature picker per selected course (the "per-course" toggle state).
  List<Widget> _perCourseFeatureSections() {
    final courses = ref.read(activeCoursesProvider).valueOrNull ?? const <Course>[];
    String nameFor(String id) {
      for (final c in courses) {
        if (c.id == id) return c.name;
      }
      return 'Course';
    }

    return _selectedCourseIds.map((courseId) {
      final selected = _perCourseFeatures[courseId] ?? const <String>{};
      return Padding(
        padding: const EdgeInsets.only(bottom: 14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(nameFor(courseId), style: Theme.of(context).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700)),
            const SizedBox(height: 6),
            _featureWrap(selected, (f, on) {
              final set = _perCourseFeatures.putIfAbsent(courseId, () => <String>{});
              on ? set.add(f) : set.remove(f);
            }),
          ],
        ),
      );
    }).toList();
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
        TextField(
          controller: _emailController,
          decoration: const InputDecoration(
            labelText: 'Email',
            helperText: 'Required - this app uses email as the unique account identifier.',
          ),
        ),
        const SizedBox(height: 12),
        TextField(controller: _dobController, decoration: const InputDecoration(labelText: 'Date of birth (YYYY-MM-DD)')),
        const SizedBox(height: 12),
        TextField(
          controller: _yearsOfExperienceController,
          keyboardType: TextInputType.number,
          decoration: const InputDecoration(labelText: 'Years of experience (optional)'),
        ),
        const SizedBox(height: 12),
        TextField(controller: _addressController, decoration: const InputDecoration(labelText: 'Address (optional)')),
        const SizedBox(height: 12),
        Row(children: [
          Expanded(child: TextField(controller: _cityController, decoration: const InputDecoration(labelText: 'City'))),
          const SizedBox(width: 12),
          Expanded(child: TextField(controller: _stateController, decoration: const InputDecoration(labelText: 'State'))),
        ]),
        const SizedBox(height: 12),
        ProfileImagePicker(
          onPicked: (file, bytes) => setState(() {
            _photoBytes = bytes;
            _photoFilename = file?.name;
          }),
        ),
        const SizedBox(height: 16),
        Text('Courses to assign', style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 4),
        Text(
          'Pick the courses this trainer will handle - features are granted per course below.',
          style: Theme.of(context).textTheme.bodySmall,
        ),
        const SizedBox(height: 8),
        _CoursesPicker(
          selectedCourseIds: _selectedCourseIds,
          onToggle: (id, selected) => setState(() {
            if (selected) {
              _selectedCourseIds.add(id);
            } else {
              _selectedCourseIds.remove(id);
              _perCourseFeatures.remove(id);
            }
          }),
        ),
        const SizedBox(height: 16),
        Text('Features to grant', style: Theme.of(context).textTheme.titleMedium),
        Text(
          'Capped to whatever features you yourself hold - the backend rejects anything beyond that (PRD §3.5).',
          style: Theme.of(context).textTheme.bodySmall,
        ),
        const SizedBox(height: 4),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: const Text('Same features for all courses'),
          subtitle: Text(_sameForAll
              ? 'One feature set applied to every selected course.'
              : 'Set features separately for each course.'),
          value: _sameForAll,
          onChanged: (v) => setState(() => _sameForAll = v),
        ),
        const SizedBox(height: 8),
        if (_sameForAll)
          _featureWrap(_sharedFeatures, (f, on) => on ? _sharedFeatures.add(f) : _sharedFeatures.remove(f))
        else if (_selectedCourseIds.isEmpty)
          Text('Pick a course above first.', style: Theme.of(context).textTheme.bodySmall)
        else
          ..._perCourseFeatureSections(),
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
