import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:nest_fe/app/theme/app_tokens.dart';
import 'package:nest_fe/app/theme/app_typography.dart';
import 'package:nest_fe/core/auth/session_controller.dart';
import 'package:nest_fe/core/design/app_text_field.dart';
import 'package:nest_fe/core/design/buttons.dart';
import 'package:nest_fe/core/design/pressable.dart';
import 'package:nest_fe/core/error/api_exception.dart';
import 'package:nest_fe/core/validation/validators.dart';
import 'package:nest_fe/core/providers/core_providers.dart';
import 'package:nest_fe/core/widgets/app_notice.dart';
import 'package:nest_fe/features/academy/presentation/academy_settings_kit.dart';

/// Your own account's login password, in two steps: prove it is you, then set the new one.
///
/// Proving it is you is either the current password, or - for someone who has forgotten it - a code
/// emailed to the address on the account. The code is checked together with the new password when
/// it is submitted (the server's reset endpoint takes both at once), so a wrong code sends you back
/// to step one rather than failing silently.
class ChangePasswordScreen extends ConsumerStatefulWidget {
  const ChangePasswordScreen({super.key});

  @override
  ConsumerState<ChangePasswordScreen> createState() => _ChangePasswordScreenState();
}

class _ChangePasswordScreenState extends ConsumerState<ChangePasswordScreen> {
  final _current = TextEditingController();
  final _code = TextEditingController();
  final _new = TextEditingController();
  final _confirm = TextEditingController();

  bool _settingNew = false;
  bool _useCode = false;
  bool _codeSent = false;
  bool _busy = false;
  bool _showPasswords = false;

  /// Set when the current password was rejected, shown under the field until it is edited.
  String? _currentError;

  @override
  void dispose() {
    _current.dispose();
    _code.dispose();
    _new.dispose();
    _confirm.dispose();
    super.dispose();
  }

  static final _codeRule = FieldPreset.otp();

  bool get _canContinue => _useCode ? _codeRule.check(_code.text) == null : _current.text.isNotEmpty;

  bool get _lengthOk => _new.text.length >= 8;
  bool get _numberOk => RegExp(r'[0-9]').hasMatch(_new.text);
  bool get _letterOk => RegExp(r'\p{L}', unicode: true).hasMatch(_new.text);
  bool get _matchOk => _confirm.text.isNotEmpty && _confirm.text == _new.text;

  /// The one password rule used everywhere a password is chosen (Validators.password): at least 8
  /// characters with a letter and a number.
  bool get _canSubmit => Validators.password()(_new.text) == null && _matchOk;

  int get _strength {
    final p = _new.text;
    if (p.isEmpty) return 0;
    var score = 0;
    if (p.length >= 8) score++;
    if (RegExp(r'[0-9]').hasMatch(p)) score++;
    if (RegExp(r'[^A-Za-z0-9]').hasMatch(p)) score++;
    if (RegExp(r'[A-Z]').hasMatch(p) && RegExp(r'[a-z]').hasMatch(p)) score++;
    return score;
  }

  /// Moves on to the new-password step. With the current password, that password is checked with
  /// the server first - a wrong one stops here instead of letting someone type a whole new password
  /// before finding out. A code is checked together with the new password at the end, since the
  /// server only accepts the two at once.
  Future<void> _continue() async {
    if (_useCode) {
      setState(() => _settingNew = true);
      return;
    }
    setState(() {
      _busy = true;
      _currentError = null;
    });
    try {
      await ref.read(authApiProvider).verifyPassword(_current.text);
      if (mounted) setState(() => _settingNew = true);
    } on ApiException catch (e) {
      if (mounted) setState(() => _currentError = e.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _sendCode() async {
    final username = ref.read(sessionControllerProvider).user?.username;
    if (username == null) return;
    setState(() => _busy = true);
    try {
      await ref.read(authApiProvider).forgotPassword(username);
      if (!mounted) return;
      setState(() => _codeSent = true);
      AppNotice.success(context, 'We emailed you a code.');
    } on ApiException catch (e) {
      if (mounted) AppNotice.error(context, e.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _submit() async {
    setState(() => _busy = true);
    try {
      final auth = ref.read(authApiProvider);
      if (_useCode) {
        final username = ref.read(sessionControllerProvider).user!.username;
        await auth.resetPassword(username, _code.text.trim(), _new.text);
      } else {
        await auth.changePassword(_current.text, _new.text);
      }
      if (!mounted) return;
      AppNotice.success(context, 'Password updated.');
      Navigator.of(context).pop();
    } on ApiException catch (e) {
      if (!mounted) return;
      AppNotice.error(context, e.message);
      // A wrong current password or code is a step-one problem - put the person back there.
      setState(() => _settingNew = false);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => _settingNew ? _newPasswordStep(context) : _verifyStep(context);

  Widget _verifyStep(BuildContext context) {
    final palette = context.palette;
    final email = ref.watch(sessionControllerProvider).user?.email;
    return SettingsPage(
      title: 'Login Password',
      footer: AppPrimaryButton(
        label: 'Continue',
        busy: _busy,
        onPressed: _canContinue ? _continue : null,
      ),
      children: [
        const SettingsNote(
          icon: Icons.lock_outline,
          text: 'This is the password you sign in with. It belongs to your own account and is not shared with the academy\'s other people.',
        ),
        const SizedBox(height: AppSpacing.x4l),
        if (!_useCode) ...[
          const SettingsFieldLabel('Current password'),
          _passwordField(_current, 'Enter your current password'),
          if (_currentError != null)
            Padding(
              padding: const EdgeInsets.only(top: AppSpacing.md),
              child: Row(children: [
                Icon(Icons.warning_amber_rounded, size: 13, color: palette.notPaid),
                const SizedBox(width: 6),
                Expanded(child: Text(_currentError!, style: TextStyle(fontSize: AppType.sm, color: palette.notPaid))),
              ]),
            ),
          const SizedBox(height: AppSpacing.lg),
          _textLink(Icons.mark_email_read_outlined, "Don't remember it? Verify with a code", () => setState(() => _useCode = true)),
        ] else ...[
          SettingsNote(
            icon: Icons.mail_outline,
            text: (email ?? '').isEmpty
                ? 'We will email a one-time code to the address on your account.'
                : 'We will email a one-time code to $email.',
          ),
          const SizedBox(height: AppSpacing.xl),
          if (!_codeSent)
            AppPrimaryButton(label: 'Send code', icon: Icons.send_rounded, busy: _busy, onPressed: _sendCode)
          else ...[
            const SettingsFieldLabel('One-time code'),
            TextField(
              controller: _code,
              keyboardType: _codeRule.keyboardType,
              inputFormatters: _codeRule.formatters,
              onChanged: (_) => setState(() {}),
              style: TextStyle(color: palette.text, letterSpacing: 4, fontSize: AppType.x4l),
              decoration: settingsInput(context, 'Enter the code'),
            ),
            const SizedBox(height: AppSpacing.lg),
            _textLink(Icons.refresh, 'Resend code', _busy ? null : _sendCode),
          ],
          const SizedBox(height: AppSpacing.lg),
          _textLink(Icons.arrow_back, 'Use my current password instead', () => setState(() {
                _useCode = false;
                _codeSent = false;
                _code.clear();
              })),
        ],
      ],
    );
  }

  Widget _newPasswordStep(BuildContext context) {
    final palette = context.palette;
    final strength = _strength;
    final (strengthLabel, strengthColor) = switch (strength) {
      0 => ('Too short', palette.notPaid),
      1 => ('Weak', palette.notPaid),
      2 => ('Fair', palette.gold),
      3 => ('Good', palette.gold),
      _ => ('Strong', palette.paidManual),
    };

    return SettingsPage(
      title: 'Set New Password',
      footer: AppPrimaryButton(label: 'Update Password', busy: _busy, onPressed: _canSubmit ? _submit : null),
      children: [
        const SettingsFieldLabel('New password'),
        _passwordField(_new, 'Enter a new password'),
        if (_new.text.isNotEmpty) ...[
          const SizedBox(height: AppSpacing.md),
          Row(
            children: [
              for (var i = 0; i < 4; i++)
                Expanded(
                  child: Container(
                    height: 4,
                    margin: EdgeInsets.only(right: i == 3 ? 0 : 4),
                    decoration: BoxDecoration(
                      color: i < strength ? strengthColor : palette.surfaceHigh,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 5),
          Text(strengthLabel, style: TextStyle(fontSize: AppType.xs, fontWeight: AppType.bold, color: strengthColor)),
        ],
        const SizedBox(height: AppSpacing.x4l),
        const SettingsFieldLabel('Confirm new password'),
        _passwordField(_confirm, 'Re-enter the new password'),
        if (_confirm.text.isNotEmpty && !_matchOk)
          Padding(
            padding: const EdgeInsets.only(top: AppSpacing.md),
            child: Row(children: [
              Icon(Icons.warning_amber_rounded, size: 13, color: palette.notPaid),
              const SizedBox(width: 6),
              Text("Passwords don't match", style: TextStyle(fontSize: AppType.sm, color: palette.notPaid)),
            ]),
          ),
        const SizedBox(height: AppSpacing.x4l),
        SettingsCard(
          padding: const EdgeInsets.all(AppSpacing.xl),
          child: Column(
            children: [
              _requirement(_lengthOk, 'At least 8 characters'),
              _requirement(_numberOk, 'Contains a number'),
              _requirement(_letterOk, 'Contains a letter'),
            ],
          ),
        ),
        const SizedBox(height: AppSpacing.lg),
        _textLink(Icons.arrow_back, 'Back', () => setState(() => _settingNew = false)),
      ],
    );
  }

  Widget _passwordField(TextEditingController controller, String hint) {
    final palette = context.palette;
    return TextField(
      controller: controller,
      obscureText: !_showPasswords,
      onChanged: (_) => setState(() => _currentError = null),
      style: TextStyle(color: palette.text),
      decoration: settingsInput(
        context,
        hint,
        suffix: IconButton(
          icon: Icon(_showPasswords ? Icons.visibility_off_outlined : Icons.visibility_outlined, size: 18, color: palette.textFaint),
          onPressed: () => setState(() => _showPasswords = !_showPasswords),
        ),
      ),
    );
  }

  Widget _requirement(bool met, String label) {
    final palette = context.palette;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Container(
            width: 15,
            height: 15,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: met ? palette.paidManualSoft : palette.surfaceHigh,
              border: Border.all(color: met ? palette.paidManual : palette.border),
            ),
            child: met ? Icon(Icons.check, size: 9, color: palette.paidManual) : null,
          ),
          const SizedBox(width: 7),
          Text(label, style: TextStyle(fontSize: AppType.sm, color: met ? palette.textMuted : palette.textFaint)),
        ],
      ),
    );
  }

  Widget _textLink(IconData icon, String label, VoidCallback? onTap) {
    final palette = context.palette;
    return Pressable(
      onTap: onTap,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 13, color: onTap == null ? palette.textFaint : palette.primary),
          const SizedBox(width: 6),
          Flexible(
            child: Text(label,
                style: TextStyle(
                    fontSize: AppType.base,
                    fontWeight: AppType.bold,
                    color: onTap == null ? palette.textFaint : palette.primary)),
          ),
        ],
      ),
    );
  }
}
