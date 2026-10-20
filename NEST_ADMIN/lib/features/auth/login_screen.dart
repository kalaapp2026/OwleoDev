import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/theme.dart';
import '../../core/auth/session.dart';
import '../../core/ui/controls.dart';
import '../../core/ui/icons.dart';

/// Same accounts and same server as the academy app: a platform owner signs in here with the
/// username and password they already have. Anyone else is turned away with a clear message.
class LoginScreen extends ConsumerStatefulWidget {
  const LoginScreen({super.key});

  @override
  ConsumerState<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends ConsumerState<LoginScreen> {
  final _user = TextEditingController();
  final _pass = TextEditingController();
  bool _busy = false;
  bool _show = false;
  String? _error;

  @override
  void dispose() {
    _user.dispose();
    _pass.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_busy) return;
    if (_user.text.trim().isEmpty || _pass.text.isEmpty) {
      setState(() => _error = 'Enter your username and password.');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    final err = await ref.read(sessionProvider.notifier).login(_user.text, _pass.text);
    if (!mounted) return;
    // On success the router redirects away; only a failure needs to stay and explain itself.
    setState(() {
      _busy = false;
      _error = err;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Hq.bg,
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 400),
            child: AutofillGroup(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Center(
                    child: Container(
                      width: 84,
                      height: 84,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        border: Border.all(color: Hq.gold, width: 2),
                        boxShadow: [BoxShadow(color: Hq.gold.withValues(alpha: .3), blurRadius: 28, offset: const Offset(0, 8))],
                      ),
                      clipBehavior: Clip.antiAlias,
                      child: Image.asset('assets/brand/logo_full.jpg', fit: BoxFit.cover),
                    ),
                  ),
                  const SizedBox(height: 22),
                  Text('Owleo HQ', textAlign: TextAlign.center, style: HqText.h1.copyWith(fontSize: 26)),
                  const SizedBox(height: 4),
                  Text('Sign in to the platform console', textAlign: TextAlign.center, style: HqText.muted),
                  const SizedBox(height: 26),
                  Container(
                    padding: const EdgeInsets.all(22),
                    decoration: BoxDecoration(
                      color: Hq.surface,
                      borderRadius: BorderRadius.circular(22),
                      border: Border.all(color: Hq.border),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        HqField(
                          label: 'Username',
                          controller: _user,
                          autofocus: true,
                          hint: 'Your Owleo username',
                          onSubmitted: (_) => FocusScope.of(context).nextFocus(),
                        ),
                        HqField(
                          label: 'Password',
                          controller: _pass,
                          obscure: !_show,
                          hint: 'Password',
                          onSubmitted: (_) => _submit(),
                          suffix: IconButton(
                            onPressed: () => setState(() => _show = !_show),
                            icon: ic(_show ? 'eye' : 'lock', 16, Hq.muted),
                            tooltip: _show ? 'Hide password' : 'Show password',
                          ),
                        ),
                        if (_error != null)
                          Padding(
                            padding: const EdgeInsets.only(bottom: 12),
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                ic('warn', 15, Hq.red),
                                const SizedBox(width: 8),
                                Expanded(child: Text(_error!, style: HqText.small.copyWith(color: Hq.red, fontSize: 12.5))),
                              ],
                            ),
                          ),
                        HqButton('Sign in', kind: BtnKind.primary, expand: true, busy: _busy, onPressed: _submit),
                      ],
                    ),
                  ),
                  const SizedBox(height: 18),
                  Text('For Owleo staff only. Academy owners, trainers and students use the Owleo Nest app.',
                      textAlign: TextAlign.center, style: HqText.sub),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Shown while the stored session is being checked on a page reload.
class SplashScreen extends StatelessWidget {
  const SplashScreen({super.key});

  @override
  Widget build(BuildContext context) => const Scaffold(
        backgroundColor: Hq.bg,
        body: Center(child: SizedBox(width: 28, height: 28, child: CircularProgressIndicator(strokeWidth: 2.5, color: Hq.primary))),
      );
}
