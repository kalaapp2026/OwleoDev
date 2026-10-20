import 'dart:async';

import 'package:flutter/material.dart';

import '../../app/theme.dart';
import 'controls.dart';
import 'icons.dart';

const _scrim = Color(0xA804070E); // rgba(4,7,14,.66)

/// The right-hand detail panel (`.drawer`): slides in from the edge, closes on scrim tap or Escape.
Future<T?> showHqDrawer<T>(BuildContext context, {required WidgetBuilder builder, double width = 500}) {
  return showGeneralDialog<T>(
    context: context,
    barrierDismissible: true,
    barrierLabel: 'Close',
    barrierColor: _scrim,
    transitionDuration: const Duration(milliseconds: 220),
    pageBuilder: (ctx, _, _) => Align(
      alignment: Alignment.centerRight,
      child: Material(
        color: Hq.bg,
        child: Container(
          width: width,
          constraints: BoxConstraints(maxWidth: MediaQuery.sizeOf(ctx).width),
          height: double.infinity,
          decoration: const BoxDecoration(border: Border(left: BorderSide(color: Hq.border))),
          child: builder(ctx),
        ),
      ),
    ),
    transitionBuilder: (ctx, anim, _, child) {
      final curved = CurvedAnimation(parent: anim, curve: Curves.easeOutCubic);
      return FadeTransition(
        opacity: anim,
        child: SlideTransition(
          position: Tween(begin: const Offset(.05, 0), end: Offset.zero).animate(curved),
          child: child,
        ),
      );
    },
  );
}

/// The centred dialog (`.modal`).
Future<T?> showHqModal<T>(BuildContext context, {required WidgetBuilder builder, double width = 520, bool dismissible = true}) {
  return showGeneralDialog<T>(
    context: context,
    barrierDismissible: dismissible,
    barrierLabel: 'Close',
    barrierColor: _scrim,
    transitionDuration: const Duration(milliseconds: 160),
    pageBuilder: (ctx, _, _) => SafeArea(
      child: Center(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Material(
            color: Colors.transparent,
            child: Container(
              width: width,
              constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(ctx).height - 32),
              padding: const EdgeInsets.all(22),
              decoration: BoxDecoration(
                color: Hq.surface,
                borderRadius: BorderRadius.circular(22),
                border: Border.all(color: Hq.border),
                boxShadow: const [BoxShadow(color: Color(0x99000000), blurRadius: 60, offset: Offset(0, 24))],
              ),
              child: builder(ctx),
            ),
          ),
        ),
      ),
    ),
    transitionBuilder: (ctx, anim, _, child) => FadeTransition(opacity: anim, child: child),
  );
}

/// A full-screen page over the shell (the prototype's `.obpage`, used for the Add academy form).
Future<T?> showHqFullPage<T>(BuildContext context, {required WidgetBuilder builder}) {
  return Navigator.of(context, rootNavigator: true).push<T>(
    PageRouteBuilder<T>(
      opaque: true,
      transitionDuration: const Duration(milliseconds: 200),
      pageBuilder: (ctx, _, _) => Scaffold(backgroundColor: Hq.bg, body: SafeArea(child: builder(ctx))),
      transitionsBuilder: (ctx, anim, _, child) => FadeTransition(opacity: anim, child: child),
    ),
  );
}

/// Title row + scrolling body + button row for a modal. Keeps every dialog laid out the same.
class ModalFrame extends StatelessWidget {
  const ModalFrame({super.key, required this.title, this.sub, required this.children, this.actions = const [], this.error});

  final String title;
  final String? sub;
  final List<Widget> children;
  final List<Widget> actions;
  final String? error;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: HqText.title),
                  if (sub != null) Padding(padding: const EdgeInsets.only(top: 1), child: Text(sub!, style: HqText.sub)),
                ],
              ),
            ),
            const SizedBox(width: 10),
            HqIconButton('x', size: 36, onTap: () => Navigator.of(context).pop()),
          ],
        ),
        const SizedBox(height: 16),
        Flexible(child: SingleChildScrollView(child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: children))),
        if (error != null && error!.isNotEmpty)
          Padding(padding: const EdgeInsets.only(bottom: 10), child: Text(error!, style: HqText.small.copyWith(color: Hq.red, fontSize: 12.5))),
        if (actions.isNotEmpty) ...[
          const SizedBox(height: 6),
          Row(mainAxisAlignment: MainAxisAlignment.end, children: [
            for (var i = 0; i < actions.length; i++) ...[if (i > 0) const SizedBox(width: 8), actions[i]],
          ]),
        ],
      ],
    );
  }
}

/// The body of a drawer: a coloured cover, an avatar/logo overlapping its bottom edge, a close
/// button, then the padded content (`.dcover` + `.dlogo` + `.dbody`).
class DrawerShell extends StatelessWidget {
  const DrawerShell({
    super.key,
    required this.child,
    this.coverColors = const [Color(0xFF0A0F1C), Color(0xFF141E33), Color(0xFF24365C)],
    this.logo,
    this.coverHeight = 104,
  });

  final Widget child;
  final List<Color> coverColors;

  /// Usually an [Avatar]-like badge; positioned on the cover's bottom-left edge.
  final Widget? logo;
  final double coverHeight;

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SizedBox(
            height: coverHeight + (logo != null ? 28 : 0),
            child: Stack(
              clipBehavior: Clip.none,
              children: [
                Container(
                  height: coverHeight,
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: coverColors,
                      stops: coverColors.length == 3 ? const [0, .45, 1] : null,
                    ),
                  ),
                ),
                Positioned(
                  top: 14,
                  right: 14,
                  child: GestureDetector(
                    onTap: () => Navigator.of(context).pop(),
                    child: MouseRegion(
                      cursor: SystemMouseCursors.click,
                      child: Container(
                        width: 40,
                        height: 40,
                        decoration: BoxDecoration(
                          color: const Color(0x7304070E),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: const Color(0x33FFFFFF)),
                        ),
                        child: Center(child: ic('x', 16, Colors.white)),
                      ),
                    ),
                  ),
                ),
                if (logo != null) Positioned(left: 20, top: coverHeight - 30, child: logo!),
              ],
            ),
          ),
          Padding(
            padding: EdgeInsets.fromLTRB(20, logo != null ? 12 : 18, 20, 28),
            child: child,
          ),
        ],
      ),
    );
  }
}

/// The 58px rounded-square logo that overlaps a drawer cover.
class DrawerLogo extends StatelessWidget {
  const DrawerLogo(this.label, {super.key, this.color = Hq.primary, this.icon});
  final String label;
  final Color color;
  final String? icon;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 58,
      height: 58,
      decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(16), border: Border.all(color: Hq.bg, width: 3)),
      child: Center(
        child: icon != null
            ? ic(icon!, 26, Hq.ink)
            : Text(label, style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w800, color: Color(0xFF10131C))),
      ),
    );
  }
}

OverlayEntry? _toast;
Timer? _toastTimer;

/// The bottom-centre confirmation pill. One at a time; a new one replaces the old.
void showToast(BuildContext context, String message) {
  _toastTimer?.cancel();
  _toast?.remove();
  final overlay = Overlay.of(context, rootOverlay: true);
  _toast = OverlayEntry(
    builder: (ctx) => Positioned(
      left: 16,
      right: 16,
      bottom: 112,
      child: IgnorePointer(
        child: Center(
          child: Container(
            constraints: const BoxConstraints(maxWidth: 560),
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: BoxDecoration(
              color: Hq.high,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: Hq.border),
              boxShadow: const [BoxShadow(color: Color(0x8C000000), blurRadius: 36, offset: Offset(0, 16))],
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                ic('check', 17, Hq.primary),
                const SizedBox(width: 10),
                Flexible(child: Text(message, style: HqText.body.copyWith(fontSize: 13, fontWeight: FontWeight.w600))),
              ],
            ),
          ),
        ),
      ),
    ),
  );
  overlay.insert(_toast!);
  _toastTimer = Timer(const Duration(milliseconds: 2800), () {
    _toast?.remove();
    _toast = null;
  });
}

/// A yes/no question. Resolves to true only on the confirm button.
Future<bool> confirmHq(
  BuildContext context, {
  required String title,
  required String body,
  String confirmLabel = 'Confirm',
  String cancelLabel = 'Cancel',
  bool danger = false,
}) async {
  final res = await showHqModal<bool>(
    context,
    width: 440,
    builder: (ctx) => Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 32,
              height: 32,
              decoration: BoxDecoration(color: (danger ? Tone.red : Tone.gold).soft, borderRadius: BorderRadius.circular(10)),
              child: Center(child: ic('warn', 17, danger ? Hq.red : Hq.gold)),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: HqText.title),
                  const SizedBox(height: 4),
                  Text(body, style: HqText.muted.copyWith(height: 1.5)),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 18),
        Row(mainAxisAlignment: MainAxisAlignment.end, children: [
          HqButton(cancelLabel, onPressed: () => Navigator.of(ctx).pop(false)),
          const SizedBox(width: 8),
          HqButton(confirmLabel,
              kind: danger ? BtnKind.danger : BtnKind.primary, onPressed: () => Navigator.of(ctx).pop(true)),
        ]),
      ],
    ),
  );
  return res ?? false;
}
