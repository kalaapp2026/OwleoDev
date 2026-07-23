import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:nest_fe/core/error/api_exception.dart';
import 'package:nest_fe/core/providers/core_providers.dart';
import 'package:nest_fe/core/widgets/app_notice.dart';
import 'package:nest_fe/features/academy/data/academy_onboarding_api.dart';

final academyOnboardingApiProvider = Provider((ref) => AcademyOnboardingApi(ref.watch(dioClientProvider)));

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

  bool get _canSubmit =>
      _academyName.text.trim().isNotEmpty &&
      _address.text.trim().isNotEmpty &&
      _city.text.trim().isNotEmpty &&
      _state.text.trim().isNotEmpty &&
      _contactNumber.text.trim().isNotEmpty &&
      _adminUsername.text.trim().isNotEmpty &&
      _adminFullName.text.trim().isNotEmpty &&
      _adminPhone.text.trim().isNotEmpty;

  Future<void> _submit() async {
    setState(() => _isSaving = true);
    try {
      final result = await ref.read(academyOnboardingApiProvider).onboard(
            academyName: _academyName.text.trim(),
            category: _category,
            address: _address.text.trim(),
            city: _city.text.trim(),
            state: _state.text.trim(),
            contactNumber: _contactNumber.text.trim(),
            email: _email.text.trim().isEmpty ? null : _email.text.trim(),
            adminUsername: _adminUsername.text.trim(),
            adminFullName: _adminFullName.text.trim(),
            adminPhone: _adminPhone.text.trim(),
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

  Widget _buildForm(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        Text('Academy details', style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 12),
        TextField(controller: _academyName, decoration: const InputDecoration(labelText: 'Academy name'), onChanged: (_) => setState(() {})),
        const SizedBox(height: 12),
        DropdownButtonFormField<String>(
          initialValue: _category,
          decoration: const InputDecoration(labelText: 'Category'),
          items: _categories.map((c) => DropdownMenuItem(value: c, child: Text(c.replaceAll('_', ' ')))).toList(),
          onChanged: (v) => setState(() => _category = v!),
        ),
        const SizedBox(height: 12),
        TextField(controller: _address, decoration: const InputDecoration(labelText: 'Address'), onChanged: (_) => setState(() {})),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(child: TextField(controller: _city, decoration: const InputDecoration(labelText: 'City'), onChanged: (_) => setState(() {}))),
            const SizedBox(width: 12),
            Expanded(child: TextField(controller: _state, decoration: const InputDecoration(labelText: 'State'), onChanged: (_) => setState(() {}))),
          ],
        ),
        const SizedBox(height: 12),
        TextField(controller: _contactNumber, keyboardType: TextInputType.phone, decoration: const InputDecoration(labelText: 'Contact number'), onChanged: (_) => setState(() {})),
        const SizedBox(height: 12),
        TextField(controller: _email, keyboardType: TextInputType.emailAddress, decoration: const InputDecoration(labelText: 'Academy email (optional)')),
        const SizedBox(height: 24),
        Text('First Academy Admin', style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 4),
        Text('A login is created for this person - they run the academy day to day.', style: Theme.of(context).textTheme.bodySmall),
        const SizedBox(height: 12),
        TextField(controller: _adminFullName, decoration: const InputDecoration(labelText: 'Admin full name'), onChanged: (_) => setState(() {})),
        const SizedBox(height: 12),
        TextField(controller: _adminUsername, decoration: const InputDecoration(labelText: 'Admin username'), onChanged: (_) => setState(() {})),
        const SizedBox(height: 12),
        TextField(controller: _adminPhone, keyboardType: TextInputType.phone, decoration: const InputDecoration(labelText: 'Admin phone'), onChanged: (_) => setState(() {})),
        const SizedBox(height: 12),
        TextField(controller: _adminEmail, keyboardType: TextInputType.emailAddress, decoration: const InputDecoration(labelText: 'Admin email (optional)')),
        const SizedBox(height: 24),
        ElevatedButton(
          onPressed: (_isSaving || !_canSubmit) ? null : _submit,
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
