import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import 'package:nest_fe/app/theme/app_tokens.dart';
import 'package:nest_fe/app/theme/app_typography.dart';
import 'package:nest_fe/core/auth/feature_keys.dart';
import 'package:nest_fe/core/auth/session_controller.dart';
import 'package:nest_fe/core/design/avatar.dart';
import 'package:nest_fe/core/design/buttons.dart';
import 'package:nest_fe/core/design/calendar_modal.dart';
import 'package:nest_fe/core/design/category_meta.dart';
import 'package:nest_fe/core/design/pressable.dart';
import 'package:nest_fe/core/design/segmented_control.dart';
import 'package:nest_fe/core/design/sheets.dart';
import 'package:nest_fe/core/design/toast.dart';
import 'package:nest_fe/core/format/money.dart';
import 'package:nest_fe/features/curriculum/data/course.dart';
import 'package:nest_fe/features/curriculum/data/curriculum_api.dart';
import 'package:nest_fe/features/enrolment/data/batch.dart';
import 'package:nest_fe/features/enrolment/data/enrolment_api.dart';
import 'package:nest_fe/features/enrolment/data/person_details.dart';
import 'package:nest_fe/features/enrolment/data/user_tab.dart';
import 'package:nest_fe/features/enrolment/presentation/widgets/feature_catalog.dart';
import 'package:nest_fe/features/enrolment/presentation/widgets/form_fields.dart';
import 'package:nest_fe/features/enrolment/presentation/widgets/user_dialogs.dart';

/// One trainer access group: a set of courses that share the same batch scope and the same
/// feature checklist.
///
/// Grouping courses rather than repeating a tile per course is the point - a trainer who teaches
/// Bharatanatyam and Kathak with identical permissions fills in one tile, and only needs a second
/// when a course genuinely differs. On save each course in the group is expanded into its own
/// entry, because that is the shape the backend stores grants in.
class _AccessGroup {
  _AccessGroup(this.id);

  final String id;
  final Set<String> courseIds = {};
  final Set<String> batchIds = {};
  final Set<String> featureKeys = {};
}

/// Create or edit a student or a trainer. Pops `true` when something was saved.
///
/// Students fill one page. Trainers fill two: the profile, then course and feature access - the
/// mapping step is long enough on its own that mixing it into one scroll buries the profile
/// fields underneath it.
class UserFormScreen extends ConsumerStatefulWidget {
  const UserFormScreen({
    super.key,
    required this.tab,
    this.editingMembershipId,
    this.editingName,
    this.initialCourseId,
  });

  final UserTab tab;

  /// Set when editing. The person's type is fixed in that case - a student does not become a
  /// trainer by editing the record.
  final String? editingMembershipId;
  final String? editingName;

  /// The course the roster was filtered to, pre-selected so the common case ("add someone to the
  /// course I am looking at") needs no extra taps.
  final String? initialCourseId;

  @override
  ConsumerState<UserFormScreen> createState() => _UserFormScreenState();
}

class _UserFormScreenState extends ConsumerState<UserFormScreen> {
  // -- identity -------------------------------------------------------------
  final _emailController = TextEditingController();
  final _firstNameController = TextEditingController();
  final _lastNameController = TextEditingController();
  final _usernameController = TextEditingController();
  final _phoneController = TextEditingController();
  final _altPhoneController = TextEditingController();

  // -- address --------------------------------------------------------------
  final _line1Controller = TextEditingController();
  final _line2Controller = TextEditingController();
  final _landmarkController = TextEditingController();
  final _cityController = TextEditingController();
  final _districtController = TextEditingController();
  final _stateController = TextEditingController();
  final _countryController = TextEditingController(text: 'India');
  final _pinController = TextEditingController();

  // -- role-specific --------------------------------------------------------
  final _guardianController = TextEditingController();
  final _emergencyController = TextEditingController();
  final _qualificationController = TextEditingController();
  final _experienceController = TextEditingController();
  final _salaryController = TextEditingController();

  String _phoneCode = '+91';
  String _altPhoneCode = '+91';
  String _emergencyCode = '+91';

  /// True once the username has been typed into by hand. Until then it tracks the name, which is
  /// what makes the auto-suggestion useful rather than something to fight with.
  bool _usernameTouched = false;

  DateTime? _dob;
  DateTime _joiningDate = DateTime.now();
  String? _gender;
  String? _bloodGroup;
  bool _active = true;

  Uint8List? _photoBytes;
  String? _photoFilename;

  /// Students: which courses to enrol in, and optionally which batches within them.
  final Set<String> _studentCourseIds = {};
  final Set<String> _studentBatchIds = {};

  /// Trainers: the access groups built on step 2.
  final List<_AccessGroup> _groups = [];
  String? _expandedGroupId;

  /// Trainer form only. Step 1 is the profile, step 2 the course mapping.
  int _step = 1;

  bool _busy = false;
  bool _loadingExisting = false;

  /// Set of section keys currently open. The optional sections start closed so the required
  /// fields are not buried under a screenful of address inputs.
  final Set<String> _openSections = {'identity', 'personal'};

  bool get _isEditing => widget.editingMembershipId != null;
  bool get _isTrainer => widget.tab == UserTab.trainer;

  @override
  void initState() {
    super.initState();
    if (widget.initialCourseId != null && !_isTrainer) {
      _studentCourseIds.add(widget.initialCourseId!);
    }
    if (_isEditing) {
      _loadExisting();
    } else if (_isTrainer && widget.initialCourseId != null) {
      final group = _AccessGroup('g0');
      group.courseIds.add(widget.initialCourseId!);
      _groups.add(group);
      _expandedGroupId = group.id;
    }
  }

  @override
  void dispose() {
    for (final c in [
      _emailController,
      _firstNameController,
      _lastNameController,
      _usernameController,
      _phoneController,
      _altPhoneController,
      _line1Controller,
      _line2Controller,
      _landmarkController,
      _cityController,
      _districtController,
      _stateController,
      _countryController,
      _pinController,
      _guardianController,
      _emergencyController,
      _qualificationController,
      _experienceController,
      _salaryController,
    ]) {
      c.dispose();
    }
    super.dispose();
  }

  // ---------------------------------------------------------------------------
  // Loading an existing record
  // ---------------------------------------------------------------------------

  Future<void> _loadExisting() async {
    setState(() => _loadingExisting = true);
    final api = ref.read(enrolmentApiProvider);
    try {
      if (_isTrainer) {
        final detail = await api.trainerDetail(widget.editingMembershipId!);
        if (!mounted) return;
        _applyCommon(
          fullName: detail.fullName,
          username: detail.username,
          email: detail.email,
          phone: detail.phone,
          dob: detail.dob,
          details: detail.details,
        );
        _experienceController.text = detail.yearsOfExperience?.toString() ?? '';
        _groups.clear();
        // One group per course as stored. Regrouping courses that happen to share a feature set
        // would be guessing at an intent the data does not record.
        var i = 0;
        for (final entry in detail.courseFeatures.entries) {
          final group = _AccessGroup('g${i++}');
          group.courseIds.add(entry.key);
          group.featureKeys.addAll(entry.value);
          group.batchIds.addAll(detail.courseBatches[entry.key] ?? const <String>{});
          _groups.add(group);
        }
      } else {
        final detail = await api.studentDetail(widget.editingMembershipId!);
        if (!mounted) return;
        _applyCommon(
          fullName: detail.fullName,
          username: detail.username,
          email: detail.email,
          phone: detail.phone,
          dob: detail.dob,
          details: detail.details,
        );
        _studentCourseIds
          ..clear()
          ..addAll(detail.courseFees.keys);
      }
    } catch (e) {
      if (mounted) showAppToast(context, e.toString().replaceFirst('Exception: ', ''));
    } finally {
      if (mounted) setState(() => _loadingExisting = false);
    }
  }

  void _applyCommon({
    required String fullName,
    required String username,
    String? email,
    String? phone,
    String? dob,
    PersonDetails? details,
  }) {
    // The separate name columns arrived in V26, so older records only have the joined name -
    // splitting it is a fallback, not the normal path.
    final first = details?.firstName;
    final last = details?.lastName;
    if ((first ?? '').isEmpty && (last ?? '').isEmpty) {
      final split = splitName(fullName);
      _firstNameController.text = split.firstName;
      _lastNameController.text = split.lastName;
    } else {
      _firstNameController.text = first ?? '';
      _lastNameController.text = last ?? '';
    }
    _usernameController.text = username;
    _usernameTouched = true;
    _emailController.text = email ?? '';

    final phoneParts = CountryCode.split(phone);
    _phoneCode = phoneParts.code;
    _phoneController.text = phoneParts.digits;

    if (dob != null && dob.isNotEmpty) _dob = DateTime.tryParse(dob);

    if (details != null) {
      final altParts = CountryCode.split(details.altPhone);
      _altPhoneCode = altParts.code;
      _altPhoneController.text = altParts.digits;

      _gender = details.gender;
      _bloodGroup = details.bloodGroup;

      _line1Controller.text = details.addressLine1 ?? '';
      _line2Controller.text = details.addressLine2 ?? '';
      _landmarkController.text = details.landmark ?? '';
      _cityController.text = details.city ?? '';
      _districtController.text = details.district ?? '';
      _stateController.text = details.state ?? '';
      _countryController.text = details.country ?? 'India';
      _pinController.text = details.pinCode ?? '';

      _guardianController.text = details.guardianName ?? '';
      final emergencyParts = CountryCode.split(details.emergencyContact);
      _emergencyCode = emergencyParts.code;
      _emergencyController.text = emergencyParts.digits;

      _qualificationController.text = details.qualification ?? '';
      _salaryController.text = details.salary?.toString() ?? '';
      if (details.joiningDate != null) _joiningDate = details.joiningDate!;
    }
    setState(() {});
  }

  // ---------------------------------------------------------------------------
  // Validation
  // ---------------------------------------------------------------------------

  static final _emailPattern = RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$');

  bool get _emailValid => _emailPattern.hasMatch(_emailController.text.trim());

  /// The address is required in full because it is what an academy falls back on when a phone
  /// number stops working - a half-filled one has none of that value.
  bool get _addressValid =>
      _line1Controller.text.trim().length > 3 &&
      _cityController.text.trim().length > 1 &&
      _stateController.text.trim().length > 1 &&
      _pinController.text.trim().length >= 4;

  bool get _commonValid =>
      _emailValid &&
      _firstNameController.text.trim().isNotEmpty &&
      _lastNameController.text.trim().isNotEmpty &&
      _usernameController.text.trim().length > 1 &&
      _dob != null &&
      (_gender ?? '').isNotEmpty &&
      _phoneController.text.trim().length >= 10 &&
      _addressValid;

  bool get _valid => _isTrainer
      ? _commonValid && _qualificationController.text.trim().length > 1
      : _commonValid && _guardianController.text.trim().length > 1;

  String _missingRequirement() {
    if (!_emailValid) return 'Enter a valid email address.';
    if (_firstNameController.text.trim().isEmpty) return 'First name is required.';
    if (_lastNameController.text.trim().isEmpty) return 'Last name is required.';
    if (_usernameController.text.trim().length < 2) return 'Pick a username.';
    if (_dob == null) return 'Select a date of birth.';
    if ((_gender ?? '').isEmpty) return 'Select a gender.';
    if (_phoneController.text.trim().length < 10) return 'Enter a 10-digit phone number.';
    if (!_addressValid) return 'Fill in address line 1, city, state and PIN code.';
    if (_isTrainer && _qualificationController.text.trim().length < 2) {
      return 'Add a qualification or experience summary.';
    }
    if (!_isTrainer && _guardianController.text.trim().length < 2) {
      return "Add the parent's or guardian's name.";
    }
    return '';
  }

  // ---------------------------------------------------------------------------
  // Field helpers
  // ---------------------------------------------------------------------------

  void _syncUsername() {
    if (_usernameTouched) return;
    final full = '${_firstNameController.text} ${_lastNameController.text}';
    _usernameController.text = slugifyUsername(full);
  }

  Future<void> _pickPhoto() async {
    final file = await ImagePicker()
        .pickImage(source: ImageSource.gallery, maxWidth: 800, imageQuality: 85);
    if (file == null) return;
    final bytes = await file.readAsBytes();
    if (!mounted) return;
    setState(() {
      _photoBytes = bytes;
      _photoFilename = file.name;
    });
  }

  Future<void> _pickDob() async {
    final picked = await showAppCalendar(
      context: context,
      month: _dob ?? DateTime(DateTime.now().year - 12),
      selectedDay: _dob?.day,
      latestMonth: DateTime.now(),
    );
    if (picked != null) setState(() => _dob = picked);
  }

  Future<void> _pickJoiningDate() async {
    final picked = await showAppCalendar(
      context: context,
      month: _joiningDate,
      selectedDay: _joiningDate.day,
    );
    if (picked != null) setState(() => _joiningDate = picked);
  }

  String _joined(String code, TextEditingController controller) {
    final digits = controller.text.trim();
    return digits.isEmpty ? '' : '$code $digits';
  }

  PersonDetails _buildDetails() => PersonDetails(
        firstName: _firstNameController.text.trim(),
        lastName: _lastNameController.text.trim(),
        gender: _gender,
        bloodGroup: _bloodGroup,
        altPhone: _joined(_altPhoneCode, _altPhoneController),
        addressLine1: _line1Controller.text.trim(),
        addressLine2: _line2Controller.text.trim(),
        landmark: _landmarkController.text.trim(),
        city: _cityController.text.trim(),
        district: _districtController.text.trim(),
        state: _stateController.text.trim(),
        country: _countryController.text.trim(),
        pinCode: _pinController.text.trim(),
        guardianName: _isTrainer ? null : _guardianController.text.trim(),
        emergencyContact:
            _isTrainer ? null : _joined(_emergencyCode, _emergencyController),
        qualification: _isTrainer ? _qualificationController.text.trim() : null,
        salary: _isTrainer ? num.tryParse(_salaryController.text.trim()) : null,
        joiningDate: _joiningDate,
      );

  /// Expands the access groups into the per-course maps the backend stores. Every course in a
  /// group inherits that group's features; batches are filtered to the ones that actually belong
  /// to each course, so a batch picked for one course in the group is not attributed to another.
  ({Map<String, Set<String>> features, Map<String, Set<String>> batches}) _expandGroups(
      List<Batch> allBatches) {
    final features = <String, Set<String>>{};
    final batches = <String, Set<String>>{};
    for (final group in _groups) {
      for (final courseId in group.courseIds) {
        features[courseId] = {...group.featureKeys};
        final own = group.batchIds
            .where((id) =>
                allBatches.any((b) => b.id == id && b.courseId == courseId))
            .toSet();
        if (own.isNotEmpty) batches[courseId] = own;
      }
    }
    return (features: features, batches: batches);
  }

  // ---------------------------------------------------------------------------
  // Saving
  // ---------------------------------------------------------------------------

  Future<void> _save(List<Batch> allBatches) async {
    setState(() => _busy = true);
    final api = ref.read(enrolmentApiProvider);
    final fullName =
        '${_firstNameController.text.trim()} ${_lastNameController.text.trim()}'.trim();
    final dob = PersonDetails.isoDate(_dob!);
    final phone = _joined(_phoneCode, _phoneController);

    try {
      if (_isTrainer) {
        final expanded = _expandGroups(allBatches);
        if (_isEditing) {
          await api.updateTrainer(
            widget.editingMembershipId!,
            fullName: fullName,
            phone: phone,
            email: _emailController.text.trim(),
            dob: dob,
            address: _line1Controller.text.trim(),
            city: _cityController.text.trim(),
            state: _stateController.text.trim(),
            yearsOfExperience: int.tryParse(_experienceController.text.trim()),
            courseFeatures: expanded.features,
            courseBatches: expanded.batches,
            details: _buildDetails(),
          );
          if (mounted) {
            showAppToast(context, '$fullName updated.');
            Navigator.of(context).pop(true);
          }
          return;
        }
        final result = await api.registerTrainer(
          username: _usernameController.text.trim(),
          fullName: fullName,
          phone: phone,
          email: _emailController.text.trim(),
          dob: dob,
          address: _line1Controller.text.trim(),
          city: _cityController.text.trim(),
          state: _stateController.text.trim(),
          yearsOfExperience: int.tryParse(_experienceController.text.trim()),
          courseFeatures: expanded.features,
          courseBatches: expanded.batches,
          details: _buildDetails(),
        );
        await _finishRegistration(
          userId: result.userId,
          membershipId: result.membershipId,
          username: result.username,
          temporaryPassword: result.temporaryPassword,
          pendingConfirmation: result.pendingConfirmation,
          fullName: fullName,
          confirm: (code) => api.confirmTrainerMembership(
              membershipId: result.membershipId, code: code),
        );
        return;
      }

      // -- student --
      final courses = _studentCourseIds
          .map((id) => {'courseId': id, 'fee': null})
          .toList(growable: false);
      if (_isEditing) {
        await api.updateStudent(
          widget.editingMembershipId!,
          fullName: fullName,
          phone: phone,
          dob: dob,
          email: _emailController.text.trim(),
          address: _line1Controller.text.trim(),
          city: _cityController.text.trim(),
          state: _stateController.text.trim(),
          courses: courses,
          details: _buildDetails(),
        );
        if (mounted) {
          showAppToast(context, '$fullName updated.');
          Navigator.of(context).pop(true);
        }
        return;
      }
      final result = await api.registerStudent(
        username: _usernameController.text.trim(),
        fullName: fullName,
        phone: phone,
        dob: dob,
        email: _emailController.text.trim(),
        address: _line1Controller.text.trim(),
        city: _cityController.text.trim(),
        state: _stateController.text.trim(),
        courses: courses,
        details: _buildDetails(),
      );
      await _finishRegistration(
        userId: result.userId,
        membershipId: result.membershipId,
        username: result.username,
        temporaryPassword: result.temporaryPassword,
        pendingConfirmation: result.pendingConfirmation,
        fullName: fullName,
        confirm: (code) =>
            api.confirmMembership(membershipId: result.membershipId, code: code),
        // Batch placement is a separate resource keyed by batch, so it can only happen once the
        // membership exists - and only when it is active, which a pending one is not.
        afterActive: () => _assignStudentBatches(api, result.membershipId),
      );
    } catch (e) {
      if (mounted) showAppToast(context, e.toString().replaceFirst('Exception: ', ''));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _assignStudentBatches(EnrolmentApi api, String membershipId) async {
    for (final batchId in _studentBatchIds) {
      await api.addMember(batchId, membershipId);
    }
  }

  /// The shared tail of both registrations: consent step if the email already has an account,
  /// then the photo, then the credentials hand-off.
  Future<void> _finishRegistration({
    required String userId,
    required String membershipId,
    required String username,
    required String? temporaryPassword,
    required bool pendingConfirmation,
    required String fullName,
    required Future<void> Function(String code) confirm,
    Future<void> Function()? afterActive,
  }) async {
    if (!mounted) return;

    if (pendingConfirmation) {
      final code = await showExistingAccountConfirm(
        context,
        fullName: fullName,
        roleNoun: _isTrainer ? 'trainer' : 'student',
        onSubmit: (code) async {
          try {
            await confirm(code);
            return null;
          } catch (e) {
            return e.toString().replaceFirst('Exception: ', '');
          }
        },
      );
      if (!mounted) return;
      if (code == null) {
        // They can read the code back later; the membership stays pending until then, so this is
        // a paused registration rather than a failed one.
        showAppToast(context, 'Waiting for $fullName to confirm. Nothing is granted yet.');
        Navigator.of(context).pop(true);
        return;
      }
      await afterActive?.call();
      if (!mounted) return;
      showAppToast(context, '$fullName confirmed and added.');
      Navigator.of(context).pop(true);
      return;
    }

    // The photo is a best-effort follow-up, not part of registration: a failure here must not
    // read as "the person was not created", because they were.
    if (_photoBytes != null) {
      try {
        await ref
            .read(enrolmentApiProvider)
            .uploadProfileImage(userId, _photoBytes!, _photoFilename!);
      } catch (e) {
        if (mounted) {
          showAppToast(context,
              'Registered, but the photo did not upload: ${e.toString().replaceFirst('Exception: ', '')}');
        }
      }
    }
    await afterActive?.call();
    if (!mounted) return;

    await showCredentialsHandoff(
      context,
      fullName: fullName,
      username: username,
      temporaryPassword: temporaryPassword ?? '(unavailable)',
      phone: _joined(_phoneCode, _phoneController),
    );
    if (mounted) Navigator.of(context).pop(true);
  }

  // ---------------------------------------------------------------------------
  // Build
  // ---------------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final accent = _isTrainer ? palette.gold : palette.primary;
    final onAccent = _isTrainer ? palette.onGold : palette.onPrimary;
    final coursesAsync = ref.watch(coursesForFeatureProvider(
        _isTrainer ? FeatureKeys.trainerRegistration : FeatureKeys.studentRegistration));
    final batchesAsync = ref.watch(allBatchesProvider);
    final onMappingStep = _isTrainer && _step == 2;

    return Scaffold(
      backgroundColor: palette.bg,
      appBar: AppBar(
        backgroundColor: palette.bg,
        leading: AppIconButton(
          icon: Icons.arrow_back,
          onTap: () {
            if (onMappingStep) {
              setState(() => _step = 1);
            } else {
              Navigator.of(context).maybePop();
            }
          },
        ),
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              onMappingStep
                  ? 'Course & feature access'
                  : _isEditing
                      ? 'Edit ${_isTrainer ? 'trainer' : 'student'}'
                      : 'Add ${_isTrainer ? 'trainer' : 'student'}',
              style: TextStyle(
                  fontSize: AppType.title, fontWeight: AppType.bold, color: palette.text),
            ),
            Text(
              onMappingStep
                  ? (_displayName().isEmpty ? 'Trainer' : _displayName())
                  : _isEditing
                      ? (widget.editingName ?? '')
                      : 'Create a ${_isTrainer ? 'trainer' : 'student'} profile',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: AppType.smd, color: palette.textMuted),
            ),
          ],
        ),
        actions: [
          if (_isTrainer)
            Padding(
              padding: const EdgeInsets.only(right: AppSpacing.page),
              child: Center(child: _stepPill(palette, accent)),
            ),
        ],
      ),
      body: coursesAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => _errorBody(palette, e),
        data: (courses) {
          final batches = batchesAsync.valueOrNull ?? const <Batch>[];
          return ListView(
            padding: const EdgeInsets.fromLTRB(
                AppSpacing.page, AppSpacing.md, AppSpacing.page, AppSpacing.x5l),
            children: [
              if (_loadingExisting)
                Padding(
                  padding: const EdgeInsets.only(bottom: AppSpacing.xxl),
                  child: LinearProgressIndicator(
                    minHeight: 2,
                    backgroundColor: palette.surfaceHigh,
                    color: accent,
                  ),
                ),
              if (onMappingStep)
                ..._mappingStep(palette, accent, courses, batches)
              else
                ..._profileStep(palette, accent, courses, batches),
              const SizedBox(height: AppSpacing.md),
              if (_isTrainer && _step == 1)
                AppPrimaryButton(
                  label: 'Continue to courses & features',
                  icon: Icons.arrow_forward,
                  background: accent,
                  foreground: onAccent,
                  onPressed: _valid ? () => setState(() => _step = 2) : null,
                )
              else
                AppPrimaryButton(
                  label: _isEditing
                      ? 'Save changes'
                      : 'Create ${_isTrainer ? 'trainer' : 'student'}',
                  icon: Icons.check,
                  busy: _busy,
                  background: accent,
                  foreground: onAccent,
                  onPressed: _valid && !_busy ? () => _save(batches) : null,
                ),
              if (!_valid) ...[
                const SizedBox(height: AppSpacing.sm),
                Text(_missingRequirement(),
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: AppType.sm, color: palette.textFaint)),
              ],
            ],
          );
        },
      ),
    );
  }

  String _displayName() =>
      '${_firstNameController.text.trim()} ${_lastNameController.text.trim()}'.trim();

  Widget _stepPill(AppPalette palette, Color accent) => Container(
        padding:
            const EdgeInsets.symmetric(horizontal: AppSpacing.md, vertical: 5),
        decoration: BoxDecoration(
          color: accent.withValues(alpha: 0.14),
          borderRadius: AppRadii.all(AppRadii.pill),
          border: Border.all(color: accent.withValues(alpha: 0.33)),
        ),
        child: Text('STEP $_step OF 2',
            style: TextStyle(
                fontSize: AppType.tiny,
                fontWeight: AppType.heavy,
                letterSpacing: 0.4,
                color: accent)),
      );

  Widget _errorBody(AppPalette palette, Object error) => Center(
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.x4l),
          child: Text(error.toString().replaceFirst('Exception: ', ''),
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: AppType.lg, color: palette.textMuted)),
        ),
      );

  void _toggleSection(String key) => setState(() {
        if (!_openSections.remove(key)) _openSections.add(key);
      });

  // ---------------------------------------------------------------------------
  // Step 1 - profile
  // ---------------------------------------------------------------------------

  List<Widget> _profileStep(
      AppPalette palette, Color accent, List<Course> courses, List<Batch> batches) {
    final age = ageFrom(_dob);
    return [
      _photoHeader(palette, accent),
      const SizedBox(height: AppSpacing.x4l),
      FormSection(
        title: 'Identity',
        subtitle: 'Email, name and login',
        icon: Icons.badge_outlined,
        accent: accent,
        expanded: _openSections.contains('identity'),
        onToggle: () => _toggleSection('identity'),
        children: [
          LabeledField(
            label: 'Email ID',
            required: true,
            hint: 'If this email already has a NEST account, registering will ask that '
                'person to confirm rather than creating a second one.',
            error: _emailController.text.trim().isEmpty || _emailValid
                ? null
                : "That doesn't look like an email address.",
            child: AppTextField(
              controller: _emailController,
              hint: 'name@example.com',
              icon: Icons.alternate_email,
              keyboardType: TextInputType.emailAddress,
              hasError: _emailController.text.trim().isNotEmpty && !_emailValid,
              onChanged: (_) => setState(() {}),
            ),
          ),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: LabeledField(
                  label: 'First name',
                  required: true,
                  child: AppTextField(
                    controller: _firstNameController,
                    hint: 'e.g. Aarav',
                    textCapitalization: TextCapitalization.words,
                    onChanged: (_) => setState(_syncUsername),
                  ),
                ),
              ),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: LabeledField(
                  label: 'Last name',
                  required: true,
                  child: AppTextField(
                    controller: _lastNameController,
                    hint: 'e.g. Shah',
                    textCapitalization: TextCapitalization.words,
                    onChanged: (_) => setState(_syncUsername),
                  ),
                ),
              ),
            ],
          ),
          LabeledField(
            label: 'Username (login ID)',
            required: true,
            hint: _isEditing
                ? "The login ID can't change once the account exists."
                : 'Suggested from the name, and editable until you save.',
            child: AppTextField(
              controller: _usernameController,
              hint: 'auto-filled from the name',
              icon: Icons.alternate_email,
              inputFormatters: [
                FilteringTextInputFormatter.allow(RegExp(r'[a-zA-Z0-9.]')),
              ],
              onChanged: (v) => setState(() {
                _usernameTouched = true;
                final lower = v.toLowerCase();
                if (lower != v) {
                  _usernameController.value = TextEditingValue(
                    text: lower,
                    selection: TextSelection.collapsed(offset: lower.length),
                  );
                }
              }),
            ),
          ),
        ],
      ),
      FormSection(
        title: 'Personal',
        subtitle: 'Date of birth, gender, contact numbers',
        icon: Icons.person_outline,
        accent: accent,
        expanded: _openSections.contains('personal'),
        onToggle: () => _toggleSection('personal'),
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: LabeledField(
                  label: 'Date of birth',
                  required: true,
                  child: PickerTile(
                    icon: Icons.cake_outlined,
                    value: formatOptionalDate(_dob),
                    placeholder: 'Select date',
                    accent: accent,
                    onTap: _pickDob,
                  ),
                ),
              ),
              const SizedBox(width: AppSpacing.md),
              SizedBox(
                width: 96,
                child: LabeledField(
                  label: 'Age',
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: AppSpacing.lg, vertical: AppSpacing.lg),
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: palette.surfaceRaised,
                      borderRadius: AppRadii.all(AppRadii.xl),
                      border: Border.all(color: palette.border),
                    ),
                    child: Text(
                      age == null ? '--' : '$age yrs',
                      style: TextStyle(
                        fontSize: AppType.xxl,
                        fontWeight: AppType.bold,
                        color: age == null ? palette.textFaint : palette.text,
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
          LabeledField(
            label: 'Gender',
            required: true,
            child: ChoicePills(
              options: genderOptions,
              value: _gender,
              accent: accent,
              onSelected: (v) => setState(() => _gender = v),
            ),
          ),
          LabeledField(
            label: 'Blood group',
            hint: 'Read out in an emergency, so it is a fixed list rather than free text.',
            child: ChoicePills(
              options: bloodGroupOptions,
              value: _bloodGroup,
              accent: palette.notPaid,
              onSelected: (v) => setState(() => _bloodGroup = v),
            ),
          ),
          LabeledField(
            label: 'Phone number',
            required: true,
            child: PhoneField(
              code: _phoneCode,
              controller: _phoneController,
              hint: '10-digit number',
              hasError: _phoneController.text.isNotEmpty &&
                  _phoneController.text.trim().length < 10,
              onCodeChanged: (c) => setState(() => _phoneCode = c),
              onChanged: (_) => setState(() {}),
            ),
          ),
          LabeledField(
            label: 'Alternate number',
            hint: 'Optional.',
            child: PhoneField(
              code: _altPhoneCode,
              controller: _altPhoneController,
              hint: 'Optional',
              onCodeChanged: (c) => setState(() => _altPhoneCode = c),
            ),
          ),
        ],
      ),
      FormSection(
        title: 'Address',
        subtitle: _addressValid ? _addressSummary() : 'Required',
        icon: Icons.home_outlined,
        accent: accent,
        badge: _addressValid ? null : 'INCOMPLETE',
        expanded: _openSections.contains('address'),
        onToggle: () => _toggleSection('address'),
        children: [
          LabeledField(
            label: 'Address line 1',
            required: true,
            bottomGap: AppSpacing.lg,
            child: AppTextField(
              controller: _line1Controller,
              hint: 'House no., street',
              textCapitalization: TextCapitalization.words,
              onChanged: (_) => setState(() {}),
            ),
          ),
          LabeledField(
            label: 'Address line 2',
            bottomGap: AppSpacing.lg,
            child: AppTextField(
              controller: _line2Controller,
              hint: 'Area, apartment (optional)',
              textCapitalization: TextCapitalization.words,
            ),
          ),
          LabeledField(
            label: 'Landmark',
            bottomGap: AppSpacing.lg,
            child: AppTextField(
              controller: _landmarkController,
              hint: 'Optional',
              textCapitalization: TextCapitalization.words,
            ),
          ),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: LabeledField(
                  label: 'City',
                  required: true,
                  bottomGap: AppSpacing.lg,
                  child: AppTextField(
                    controller: _cityController,
                    hint: 'City',
                    textCapitalization: TextCapitalization.words,
                    onChanged: (_) => setState(() {}),
                  ),
                ),
              ),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: LabeledField(
                  label: 'District',
                  bottomGap: AppSpacing.lg,
                  child: AppTextField(
                    controller: _districtController,
                    hint: 'District',
                    textCapitalization: TextCapitalization.words,
                  ),
                ),
              ),
            ],
          ),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: LabeledField(
                  label: 'State',
                  required: true,
                  bottomGap: AppSpacing.lg,
                  child: AppTextField(
                    controller: _stateController,
                    hint: 'State',
                    textCapitalization: TextCapitalization.words,
                    onChanged: (_) => setState(() {}),
                  ),
                ),
              ),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: LabeledField(
                  label: 'Country',
                  bottomGap: AppSpacing.lg,
                  child: AppTextField(
                    controller: _countryController,
                    hint: 'Country',
                    textCapitalization: TextCapitalization.words,
                  ),
                ),
              ),
            ],
          ),
          LabeledField(
            label: 'PIN code',
            required: true,
            bottomGap: AppSpacing.lg,
            child: SizedBox(
              width: 170,
              child: AppTextField(
                controller: _pinController,
                hint: 'PIN code',
                keyboardType: TextInputType.number,
                inputFormatters: [
                  FilteringTextInputFormatter.digitsOnly,
                  LengthLimitingTextInputFormatter(10),
                ],
                onChanged: (_) => setState(() {}),
              ),
            ),
          ),
        ],
      ),
      if (_isTrainer)
        FormSection(
          title: 'Professional',
          subtitle: 'Qualification, experience, pay',
          icon: Icons.workspace_premium_outlined,
          accent: accent,
          expanded: _openSections.contains('professional'),
          onToggle: () => _toggleSection('professional'),
          children: [
            LabeledField(
              label: 'Qualification / experience summary',
              required: true,
              child: AppTextField(
                controller: _qualificationController,
                hint: 'e.g. Bharatanatyam Visharad, 12 yrs stage experience',
                textCapitalization: TextCapitalization.sentences,
                onChanged: (_) => setState(() {}),
              ),
            ),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: LabeledField(
                    label: 'Experience (years)',
                    child: AppTextField(
                      controller: _experienceController,
                      hint: 'e.g. 8',
                      keyboardType: TextInputType.number,
                      inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                    ),
                  ),
                ),
                const SizedBox(width: AppSpacing.md),
                Expanded(
                  child: LabeledField(
                    label: 'Monthly salary',
                    hint: 'Optional. Visible only to this academy.',
                    child: AppTextField(
                      controller: _salaryController,
                      hint: 'e.g. 20000',
                      icon: Icons.currency_rupee,
                      keyboardType: TextInputType.number,
                      inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                    ),
                  ),
                ),
              ],
            ),
          ],
        )
      else
        FormSection(
          title: 'Guardian & emergency',
          subtitle: 'Who to call, and who to call first',
          icon: Icons.emergency_outlined,
          accent: accent,
          badge: _guardianController.text.trim().length > 1 ? null : 'INCOMPLETE',
          expanded: _openSections.contains('guardian'),
          onToggle: () => _toggleSection('guardian'),
          children: [
            LabeledField(
              label: "Parent's / guardian's name",
              required: true,
              child: AppTextField(
                controller: _guardianController,
                hint: 'e.g. Nikhil Shah',
                textCapitalization: TextCapitalization.words,
                onChanged: (_) => setState(() {}),
              ),
            ),
            LabeledField(
              label: 'Emergency contact number',
              hint: 'Optional, but this is the number called when the usual one does not answer.',
              child: PhoneField(
                code: _emergencyCode,
                controller: _emergencyController,
                hint: '10-digit number',
                onCodeChanged: (c) => setState(() => _emergencyCode = c),
              ),
            ),
          ],
        ),
      if (!_isTrainer) _studentCoursesSection(palette, accent, courses, batches),
      FormSection(
        title: 'Membership',
        subtitle: 'Joining date and status',
        icon: Icons.event_available_outlined,
        accent: accent,
        expanded: _openSections.contains('membership'),
        onToggle: () => _toggleSection('membership'),
        children: [
          LabeledField(
            label: 'Joining date',
            hint: 'When they join THIS academy - a person can join a second one years later.',
            child: PickerTile(
              icon: Icons.calendar_today_outlined,
              value: formatFeeDate(_joiningDate),
              placeholder: 'Select date',
              accent: accent,
              onTap: _pickJoiningDate,
            ),
          ),
          LabeledField(
            label: 'Status',
            hint: 'Inactive ${_isTrainer ? 'trainers' : 'students'} stay in history but drop '
                'off active lists.',
            child: AppSegmentedControl<bool>(
              options: const [true, false],
              labelOf: (a) => a ? 'Active' : 'Inactive',
              isSelected: (a) => a == _active,
              activeColorOf: (_, a) => a ? palette.paidManual : palette.surfaceHigh,
              activeTextColorOf: (_, a) => a ? palette.onPrimary : palette.textMuted,
              onTap: (a) => setState(() => _active = a),
            ),
          ),
        ],
      ),
    ];
  }

  String _addressSummary() {
    final parts = [
      _cityController.text.trim(),
      _stateController.text.trim(),
      _pinController.text.trim(),
    ].where((p) => p.isNotEmpty);
    return parts.join(', ');
  }

  Widget _photoHeader(AppPalette palette, Color accent) {
    final name = _displayName();
    return Row(
      children: [
        Pressable(
          onTap: _pickPhoto,
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              Container(
                height: 68,
                width: 68,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(color: accent.withValues(alpha: 0.4), width: 2),
                  image: _photoBytes == null
                      ? null
                      : DecorationImage(
                          image: MemoryImage(_photoBytes!), fit: BoxFit.cover),
                ),
                child: _photoBytes != null
                    ? null
                    : name.isEmpty
                        ? Icon(Icons.add_a_photo_outlined,
                            size: 22, color: palette.textFaint)
                        : Padding(
                            padding: const EdgeInsets.all(2),
                            child: PersonAvatar(name: name, seed: name, size: 60),
                          ),
              ),
              Positioned(
                right: -2,
                bottom: -2,
                child: Container(
                  height: 24,
                  width: 24,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: accent,
                    shape: BoxShape.circle,
                    border: Border.all(color: palette.bg, width: 2),
                  ),
                  child: Icon(Icons.camera_alt,
                      size: 12,
                      color: _isTrainer ? palette.onGold : palette.onPrimary),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(width: AppSpacing.xl),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(name.isEmpty ? 'New ${_isTrainer ? 'trainer' : 'student'}' : name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                      fontSize: AppType.display,
                      fontWeight: AppType.bold,
                      color: name.isEmpty ? palette.textFaint : palette.text)),
              const SizedBox(height: 3),
              Pressable(
                onTap: _pickPhoto,
                child: Text(_photoBytes == null ? 'Add a photo' : 'Change photo',
                    style: TextStyle(
                        fontSize: AppType.md,
                        fontWeight: AppType.bold,
                        color: accent)),
              ),
            ],
          ),
        ),
        if (_photoBytes != null)
          Pressable(
            onTap: () => setState(() {
              _photoBytes = null;
              _photoFilename = null;
            }),
            child: Padding(
              padding: const EdgeInsets.all(AppSpacing.sm),
              child: Icon(Icons.close_rounded, size: 16, color: palette.textFaint),
            ),
          ),
      ],
    );
  }

  Widget _studentCoursesSection(
      AppPalette palette, Color accent, List<Course> courses, List<Batch> batches) {
    final relevant =
        batches.where((b) => _studentCourseIds.contains(b.courseId)).toList();
    final selectedCourses =
        courses.where((c) => _studentCourseIds.contains(c.id)).toList();
    final selectedBatches =
        relevant.where((b) => _studentBatchIds.contains(b.id)).toList();

    return FormSection(
      title: 'Courses & batches',
      subtitle: selectedCourses.isEmpty
          ? 'Not enrolled in anything yet'
          : selectedCourses.map((c) => c.name).join(', '),
      icon: Icons.school_outlined,
      accent: accent,
      badge: _studentCourseIds.isEmpty
          ? null
          : '${_studentCourseIds.length} COURSE${_studentCourseIds.length == 1 ? '' : 'S'}',
      expanded: _openSections.contains('courses'),
      onToggle: () => _toggleSection('courses'),
      children: [
        LabeledField(
          label: 'Enrolled courses',
          hint: 'A student can join several courses at this academy in one registration.',
          child: PickerTile(
            icon: Icons.menu_book_outlined,
            value: selectedCourses.map((c) => c.name).join(', '),
            placeholder: 'Select course(s)',
            accent: accent,
            trailing: _studentCourseIds.isEmpty ? 'Select' : 'Edit',
            onTap: () async {
              final picked = await showAppMultiSelectSheet<Course>(
                context: context,
                title: 'Courses to enrol in',
                options: courses,
                labelOf: (c) => c.name,
                initialSelection:
                    courses.where((c) => _studentCourseIds.contains(c.id)).toList(),
              );
              if (picked == null) return;
              setState(() {
                _studentCourseIds
                  ..clear()
                  ..addAll(picked.map((c) => c.id));
                // A batch belongs to exactly one course, so dropping a course must drop the
                // batches under it or the student ends up in a batch they cannot attend.
                _studentBatchIds.removeWhere((id) => !batches.any(
                    (b) => b.id == id && _studentCourseIds.contains(b.courseId)));
              });
            },
          ),
        ),
        LabeledField(
          label: 'Batches',
          hint: relevant.isEmpty
              ? 'No batches on the selected course(s) yet - they can be placed in one later.'
              : 'Optional. Placing them now saves a trip to the batch screen.',
          child: PickerTile(
            icon: Icons.schedule,
            value: selectedBatches.map((b) => b.name).join(', '),
            placeholder: _studentCourseIds.isEmpty
                ? 'Select a course first'
                : relevant.isEmpty
                    ? 'No batches on this course yet'
                    : 'Select batch (optional)',
            accent: accent,
            trailing: relevant.isEmpty ? null : 'Select',
            onTap: relevant.isEmpty
                ? null
                : () async {
                    final picked = await showAppMultiSelectSheet<Batch>(
                      context: context,
                      title: 'Batches',
                      options: relevant,
                      labelOf: (b) => b.name,
                      initialSelection: selectedBatches,
                    );
                    if (picked == null) return;
                    setState(() {
                      _studentBatchIds
                        ..clear()
                        ..addAll(picked.map((b) => b.id));
                    });
                  },
          ),
        ),
      ],
    );
  }

  // ---------------------------------------------------------------------------
  // Step 2 - trainer course & feature mapping
  // ---------------------------------------------------------------------------

  List<Widget> _mappingStep(
      AppPalette palette, Color accent, List<Course> courses, List<Batch> batches) {
    // What this admin may hand out. A trainer creating another trainer can only pass on what they
    // themselves hold (PRD 3.5) - offering more here would just produce a 403 at save time.
    final user = ref.watch(sessionControllerProvider).user;
    final isAdmin = user != null && (user.isSuperAdmin || user.isActiveAcademyAdmin);
    final grantable = isAdmin
        ? trainerGrantableFeatures
        : trainerGrantableFeatures
            .where((f) => user?.hasFeature(f) ?? false)
            .toList();

    return [
      Padding(
        padding: const EdgeInsets.only(bottom: AppSpacing.xl),
        child: Text(
          'Group the courses that share the same access into one tile. Add another tile only '
          'when a course needs a different set of permissions or batches.',
          style: TextStyle(fontSize: AppType.md, color: palette.textMuted, height: 1.5),
        ),
      ),
      for (final group in _groups)
        _AccessGroupTile(
          group: group,
          allCourses: courses,
          allBatches: batches,
          accent: accent,
          grantableFeatures: grantable,
          expanded: _expandedGroupId == group.id,
          onToggleExpanded: () => setState(() =>
              _expandedGroupId = _expandedGroupId == group.id ? null : group.id),
          onChanged: () => setState(() {}),
          onRemove: () => setState(() {
            _groups.remove(group);
            if (_expandedGroupId == group.id) _expandedGroupId = null;
          }),
          claimCourse: _claimCourse,
        ),
      const SizedBox(height: AppSpacing.sm),
      Pressable(
        onTap: () => setState(() {
          final group = _AccessGroup('g${DateTime.now().microsecondsSinceEpoch}');
          _groups.add(group);
          _expandedGroupId = group.id;
        }),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: AppSpacing.xl),
          decoration: BoxDecoration(
            borderRadius: AppRadii.all(AppRadii.xxl),
            border: Border.all(color: palette.border, style: BorderStyle.solid),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.add, size: 16, color: accent),
              const SizedBox(width: AppSpacing.sm),
              Text('Add access group',
                  style: TextStyle(
                      fontSize: AppType.xl,
                      fontWeight: AppType.bold,
                      color: accent)),
            ],
          ),
        ),
      ),
      if (_groups.isEmpty) ...[
        const SizedBox(height: AppSpacing.lg),
        Text(
          'No courses mapped yet. Both the mapping and the permissions are optional, but a '
          'trainer only sees a feature on their home screen once it is tied to a course here.',
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: AppType.sm, color: palette.textFaint, height: 1.5),
        ),
      ],
      const SizedBox(height: AppSpacing.xl),
    ];
  }

  /// Moves a course into one group, taking it out of whichever group had it.
  ///
  /// A course can only sit in one group: two groups holding it would mean two different answers
  /// to "what can this trainer do here", and the backend stores one set per course.
  void _claimCourse(_AccessGroup target, String courseId) {
    setState(() {
      if (target.courseIds.contains(courseId)) {
        target.courseIds.remove(courseId);
      } else {
        for (final other in _groups) {
          if (other != target) other.courseIds.remove(courseId);
        }
        target.courseIds.add(courseId);
      }
      // Batches follow their course out.
      for (final group in _groups) {
        group.batchIds.removeWhere((batchId) {
          final batch = ref
              .read(allBatchesProvider)
              .valueOrNull
              ?.where((b) => b.id == batchId)
              .firstOrNull;
          return batch != null && !group.courseIds.contains(batch.courseId);
        });
      }
    });
  }
}

/// One access group's card: which courses, which batches, which permissions.
class _AccessGroupTile extends StatelessWidget {
  const _AccessGroupTile({
    required this.group,
    required this.allCourses,
    required this.allBatches,
    required this.accent,
    required this.grantableFeatures,
    required this.expanded,
    required this.onToggleExpanded,
    required this.onChanged,
    required this.onRemove,
    required this.claimCourse,
  });

  final _AccessGroup group;
  final List<Course> allCourses;
  final List<Batch> allBatches;
  final Color accent;
  final List<String> grantableFeatures;
  final bool expanded;
  final VoidCallback onToggleExpanded;
  final VoidCallback onChanged;
  final VoidCallback onRemove;
  final void Function(_AccessGroup group, String courseId) claimCourse;

  List<Course> get _courses =>
      allCourses.where((c) => group.courseIds.contains(c.id)).toList();

  List<Batch> get _relevantBatches =>
      allBatches.where((b) => group.courseIds.contains(b.courseId)).toList();

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final courses = _courses;
    final relevant = _relevantBatches;
    final selectedBatches =
        relevant.where((b) => group.batchIds.contains(b.id)).toList();

    return Container(
      margin: const EdgeInsets.only(bottom: AppSpacing.md),
      decoration: BoxDecoration(
        color: palette.surfaceRaised,
        borderRadius: AppRadii.all(AppRadii.xxl),
        border: Border.all(
          // An empty group grants nothing and is nearly always half-finished rather than
          // deliberate, so it is flagged rather than left looking complete.
          color: group.featureKeys.isEmpty || group.courseIds.isEmpty
              ? palette.gold.withValues(alpha: 0.4)
              : palette.borderSoft,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Pressable(
            onTap: onToggleExpanded,
            child: Padding(
              padding: const EdgeInsets.all(AppSpacing.lg),
              child: Row(
                children: [
                  SizedBox(
                    width: courses.isEmpty
                        ? 9
                        : (courses.length.clamp(1, 3) * 7) + 2,
                    height: 9,
                    child: Stack(
                      children: [
                        for (var i = 0; i < courses.length.clamp(0, 3); i++)
                          Positioned(
                            left: i * 7.0,
                            child: Container(
                              height: 9,
                              width: 9,
                              decoration: BoxDecoration(
                                color: courses[i].category.meta(palette).color,
                                shape: BoxShape.circle,
                                border: Border.all(
                                    color: palette.surfaceRaised, width: 1.5),
                              ),
                            ),
                          ),
                        if (courses.isEmpty)
                          Container(
                            height: 9,
                            width: 9,
                            decoration: BoxDecoration(
                                color: palette.textFaint, shape: BoxShape.circle),
                          ),
                      ],
                    ),
                  ),
                  const SizedBox(width: AppSpacing.lg),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          courses.isEmpty
                              ? 'No courses selected'
                              : courses.map((c) => c.name).join(', '),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: AppType.x3l,
                            fontWeight: AppType.bold,
                            color: courses.isEmpty ? palette.textFaint : palette.text,
                          ),
                        ),
                        if (!expanded) ...[
                          const SizedBox(height: 2),
                          Text(
                            _summary(selectedBatches),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: AppType.sm,
                              color: group.featureKeys.isEmpty
                                  ? palette.gold
                                  : palette.textFaint,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                  Pressable(
                    onTap: onRemove,
                    child: Padding(
                      padding: const EdgeInsets.all(AppSpacing.xs),
                      child: Icon(Icons.close_rounded,
                          size: 15, color: palette.textFaint),
                    ),
                  ),
                  const SizedBox(width: AppSpacing.xs),
                  AnimatedRotation(
                    turns: expanded ? 0.5 : 0,
                    duration: AppMotion.chevron,
                    child: Icon(Icons.keyboard_arrow_down_rounded,
                        size: 20, color: accent),
                  ),
                ],
              ),
            ),
          ),
          AnimatedSize(
            duration: AppMotion.collapse,
            curve: AppMotion.enter,
            alignment: Alignment.topCenter,
            child: expanded
                ? Padding(
                    padding: const EdgeInsets.fromLTRB(
                        AppSpacing.lg, 0, AppSpacing.lg, AppSpacing.lg),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        if (courses.isNotEmpty) ...[
                          Wrap(
                            spacing: AppSpacing.xs,
                            runSpacing: AppSpacing.xs,
                            children: courses
                                .map((c) => _CourseChip(
                                      course: c,
                                      accent: accent,
                                      onRemove: () {
                                        claimCourse(group, c.id);
                                        onChanged();
                                      },
                                    ))
                                .toList(),
                          ),
                          const SizedBox(height: AppSpacing.md),
                        ],
                        PickerTile(
                          icon: Icons.menu_book_outlined,
                          value: courses.isEmpty ? null : 'Edit courses',
                          placeholder: 'Select course(s) for this group',
                          accent: accent,
                          onTap: () async {
                            final picked = await showAppMultiSelectSheet<Course>(
                              context: context,
                              title: 'Courses in this group',
                              options: allCourses,
                              labelOf: (c) => c.name,
                              initialSelection: courses,
                            );
                            if (picked == null) return;
                            final want = picked.map((c) => c.id).toSet();
                            for (final id in {...group.courseIds, ...want}) {
                              final has = group.courseIds.contains(id);
                              if (want.contains(id) != has) claimCourse(group, id);
                            }
                            onChanged();
                          },
                        ),
                        const SizedBox(height: AppSpacing.md),
                        PickerTile(
                          icon: Icons.schedule,
                          value: selectedBatches.map((b) => b.name).join(', '),
                          placeholder: relevant.isEmpty
                              ? 'No batches on these courses yet'
                              : 'All batches (tap to narrow)',
                          accent: accent,
                          onTap: relevant.isEmpty
                              ? null
                              : () async {
                                  final picked =
                                      await showAppMultiSelectSheet<Batch>(
                                    context: context,
                                    title: 'Batches in scope',
                                    options: relevant,
                                    labelOf: (b) => b.name,
                                    initialSelection: selectedBatches,
                                  );
                                  if (picked == null) return;
                                  group.batchIds
                                    ..clear()
                                    // Picking every batch says the same thing as picking none -
                                    // store it as none so a batch added tomorrow is in scope too.
                                    ..addAll(picked.length == relevant.length
                                        ? const <String>[]
                                        : picked.map((b) => b.id));
                                  onChanged();
                                },
                        ),
                        if (group.batchIds.isEmpty && relevant.isNotEmpty) ...[
                          const SizedBox(height: AppSpacing.xs),
                          Text(
                            'All ${relevant.length} batch${relevant.length == 1 ? '' : 'es'}, '
                            'including any added later.',
                            style: TextStyle(
                                fontSize: AppType.sm, color: palette.textFaint),
                          ),
                        ],
                        const SizedBox(height: AppSpacing.x4l),
                        Row(
                          children: [
                            Expanded(
                              child: Text(
                                courses.length > 1
                                    ? 'ACCESS ON THESE COURSES'
                                    : 'ACCESS ON THIS COURSE',
                                style: AppType.sectionLabel(palette.textMuted),
                              ),
                            ),
                            Pressable(
                              onTap: () {
                                final all = group.featureKeys.length ==
                                    grantableFeatures.length;
                                group.featureKeys
                                  ..clear()
                                  ..addAll(all ? const <String>[] : grantableFeatures);
                                onChanged();
                              },
                              child: Text(
                                group.featureKeys.length == grantableFeatures.length
                                    ? 'Clear all'
                                    : 'Select all',
                                style: TextStyle(
                                    fontSize: AppType.sm,
                                    fontWeight: AppType.bold,
                                    color: accent),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: AppSpacing.md),
                        Container(
                          decoration: BoxDecoration(
                            borderRadius: AppRadii.all(AppRadii.lg),
                            border: Border.all(color: palette.borderSoft),
                          ),
                          clipBehavior: Clip.antiAlias,
                          child: Column(
                            children: [
                              for (var i = 0; i < grantableFeatures.length; i++)
                                _FeatureRow(
                                  featureKey: grantableFeatures[i],
                                  selected: group.featureKeys
                                      .contains(grantableFeatures[i]),
                                  accent: accent,
                                  showDivider: i < grantableFeatures.length - 1,
                                  onTap: () {
                                    if (!group.featureKeys
                                        .remove(grantableFeatures[i])) {
                                      group.featureKeys.add(grantableFeatures[i]);
                                    }
                                    onChanged();
                                  },
                                ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  )
                : const SizedBox(width: double.infinity),
          ),
        ],
      ),
    );
  }

  String _summary(List<Batch> selectedBatches) {
    if (group.courseIds.isEmpty) return 'Pick a course to start';
    if (group.featureKeys.isEmpty) return 'No permissions yet';
    final n = group.featureKeys.length;
    final scope = selectedBatches.isEmpty
        ? 'all batches'
        : selectedBatches.map((b) => b.name).join(', ');
    return '$n permission${n == 1 ? '' : 's'} - $scope';
  }
}

class _CourseChip extends StatelessWidget {
  const _CourseChip(
      {required this.course, required this.accent, required this.onRemove});

  final Course course;
  final Color accent;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return Container(
      padding: const EdgeInsets.fromLTRB(AppSpacing.md, 4, AppSpacing.xs, 4),
      decoration: BoxDecoration(
        color: accent.withValues(alpha: 0.1),
        borderRadius: AppRadii.all(AppRadii.pill),
        border: Border.all(color: accent.withValues(alpha: 0.35)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            height: 7,
            width: 7,
            decoration: BoxDecoration(
                color: course.category.meta(palette).color, shape: BoxShape.circle),
          ),
          const SizedBox(width: AppSpacing.xs),
          Text(course.name,
              style: TextStyle(
                  fontSize: AppType.smd,
                  fontWeight: AppType.medium,
                  color: palette.text)),
          Pressable(
            onTap: onRemove,
            child: Padding(
              padding: const EdgeInsets.all(3),
              child: Icon(Icons.close_rounded, size: 11, color: palette.textFaint),
            ),
          ),
        ],
      ),
    );
  }
}

class _FeatureRow extends StatelessWidget {
  const _FeatureRow({
    required this.featureKey,
    required this.selected,
    required this.accent,
    required this.showDivider,
    required this.onTap,
  });

  final String featureKey;
  final bool selected;
  final Color accent;
  final bool showDivider;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return Pressable(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.lg, vertical: AppSpacing.md),
        decoration: BoxDecoration(
          color: selected ? accent.withValues(alpha: 0.1) : Colors.transparent,
          border: showDivider
              ? Border(bottom: BorderSide(color: palette.borderSoft))
              : null,
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.only(top: 1),
              child: Icon(featureIcon(featureKey),
                  size: 15, color: selected ? accent : palette.textFaint),
            ),
            const SizedBox(width: AppSpacing.md),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(featureLabel(featureKey),
                      style: TextStyle(
                        fontSize: AppType.lg,
                        fontWeight: AppType.medium,
                        color: selected ? palette.text : palette.textMuted,
                      )),
                  const SizedBox(height: 2),
                  Text(featureDescription(featureKey),
                      style: TextStyle(
                          fontSize: AppType.xs,
                          color: palette.textFaint,
                          height: 1.4)),
                ],
              ),
            ),
            const SizedBox(width: AppSpacing.md),
            Padding(
              padding: const EdgeInsets.only(top: 1),
              child: Container(
                height: 18,
                width: 18,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: selected ? accent : Colors.transparent,
                  borderRadius: AppRadii.all(AppRadii.xs),
                  border: Border.all(
                      color: selected ? accent : palette.border, width: 1.5),
                ),
                child: selected
                    ? Icon(Icons.check,
                        size: 12,
                        color: accent == palette.gold
                            ? palette.onGold
                            : palette.onPrimary)
                    : null,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
