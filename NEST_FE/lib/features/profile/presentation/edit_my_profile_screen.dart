import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:nest_fe/app/theme/app_tokens.dart';
import 'package:nest_fe/app/theme/app_typography.dart';
import 'package:nest_fe/core/auth/session_controller.dart';
import 'package:nest_fe/core/design/app_date_picker.dart';
import 'package:nest_fe/core/design/app_text_field.dart';
import 'package:nest_fe/core/design/buttons.dart';
import 'package:nest_fe/core/design/segmented_control.dart';
import 'package:nest_fe/core/error/api_exception.dart';
import 'package:nest_fe/core/validation/countries.dart';
import 'package:nest_fe/core/validation/phone_rules.dart';
import 'package:nest_fe/core/validation/validators.dart';
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
  // The alternate number is held as a calling code beside its digits, like every phone field.
  late final _altParts = PhoneRules.parseStored(_p.altPhone);
  late final _altPhone = TextEditingController(text: _altParts.digits);
  late String _altDial = _altParts.dial;
  late Country? _altCountry = (_p.altPhone ?? '').trim().isEmpty ? null : _altParts.country;
  bool _showErrors = false;
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

  /// The first thing wrong with the form; null when it can be saved. The PIN rule follows the
  /// country of the number on the account: six digits for India, looser elsewhere.
  String? _problem() =>
      Validators.personName(label: 'name')(_name.text) ??
      PhoneRules.validate(dial: _altDial, digits: _altPhone.text, iso: _altCountry?.iso, kind: PhoneKind.any, required: false) ??
      Validators.personName(label: "guardian's name", required: false)(_guardian.text) ??
      Validators.text(label: 'address line 1', min: 4, max: 120, required: false)(_line1.text) ??
      Validators.text(label: 'address line 2', max: 120, required: false)(_line2.text) ??
      Validators.text(label: 'landmark', max: 80, required: false)(_landmark.text) ??
      Validators.title(label: 'city', max: 60, required: false)(_city.text) ??
      Validators.title(label: 'district', max: 60, required: false)(_district.text) ??
      Validators.title(label: 'state', max: 60, required: false)(_state.text) ??
      Validators.pinCode(countryName: _pinCountry, required: false)(_pin.text);

  String? get _pinCountry => PhoneRules.parseStored(_p.phone).dial == '+91' ? null : 'elsewhere';

  Future<void> _save() async {
    final problem = _problem();
    if (problem != null) {
      setState(() => _showErrors = true);
      AppNotice.error(context, problem);
      return;
    }
    setState(() => _saving = true);
    String? t(TextEditingController c) => c.text.trim().isEmpty ? null : c.text.trim();
    final altCheck = PhoneRules.check(dial: _altDial, digits: _altPhone.text, iso: _altCountry?.iso, kind: PhoneKind.any, required: false);
    try {
      await ref.read(selfProfileApiProvider).update({
        'fullName': _name.text.trim(),
        'altPhone': altCheck.nsn.isEmpty ? null : PhoneRules.format(_altDial, altCheck.nsn),
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
          LabeledTextField(
              label: 'Full name',
              controller: _name,
              hint: 'Full name',
              preset: FieldPreset.personName(),
              showErrors: _showErrors,
              onChanged: (_) => setState(() {})),
          gap,
          InfoLine(label: 'Phone', value: _p.phone, icon: Icons.phone_outlined),
          Text('Phone and email are changed by your academy.',
              style: TextStyle(fontSize: AppType.sm, color: palette.textFaint)),
          gap,
          const FormLabel('Alternate phone (optional)'),
          PhoneInput(
            dial: _altDial,
            country: _altCountry,
            controller: _altPhone,
            hint: 'Alternate contact',
            kind: PhoneKind.any,
            required: false,
            showErrors: _showErrors,
            onDialChanged: (d) => setState(() {
              _altDial = d;
              _altCountry = null;
            }),
            onCountryChanged: (c) => setState(() => _altCountry = c),
          ),
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
          LabeledTextField(
              label: 'Guardian name',
              controller: _guardian,
              hint: 'Parent / guardian name',
              preset: FieldPreset.personName(label: "guardian's name", required: false),
              showErrors: _showErrors),
          const SizedBox(height: AppSpacing.x5l),
          Text('ADDRESS',
              style: TextStyle(
                  fontSize: AppType.tiny, fontWeight: AppType.bold, color: palette.textFaint, letterSpacing: 0.4)),
          gap,
          LabeledTextField(
              label: 'Address line 1',
              controller: _line1,
              hint: 'House / flat, street',
              preset: FieldPreset.text(label: 'address line 1', min: 4, max: 120, required: false),
              showErrors: _showErrors),
          gap,
          LabeledTextField(
              label: 'Address line 2 (optional)',
              controller: _line2,
              hint: 'Area, apartment',
              preset: FieldPreset.text(label: 'address line 2', max: 120, required: false),
              showErrors: _showErrors),
          gap,
          LabeledTextField(
              label: 'Landmark (optional)',
              controller: _landmark,
              preset: FieldPreset.text(label: 'landmark', max: 80, required: false),
              showErrors: _showErrors),
          gap,
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                  child: LabeledTextField(
                      label: 'City',
                      controller: _city,
                      preset: FieldPreset.title(label: 'city', max: 60, required: false),
                      showErrors: _showErrors)),
              const SizedBox(width: AppSpacing.lg),
              Expanded(
                  child: LabeledTextField(
                      label: 'Pin code',
                      controller: _pin,
                      preset: FieldPreset.pinCode(countryName: _pinCountry, required: false),
                      showErrors: _showErrors)),
            ],
          ),
          gap,
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                  child: LabeledTextField(
                      label: 'District',
                      controller: _district,
                      preset: FieldPreset.title(label: 'district', max: 60, required: false),
                      showErrors: _showErrors)),
              const SizedBox(width: AppSpacing.lg),
              Expanded(
                  child: LabeledTextField(
                      label: 'State',
                      controller: _state,
                      preset: FieldPreset.title(label: 'state', max: 60, required: false),
                      showErrors: _showErrors)),
            ],
          ),
          const SizedBox(height: AppSpacing.x5l),
          AppPrimaryButton(
            label: 'Save changes',
            icon: Icons.check,
            busy: _saving,
            onPressed: _save,
          ),
          const SizedBox(height: AppSpacing.x5l),
        ],
      ),
    );
  }
}
