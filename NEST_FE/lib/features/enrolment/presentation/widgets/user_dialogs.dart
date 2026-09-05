import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:nest_fe/app/theme/app_tokens.dart';
import 'package:nest_fe/app/theme/app_typography.dart';
import 'package:nest_fe/core/design/avatar.dart';
import 'package:nest_fe/core/design/buttons.dart';
import 'package:nest_fe/core/design/pressable.dart';
import 'package:nest_fe/core/design/toast.dart';
import 'package:url_launcher/url_launcher.dart';

/// Hands over a newly created account's login details.
///
/// A dialog rather than a toast, and modal rather than a row on the list, because this is the one
/// and only moment the temporary password exists in readable form - the server stores a hash, so
/// dismissing this without noting it down means a password reset. Copy and share are the whole
/// point of the screen; "Done" is deliberately the quietest control on it.
Future<void> showCredentialsHandoff(
  BuildContext context, {
  required String fullName,
  required String username,
  required String temporaryPassword,
  String? phone,
  String title = 'Account created',
}) {
  return showDialog(
    context: context,
    barrierColor: const Color(0xB8040710),
    builder: (context) => _CredentialsDialog(
      fullName: fullName,
      username: username,
      temporaryPassword: temporaryPassword,
      phone: phone,
      title: title,
    ),
  );
}

class _CredentialsDialog extends StatelessWidget {
  const _CredentialsDialog({
    required this.fullName,
    required this.username,
    required this.temporaryPassword,
    required this.phone,
    required this.title,
  });

  final String fullName;
  final String username;
  final String temporaryPassword;
  final String? phone;
  final String title;

  String get _message =>
      'Hi $fullName, your NEST account is ready.\n\n'
      'Username: $username\n'
      'Temporary password: $temporaryPassword\n\n'
      'Please change your password when you first sign in.';

  /// Digits only - wa.me and the sms: scheme both reject the spaces and the leading + that the
  /// stored number carries.
  String get _dialDigits => (phone ?? '').replaceAll(RegExp(r'[^0-9]'), '');

  Future<void> _share(BuildContext context, {required bool whatsapp}) async {
    final digits = _dialDigits;
    final encoded = Uri.encodeComponent(_message);
    final uri = whatsapp
        ? Uri.parse('https://wa.me/$digits?text=$encoded')
        // `?body=` is the form both Android and iOS accept; `&` here would be read as another
        // recipient on some Android dialers.
        : Uri.parse('sms:$digits?body=$encoded');

    final launched = await launchUrl(uri, mode: LaunchMode.externalApplication);
    if (!launched && context.mounted) {
      await Clipboard.setData(ClipboardData(text: _message));
      if (context.mounted) {
        showAppToast(context, "Couldn't open that app - details copied instead.");
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final canMessage = _dialDigits.length >= 8;

    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.all(AppSpacing.x5l),
      child: Container(
        constraints: const BoxConstraints(maxWidth: 400),
        padding: const EdgeInsets.all(AppSpacing.x5l),
        decoration: BoxDecoration(
          color: palette.surface,
          borderRadius: AppRadii.all(AppRadii.sheet),
          border: Border.all(color: palette.border),
          boxShadow: AppShadows.dropdown,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Container(
                  height: 40,
                  width: 40,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: palette.paidManualSoft,
                    shape: BoxShape.circle,
                  ),
                  child: Icon(Icons.check_rounded, size: 22, color: palette.paidManual),
                ),
                const SizedBox(width: AppSpacing.lg),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(title,
                          style: TextStyle(
                              fontSize: AppType.title,
                              fontWeight: AppType.bold,
                              letterSpacing: AppType.titleTracking,
                              color: palette.text)),
                      const SizedBox(height: 2),
                      Text(fullName,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                              fontSize: AppType.smd, color: palette.textMuted)),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.x4l),
            _CredentialField(label: 'Username', value: username),
            const SizedBox(height: AppSpacing.md),
            _CredentialField(label: 'Temporary password', value: temporaryPassword, mono: true),
            const SizedBox(height: AppSpacing.xl),
            Container(
              padding: const EdgeInsets.all(AppSpacing.lg),
              decoration: BoxDecoration(
                color: palette.goldSoft,
                borderRadius: AppRadii.all(AppRadii.lg),
                border: Border.all(color: palette.gold.withValues(alpha: 0.25)),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(Icons.lock_clock_outlined, size: 14, color: palette.gold),
                  const SizedBox(width: AppSpacing.sm),
                  Expanded(
                    child: Text(
                      'This password is shown once. If it is lost, reset it from the '
                      'user list - it cannot be read back.',
                      style: TextStyle(
                          fontSize: AppType.sm, color: palette.textMuted, height: 1.45),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: AppSpacing.x4l),
            Row(
              children: [
                Expanded(
                  child: _ShareButton(
                    label: 'WhatsApp',
                    icon: Icons.chat_bubble_outline,
                    accent: palette.paidManual,
                    onTap: canMessage ? () => _share(context, whatsapp: true) : null,
                  ),
                ),
                const SizedBox(width: AppSpacing.md),
                Expanded(
                  child: _ShareButton(
                    label: 'SMS',
                    icon: Icons.sms_outlined,
                    accent: palette.gateway,
                    onTap: canMessage ? () => _share(context, whatsapp: false) : null,
                  ),
                ),
                const SizedBox(width: AppSpacing.md),
                Expanded(
                  child: _ShareButton(
                    label: 'Copy all',
                    icon: Icons.copy_all_outlined,
                    accent: palette.primary,
                    onTap: () {
                      Clipboard.setData(ClipboardData(text: _message));
                      showAppToast(context, 'Login details copied.');
                    },
                  ),
                ),
              ],
            ),
            if (!canMessage) ...[
              const SizedBox(height: AppSpacing.sm),
              Text('No phone number on file, so the message options are off.',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: AppType.sm, color: palette.textFaint)),
            ],
            const SizedBox(height: AppSpacing.xl),
            AppPrimaryButton(
              label: 'Done',
              onPressed: () => Navigator.of(context).pop(),
            ),
          ],
        ),
      ),
    );
  }
}

class _CredentialField extends StatelessWidget {
  const _CredentialField({required this.label, required this.value, this.mono = false});

  final String label;
  final String value;
  final bool mono;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return Container(
      padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.xl, vertical: AppSpacing.lg),
      decoration: BoxDecoration(
        color: palette.surfaceRaised,
        borderRadius: AppRadii.all(AppRadii.lg),
        border: Border.all(color: palette.border),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(label.toUpperCase(),
                    style: AppType.sectionLabel(palette.textFaint)),
                const SizedBox(height: 3),
                SelectableText(
                  value,
                  style: TextStyle(
                    fontSize: AppType.display,
                    fontWeight: AppType.bold,
                    color: palette.text,
                    // The temp password mixes l/1/O/0 - a proportional face makes those
                    // indistinguishable to whoever is reading it out loud.
                    fontFamily: mono ? 'monospace' : null,
                    letterSpacing: mono ? 0.6 : null,
                  ),
                ),
              ],
            ),
          ),
          Pressable(
            onTap: () {
              Clipboard.setData(ClipboardData(text: value));
              showAppToast(context, '$label copied.');
            },
            child: Padding(
              padding: const EdgeInsets.all(AppSpacing.xs),
              child: Icon(Icons.copy_outlined, size: 16, color: palette.primary),
            ),
          ),
        ],
      ),
    );
  }
}

class _ShareButton extends StatelessWidget {
  const _ShareButton({
    required this.label,
    required this.icon,
    required this.accent,
    required this.onTap,
  });

  final String label;
  final IconData icon;
  final Color accent;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final enabled = onTap != null;
    return Opacity(
      opacity: enabled ? 1 : 0.4,
      child: Pressable(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: AppSpacing.lg),
          decoration: BoxDecoration(
            color: palette.surfaceRaised,
            borderRadius: AppRadii.all(AppRadii.lg),
            border: Border.all(color: accent.withValues(alpha: 0.3)),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 17, color: accent),
              const SizedBox(height: AppSpacing.xs),
              Text(label,
                  style: TextStyle(
                      fontSize: AppType.sm,
                      fontWeight: AppType.bold,
                      color: palette.textMuted)),
            ],
          ),
        ),
      ),
    );
  }
}

/// Asks for the code sent to an existing NEST user's Notifications tab.
///
/// This appears when the email typed into the form already belongs to a NEST account - a student
/// at another academy, say. No duplicate account is created and nothing is granted until that
/// person reads their code back, which is what makes this a consent step rather than a formality:
/// an academy must not be able to add someone to its roster unilaterally.
///
/// Returns the entered code, or null if dismissed.
Future<String?> showExistingAccountConfirm(
  BuildContext context, {
  required String fullName,
  required String roleNoun,
  required Future<String?> Function(String code) onSubmit,
}) {
  return showDialog<String>(
    context: context,
    barrierDismissible: false,
    barrierColor: const Color(0xB8040710),
    builder: (context) => _ConfirmCodeDialog(
      fullName: fullName,
      roleNoun: roleNoun,
      onSubmit: onSubmit,
    ),
  );
}

class _ConfirmCodeDialog extends StatefulWidget {
  const _ConfirmCodeDialog({
    required this.fullName,
    required this.roleNoun,
    required this.onSubmit,
  });

  final String fullName;
  final String roleNoun;

  /// Returns an error message to show inline, or null on success (which closes the dialog).
  final Future<String?> Function(String code) onSubmit;

  @override
  State<_ConfirmCodeDialog> createState() => _ConfirmCodeDialogState();
}

class _ConfirmCodeDialogState extends State<_ConfirmCodeDialog> {
  final _controller = TextEditingController();
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final code = _controller.text.trim();
    if (code.isEmpty) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    final error = await widget.onSubmit(code);
    if (!mounted) return;
    if (error == null) {
      Navigator.of(context).pop(code);
    } else {
      setState(() {
        _busy = false;
        _error = error;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.all(AppSpacing.x5l),
      child: Container(
        constraints: const BoxConstraints(maxWidth: 380),
        padding: const EdgeInsets.all(AppSpacing.x5l),
        decoration: BoxDecoration(
          color: palette.surface,
          borderRadius: AppRadii.all(AppRadii.sheet),
          border: Border.all(color: palette.border),
          boxShadow: AppShadows.dropdown,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                PersonAvatar(name: widget.fullName, seed: widget.fullName, size: 40),
                const SizedBox(width: AppSpacing.lg),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text('Already on NEST',
                          style: TextStyle(
                              fontSize: AppType.title,
                              fontWeight: AppType.bold,
                              letterSpacing: AppType.titleTracking,
                              color: palette.text)),
                      const SizedBox(height: 2),
                      Text(widget.fullName,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                              fontSize: AppType.smd, color: palette.textMuted)),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.x4l),
            Text(
              'This email already has a NEST account, so no new one was created. '
              'A code was sent to their Notifications tab - ask them to read it out to '
              'confirm they agree to join as a ${widget.roleNoun}.',
              style: TextStyle(
                  fontSize: AppType.md, color: palette.textMuted, height: 1.5),
            ),
            const SizedBox(height: AppSpacing.x4l),
            TextField(
              controller: _controller,
              autofocus: true,
              keyboardType: TextInputType.number,
              textAlign: TextAlign.center,
              onSubmitted: (_) => _submit(),
              style: TextStyle(
                fontSize: 26,
                fontWeight: AppType.bold,
                letterSpacing: 8,
                color: palette.text,
              ),
              decoration: InputDecoration(
                isDense: true,
                hintText: '······',
                hintStyle: TextStyle(
                    fontSize: 26, letterSpacing: 8, color: palette.textFaint),
                filled: true,
                fillColor: palette.surfaceRaised,
                contentPadding: const EdgeInsets.symmetric(vertical: AppSpacing.xl),
                border: OutlineInputBorder(
                  borderRadius: AppRadii.all(AppRadii.lg),
                  borderSide: BorderSide(color: palette.border),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: AppRadii.all(AppRadii.lg),
                  borderSide: BorderSide(
                      color: _error == null ? palette.border : palette.notPaid),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: AppRadii.all(AppRadii.lg),
                  borderSide: BorderSide(color: palette.primary),
                ),
              ),
            ),
            if (_error != null) ...[
              const SizedBox(height: AppSpacing.sm),
              Text(_error!,
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: AppType.sm, color: palette.notPaid)),
            ],
            const SizedBox(height: AppSpacing.x4l),
            AppPrimaryButton(
              label: 'Confirm',
              icon: Icons.check,
              busy: _busy,
              onPressed: _submit,
            ),
            const SizedBox(height: AppSpacing.sm),
            Center(
              child: Pressable(
                onTap: () => Navigator.of(context).pop(),
                child: Padding(
                  padding: const EdgeInsets.all(AppSpacing.sm),
                  child: Text('Not now',
                      style: TextStyle(
                          fontSize: AppType.md,
                          fontWeight: AppType.medium,
                          color: palette.textMuted)),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
