import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:nest_fe/app/theme/app_tokens.dart';
import 'package:nest_fe/app/theme/app_typography.dart';
import 'package:nest_fe/app/theme/theme_controller.dart';
import 'package:nest_fe/core/auth/session_controller.dart';
import 'package:nest_fe/core/design/buttons.dart';
import 'package:nest_fe/core/design/calendar_modal.dart';
import 'package:nest_fe/core/design/pressable.dart';
import 'package:nest_fe/core/design/segmented_control.dart';
import 'package:nest_fe/core/error/api_exception.dart';
import 'package:nest_fe/core/widgets/app_notice.dart';
import 'package:nest_fe/features/auth/data/auth_api.dart';
import 'package:nest_fe/l10n/app_localizations.dart';

enum _AuthMode { signIn, signUp }

enum _SignInStage { form, otp }

/// Login and signup, unified into one screen with a Login / Create Account switcher - a port of
/// the auth screen from the React prototype (glowing dusk backdrop, pulsing owl mark, pill
/// fields), with email/username and password on the SAME screen rather than split across stages.
///
/// The backend's unified login still resolves the account first (POST /auth/identify) before
/// attempting the password, since some accounts may be OTP-based - that happens invisibly inside
/// one submit here instead of as a separate screen; the OTP stage only ever appears as a fallback
/// for the (currently rare) account that needs it.
///
/// [SignupScreen] renders the same widget defaulted to the signup side, so both `/login` and
/// `/signup` keep working as separate routes without duplicating this logic.
class LoginScreen extends StatelessWidget {
  const LoginScreen({super.key});

  @override
  Widget build(BuildContext context) => const _AuthScreen(initialMode: _AuthMode.signIn);
}

/// Public self-signup (PRD 7.4 addendum) - the account is created from five required fields
/// (username/password/fullName/phone/email); everything else on this form (DOB, gender, blood
/// group, guardian, address) is optional and layered on afterward via the same PersonDetails merge
/// the staff-side student/trainer registration forms use. See [LoginScreen] - both routes share
/// [_AuthScreen].
class SignupScreen extends StatelessWidget {
  const SignupScreen({super.key});

  @override
  Widget build(BuildContext context) => const _AuthScreen(initialMode: _AuthMode.signUp);
}

const List<String> _kGenders = ['Male', 'Female', 'Other'];
const List<String> _kBloodGroups = ['A+', 'A-', 'B+', 'B-', 'O+', 'O-', 'AB+', 'AB-'];

class _AuthScreen extends ConsumerStatefulWidget {
  const _AuthScreen({required this.initialMode});

  final _AuthMode initialMode;

  @override
  ConsumerState<_AuthScreen> createState() => _AuthScreenState();
}

class _AuthScreenState extends ConsumerState<_AuthScreen> {
  late _AuthMode _mode = widget.initialMode;

  // --- Sign-in: email/username + password on one screen, OTP only as a fallback stage ---
  final _identifierController = TextEditingController();
  final _passwordController = TextEditingController();
  final _codeController = TextEditingController();
  _SignInStage _signInStage = _SignInStage.form;
  String? _resolvedUsername;
  String? _maskedPhone;
  bool _obscureSignInPassword = true;

  // --- Sign-up: every field the prototype collects, mapped onto the real signup contract
  // (username/password/fullName/phone/email required; dob + PersonDetails optional) ---
  final _firstNameController = TextEditingController();
  final _lastNameController = TextEditingController();
  final _usernameController = TextEditingController();
  final _emailController = TextEditingController();
  final _signupPasswordController = TextEditingController();
  final _confirmPasswordController = TextEditingController();
  final _phoneController = TextEditingController();
  final _altPhoneController = TextEditingController();
  final _guardianNameController = TextEditingController();
  final _addressLine1Controller = TextEditingController();
  final _addressLine2Controller = TextEditingController();
  final _cityController = TextEditingController();
  final _pinCodeController = TextEditingController();
  final _districtController = TextEditingController();
  final _stateController = TextEditingController();
  DateTime? _dob;
  String? _gender;
  String? _bloodGroup;
  bool _obscureSignupPassword = true;
  bool _obscureConfirmPassword = true;

  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    _signupPasswordController.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _identifierController.dispose();
    _passwordController.dispose();
    _codeController.dispose();
    _firstNameController.dispose();
    _lastNameController.dispose();
    _usernameController.dispose();
    _emailController.dispose();
    _signupPasswordController.dispose();
    _confirmPasswordController.dispose();
    _phoneController.dispose();
    _altPhoneController.dispose();
    _guardianNameController.dispose();
    _addressLine1Controller.dispose();
    _addressLine2Controller.dispose();
    _cityController.dispose();
    _pinCodeController.dispose();
    _districtController.dispose();
    _stateController.dispose();
    super.dispose();
  }

  Future<void> _submitSignIn() async {
    final identifier = _identifierController.text.trim();
    final password = _passwordController.text;
    if (identifier.isEmpty || password.isEmpty) {
      AppNotice.error(context, 'Enter your email or username, and your password.');
      return;
    }

    setState(() => _isLoading = true);
    try {
      final identifyResult = await ref.read(sessionControllerProvider.notifier).identify(identifier);
      if (identifyResult.authMethod == AuthMethod.password) {
        await ref.read(sessionControllerProvider.notifier).loginWithPassword(identifyResult.username, password);
      } else {
        // Rare fallback: this account has no password on file, so whatever was typed into the
        // password field above is moot - the backend already sent a code as a side effect of
        // identify(), so all that's left is to collect it.
        setState(() {
          _resolvedUsername = identifyResult.username;
          _maskedPhone = identifyResult.maskedPhone;
          _signInStage = _SignInStage.otp;
        });
      }
    } on ApiException catch (e) {
      if (mounted) AppNotice.error(context, e.message);
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _resendOtp() async {
    setState(() => _isLoading = true);
    try {
      await ref.read(sessionControllerProvider.notifier).resendOtp(_identifierController.text.trim());
      if (mounted) AppNotice.success(context, 'A new code was sent.');
    } on ApiException catch (e) {
      if (mounted) AppNotice.error(context, e.message);
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _submitOtp() async {
    setState(() => _isLoading = true);
    try {
      await ref.read(sessionControllerProvider.notifier).verifyOtp(
            _identifierController.text.trim(),
            _codeController.text.trim(),
          );
    } on ApiException catch (e) {
      if (mounted) AppNotice.error(context, e.message);
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _backToSignInForm() {
    setState(() {
      _signInStage = _SignInStage.form;
      _resolvedUsername = null;
      _maskedPhone = null;
      _codeController.clear();
    });
  }

  Future<void> _submitSignup() async {
    final firstName = _firstNameController.text.trim();
    final lastName = _lastNameController.text.trim();
    final username = _usernameController.text.trim();
    final email = _emailController.text.trim();
    final password = _signupPasswordController.text;
    final confirm = _confirmPasswordController.text;
    final phone = _phoneController.text.trim();

    if (firstName.isEmpty || lastName.isEmpty || username.isEmpty || phone.isEmpty || email.isEmpty) {
      AppNotice.error(context, 'Fill in your name, username, phone and email.');
      return;
    }
    if (!email.contains('@') || !email.contains('.')) {
      AppNotice.error(context, 'Enter a valid email address.');
      return;
    }
    if (password.length < 6) {
      AppNotice.error(context, 'Password should be at least 6 characters.');
      return;
    }
    if (password != confirm) {
      AppNotice.error(context, "Passwords don't match.");
      return;
    }

    setState(() => _isLoading = true);
    try {
      await ref.read(sessionControllerProvider.notifier).signup(
            username: username,
            password: password,
            fullName: '$firstName $lastName'.trim(),
            phone: phone,
            email: email,
            dob: _dob,
            details: SignupPersonDetails(
              firstName: firstName,
              lastName: lastName,
              gender: _gender,
              bloodGroup: _bloodGroup,
              altPhone: _emptyToNull(_altPhoneController.text),
              addressLine1: _emptyToNull(_addressLine1Controller.text),
              addressLine2: _emptyToNull(_addressLine2Controller.text),
              city: _emptyToNull(_cityController.text),
              district: _emptyToNull(_districtController.text),
              state: _emptyToNull(_stateController.text),
              pinCode: _emptyToNull(_pinCodeController.text),
              guardianName: _emptyToNull(_guardianNameController.text),
            ),
          );
      if (mounted) context.go('/become-artist');
    } on ApiException catch (e) {
      if (mounted) AppNotice.error(context, e.message);
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  String? _emptyToNull(String raw) {
    final trimmed = raw.trim();
    return trimmed.isEmpty ? null : trimmed;
  }

  void _setMode(_AuthMode mode) {
    if (mode == _mode) return;
    setState(() => _mode = mode);
  }

  Future<void> _pickDob() async {
    final now = DateTime.now();
    final picked = await showAppCalendar(
      context: context,
      month: _dob ?? DateTime(now.year - 18, now.month),
      selectedDay: _dob?.day,
      earliestMonth: DateTime(now.year - 100, 1),
      latestMonth: DateTime(now.year, now.month),
    );
    if (picked != null) setState(() => _dob = picked);
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final canPopFreely = _mode == _AuthMode.signUp || _signInStage == _SignInStage.form;

    return PopScope(
      canPop: canPopFreely,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _backToSignInForm();
      },
      child: Scaffold(
        backgroundColor: palette.bg,
        body: Stack(
          children: [
            const Positioned.fill(child: _AuthGlowBackground()),
            SafeArea(
              child: Column(
                children: [
                  const Padding(
                    padding: EdgeInsets.fromLTRB(AppSpacing.page, AppSpacing.md, AppSpacing.page, 0),
                    child: Row(mainAxisAlignment: MainAxisAlignment.end, children: [_ThemeToggleButton()]),
                  ),
                  Expanded(
                    child: Center(
                      child: SingleChildScrollView(
                        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.x5l, vertical: AppSpacing.lg),
                        child: ConstrainedBox(
                          constraints: const BoxConstraints(maxWidth: 420),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              const Center(child: _AuthLogo()),
                              const SizedBox(height: AppSpacing.xl),
                              Text(
                                'Owleo N.E.S.T.',
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                  fontSize: 22,
                                  fontWeight: AppType.heavy,
                                  letterSpacing: -0.3,
                                  color: palette.text,
                                ),
                              ),
                              const SizedBox(height: AppSpacing.xxs),
                              Text(
                                AppLocalizations.of(context).appTagline,
                                textAlign: TextAlign.center,
                                style: TextStyle(fontSize: AppType.base, color: palette.textMuted),
                              ),
                              const SizedBox(height: AppSpacing.x5l),
                              AppSegmentedControl<_AuthMode>(
                                options: _AuthMode.values,
                                labelOf: (m) => m == _AuthMode.signIn
                                    ? AppLocalizations.of(context).authLogIn
                                    : AppLocalizations.of(context).authCreateAccount,
                                isSelected: (m) => m == _mode,
                                onTap: _setMode,
                              ),
                              const SizedBox(height: AppSpacing.x5l),
                              AnimatedSwitcher(
                                duration: AppMotion.screen,
                                switchInCurve: AppMotion.enter,
                                child: _mode == _AuthMode.signIn ? _buildSignIn() : _buildSignUpPanel(),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSignIn() {
    return AnimatedSwitcher(
      key: const ValueKey('signin'),
      duration: AppMotion.screen,
      switchInCurve: AppMotion.enter,
      child: switch (_signInStage) {
        _SignInStage.form => _buildSignInForm(),
        _SignInStage.otp => _buildOtpStep(),
      },
    );
  }

  Widget _buildSignInForm() {
    return Column(
      key: const ValueKey('signin-form'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _AuthField(
          label: 'Email or Username',
          controller: _identifierController,
          autofocus: true,
          trailingIcon: Icons.mail_outline,
          textInputAction: TextInputAction.next,
        ),
        const SizedBox(height: AppSpacing.xl),
        _AuthField(
          label: AppLocalizations.of(context).authPassword,
          controller: _passwordController,
          obscured: _obscureSignInPassword,
          onToggleObscured: () => setState(() => _obscureSignInPassword = !_obscureSignInPassword),
          textInputAction: TextInputAction.done,
          onSubmitted: (_) => _submitSignIn(),
        ),
        const SizedBox(height: AppSpacing.sm),
        Align(
          alignment: Alignment.centerRight,
          child: _AuthLink(label: 'Forgot password?', onTap: () => _showForgotPasswordSheet(context)),
        ),
        const SizedBox(height: AppSpacing.xl),
        AppPrimaryButton(
          label: AppLocalizations.of(context).authLogIn,
          icon: Icons.login_rounded,
          busy: _isLoading,
          onPressed: _submitSignIn,
        ),
      ],
    );
  }

  Widget _buildOtpStep() {
    final palette = context.palette;
    return Column(
      key: const ValueKey('otp'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _IdentifierBanner(label: _resolvedUsername ?? _identifierController.text.trim(), onChange: _backToSignInForm),
        const SizedBox(height: AppSpacing.md),
        Text(
          _maskedPhone == null ? 'A code was sent to your registered mobile number.' : 'A code was sent to $_maskedPhone.',
          style: TextStyle(fontSize: AppType.sm, color: palette.textMuted),
        ),
        const SizedBox(height: AppSpacing.xxl),
        _AuthField(
          label: '6-digit code',
          controller: _codeController,
          autofocus: true,
          keyboardType: TextInputType.number,
          trailingIcon: Icons.sms_outlined,
          textInputAction: TextInputAction.done,
          onSubmitted: (_) => _submitOtp(),
        ),
        const SizedBox(height: AppSpacing.sm),
        Align(
          alignment: Alignment.centerLeft,
          child: _AuthLink(
            label: AppLocalizations.of(context).authResendCode,
            onTap: _isLoading ? null : _resendOtp,
          ),
        ),
        const SizedBox(height: AppSpacing.xxl),
        AppPrimaryButton(
          label: AppLocalizations.of(context).authVerifyAndLogIn,
          icon: Icons.check_circle_outline,
          busy: _isLoading,
          onPressed: _submitOtp,
        ),
      ],
    );
  }

  Widget _buildSignUpPanel() {
    return Column(
      key: const ValueKey('signup'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(
              child: _AuthField(label: 'First name', controller: _firstNameController, autofocus: true),
            ),
            const SizedBox(width: AppSpacing.lg),
            Expanded(
              child: _AuthField(label: 'Last name', controller: _lastNameController),
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.xl),
        _AuthField(
          label: AppLocalizations.of(context).authUsername,
          controller: _usernameController,
          trailingIcon: Icons.alternate_email,
        ),
        const SizedBox(height: AppSpacing.xl),
        _AuthField(
          label: AppLocalizations.of(context).authEmail,
          controller: _emailController,
          keyboardType: TextInputType.emailAddress,
          trailingIcon: Icons.mail_outline,
        ),
        const SizedBox(height: AppSpacing.xl),
        _AuthField(
          label: AppLocalizations.of(context).authPassword,
          controller: _signupPasswordController,
          obscured: _obscureSignupPassword,
          onToggleObscured: () => setState(() => _obscureSignupPassword = !_obscureSignupPassword),
        ),
        _PasswordStrengthBar(password: _signupPasswordController.text),
        const SizedBox(height: AppSpacing.xl),
        _AuthField(
          label: 'Confirm password',
          controller: _confirmPasswordController,
          obscured: _obscureConfirmPassword,
          onToggleObscured: () => setState(() => _obscureConfirmPassword = !_obscureConfirmPassword),
        ),
        const SizedBox(height: AppSpacing.x5l),
        _AuthSectionDivider(label: 'Personal details'),
        const SizedBox(height: AppSpacing.xl),
        _AuthField(
          label: AppLocalizations.of(context).authMobileNumber,
          controller: _phoneController,
          keyboardType: TextInputType.phone,
          trailingIcon: Icons.phone_outlined,
        ),
        const SizedBox(height: AppSpacing.xl),
        _AuthField(
          label: 'Alternate phone (optional)',
          controller: _altPhoneController,
          keyboardType: TextInputType.phone,
          trailingIcon: Icons.phone_outlined,
        ),
        const SizedBox(height: AppSpacing.xl),
        _AuthDateField(label: 'Date of birth', value: _dob, onTap: _pickDob),
        const SizedBox(height: AppSpacing.xl),
        _AuthGenderToggle(value: _gender, onChanged: (v) => setState(() => _gender = v)),
        const SizedBox(height: AppSpacing.xl),
        _AuthBloodGroupPicker(value: _bloodGroup, onChanged: (v) => setState(() => _bloodGroup = v)),
        const SizedBox(height: AppSpacing.xl),
        _AuthField(label: 'Guardian name', controller: _guardianNameController, trailingIcon: Icons.badge_outlined),
        const SizedBox(height: AppSpacing.x5l),
        _AuthSectionDivider(label: 'Address'),
        const SizedBox(height: AppSpacing.xl),
        _AuthField(label: 'Address line 1', controller: _addressLine1Controller),
        const SizedBox(height: AppSpacing.xl),
        _AuthField(label: 'Address line 2 (optional)', controller: _addressLine2Controller),
        const SizedBox(height: AppSpacing.xl),
        Row(
          children: [
            Expanded(child: _AuthField(label: 'City', controller: _cityController)),
            const SizedBox(width: AppSpacing.lg),
            Expanded(child: _AuthField(label: 'Pin code', controller: _pinCodeController, keyboardType: TextInputType.number)),
          ],
        ),
        const SizedBox(height: AppSpacing.xl),
        Row(
          children: [
            Expanded(child: _AuthField(label: 'District', controller: _districtController)),
            const SizedBox(width: AppSpacing.lg),
            Expanded(child: _AuthField(label: 'State', controller: _stateController)),
          ],
        ),
        const SizedBox(height: AppSpacing.x5l),
        AppPrimaryButton(
          label: AppLocalizations.of(context).authCreateAccount,
          icon: Icons.person_add_alt_1_rounded,
          busy: _isLoading,
          onPressed: _submitSignup,
        ),
      ],
    );
  }
}

void _showForgotPasswordSheet(BuildContext context) {
  showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (_) => const _ForgotPasswordSheet(),
  );
}

/// Two-step forgot-password flow, wired to the real backend: request a code (emailed to whatever
/// address is on file for the account), then verify that code and set a new password in one call.
/// Deliberately does not log the user in afterward - a reset revokes every session server-side, so
/// the natural next step is a normal login with the new password.
class _ForgotPasswordSheet extends ConsumerStatefulWidget {
  const _ForgotPasswordSheet();

  @override
  ConsumerState<_ForgotPasswordSheet> createState() => _ForgotPasswordSheetState();
}

enum _ForgotStage { request, reset }

class _ForgotPasswordSheetState extends ConsumerState<_ForgotPasswordSheet> {
  final _identifierController = TextEditingController();
  final _codeController = TextEditingController();
  final _newPasswordController = TextEditingController();
  final _confirmPasswordController = TextEditingController();
  _ForgotStage _stage = _ForgotStage.request;
  bool _isLoading = false;
  bool _obscureNewPassword = true;

  @override
  void dispose() {
    _identifierController.dispose();
    _codeController.dispose();
    _newPasswordController.dispose();
    _confirmPasswordController.dispose();
    super.dispose();
  }

  Future<void> _sendCode() async {
    final identifier = _identifierController.text.trim();
    if (identifier.isEmpty) {
      AppNotice.error(context, 'Enter your email or username.');
      return;
    }
    setState(() => _isLoading = true);
    try {
      await ref.read(sessionControllerProvider.notifier).forgotPassword(identifier);
      if (mounted) setState(() => _stage = _ForgotStage.reset);
    } on ApiException catch (e) {
      if (mounted) AppNotice.error(context, e.message);
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _resendCode() async {
    setState(() => _isLoading = true);
    try {
      await ref.read(sessionControllerProvider.notifier).forgotPassword(_identifierController.text.trim());
      if (mounted) AppNotice.success(context, 'A new code was sent.');
    } on ApiException catch (e) {
      if (mounted) AppNotice.error(context, e.message);
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _resetPassword() async {
    final code = _codeController.text.trim();
    final newPassword = _newPasswordController.text;
    if (code.isEmpty) {
      AppNotice.error(context, 'Enter the code we emailed you.');
      return;
    }
    if (newPassword.length < 6) {
      AppNotice.error(context, 'Password should be at least 6 characters.');
      return;
    }
    if (newPassword != _confirmPasswordController.text) {
      AppNotice.error(context, "Passwords don't match.");
      return;
    }
    setState(() => _isLoading = true);
    try {
      await ref.read(sessionControllerProvider.notifier).resetPassword(
            _identifierController.text.trim(),
            code,
            newPassword,
          );
      if (mounted) {
        Navigator.of(context).pop();
        AppNotice.success(context, 'Password reset - log in with your new password.');
      }
    } on ApiException catch (e) {
      if (mounted) AppNotice.error(context, e.message);
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: Container(
        decoration: BoxDecoration(color: palette.surface, borderRadius: AppRadii.sheetTop),
        padding: const EdgeInsets.fromLTRB(AppSpacing.x5l, AppSpacing.xl, AppSpacing.x5l, AppSpacing.x6l),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Center(
              child: Container(
                width: 40,
                height: 4,
                margin: const EdgeInsets.only(bottom: AppSpacing.x4l),
                decoration: BoxDecoration(color: palette.border, borderRadius: AppRadii.all(AppRadii.pill)),
              ),
            ),
            Text(
              _stage == _ForgotStage.request ? 'Reset password' : 'Enter your reset code',
              style: TextStyle(fontSize: AppType.title, fontWeight: AppType.heavy, color: palette.text),
            ),
            const SizedBox(height: AppSpacing.xs),
            Text(
              _stage == _ForgotStage.request
                  ? "Enter the email or username on your account and we'll email a reset code to the address on file."
                  : "Enter the code we emailed you, along with a new password.",
              style: TextStyle(fontSize: AppType.sm, color: palette.textMuted),
            ),
            const SizedBox(height: AppSpacing.x5l),
            if (_stage == _ForgotStage.request) ...[
              _AuthField(
                label: 'Email or Username',
                controller: _identifierController,
                autofocus: true,
                trailingIcon: Icons.mail_outline,
                textInputAction: TextInputAction.done,
                onSubmitted: (_) => _sendCode(),
              ),
              const SizedBox(height: AppSpacing.x5l),
              AppPrimaryButton(label: 'Send reset code', icon: Icons.send_rounded, busy: _isLoading, onPressed: _sendCode),
            ] else ...[
              _AuthField(
                label: '6-digit code',
                controller: _codeController,
                autofocus: true,
                keyboardType: TextInputType.number,
                trailingIcon: Icons.sms_outlined,
              ),
              const SizedBox(height: AppSpacing.xl),
              _AuthField(
                label: 'New password',
                controller: _newPasswordController,
                obscured: _obscureNewPassword,
                onToggleObscured: () => setState(() => _obscureNewPassword = !_obscureNewPassword),
              ),
              _PasswordStrengthBar(password: _newPasswordController.text),
              const SizedBox(height: AppSpacing.xl),
              _AuthField(
                label: 'Confirm new password',
                controller: _confirmPasswordController,
                obscured: _obscureNewPassword,
                textInputAction: TextInputAction.done,
                onSubmitted: (_) => _resetPassword(),
              ),
              const SizedBox(height: AppSpacing.sm),
              Align(
                alignment: Alignment.centerLeft,
                child: _AuthLink(label: 'Resend code', onTap: _isLoading ? null : _resendCode),
              ),
              const SizedBox(height: AppSpacing.xl),
              AppPrimaryButton(label: 'Reset password', icon: Icons.lock_reset_rounded, busy: _isLoading, onPressed: _resetPassword),
            ],
          ],
        ),
      ),
    );
  }
}

/// "Logging in as X - not you? Change" - shown once identify() resolves to a specific OTP-based
/// account, so the user isn't left wondering what they typed a moment ago.
class _IdentifierBanner extends StatelessWidget {
  const _IdentifierBanner({required this.label, required this.onChange});

  final String label;
  final VoidCallback onChange;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xl, vertical: AppSpacing.lg),
      decoration: BoxDecoration(
        color: palette.surfaceRaised,
        borderRadius: AppRadii.all(AppRadii.pill),
        border: Border.all(color: palette.borderSoft),
      ),
      child: Row(
        children: [
          Icon(Icons.account_circle_outlined, size: 18, color: palette.textMuted),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Text(
              label,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: AppType.md, fontWeight: AppType.semi, color: palette.text),
            ),
          ),
          _AuthLink(label: AppLocalizations.of(context).authChange, onTap: onChange),
        ],
      ),
    );
  }
}

/// A small text link in the primary accent - resend/change/forgot-password affordances that sit
/// beside or under a field rather than as a full-width button.
class _AuthLink extends StatelessWidget {
  const _AuthLink({required this.label, required this.onTap});

  final String label;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return TextButton(
      onPressed: onTap,
      style: TextButton.styleFrom(
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm, vertical: AppSpacing.xs),
        minimumSize: Size.zero,
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
      ),
      child: Text(
        label,
        style: TextStyle(fontSize: AppType.sm, fontWeight: AppType.bold, color: palette.primary),
      ),
    );
  }
}

/// A thin labelled hairline splitting the sign-up form into Identity / Personal details / Address,
/// so a long form still reads as a sequence of short ones.
class _AuthSectionDivider extends StatelessWidget {
  const _AuthSectionDivider({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return Row(
      children: [
        Text(
          label.toUpperCase(),
          style: TextStyle(fontSize: AppType.tiny, fontWeight: AppType.bold, color: palette.textFaint, letterSpacing: AppType.capsTracking),
        ),
        const SizedBox(width: AppSpacing.md),
        Expanded(child: Container(height: 1, color: palette.borderSoft)),
      ],
    );
  }
}

/// Rounded pill field matching the prototype's inputs: a soft-filled well that lifts and glows on
/// focus, with an optional right-aligned icon or a password visibility toggle.
class _AuthField extends StatefulWidget {
  const _AuthField({
    required this.label,
    required this.controller,
    this.autofocus = false,
    this.keyboardType,
    this.textInputAction,
    this.onSubmitted,
    this.trailingIcon,
    this.obscured,
    this.onToggleObscured,
  });

  final String label;
  final TextEditingController controller;
  final bool autofocus;
  final TextInputType? keyboardType;
  final TextInputAction? textInputAction;
  final ValueChanged<String>? onSubmitted;
  final IconData? trailingIcon;

  /// Non-null on a password field - drives the obscure state and shows the eye toggle instead of
  /// [trailingIcon].
  final bool? obscured;
  final VoidCallback? onToggleObscured;

  @override
  State<_AuthField> createState() => _AuthFieldState();
}

class _AuthFieldState extends State<_AuthField> {
  final _focusNode = FocusNode();
  bool _focused = false;

  @override
  void initState() {
    super.initState();
    _focusNode.addListener(() => setState(() => _focused = _focusNode.hasFocus));
  }

  @override
  void dispose() {
    _focusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final isPassword = widget.obscured != null;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(left: AppSpacing.xxs, bottom: AppSpacing.xs),
          child: Text(
            widget.label,
            style: TextStyle(fontSize: AppType.xs, fontWeight: AppType.bold, color: palette.textFaint),
          ),
        ),
        AnimatedContainer(
          duration: AppMotion.focus,
          curve: AppMotion.enter,
          decoration: BoxDecoration(
            color: _focused ? palette.surfaceHigh : palette.surfaceRaised,
            borderRadius: AppRadii.all(AppRadii.pill),
            border: Border.all(color: _focused ? palette.primary : palette.borderSoft, width: 1.5),
            boxShadow: _focused ? AppShadows.focusGlow(palette.primary) : null,
          ),
          child: TextField(
            controller: widget.controller,
            focusNode: _focusNode,
            autofocus: widget.autofocus,
            obscureText: isPassword && widget.obscured!,
            keyboardType: widget.keyboardType,
            textInputAction: widget.textInputAction,
            onSubmitted: widget.onSubmitted,
            style: TextStyle(fontSize: AppType.xl, fontWeight: AppType.semi, color: palette.text),
            decoration: InputDecoration(
              filled: false,
              border: InputBorder.none,
              focusedBorder: InputBorder.none,
              enabledBorder: InputBorder.none,
              isDense: true,
              contentPadding: const EdgeInsets.symmetric(horizontal: AppSpacing.x4l, vertical: AppSpacing.lg),
              suffixIcon: isPassword
                  ? IconButton(
                      icon: Icon(
                        widget.obscured! ? Icons.visibility_outlined : Icons.visibility_off_outlined,
                        size: 18,
                        color: _focused ? palette.primary : palette.textFaint,
                      ),
                      onPressed: widget.onToggleObscured,
                    )
                  : (widget.trailingIcon == null
                      ? null
                      : Padding(
                          padding: const EdgeInsets.only(right: AppSpacing.md),
                          child: Icon(widget.trailingIcon, size: 18, color: _focused ? palette.primary : palette.textFaint),
                        )),
            ),
          ),
        ),
      ],
    );
  }
}

/// Same pill shell as [_AuthField], but a tappable date display instead of a text field - opens
/// the app's own calendar dialog rather than a native date input.
class _AuthDateField extends StatelessWidget {
  const _AuthDateField({required this.label, required this.value, required this.onTap});

  final String label;
  final DateTime? value;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final text = value == null
        ? 'Select date'
        : '${value!.day.toString().padLeft(2, '0')}/${value!.month.toString().padLeft(2, '0')}/${value!.year}';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(left: AppSpacing.xxs, bottom: AppSpacing.xs),
          child: Text(label, style: TextStyle(fontSize: AppType.xs, fontWeight: AppType.bold, color: palette.textFaint)),
        ),
        Pressable(
          onTap: onTap,
          child: Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.x4l, vertical: AppSpacing.lg + 2),
            decoration: BoxDecoration(
              color: palette.surfaceRaised,
              borderRadius: AppRadii.all(AppRadii.pill),
              border: Border.all(color: palette.borderSoft, width: 1.5),
            ),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    text,
                    style: TextStyle(
                      fontSize: AppType.xl,
                      fontWeight: AppType.semi,
                      color: value == null ? palette.textFaint : palette.text,
                    ),
                  ),
                ),
                Icon(Icons.calendar_today_outlined, size: 16, color: palette.textFaint),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

/// Three-way Male/Female/Other segmented row for the sign-up form's gender field.
class _AuthGenderToggle extends StatelessWidget {
  const _AuthGenderToggle({required this.value, required this.onChanged});

  final String? value;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(left: AppSpacing.xxs, bottom: AppSpacing.xs),
          child: Text('Gender', style: TextStyle(fontSize: AppType.xs, fontWeight: AppType.bold, color: palette.textFaint)),
        ),
        Row(
          children: [
            for (final g in _kGenders) ...[
              if (g != _kGenders.first) const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: _AuthChip(label: g, selected: value == g, onTap: () => onChanged(g)),
              ),
            ],
          ],
        ),
      ],
    );
  }
}

/// Wrap of blood-group chips for the sign-up form.
class _AuthBloodGroupPicker extends StatelessWidget {
  const _AuthBloodGroupPicker({required this.value, required this.onChanged});

  final String? value;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(left: AppSpacing.xxs, bottom: AppSpacing.xs),
          child: Text('Blood group', style: TextStyle(fontSize: AppType.xs, fontWeight: AppType.bold, color: palette.textFaint)),
        ),
        Wrap(
          spacing: AppSpacing.sm,
          runSpacing: AppSpacing.sm,
          children: [
            for (final bg in _kBloodGroups) _AuthChip(label: bg, selected: value == bg, onTap: () => onChanged(bg)),
          ],
        ),
      ],
    );
  }
}

class _AuthChip extends StatelessWidget {
  const _AuthChip({required this.label, required this.selected, required this.onTap});

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return Pressable(
      onTap: onTap,
      child: AnimatedContainer(
        duration: AppMotion.fade,
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xl, vertical: AppSpacing.lg),
        decoration: BoxDecoration(
          color: selected ? palette.primarySoft : palette.surfaceRaised,
          borderRadius: AppRadii.all(AppRadii.pill),
          border: Border.all(color: selected ? palette.primary : palette.borderSoft, width: 1.5),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: AppType.md,
            fontWeight: AppType.bold,
            color: selected ? palette.primary : palette.textMuted,
          ),
        ),
      ),
    );
  }
}

/// Length + character-class heuristic, purely a client-side nudge - the backend is the actual
/// authority on whether a password is acceptable (6 characters minimum).
class _PasswordStrengthBar extends StatelessWidget {
  const _PasswordStrengthBar({required this.password});

  final String password;

  static int _scoreOf(String password) {
    var score = 0;
    if (password.length >= 6) score++;
    if (password.length >= 10) score++;
    if (RegExp(r'[A-Z]').hasMatch(password)) score++;
    if (RegExp(r'[0-9]').hasMatch(password)) score++;
    if (RegExp(r'[^A-Za-z0-9]').hasMatch(password)) score++;
    return score > 4 ? 4 : score;
  }

  @override
  Widget build(BuildContext context) {
    if (password.isEmpty) return const SizedBox.shrink();
    final palette = context.palette;
    final score = _scoreOf(password);
    final levels = [
      (label: 'Too short', color: palette.notPaid),
      (label: 'Weak', color: palette.notPaid),
      (label: 'Fair', color: palette.gold),
      (label: 'Good', color: palette.primary),
      (label: 'Strong', color: palette.primary),
    ];
    final level = levels[score];
    final pct = (score / 4).clamp(0.12, 1.0);

    return Padding(
      padding: const EdgeInsets.fromLTRB(AppSpacing.xxs, AppSpacing.sm, AppSpacing.xxs, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          LayoutBuilder(
            builder: (context, constraints) => Stack(
              children: [
                Container(
                  height: 6,
                  width: constraints.maxWidth,
                  decoration: BoxDecoration(color: palette.surfaceHigh, borderRadius: AppRadii.all(AppRadii.sm)),
                ),
                AnimatedContainer(
                  duration: AppMotion.progress,
                  curve: AppMotion.enter,
                  height: 6,
                  width: constraints.maxWidth * pct,
                  decoration: BoxDecoration(color: level.color, borderRadius: AppRadii.all(AppRadii.sm)),
                ),
              ],
            ),
          ),
          const SizedBox(height: AppSpacing.xs),
          Text(level.label, style: TextStyle(fontSize: AppType.tiny, fontWeight: AppType.bold, color: level.color)),
        ],
      ),
    );
  }
}

/// The owl mark with a slow breathing scale and a pulsing gold halo behind it - the one bit of
/// ambient motion the prototype's auth screen has, ported with Flutter's own animation
/// primitives rather than the CSS keyframes it was built with.
class _AuthLogo extends StatefulWidget {
  const _AuthLogo();

  @override
  State<_AuthLogo> createState() => _AuthLogoState();
}

class _AuthLogoState extends State<_AuthLogo> with TickerProviderStateMixin {
  late final AnimationController _pulse = AnimationController(vsync: this, duration: const Duration(milliseconds: 2400))..repeat();
  late final AnimationController _breathe = AnimationController(vsync: this, duration: const Duration(milliseconds: 3600))..repeat(reverse: true);

  @override
  void dispose() {
    _pulse.dispose();
    _breathe.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return SizedBox(
      width: 120,
      height: 120,
      child: Stack(
        alignment: Alignment.center,
        children: [
          AnimatedBuilder(
            animation: _pulse,
            builder: (context, _) {
              final t = _pulse.value;
              return Opacity(
                opacity: (0.55 * (1 - t)).clamp(0.0, 1.0),
                child: Transform.scale(
                  scale: 0.9 + 0.65 * t,
                  child: Container(
                    width: 88,
                    height: 88,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      gradient: RadialGradient(colors: [palette.gold, palette.gold.withValues(alpha: 0)]),
                    ),
                  ),
                ),
              );
            },
          ),
          ScaleTransition(
            scale: Tween(begin: 1.0, end: 1.035).animate(CurvedAnimation(parent: _breathe, curve: Curves.easeInOut)),
            child: Container(
              width: 74,
              height: 74,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(color: palette.gold, width: 2),
                boxShadow: [BoxShadow(color: palette.gold.withValues(alpha: 0.35), blurRadius: 22, offset: const Offset(0, 8))],
              ),
              child: const ClipOval(
                child: Image(image: AssetImage('assets/brand/owl_icon.png'), fit: BoxFit.cover),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Soft, slow-drifting glow orbs plus a handful of twinkling points behind the form - the
/// "dusk nest" backdrop from the prototype, built from plain radial gradients rather than a blur
/// filter so it stays cheap to animate.
class _AuthGlowBackground extends StatefulWidget {
  const _AuthGlowBackground();

  @override
  State<_AuthGlowBackground> createState() => _AuthGlowBackgroundState();
}

class _AuthGlowBackgroundState extends State<_AuthGlowBackground> with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(vsync: this, duration: const Duration(seconds: 8))..repeat();

  static const _twinkles = [
    (top: 0.16, left: 0.14, phase: 0.0),
    (top: 0.28, left: 0.82, phase: 1.1),
    (top: 0.58, left: 0.10, phase: 2.3),
    (top: 0.70, left: 0.78, phase: 0.6),
    (top: 0.45, left: 0.50, phase: 1.7),
  ];

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final twinkleColors = [palette.gold, palette.primary, palette.primary, palette.gold, palette.violet];

    return IgnorePointer(
      child: ClipRect(
        child: AnimatedBuilder(
          animation: _controller,
          builder: (context, _) {
            final t = _controller.value;
            final angle = t * 2 * pi;
            final size = MediaQuery.sizeOf(context);
            return Stack(
              children: [
                _orb(top: -70 + 12 * sin(angle), left: -70 + 12 * cos(angle), size: 260, color: palette.primary.withValues(alpha: 0.24)),
                _orb(
                  bottom: -50 + 10 * cos(angle + 1.2),
                  right: -60 + 10 * sin(angle + 1.2),
                  size: 220,
                  color: palette.gold.withValues(alpha: 0.2),
                ),
                _orb(
                  top: size.height * 0.32 + 8 * sin(angle + 0.6),
                  right: -50,
                  size: 160,
                  color: palette.violet.withValues(alpha: 0.16),
                ),
                for (var i = 0; i < _twinkles.length; i++) _twinkle(size, _twinkles[i], twinkleColors[i], t),
              ],
            );
          },
        ),
      ),
    );
  }

  Widget _orb({double? top, double? bottom, double? left, double? right, required double size, required Color color}) {
    return Positioned(
      top: top,
      bottom: bottom,
      left: left,
      right: right,
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(shape: BoxShape.circle, gradient: RadialGradient(colors: [color, color.withValues(alpha: 0)])),
      ),
    );
  }

  Widget _twinkle(Size screenSize, ({double top, double left, double phase}) f, Color color, double t) {
    final opacity = 0.25 + 0.75 * ((sin((t * 2 * pi) + f.phase * pi) + 1) / 2);
    return Positioned(
      top: screenSize.height * f.top,
      left: screenSize.width * f.left,
      child: Opacity(
        opacity: opacity.clamp(0.0, 1.0),
        child: Container(
          width: 4,
          height: 4,
          decoration: BoxDecoration(shape: BoxShape.circle, color: color, boxShadow: [BoxShadow(color: color, blurRadius: 6)]),
        ),
      ),
    );
  }
}

/// Cycles System -> Light -> Dark, the same per-account preference already synced by
/// [ThemeModeController], just reachable from the auth screen before anyone's signed in yet.
class _ThemeToggleButton extends ConsumerWidget {
  const _ThemeToggleButton();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final mode = ref.watch(themeModeProvider);
    final icon = switch (mode) {
      ThemeMode.light => Icons.light_mode_outlined,
      ThemeMode.dark => Icons.dark_mode_outlined,
      ThemeMode.system => Icons.brightness_auto_outlined,
    };
    return AppIconButton(
      icon: icon,
      tooltip: 'Theme: ${mode.name}',
      onTap: () {
        final next = switch (mode) {
          ThemeMode.system => ThemeMode.light,
          ThemeMode.light => ThemeMode.dark,
          ThemeMode.dark => ThemeMode.system,
        };
        ref.read(themeModeProvider.notifier).setThemeMode(next);
      },
    );
  }
}
