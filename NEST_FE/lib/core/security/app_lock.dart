import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:nest_fe/app/theme/app_tokens.dart';

/// App Lock: a 4-digit PIN asked for on a cold start and after the app has been in the background
/// for a while.
///
/// The PIN belongs to THIS DEVICE, not the account - it guards the screen in front of whoever is
/// holding the phone, so it sits in the platform keystore (via flutter_secure_storage) and is
/// cleared on log out. It is a screen lock, not a replacement for signing in.
class AppLockState {
  const AppLockState({required this.ready, required this.hasPin, required this.locked});
  final bool ready;
  final bool hasPin;
  final bool locked;

  AppLockState copyWith({bool? ready, bool? hasPin, bool? locked}) => AppLockState(
        ready: ready ?? this.ready,
        hasPin: hasPin ?? this.hasPin,
        locked: locked ?? this.locked,
      );
}

class AppLockController extends Notifier<AppLockState> with WidgetsBindingObserver {
  static const _key = 'nest.appLockPin';
  static const _relockAfter = Duration(seconds: 30);
  static const _storage = FlutterSecureStorage(aOptions: AndroidOptions(encryptedSharedPreferences: true));

  DateTime? _backgroundedAt;

  @override
  AppLockState build() {
    WidgetsBinding.instance.addObserver(this);
    ref.onDispose(() => WidgetsBinding.instance.removeObserver(this));
    _load();
    // Locked until we know there is no PIN, so a cold start never flashes the app before the lock.
    return const AppLockState(ready: false, hasPin: false, locked: true);
  }

  Future<void> _load() async {
    String? pin;
    try {
      pin = await _storage.read(key: _key).timeout(const Duration(seconds: 5));
    } catch (_) {
      pin = null;
    }
    final has = pin != null && pin.length == 4;
    state = AppLockState(ready: true, hasPin: has, locked: has);
  }

  @override
  // ignore: avoid_renaming_method_parameters
  void didChangeAppLifecycleState(AppLifecycleState lifecycle) {
    if (!state.hasPin) return;
    if (lifecycle == AppLifecycleState.paused || lifecycle == AppLifecycleState.hidden) {
      _backgroundedAt ??= DateTime.now();
    } else if (lifecycle == AppLifecycleState.resumed) {
      final since = _backgroundedAt;
      _backgroundedAt = null;
      if (since != null && DateTime.now().difference(since) >= _relockAfter) {
        state = state.copyWith(locked: true);
      }
    }
  }

  Future<bool> verify(String pin) async {
    final stored = await _storage.read(key: _key);
    return stored != null && stored == pin;
  }

  void unlock() => state = state.copyWith(locked: false);

  Future<void> setPin(String pin) async {
    await _storage.write(key: _key, value: pin);
    state = state.copyWith(hasPin: true, locked: false);
  }

  Future<void> clear() async {
    await _storage.delete(key: _key);
    state = state.copyWith(hasPin: false, locked: false);
  }
}

final appLockProvider = NotifierProvider<AppLockController, AppLockState>(AppLockController.new);

/// Wraps the whole app: shows the PIN screen over it while locked.
class AppLockGate extends ConsumerWidget {
  const AppLockGate({super.key, required this.child});
  final Widget? child;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final lock = ref.watch(appLockProvider);
    return Stack(children: [
      ?child,
      if (lock.locked)
        Positioned.fill(
          child: lock.ready
              ? PinEntryScreen(
                  title: 'Enter your PIN',
                  subtitle: 'Unlock Owleo N.E.S.T.',
                  onComplete: (pin) async {
                    final ok = await ref.read(appLockProvider.notifier).verify(pin);
                    if (ok) {
                      ref.read(appLockProvider.notifier).unlock();
                    }
                    return ok;
                  },
                )
              : Material(color: context.palette.bg, child: const Center(child: CircularProgressIndicator())),
        ),
    ]);
  }
}

/// A 4-box PIN entry. [onComplete] gets the four digits and returns whether they were accepted;
/// on false the boxes shake and clear.
class PinEntryScreen extends StatefulWidget {
  const PinEntryScreen({super.key, required this.title, this.subtitle, required this.onComplete, this.onCancel});
  final String title;
  final String? subtitle;
  final Future<bool> Function(String pin) onComplete;
  final VoidCallback? onCancel;

  @override
  State<PinEntryScreen> createState() => _PinEntryScreenState();
}

class _PinEntryScreenState extends State<PinEntryScreen> with SingleTickerProviderStateMixin {
  final _controller = TextEditingController();
  final _focus = FocusNode();
  late final AnimationController _shake =
      AnimationController(vsync: this, duration: const Duration(milliseconds: 380));
  bool _wrong = false;
  bool _busy = false;

  @override
  void dispose() {
    _controller.dispose();
    _focus.dispose();
    _shake.dispose();
    super.dispose();
  }

  Future<void> _changed(String value) async {
    setState(() => _wrong = false);
    if (value.length < 4 || _busy) return;
    _busy = true;
    final ok = await widget.onComplete(value);
    _busy = false;
    if (!mounted) return;
    if (!ok) {
      setState(() => _wrong = true);
      _controller.clear();
      _shake.forward(from: 0);
    }
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return Material(
      color: palette.bg,
      child: SafeArea(
        child: Stack(children: [
          if (widget.onCancel != null)
            Positioned(
              left: 8,
              top: 8,
              child: IconButton(onPressed: widget.onCancel, icon: const Icon(Icons.arrow_back)),
            ),
          Center(
            child: Padding(
              padding: const EdgeInsets.all(28),
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                Container(
                  width: 56,
                  height: 56,
                  decoration: BoxDecoration(color: palette.violetSoft, borderRadius: BorderRadius.circular(18)),
                  child: Icon(Icons.lock_outline, size: 24, color: palette.violet),
                ),
                const SizedBox(height: 18),
                Text(widget.title, style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: palette.text)),
                if (widget.subtitle != null) ...[
                  const SizedBox(height: 4),
                  Text(widget.subtitle!, style: TextStyle(fontSize: 12, color: palette.textMuted)),
                ],
                const SizedBox(height: 24),
                // Boxes are drawn; one hidden field underneath takes the actual typing.
                GestureDetector(
                  onTap: _focus.requestFocus,
                  child: AnimatedBuilder(
                    animation: _shake,
                    builder: (context, child) => Transform.translate(
                      offset: Offset(8 * math.sin(_shake.value * 6 * math.pi) * (1 - _shake.value), 0),
                      child: child,
                    ),
                    child: Stack(alignment: Alignment.center, children: [
                      Row(mainAxisSize: MainAxisSize.min, children: [
                        for (var i = 0; i < 4; i++)
                          Container(
                            width: 48,
                            height: 56,
                            margin: const EdgeInsets.symmetric(horizontal: 5),
                            alignment: Alignment.center,
                            decoration: BoxDecoration(
                              color: palette.surfaceHigh,
                              borderRadius: BorderRadius.circular(14),
                              border: Border.all(
                                color: _wrong
                                    ? palette.notPaid
                                    : _controller.text.length == i ? palette.primary : palette.border,
                                width: 1.5,
                              ),
                            ),
                            child: Text(i < _controller.text.length ? '•' : '',
                                style: TextStyle(fontSize: 26, color: palette.text)),
                          ),
                      ]),
                      Opacity(
                        opacity: 0,
                        child: SizedBox(
                          width: 220,
                          height: 56,
                          child: TextField(
                            controller: _controller,
                            focusNode: _focus,
                            autofocus: true,
                            keyboardType: TextInputType.number,
                            maxLength: 4,
                            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                            onChanged: (v) {
                              setState(() {});
                              _changed(v);
                            },
                          ),
                        ),
                      ),
                    ]),
                  ),
                ),
                const SizedBox(height: 14),
                AnimatedOpacity(
                  opacity: _wrong ? 1 : 0,
                  duration: const Duration(milliseconds: 150),
                  child: Text("That PIN didn't match", style: TextStyle(fontSize: 12, color: palette.notPaid)),
                ),
              ]),
            ),
          ),
        ]),
      ),
    );
  }
}

/// Set (or change) the PIN: enter it, then enter it again. Pops with true once saved.
class PinSetupScreen extends ConsumerStatefulWidget {
  const PinSetupScreen({super.key});

  @override
  ConsumerState<PinSetupScreen> createState() => _PinSetupScreenState();
}

class _PinSetupScreenState extends ConsumerState<PinSetupScreen> {
  String? _first;

  @override
  Widget build(BuildContext context) {
    return PinEntryScreen(
      key: ValueKey(_first == null),
      title: _first == null ? 'Create a PIN' : 'Confirm your PIN',
      subtitle: _first == null ? 'Choose a 4-digit PIN to lock the app' : 'Enter the same PIN again',
      onCancel: () => Navigator.of(context).pop(false),
      onComplete: (pin) async {
        if (_first == null) {
          setState(() => _first = pin);
          return true;
        }
        if (pin != _first) {
          setState(() => _first = null);
          return false;
        }
        final nav = Navigator.of(context);
        await ref.read(appLockProvider.notifier).setPin(pin);
        nav.pop(true);
        return true;
      },
    );
  }
}
