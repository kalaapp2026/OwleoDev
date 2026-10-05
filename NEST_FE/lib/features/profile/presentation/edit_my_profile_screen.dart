import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:nest_fe/app/theme/app_tokens.dart';
import 'package:nest_fe/app/theme/app_typography.dart';
import 'package:nest_fe/core/auth/session_controller.dart';
import 'package:nest_fe/core/design/app_date_picker.dart';
import 'package:nest_fe/core/design/buttons.dart';
import 'package:nest_fe/core/design/segmented_control.dart';
import 'package:nest_fe/core/error/api_exception.dart';
import 'package:nest_fe/core/widgets/app_notice.dart';
import 'package:nest_fe/features/enrolment/data/person_details.dart' show bloodGroupOptions, genderOptions;
import 'package:nest_fe/features/profile/data/self_profile.dart';
import 'package:nest_fe/features/profile/data/self_profile_api.dart';
import 'package:nest_fe/features/profile/presentation/profile_widgets.dart';

class EditMyProfileScreen extends ConsumerStatefulWidget {
  const EditMyProfileScreen({super.key, required this.profile});
  final SelfProfile profile;

  @override
  ConsumerState<EditMyProfileScreen> createState() => _EditMyProfileScreenState();
}

class _EditMyProfileScreenState extends ConsumerState<EditMyProfileScreen> {
  late final SelfProfile _p = widget.profile;
  late final _name = TextEditingController(text: _p.fullName);
  late final _altPhone = TextEditingController(text: _p.altPhone);
  late final _guardian = TextEditingController(text: _p.guardianName);
  late final _line1 = TextEditingController(text: _p.addressLine1);
  late final _line2 = TextEditingController(text: _p.addressLine2);
  late final _landmark = TextEditingController(text: _p.landmark);
  late final _city = TextEditingController(text: _p.city);
  late final _pin = TextEditingController(text: _p.pinCode);
  late final _district = TextEditingController(text: _p.district);
  late final _state = TextEditingController(text: _p.state);
  late DateTime? _dob = _p.dob;
  late String? _gender = _p.gender;
  late String? _blood = _p.bloodGroup;
  bool _saving = false;

  @override
  void dispose() {
    for (final c in [_name, _altPhone, _guardian, _line1, _line2, _landmark, _city, _pin, _district, _state]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _pickDob() async {
    final picked = await showAppDatePicker(
      context: context,
      title: 'Date of birth',
      value: _dob ?? DateTime(DateTime.now().year - 12),
      maxDate: DateTime.now(),
    );
    if (picked != null) setState(() => _dob = picked);
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    String? t(TextEditingController c) => c.text.trim().isEmpty ? null : c.text.trim();
    try {
      await ref.read(selfProfileApiProvider).update({
        'fullName': _name.text.trim(),
        'altPhone': t(_altPhone),
        'dob': _dob == null ? null : wireDate(_dob!),
        'gender': _gender,
        'bloodGroup': _blood,
        'guardianName': t(_guardian),
        'addressLine1': t(_line1),
        'addressLine2': t(_line2),
        'landmark': t(_landmark),
        'city': t(_city),
        'district': t(_district),
        'state': t(_state),
        'pinCode': t(_pin),
      });
      ref.invalidate(selfProfileProvider);
      // The session's copy carries the name shown in headers.
      await ref.read(sessionControllerProvider.notifier).refreshProfile();
      if (mounted) {
        AppNotice.success(context, 'Profile updated.');
        Navigator.of(context).pop();
      }
    } on ApiException catch (e) {
      if (mounted) AppNotice.error(context, e.message);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    const gap = SizedBox(height: AppSpacing.xl);
    return Scaffold(
      backgroundColor: palette.bg,
      appBar: AppBar(title: const Text('Edit Profile')),
      body: ListView(
        padding: const EdgeInsets.all(AppSpacing.page),
        children: [
          LabeledTextField(label: 'Full name', controller: _name, hint: 'Full name', onChanged: (_) => setState(() {})),
          gap,
          InfoLine(label: 'Phone', value: _p.phone, icon: Icons.phone_outlined),
          Text('Phone and email are changed by your academy.',
              style: TextStyle(fontSize: AppType.sm, color: palette.textFaint)),
          gap,
          LabeledTextField(
              label: 'Alternate phone (optional)',
              controller: _altPhone,
              hint: 'Alternate contact',
              keyboardType: TextInputType.phone),
          gap,
          PickerField(
            label: 'Date of birth',
            text: _dob == null ? 'Select date' : longDate(_dob!),
            placeholder: _dob == null,
            icon: Icons.cake_outlined,
            onTap: _pickDob,
          ),
          gap,
          const FormLabel('Gender'),
          AppSegmentedControl<String>(
            options: genderOptions,
            labelOf: (v) => v,
            isSelected: (v) => v == _gender,
            onTap: (v) => setState(() => _gender = v),
          ),
          gap,
          const FormLabel('Blood group'),
          ChipChoices<String>(
            options: bloodGroupOptions,
            selected: _blood,
            labelOf: (v) => v,
            onSelected: (v) => setState(() => _blood = v),
          ),
          gap,
          LabeledTextField(label: 'Guardian name', controller: _guardian, hint: 'Parent / guardian name'),
          const SizedBox(height: AppSpacing.x5l),
          Text('ADDRESS',
              style: TextStyle(
                  fontSize: AppType.tiny, fontWeight: AppType.bold, color: palette.textFaint, letterSpacing: 0.4)),
          gap,
          LabeledTextField(label: 'Address line 1', controller: _line1, hint: 'House / flat, street'),
          gap,
          LabeledTextField(label: 'Address line 2 (optional)', controller: _line2, hint: 'Area, apartment'),
          gap,
          LabeledTextField(label: 'Landmark (optional)', controller: _landmark),
          gap,
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(child: LabeledTextField(label: 'City', controller: _city)),
              const SizedBox(width: AppSpacing.lg),
              Expanded(child: LabeledTextField(label: 'Pin code', controller: _pin, keyboardType: TextInputType.number)),
            ],
          ),
          gap,
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(child: LabeledTextField(label: 'District', controller: _district)),
              const SizedBox(width: AppSpacing.lg),
              Expanded(child: LabeledTextField(label: 'State', controller: _state)),
            ],
          ),
          const SizedBox(height: AppSpacing.x5l),
          AppPrimaryButton(
            label: 'Save changes',
            icon: Icons.check,
            busy: _saving,
            onPressed: _name.text.trim().isEmpty ? null : _save,
          ),
          const SizedBox(height: AppSpacing.x5l),
        ],
      ),
    );
  }
}
