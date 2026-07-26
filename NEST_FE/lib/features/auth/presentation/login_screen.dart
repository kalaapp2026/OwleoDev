import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:nest_fe/core/auth/session_controller.dart';
import 'package:nest_fe/core/error/api_exception.dart';
import 'package:nest_fe/core/widgets/app_notice.dart';
import 'package:nest_fe/core/widgets/owleo_wordmark.dart';
import 'package:nest_fe/features/auth/data/auth_api.dart';

enum _Stage { identify, password, otp }

/// Single unified login flow: one identifier (username or mobile number), and the backend - not
/// the user - decides whether the next step is a password or an OTP. No manual "Admin/Trainer vs
/// Student/Guest" choice.
class LoginScreen extends ConsumerStatefulWidget {
  const LoginScreen({super.key});

  @override
  ConsumerState<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends ConsumerState<LoginScreen> {
  final _identifierController = TextEditingController();
  final _passwordController = TextEditingController();
  final _codeController = TextEditingController();

  _Stage _stage = _Stage.identify;
  String? _resolvedUsername;
  String? _maskedPhone;
  bool _isLoading = false;
  bool _obscurePassword = true;

  @override
  void dispose() {
    _identifierController.dispose();
    _passwordController.dispose();
    _codeController.dispose();
    super.dispose();
  }

  String get _identifier => _identifierController.text.trim();

  Future<void> _identify() async {
    if (_identifier.isEmpty) return;
    setState(() => _isLoading = true);
    try {
      final result = await ref.read(sessionControllerProvider.notifier).identify(_identifier);
      setState(() {
        _resolvedUsername = result.username;
        _maskedPhone = result.maskedPhone;
        _stage = result.authMethod == AuthMethod.password ? _Stage.password : _Stage.otp;
      });
    } on ApiException catch (e) {
      if (mounted) AppNotice.error(context, e.message);
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _submitPassword() async {
    setState(() => _isLoading = true);
    try {
      await ref.read(sessionControllerProvider.notifier).loginWithPassword(
            _resolvedUsername ?? _identifier,
            _passwordController.text,
          );
    } on ApiException catch (e) {
      if (mounted) AppNotice.error(context, e.message);
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _resendOtp() async {
    setState(() => _isLoading = true);
    try {
      await ref.read(sessionControllerProvider.notifier).resendOtp(_identifier);
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
            _identifier,
            _codeController.text.trim(),
          );
    } on ApiException catch (e) {
      if (mounted) AppNotice.error(context, e.message);
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _startOver() {
    setState(() {
      _stage = _Stage.identify;
      _resolvedUsername = null;
      _maskedPhone = null;
      _passwordController.clear();
      _codeController.clear();
    });
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: _stage == _Stage.identify,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _startOver();
      },
      child: Scaffold(
        body: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 420),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const SizedBox(height: 24),
                    const Center(child: OwleoWordmark(size: OwleoWordmarkSize.large)),
                    const SizedBox(height: 8),
                    Center(
                      child: Text(
                        'Your business. Organized. Automated.',
                        style: Theme.of(context).textTheme.bodyMedium,
                        textAlign: TextAlign.center,
                      ),
                    ),
                    const SizedBox(height: 40),
                    AnimatedSwitcher(
                      duration: const Duration(milliseconds: 200),
                      child: switch (_stage) {
                        _Stage.identify => _buildIdentifyStep(),
                        _Stage.password => _buildPasswordStep(),
                        _Stage.otp => _buildOtpStep(),
                      },
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildIdentifyStep() {
    return Column(
      key: const ValueKey('identify'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        TextField(
          controller: _identifierController,
          autofocus: true,
          decoration: const InputDecoration(
            labelText: 'Username or mobile number',
            prefixIcon: Icon(Icons.person_outline),
          ),
          textInputAction: TextInputAction.done,
          onSubmitted: (_) => _identify(),
        ),
        const SizedBox(height: 22),
        ElevatedButton(
          onPressed: _isLoading ? null : _identify,
          child: _isLoading
              ? const SizedBox(height: 18, width: 18, child: CircularProgressIndicator(strokeWidth: 2))
              : const Text('Continue'),
        ),
        const SizedBox(height: 12),
        Center(
          child: TextButton(
            onPressed: _isLoading ? null : () => context.push('/signup'),
            child: const Text('Create account'),
          ),
        ),
      ],
    );
  }

  Widget _buildPasswordStep() {
    return Column(
      key: const ValueKey('password'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _IdentifierBanner(label: _resolvedUsername ?? _identifier, onChange: _startOver),
        const SizedBox(height: 16),
        TextField(
          controller: _passwordController,
          autofocus: true,
          obscureText: _obscurePassword,
          decoration: InputDecoration(
            labelText: 'Password',
            prefixIcon: const Icon(Icons.lock_outline),
            suffixIcon: IconButton(
              icon: Icon(_obscurePassword ? Icons.visibility_outlined : Icons.visibility_off_outlined),
              onPressed: () => setState(() => _obscurePassword = !_obscurePassword),
            ),
          ),
          onSubmitted: (_) => _submitPassword(),
        ),
        const SizedBox(height: 22),
        ElevatedButton(
          onPressed: _isLoading ? null : _submitPassword,
          child: _isLoading
              ? const SizedBox(height: 18, width: 18, child: CircularProgressIndicator(strokeWidth: 2))
              : const Text('Log in'),
        ),
      ],
    );
  }

  Widget _buildOtpStep() {
    return Column(
      key: const ValueKey('otp'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _IdentifierBanner(label: _resolvedUsername ?? _identifier, onChange: _startOver),
        const SizedBox(height: 8),
        Text(
          _maskedPhone == null ? 'A code was sent to your registered mobile number.' : 'A code was sent to $_maskedPhone.',
          style: Theme.of(context).textTheme.bodySmall,
        ),
        const SizedBox(height: 16),
        TextField(
          controller: _codeController,
          autofocus: true,
          keyboardType: TextInputType.number,
          decoration: const InputDecoration(labelText: '6-digit code', prefixIcon: Icon(Icons.sms_outlined)),
          onSubmitted: (_) => _submitOtp(),
        ),
        const SizedBox(height: 6),
        Align(
          alignment: Alignment.centerLeft,
          child: TextButton(onPressed: _isLoading ? null : _resendOtp, child: const Text('Resend code')),
        ),
        const SizedBox(height: 16),
        ElevatedButton(
          onPressed: _isLoading ? null : _submitOtp,
          child: _isLoading
              ? const SizedBox(height: 18, width: 18, child: CircularProgressIndicator(strokeWidth: 2))
              : const Text('Verify & log in'),
        ),
      ],
    );
  }
}

/// "Logging in as X - not you? Change" - shown once the identifier step resolves to a specific
/// account, so the user isn't left wondering what they typed a moment ago.
class _IdentifierBanner extends StatelessWidget {
  const _IdentifierBanner({required this.label, required this.onChange});

  final String label;
  final VoidCallback onChange;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(Icons.account_circle_outlined, size: 18, color: Theme.of(context).colorScheme.onSurfaceVariant),
        const SizedBox(width: 8),
        Expanded(
          child: Text(label, overflow: TextOverflow.ellipsis, style: Theme.of(context).textTheme.bodyMedium),
        ),
        TextButton(onPressed: onChange, child: const Text('Change')),
      ],
    );
  }
}
