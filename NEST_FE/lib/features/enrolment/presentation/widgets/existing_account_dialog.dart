import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:nest_fe/app/theme/app_tokens.dart';
import 'package:nest_fe/app/theme/app_typography.dart';
import 'package:nest_fe/core/design/pressable.dart';
import 'package:nest_fe/features/enrolment/data/enrolment_api.dart';

/// The result of checking a typed code: the unlocked profile, or the reason it was refused.
typedef OtpVerifyResult = ({ExistingAccountProfile? profile, String? error});

/// Shown when the email being registered already has an Owleo account.
///
/// A code is sent to that person's own notifications as the dialog opens; the creator types what
/// they read out into six boxes and, on a match, the dialog confirms and closes with the person's
/// saved details so the form can be filled from them. "Enter manually" closes it with null and the
/// creator carries on filling the form themselves.
///
/// [maskedName] is deliberately not the full name: nothing about the account is disclosed to the
/// creator until the person has agreed, and the code is what proves they have.
Future<ExistingAccountProfile?> showExistingAccountOtp(
  BuildContext context, {
  required String maskedName,
  required Future<String?> Function() onSend,
  required Future<OtpVerifyResult> Function(String code) onVerify,
}) {
  return showDialog<ExistingAccountProfile>(
    context: context,
    barrierDismissible: false,
    barrierColor: const Color(0xB8040710),
    builder: (context) => _ExistingAccountDialog(
      maskedName: maskedName,
      onSend: onSend,
      onVerify: onVerify,
    ),
  );
}

enum _Stage { entering, verifying, incorrect, verified }

class _ExistingAccountDialog extends StatefulWidget {
  const _ExistingAccountDialog({
    required this.maskedName,
    required this.onSend,
    required this.onVerify,
  });

  final String maskedName;

  /// Posts the code to the person; returns an error message, or null when it was sent.
  final Future<String?> Function() onSend;
  final Future<OtpVerifyResult> Function(String code) onVerify;

  @override
  State<_ExistingAccountDialog> createState() => _ExistingAccountDialogState();
}

class _ExistingAccountDialogState extends State<_ExistingAccountDialog> {
  static const _length = 6;

  // Timings. Deliberately unhurried - this is a moment of trust (someone confirming it is really
  // them), and a dialog that snaps from one state to the next reads as broken rather than fast.
  static const _verifyingFor = Duration(milliseconds: 1100);
  static const _verifiedFor = Duration(milliseconds: 2000);
  static const _swap = Duration(milliseconds: 450);
  static const _boxFade = Duration(milliseconds: 260);
  static const _shakeFor = Duration(milliseconds: 650);

  /// Bumped on every wrong code so the shake restarts even when the boxes look the same.
  int _shakes = 0;

  final _controller = TextEditingController();
  final _focus = FocusNode();

  _Stage _stage = _Stage.entering;
  String? _error;
  String? _note;
  bool _sending = false;
  String _firstName = '';

  @override
  void initState() {
    super.initState();
    // The code goes out as the dialog opens - the creator should be able to ask for it straight away.
    WidgetsBinding.instance.addPostFrameCallback((_) => _send());
  }

  @override
  void dispose() {
    _controller.dispose();
    _focus.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    if (_sending) return;
    setState(() {
      _sending = true;
      _note = null;
      _error = null;
    });
    final error = await widget.onSend();
    if (!mounted) return;
    setState(() {
      _sending = false;
      if (error == null) {
        _note = 'Code sent to their registered login.';
      } else {
        _error = error;
      }
    });
  }

  Future<void> _verify() async {
    final code = _controller.text;
    if (code.length != _length) return;
    setState(() {
      _stage = _Stage.verifying;
      _error = null;
    });
    // The check itself is usually instant, which made "verifying" a flicker nobody could read. Hold
    // it for a beat so the spinners register and the result lands as an event, not a glitch.
    final results = await Future.wait<Object?>([
      widget.onVerify(code),
      Future<void>.delayed(_verifyingFor),
    ]);
    final result = results.first! as OtpVerifyResult;
    if (!mounted) return;
    final profile = result.profile;
    if (profile != null) {
      setState(() {
        _stage = _Stage.verified;
        _firstName = profile.fullName.trim().split(RegExp(r'\s+')).first;
      });
      // Long enough to read "Verified" and watch the check settle before the form fills in.
      await Future<void>.delayed(_verifiedFor);
      if (mounted) Navigator.of(context).pop(profile);
    } else {
      setState(() {
        _stage = _Stage.incorrect;
        _error = result.error ?? 'Incorrect code.';
        _shakes++;
      });
    }
  }

  void _retry() {
    _controller.clear();
    setState(() {
      _stage = _Stage.entering;
      _error = null;
    });
    _focus.requestFocus();
  }

  String get _initials {
    final letters = widget.maskedName
        .split(RegExp(r'\s+'))
        .where((w) => w.isNotEmpty)
        .map((w) => w[0].toUpperCase())
        .take(2)
        .join();
    return letters.isEmpty ? '?' : letters;
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final verified = _stage == _Stage.verified;
    final incorrect = _stage == _Stage.incorrect;

    final label = verified
        ? 'VERIFIED'
        : incorrect
            ? 'INCORRECT CODE'
            : 'ENTER OTP';
    final labelColor = verified
        ? palette.paidManual
        : incorrect
            ? palette.notPaid
            : palette.textMuted;

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
        // The card eases to its new height as the layout changes (the form of the dialog shrinks
        // on success) instead of jumping.
        child: AnimatedSize(
          duration: _swap,
          curve: Curves.easeInOutCubic,
          alignment: Alignment.topCenter,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Center(
              child: Container(
                width: 40,
                height: 40,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: palette.gatewaySoft,
                  border: Border.all(color: palette.gateway.withValues(alpha: 0.5)),
                ),
                child: Text(_initials,
                    style: TextStyle(
                        fontSize: AppType.md, fontWeight: AppType.bold, color: palette.gateway)),
              ),
            ),
            const SizedBox(height: AppSpacing.lg),
            Text(widget.maskedName,
                textAlign: TextAlign.center,
                style: TextStyle(
                    fontSize: AppType.title,
                    fontWeight: AppType.bold,
                    letterSpacing: AppType.titleTracking,
                    color: palette.text)),
            const SizedBox(height: AppSpacing.xs),
            Text('Owleo account found',
                textAlign: TextAlign.center,
                style: TextStyle(
                    fontSize: AppType.smd, fontWeight: AppType.semi, color: palette.gold)),
            const SizedBox(height: AppSpacing.xl),
            _fadeSwap(Text(
              verified
                  ? "Auto-filling ${_firstName.isEmpty ? 'their' : '$_firstName’s'} saved details…"
                  : 'This email is already linked to an Owleo account. Ask them for the OTP sent to '
                      'their registered login to verify and auto-fill their saved details.',
              key: ValueKey(verified),
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: AppType.md, color: palette.textMuted, height: 1.5),
            )),
            const SizedBox(height: AppSpacing.x4l),
            _fadeSwap(Text(label,
                key: ValueKey(label),
                textAlign: TextAlign.center,
                style: TextStyle(
                    fontSize: AppType.sm,
                    fontWeight: AppType.heavy,
                    letterSpacing: 0.6,
                    color: labelColor))),
            const SizedBox(height: AppSpacing.md),
            _fadeSwap(verified
                ? Center(
                    key: const ValueKey('verified'),
                    // The check draws in with a small overshoot, so success feels earned.
                    child: TweenAnimationBuilder<double>(
                      tween: Tween(begin: 0.4, end: 1),
                      duration: const Duration(milliseconds: 650),
                      curve: Curves.elasticOut,
                      builder: (context, scale, child) =>
                          Transform.scale(scale: scale, child: child),
                      child: Container(
                        width: 56,
                        height: 40,
                        decoration: BoxDecoration(
                          color: palette.paidManualSoft,
                          borderRadius: AppRadii.all(AppRadii.lg),
                          border: Border.all(color: palette.paidManual),
                        ),
                        child: Icon(Icons.check_rounded, size: 22, color: palette.paidManual),
                      ),
                    ),
                  )
                : KeyedSubtree(
                    key: const ValueKey('boxes'),
                    child: _shaking(child: _boxes(palette, incorrect)),
                  )),
            if (incorrect) ...[
              const SizedBox(height: AppSpacing.md),
              Center(
                child: Text.rich(
                  TextSpan(
                    style: TextStyle(fontSize: AppType.sm, color: palette.notPaid),
                    children: [
                      TextSpan(text: '${_error ?? 'Incorrect code.'} '),
                      WidgetSpan(
                        alignment: PlaceholderAlignment.baseline,
                        baseline: TextBaseline.alphabetic,
                        child: Pressable(
                          onTap: _retry,
                          child: Text('Retry',
                              style: TextStyle(
                                  fontSize: AppType.sm,
                                  fontWeight: AppType.bold,
                                  color: palette.notPaid,
                                  decoration: TextDecoration.underline,
                                  decorationColor: palette.notPaid)),
                        ),
                      ),
                    ],
                  ),
                  textAlign: TextAlign.center,
                ),
              ),
            ] else if (_error != null && !verified) ...[
              const SizedBox(height: AppSpacing.md),
              Text(_error!,
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: AppType.sm, color: palette.notPaid)),
            ] else if (_note != null && _stage == _Stage.entering) ...[
              const SizedBox(height: AppSpacing.md),
              Text(_note!,
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: AppType.sm, color: palette.textFaint)),
            ],
            if (!verified) ...[
              const SizedBox(height: AppSpacing.lg),
              Align(
                alignment: Alignment.centerLeft,
                child: Pressable(
                  onTap: _sending || _stage == _Stage.verifying ? () {} : _send,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
                    child: Text(_sending ? 'Sending…' : 'Resend OTP',
                        style: TextStyle(
                            fontSize: AppType.md,
                            fontWeight: AppType.bold,
                            color: palette.gold)),
                  ),
                ),
              ),
              const SizedBox(height: AppSpacing.md),
              Pressable(
                onTap: _stage == _Stage.verifying ? () {} : () => Navigator.of(context).pop(),
                child: Container(
                  padding: const EdgeInsets.symmetric(vertical: AppSpacing.xl),
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: palette.surfaceRaised,
                    borderRadius: AppRadii.all(AppRadii.lg),
                    border: Border.all(color: palette.border),
                  ),
                  child: Text('Enter manually',
                      style: TextStyle(
                          fontSize: AppType.lg,
                          fontWeight: AppType.bold,
                          color: palette.text)),
                ),
              ),
            ],
          ],
        ),
        ),
      ),
    );
  }

  /// Eases between two states of the same slot (label, message, boxes -> check) rather than
  /// swapping them in place. Sequential, not a cross-fade: the old content fades out over the first
  /// half and the new fades in over the second, so two labels are never readable on top of each
  /// other (a plain cross-fade stacked "ENTER OTP" and "INCORRECT CODE" into a smear).
  Widget _fadeSwap(Widget child) => AnimatedSwitcher(
        duration: _swap,
        transitionBuilder: (child, animation) {
          final t = animation.drive(CurveTween(curve: const Interval(0.5, 1, curve: Curves.easeOut)));
          return FadeTransition(
            opacity: t,
            child: ScaleTransition(scale: Tween<double>(begin: 0.94, end: 1).animate(t), child: child),
          );
        },
        child: child,
      );

  /// A short horizontal shake, restarted by [_shakes]; a damped sine so it settles rather than stops.
  Widget _shaking({required Widget child}) {
    if (_shakes == 0) return child;
    return TweenAnimationBuilder<double>(
      key: ValueKey(_shakes),
      tween: Tween(begin: 0, end: 1),
      duration: _shakeFor,
      curve: Curves.linear,
      builder: (context, t, child) => Transform.translate(
        offset: Offset(math.sin(t * math.pi * 5) * 9 * (1 - t), 0),
        child: child,
      ),
      child: child,
    );
  }

  /// Six display boxes with one real (invisible) field laid over them. Typing, pasting and the
  /// platform keyboard all behave like any text field; the boxes just show what it holds.
  Widget _boxes(AppPalette palette, bool incorrect) {
    final text = _controller.text;
    final verifying = _stage == _Stage.verifying;
    return SizedBox(
      height: 46,
      child: Stack(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              for (var i = 0; i < _length; i++)
                _box(palette, i < text.length ? text[i] : '', i,
                    filled: i < text.length,
                    current: !incorrect && !verifying && i == text.length && i < _length,
                    incorrect: incorrect,
                    spinning: verifying),
            ],
          ),
          Positioned.fill(
            child: Opacity(
              opacity: 0.0,
              child: TextField(
                controller: _controller,
                focusNode: _focus,
                autofocus: true,
                enabled: !verifying,
                keyboardType: TextInputType.number,
                inputFormatters: [
                  FilteringTextInputFormatter.digitsOnly,
                  LengthLimitingTextInputFormatter(_length),
                ],
                showCursor: false,
                enableInteractiveSelection: false,
                onChanged: (value) {
                  // Typing again after a wrong code starts a fresh attempt.
                  if (_stage == _Stage.incorrect) {
                    _stage = _Stage.entering;
                    _error = null;
                  }
                  setState(() {});
                  if (value.length == _length) _verify();
                },
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _box(AppPalette palette, String digit, int index,
      {required bool filled,
      required bool current,
      required bool incorrect,
      required bool spinning}) {
    final border = incorrect
        ? palette.notPaid
        : current
            ? palette.gold
            : filled
                ? palette.gold.withValues(alpha: 0.7)
                : palette.border;
    // Border, fill and the digit all ease between states: the active box slides along as you type,
    // a digit pops in rather than appearing, and a wrong code washes the row red instead of snapping.
    return AnimatedContainer(
      duration: _boxFade,
      curve: Curves.easeOutCubic,
      width: 42,
      height: 46,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: incorrect ? palette.notPaidSoft : palette.surfaceRaised,
        borderRadius: AppRadii.all(AppRadii.lg),
        border: Border.all(color: border, width: current ? 1.6 : 1),
      ),
      child: spinning && filled
          // Staggered by position so the spinners ripple across the row rather than starting in step.
          ? TweenAnimationBuilder<double>(
              tween: Tween(begin: 0, end: 1),
              duration: Duration(milliseconds: 250 + index * 90),
              curve: Curves.easeOut,
              builder: (context, t, child) => Opacity(opacity: t, child: child),
              child: SizedBox(
                width: 14,
                height: 14,
                child: CircularProgressIndicator(strokeWidth: 1.6, color: palette.gold),
              ),
            )
          : AnimatedScale(
              scale: digit.isEmpty ? 0.5 : 1,
              duration: _boxFade,
              curve: Curves.easeOutBack,
              child: AnimatedOpacity(
                opacity: digit.isEmpty ? 0 : 1,
                duration: _boxFade,
                child: Text(digit.isEmpty ? ' ' : digit,
                    style: TextStyle(
                        fontSize: 20, fontWeight: AppType.bold, color: palette.text)),
              ),
            ),
    );
  }
}
