import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:nest_fe/core/error/api_exception.dart';
import 'package:nest_fe/core/widgets/app_notice.dart';
import 'package:nest_fe/core/widgets/async_value_view.dart';
import 'package:nest_fe/features/curriculum/data/course.dart';
import 'package:nest_fe/features/curriculum/data/curriculum_api.dart';
import 'package:nest_fe/features/enrolment/data/enrolment_api.dart';
import 'package:nest_fe/features/enrolment/presentation/batches_screen.dart';
import 'package:nest_fe/features/enrolment/presentation/course_feature_assigner.dart';

// ============================ Trainer edit ============================

/// Edit an existing trainer's profile + per-course features. Pre-fills from GET /trainers/{id},
/// saves via PUT. Username is fixed (login id), so it isn't editable.
class EditTrainerScreen extends ConsumerStatefulWidget {
  const EditTrainerScreen({super.key, required this.membershipId});
  final String membershipId;

  @override
  ConsumerState<EditTrainerScreen> createState() => _EditTrainerScreenState();
}

class _EditTrainerScreenState extends ConsumerState<EditTrainerScreen> {
  final _fullName = TextEditingController();
  final _phone = TextEditingController();
  final _email = TextEditingController();
  final _dob = TextEditingController();
  final _address = TextEditingController();
  final _city = TextEditingController();
  final _state = TextEditingController();
  final _yearsOfExperience = TextEditingController();

  Map<String, Set<String>> _courseFeatures = {};
  TrainerDetail? _detail;
  bool _loading = true;
  String? _loadError;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final d = await ref.read(enrolmentApiProvider).trainerDetail(widget.membershipId);
      _fullName.text = d.fullName;
      _phone.text = d.phone ?? '';
      _email.text = d.email ?? '';
      _dob.text = d.dob ?? '';
      _address.text = d.address ?? '';
      _city.text = d.city ?? '';
      _state.text = d.state ?? '';
      _yearsOfExperience.text = d.yearsOfExperience?.toString() ?? '';
      setState(() {
        _detail = d;
        _courseFeatures = d.courseFeatures;
        _loading = false;
      });
    } on ApiException catch (e) {
      setState(() {
        _loadError = e.message;
        _loading = false;
      });
    }
  }

  @override
  void dispose() {
    _fullName.dispose();
    _phone.dispose();
    _email.dispose();
    _dob.dispose();
    _address.dispose();
    _city.dispose();
    _state.dispose();
    _yearsOfExperience.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_courseFeatures.isEmpty) {
      AppNotice.error(context, 'Assign the trainer to at least one course.');
      return;
    }
    if (_email.text.trim().isEmpty || _dob.text.trim().isEmpty) {
      AppNotice.error(context, 'Email and date of birth are required.');
      return;
    }
    setState(() => _saving = true);
    try {
      await ref.read(enrolmentApiProvider).updateTrainer(
            widget.membershipId,
            fullName: _fullName.text.trim(),
            phone: _phone.text.trim(),
            email: _email.text.trim(),
            dob: _dob.text.trim(),
            address: _address.text.trim().isEmpty ? null : _address.text.trim(),
            city: _city.text.trim().isEmpty ? null : _city.text.trim(),
            state: _state.text.trim().isEmpty ? null : _state.text.trim(),
            yearsOfExperience: int.tryParse(_yearsOfExperience.text.trim()),
            courseFeatures: _courseFeatures,
          );
      if (mounted) {
        AppNotice.success(context, 'Trainer updated.');
        Navigator.of(context).pop(true);
      }
    } on ApiException catch (e) {
      if (mounted) AppNotice.error(context, e.message);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(_detail == null ? 'Edit trainer' : 'Edit ${_detail!.fullName}')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _loadError != null
              ? Center(child: Padding(padding: const EdgeInsets.all(24), child: Text(_loadError!)))
              : ListView(
                  padding: const EdgeInsets.all(20),
                  children: [
                    Text('@${_detail!.username}', style: Theme.of(context).textTheme.bodySmall),
                    const SizedBox(height: 12),
                    TextField(controller: _fullName, decoration: const InputDecoration(labelText: 'Full name')),
                    const SizedBox(height: 12),
                    TextField(controller: _phone, decoration: const InputDecoration(labelText: 'Phone')),
                    const SizedBox(height: 12),
                    TextField(controller: _email, decoration: const InputDecoration(labelText: 'Email')),
                    const SizedBox(height: 12),
                    TextField(controller: _dob, decoration: const InputDecoration(labelText: 'Date of birth (YYYY-MM-DD)')),
                    const SizedBox(height: 12),
                    TextField(
                      controller: _yearsOfExperience,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(labelText: 'Years of experience (optional)'),
                    ),
                    const SizedBox(height: 12),
                    TextField(controller: _address, decoration: const InputDecoration(labelText: 'Address (optional)')),
                    const SizedBox(height: 12),
                    Row(children: [
                      Expanded(child: TextField(controller: _city, decoration: const InputDecoration(labelText: 'City'))),
                      const SizedBox(width: 12),
                      Expanded(child: TextField(controller: _state, decoration: const InputDecoration(labelText: 'State'))),
                    ]),
                    const SizedBox(height: 16),
                    CourseFeatureAssigner(
                      initial: _detail!.courseFeatures,
                      onChanged: (m) => _courseFeatures = m,
                    ),
                    const SizedBox(height: 18),
                    ElevatedButton(
                      onPressed: _saving ? null : _save,
                      child: _saving
                          ? const SizedBox(height: 18, width: 18, child: CircularProgressIndicator(strokeWidth: 2))
                          : const Text('Save changes'),
                    ),
                  ],
                ),
    );
  }
}

// ============================ Student edit ============================

/// Edit an existing student's profile + enrolled courses/fees. Pre-fills from GET /students/{id}.
class EditStudentScreen extends ConsumerStatefulWidget {
  const EditStudentScreen({super.key, required this.membershipId});
  final String membershipId;

  @override
  ConsumerState<EditStudentScreen> createState() => _EditStudentScreenState();
}

class _EditStudentScreenState extends ConsumerState<EditStudentScreen> {
  final _fullName = TextEditingController();
  final _phone = TextEditingController();
  final _dob = TextEditingController();
  final _email = TextEditingController();
  final _address = TextEditingController();
  final _city = TextEditingController();
  final _state = TextEditingController();

  /// courseId -> fee text controller (only for selected courses).
  final _feeControllers = <String, TextEditingController>{};
  final _selectedCourseIds = <String>{};

  StudentDetail? _detail;
  bool _loading = true;
  String? _loadError;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final d = await ref.read(enrolmentApiProvider).studentDetail(widget.membershipId);
      _fullName.text = d.fullName;
      _phone.text = d.phone ?? '';
      _dob.text = d.dob ?? '';
      _email.text = d.email ?? '';
      _address.text = d.address ?? '';
      _city.text = d.city ?? '';
      _state.text = d.state ?? '';
      d.courseFees.forEach((courseId, fee) {
        _selectedCourseIds.add(courseId);
        _feeControllers[courseId] = TextEditingController(text: fee?.toString() ?? '');
      });
      setState(() {
        _detail = d;
        _loading = false;
      });
    } on ApiException catch (e) {
      setState(() {
        _loadError = e.message;
        _loading = false;
      });
    }
  }

  @override
  void dispose() {
    for (final c in [_fullName, _phone, _dob, _email, _address, _city, _state]) {
      c.dispose();
    }
    for (final c in _feeControllers.values) {
      c.dispose();
    }
    super.dispose();
  }

  void _toggleCourse(String courseId, bool selected) {
    setState(() {
      if (selected) {
        _selectedCourseIds.add(courseId);
        _feeControllers.putIfAbsent(courseId, () => TextEditingController());
      } else {
        _selectedCourseIds.remove(courseId);
      }
    });
  }

  Future<void> _save() async {
    if (_selectedCourseIds.isEmpty) {
      AppNotice.error(context, 'A student needs at least one course.');
      return;
    }
    if (_dob.text.trim().isEmpty) {
      AppNotice.error(context, 'Date of birth is required.');
      return;
    }
    setState(() => _saving = true);
    try {
      final courses = _selectedCourseIds.map((id) {
        final raw = _feeControllers[id]?.text.trim() ?? '';
        return {'courseId': id, 'fee': raw.isEmpty ? null : num.tryParse(raw)};
      }).toList();
      await ref.read(enrolmentApiProvider).updateStudent(
            widget.membershipId,
            fullName: _fullName.text.trim(),
            phone: _phone.text.trim(),
            dob: _dob.text.trim(),
            email: _email.text.trim().isEmpty ? null : _email.text.trim(),
            address: _address.text.trim().isEmpty ? null : _address.text.trim(),
            city: _city.text.trim().isEmpty ? null : _city.text.trim(),
            state: _state.text.trim().isEmpty ? null : _state.text.trim(),
            courses: courses,
          );
      if (mounted) {
        AppNotice.success(context, 'Student updated.');
        Navigator.of(context).pop(true);
      }
    } on ApiException catch (e) {
      if (mounted) AppNotice.error(context, e.message);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(_detail == null ? 'Edit student' : 'Edit ${_detail!.fullName}')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _loadError != null
              ? Center(child: Padding(padding: const EdgeInsets.all(24), child: Text(_loadError!)))
              : ListView(
                  padding: const EdgeInsets.all(20),
                  children: [
                    Text('@${_detail!.username}', style: Theme.of(context).textTheme.bodySmall),
                    const SizedBox(height: 12),
                    TextField(controller: _fullName, decoration: const InputDecoration(labelText: 'Full name')),
                    const SizedBox(height: 12),
                    TextField(controller: _phone, decoration: const InputDecoration(labelText: 'Phone')),
                    const SizedBox(height: 12),
                    TextField(controller: _dob, decoration: const InputDecoration(labelText: 'Date of birth (YYYY-MM-DD)')),
                    const SizedBox(height: 12),
                    TextField(controller: _email, decoration: const InputDecoration(labelText: 'Email')),
                    const SizedBox(height: 12),
                    TextField(controller: _address, decoration: const InputDecoration(labelText: 'Address (optional)')),
                    const SizedBox(height: 12),
                    Row(children: [
                      Expanded(child: TextField(controller: _city, decoration: const InputDecoration(labelText: 'City'))),
                      const SizedBox(width: 12),
                      Expanded(child: TextField(controller: _state, decoration: const InputDecoration(labelText: 'State'))),
                    ]),
                    const SizedBox(height: 16),
                    Text('Courses & fees', style: Theme.of(context).textTheme.titleMedium),
                    const SizedBox(height: 8),
                    _CourseFeeEditor(
                      selectedCourseIds: _selectedCourseIds,
                      feeControllers: _feeControllers,
                      onToggle: _toggleCourse,
                    ),
                    const SizedBox(height: 18),
                    ElevatedButton(
                      onPressed: _saving ? null : _save,
                      child: _saving
                          ? const SizedBox(height: 18, width: 18, child: CircularProgressIndicator(strokeWidth: 2))
                          : const Text('Save changes'),
                    ),
                  ],
                ),
    );
  }
}

/// Per-course checkbox + editable agreed-fee field, for the student edit form.
class _CourseFeeEditor extends ConsumerWidget {
  const _CourseFeeEditor({required this.selectedCourseIds, required this.feeControllers, required this.onToggle});

  final Set<String> selectedCourseIds;
  final Map<String, TextEditingController> feeControllers;
  final void Function(String courseId, bool selected) onToggle;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final coursesAsync = ref.watch(activeCoursesProvider);
    return AsyncValueView<List<Course>>(
      value: coursesAsync,
      onRetry: () => ref.invalidate(activeCoursesProvider),
      data: (context, courses) {
        if (courses.isEmpty) {
          return const Text('No active courses in this academy yet.', style: TextStyle(fontSize: 12.5));
        }
        return Column(
          children: courses.map((c) {
            final selected = selectedCourseIds.contains(c.id);
            return Column(
              children: [
                CheckboxListTile(
                  contentPadding: EdgeInsets.zero,
                  controlAffinity: ListTileControlAffinity.leading,
                  dense: true,
                  title: Text(c.name),
                  value: selected,
                  onChanged: (v) => onToggle(c.id, v ?? false),
                ),
                if (selected)
                  Padding(
                    padding: const EdgeInsets.only(left: 32, bottom: 8),
                    child: TextField(
                      controller: feeControllers[c.id],
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(labelText: 'Agreed fee (₹) - blank = course default'),
                    ),
                  ),
              ],
            );
          }).toList(),
        );
      },
    );
  }
}
