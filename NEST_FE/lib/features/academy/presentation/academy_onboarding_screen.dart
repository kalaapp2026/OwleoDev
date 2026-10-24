import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:nest_fe/core/design/app_text_field.dart';
import 'package:nest_fe/core/error/api_exception.dart';
import 'package:nest_fe/core/validation/countries.dart';
import 'package:nest_fe/core/validation/phone_rules.dart';
import 'package:nest_fe/core/validation/validators.dart';
import 'package:nest_fe/core/providers/core_providers.dart';
import 'package:nest_fe/core/widgets/app_notice.dart';
import 'package:nest_fe/features/academy/data/academy_onboarding_api.dart';

final academyOnboardingApiProvider = Provider((ref) => AcademyOnboardingApi(ref.watch(dioClientProvider)));

/// Super Admin only - every academy incl. suspended. Backs the academy-management screen and the
/// broadcast console's academy picker.
final allAcademiesProvider =
    FutureProvider.autoDispose<List<AcademyBrief>>((ref) => ref.watch(academyOnboardingApiProvider).listAll());

const _categories = ['DANCE', 'MUSIC', 'MULTI_DISCIPLINE'];

/// PRD 3.2 / 2.4: Super Admin onboards an academy plus its first Academy Admin in one form. On
/// success the admin's generated temp password is shown once so it can be handed over.
class AcademyOnboardingScreen extends ConsumerStatefulWidget {
  const AcademyOnboardingScreen({super.key});

  @override
  ConsumerState<AcademyOnboardingScreen> createState() => _AcademyOnboardingScreenState();
}

class _AcademyOnboardingScreenState extends ConsumerState<AcademyOnboardingScreen> {
  final _academyName = TextEditingController();
  final _address = TextEditingController();
  final _city = TextEditingController();
  final _state = TextEditingController();
  final _contactNumber = TextEditingController();
  final _email = TextEditingController();
  final _adminUsername = TextEditingController();
  final _adminFullName = TextEditingController();
  final _adminPhone = TextEditingController();
  final _adminEmail = TextEditingController();

  String _category = _categories.first;
  bool _isSaving = false;

  // Each phone keeps its calling code and country beside the digits.
  String _contactDial = '+91';
  Country? _contactCountry;
  String _adminDial = '+91';
  Country? _adminCountry;

  /// Set when Create is tapped with something wrong, so every error shows at once.
  bool _showErrors = false;
  OnboardAcademyResult? _result;

  @override
  void dispose() {
    for (final c in [
      _academyName, _address, _city, _state, _contactNumber, _email,
      _adminUsername, _adminFullName, _adminPhone, _adminEmail,
    ]) {
      c.dispose();
    }
    super.dispose();
  }

  /// The first thing wrong with the form, in the order it is laid out; null when it can be sent.
  String? _problem() =>
      Validators.title(label: 'academy name', max: 80)(_academyName.text) ??
      Validators.text(label: 'address', min: 4, max: 160)(_address.text) ??
      Validators.title(label: 'city', max: 60)(_city.text) ??
      Validators.title(label: 'state', max: 60)(_state.text) ??
      PhoneRules.validate(dial: _contactDial, digits: _contactNumber.text, iso: _contactCountry?.iso) ??
      Validators.email(required: false)(_email.text) ??
      Validators.personName(label: "admin's name")(_adminFullName.text) ??
      Validators.username()(_adminUsername.text) ??
      PhoneRules.validate(dial: _adminDial, digits: _adminPhone.text, iso: _adminCountry?.iso) ??
      Validators.email(required: false)(_adminEmail.text);

  String _phone(String dial, TextEditingController c, Country? country) =>
      PhoneRules.format(dial, PhoneRules.check(dial: dial, digits: c.text, iso: country?.iso).nsn);

  Future<void> _submit() async {
    final problem = _problem();
    if (problem != null) {
      setState(() => _showErrors = true);
      AppNotice.error(context, problem);
      return;
    }
    setState(() => _isSaving = true);
    try {
      final result = await ref.read(academyOnboardingApiProvider).onboard(
            academyName: _academyName.text.trim(),
            category: _category,
            address: _address.text.trim(),
            city: _city.text.trim(),
            state: _state.text.trim(),
            contactNumber: _phone(_contactDial, _contactNumber, _contactCountry),
            email: _email.text.trim().isEmpty ? null : _email.text.trim(),
            adminUsername: _adminUsername.text.trim(),
            adminFullName: _adminFullName.text.trim(),
            adminPhone: _phone(_adminDial, _adminPhone, _adminCountry),
            adminEmail: _adminEmail.text.trim().isEmpty ? null : _adminEmail.text.trim(),
          );
      if (mounted) setState(() => _result = result);
    } on ApiException catch (e) {
      if (mounted) AppNotice.error(context, e.message);
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Academy onboarding')),
      body: _result != null ? _SuccessView(result: _result!) : _buildForm(context),
    );
  }

  /// A caption above a control that has no label of its own (the phone input).
  Widget _labelled(String label, Widget child) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(left: 2, bottom: 6),
            child: Text(label, style: Theme.of(context).textTheme.bodySmall),
          ),
          child,
        ],
      );

  Widget _buildForm(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        Text('Academy details', style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 12),
        ValidatedTextField(
          controller: _academyName,
          label: 'Academy name',
          preset: FieldPreset.title(label: 'academy name', max: 80),
          showErrors: _showErrors,
        ),
        const SizedBox(height: 12),
        DropdownButtonFormField<String>(
          initialValue: _category,
          decoration: const InputDecoration(labelText: 'Category'),
          items: _categories.map((c) => DropdownMenuItem(value: c, child: Text(c.replaceAll('_', ' ')))).toList(),
          onChanged: (v) => setState(() => _category = v!),
        ),
        const SizedBox(height: 12),
        ValidatedTextField(
          controller: _address,
          label: 'Address',
          preset: FieldPreset.text(label: 'address', min: 4, max: 160),
          showErrors: _showErrors,
        ),
        const SizedBox(height: 12),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: ValidatedTextField(
                controller: _city,
                label: 'City',
                preset: FieldPreset.title(label: 'city', max: 60),
                showErrors: _showErrors,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: ValidatedTextField(
                controller: _state,
                label: 'State',
                preset: FieldPreset.title(label: 'state', max: 60),
                showErrors: _showErrors,
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        _labelled(
          'Contact number',
          PhoneInput(
            dial: _contactDial,
            country: _contactCountry,
            controller: _contactNumber,
            showErrors: _showErrors,
            onDialChanged: (d) => setState(() {
              _contactDial = d;
              _contactCountry = null;
            }),
            onCountryChanged: (c) => setState(() => _contactCountry = c),
          ),
        ),
        const SizedBox(height: 12),
        ValidatedTextField(
          controller: _email,
          label: 'Academy email (optional)',
          preset: FieldPreset.email(required: false),
          showErrors: _showErrors,
        ),
        const SizedBox(height: 24),
        Text('First Academy Admin', style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 4),
        Text('A login is created for this person - they run the academy day to day.', style: Theme.of(context).textTheme.bodySmall),
        const SizedBox(height: 12),
        ValidatedTextField(
          controller: _adminFullName,
          label: 'Admin full name',
          preset: FieldPreset.personName(label: "admin's name"),
          showErrors: _showErrors,
        ),
        const SizedBox(height: 12),
        ValidatedTextField(
          controller: _adminUsername,
          label: 'Admin username',
          preset: FieldPreset.username(),
          showErrors: _showErrors,
        ),
        const SizedBox(height: 12),
        _labelled(
          'Admin phone',
          PhoneInput(
            dial: _adminDial,
            country: _adminCountry,
            controller: _adminPhone,
            showErrors: _showErrors,
            onDialChanged: (d) => setState(() {
              _adminDial = d;
              _adminCountry = null;
            }),
            onCountryChanged: (c) => setState(() => _adminCountry = c),
          ),
        ),
        const SizedBox(height: 12),
        ValidatedTextField(
          controller: _adminEmail,
          label: 'Admin email (optional)',
          preset: FieldPreset.email(required: false),
          showErrors: _showErrors,
        ),
        const SizedBox(height: 24),
        ElevatedButton(
          onPressed: _isSaving ? null : _submit,
          child: _isSaving
              ? const SizedBox(height: 18, width: 18, child: CircularProgressIndicator(strokeWidth: 2))
              : const Text('Create academy'),
        ),
      ],
    );
  }
}

class _SuccessView extends StatelessWidget {
  const _SuccessView({required this.result});
  final OnboardAcademyResult result;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        Icon(Icons.check_circle_outline, color: colorScheme.primary, size: 48),
        const SizedBox(height: 12),
        Text('${result.academyName} created', style: Theme.of(context).textTheme.titleLarge, textAlign: TextAlign.center),
        const SizedBox(height: 24),
        Card(
          color: colorScheme.primaryContainer.withValues(alpha: 0.35),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Admin login', style: Theme.of(context).textTheme.titleSmall),
                const SizedBox(height: 10),
                _CredRow(label: 'Username', value: result.adminUsername),
                const SizedBox(height: 6),
                _CredRow(label: 'Temp password', value: result.adminTemporaryPassword),
                const SizedBox(height: 12),
                Text(
                  'Share these with the academy admin. They\'ll be asked to change the password on first login.',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 24),
        OutlinedButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Done')),
      ],
    );
  }
}

class _CredRow extends StatelessWidget {
  const _CredRow({required this.label, required this.value});
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        SizedBox(width: 120, child: Text(label, style: Theme.of(context).textTheme.bodySmall)),
        Expanded(child: SelectableText(value, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15))),
      ],
    );
  }
}
