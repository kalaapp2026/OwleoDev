import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:nest_fe/app/theme/app_tokens.dart';
import 'package:nest_fe/app/theme/app_typography.dart';
import 'package:nest_fe/core/design/app_text_field.dart';
import 'package:nest_fe/core/design/buttons.dart';
import 'package:nest_fe/core/design/confirm_dialog.dart';
import 'package:nest_fe/core/design/pressable.dart';
import 'package:nest_fe/core/error/api_exception.dart';
import 'package:nest_fe/core/widgets/app_notice.dart';
import 'package:nest_fe/features/academy/data/academy_settings_api.dart';
import 'package:nest_fe/features/academy/presentation/academy_settings_kit.dart';

const _reasons = ['Stepping down', 'Selling the academy', 'Other'];

final _emailRule = FieldPreset.email();
final _notesRule = FieldPreset.text(label: 'notes', max: 1000, required: false);

/// Asks the Owleo team to hand the academy to a new owner. Ownership affects billing and access for
/// everyone, so it is a request the team verifies and carries out, not something changed in-app.
class OwnershipTransferScreen extends ConsumerStatefulWidget {
  const OwnershipTransferScreen({super.key});

  @override
  ConsumerState<OwnershipTransferScreen> createState() => _OwnershipTransferScreenState();
}

class _OwnershipTransferScreenState extends ConsumerState<OwnershipTransferScreen> {
  final _email = TextEditingController();
  final _notes = TextEditingController();
  String _reason = _reasons.first;
  bool _saving = false;

  @override
  void dispose() {
    _email.dispose();
    _notes.dispose();
    super.dispose();
  }

  bool get _valid => _emailRule.check(_email.text) == null && _notesRule.check(_notes.text) == null;

  Future<void> _submit() async {
    final confirmed = await showAppConfirmDialog(
      context: context,
      title: 'Submit ownership transfer request?',
      message: "The Owleo team will reach out to verify this request and arrange the handover to ${_email.text.trim()}.",
      confirmLabel: 'Submit',
      destructive: false,
    );
    if (!confirmed || !mounted) return;
    setState(() => _saving = true);
    try {
      await ref.read(academySettingsApiProvider).submitRequest(
            kind: AcademyRequestKind.ownershipTransfer,
            targetEmail: _email.text.trim(),
            reason: _reason,
            details: _notes.text.trim().isEmpty ? null : _notes.text.trim(),
          );
      ref.invalidate(myAcademyRequestsProvider);
      if (!mounted) return;
      AppNotice.success(context, 'Transfer request sent. The team will be in touch.');
      Navigator.of(context).pop();
    } on ApiException catch (e) {
      if (mounted) AppNotice.error(context, e.message);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return SettingsPage(
      title: 'Request Ownership Transfer',
      footer: AppPrimaryButton(
        label: 'Submit Transfer Request',
        busy: _saving,
        onPressed: _valid ? _submit : null,
      ),
      children: [
        SettingsCard(
          color: palette.goldSoft,
          borderColor: palette.gold.withValues(alpha: 0.27),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(Icons.verified_user_outlined, size: 16, color: palette.gold),
              const SizedBox(width: AppSpacing.lg),
              Expanded(
                child: Text(
                  "Ownership can't be reassigned directly in the app, to keep the academy secure. "
                  'Submit this request and the Owleo team will verify it and complete the transfer.',
                  style: TextStyle(fontSize: AppType.sm, height: 1.6, color: palette.textMuted),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: AppSpacing.x4l),
        const SettingsFieldLabel("New owner's email"),
        CheckedField(
          controller: _email,
          preset: _emailRule,
          builder: (context, hasError) => TextField(
            controller: _email,
            keyboardType: _emailRule.keyboardType,
            inputFormatters: _emailRule.formatters,
            onChanged: (_) => setState(() {}),
            style: TextStyle(color: palette.text),
            decoration: settingsInput(context, 'their-email@example.com'),
          ),
        ),
        const SizedBox(height: AppSpacing.x4l),
        const SettingsFieldLabel('Reason'),
        Wrap(
          spacing: AppSpacing.md,
          runSpacing: AppSpacing.md,
          children: [
            for (final r in _reasons)
              Pressable(
                onTap: () => setState(() => _reason = r),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 8),
                  decoration: BoxDecoration(
                    color: r == _reason ? palette.goldSoft : palette.surfaceRaised,
                    borderRadius: AppRadii.all(AppRadii.pill),
                    border: Border.all(color: r == _reason ? palette.gold : palette.border),
                  ),
                  child: Text(r,
                      style: TextStyle(
                          fontSize: AppType.smd,
                          fontWeight: AppType.bold,
                          color: r == _reason ? palette.gold : palette.textMuted)),
                ),
              ),
          ],
        ),
        const SizedBox(height: AppSpacing.x4l),
        const SettingsFieldLabel('Notes (optional)'),
        CheckedField(
          controller: _notes,
          preset: _notesRule,
          builder: (context, hasError) => TextField(
            controller: _notes,
            maxLines: 4,
            maxLength: 1000,
            onChanged: (_) => setState(() {}),
            textCapitalization: _notesRule.textCapitalization,
            style: TextStyle(color: palette.text),
            decoration: settingsInput(context, 'Anything the team should know').copyWith(counterText: ''),
          ),
        ),
      ],
    );
  }
}
