import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:nest_fe/app/theme/app_tokens.dart';
import 'package:nest_fe/core/design/pressable.dart';
import 'package:nest_fe/features/notification/data/notification_api.dart';
import 'package:nest_fe/features/notification/presentation/notifications_screen.dart';

/// The bell: shows the unread count and toggles the notification panel open over the screen.
class NotificationBell extends ConsumerStatefulWidget {
  const NotificationBell({super.key, required this.module, this.tile = false});

  final NotificationModule module;

  /// A bordered square tile with a small red count, as on the student screens' headers, rather than
  /// the app bar's plain icon button.
  final bool tile;

  @override
  ConsumerState<NotificationBell> createState() => _NotificationBellState();
}

class _NotificationBellState extends ConsumerState<NotificationBell> {
  final _link = LayerLink();
  OverlayEntry? _overlayEntry;

  void _toggle() => _overlayEntry != null ? _close() : _open();

  void _open() {
    final overlay = Overlay.of(context);
    _overlayEntry = OverlayEntry(
      builder: (overlayContext) => Stack(
        children: [
          // Full-screen scrim - tapping anywhere outside the panel closes it.
          Positioned.fill(
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: _close,
              child: ColoredBox(
                color: Theme.of(overlayContext).brightness == Brightness.dark
                    ? const Color(0x9904070E)
                    : const Color(0x73241B10),
              ),
            ),
          ),
          // A card hung from the top of the screen with a 14px margin each side, over the header -
          // the prototype's notification sheet.
          Builder(builder: (ctx) {
            final media = MediaQuery.of(ctx);
            final palette = ctx.palette;
            final width = (media.size.width - 28).clamp(0.0, 420.0);
            return Positioned(
              top: media.padding.top + 14,
              left: (media.size.width - width) / 2,
              width: width,
              child: Material(
                color: palette.surface,
                elevation: 12,
                shadowColor: Colors.black45,
                shape: RoundedRectangleBorder(
                  borderRadius: AppRadii.all(AppRadii.x4l),
                  side: BorderSide(color: palette.border),
                ),
                clipBehavior: Clip.antiAlias,
                child: ConstrainedBox(
                  constraints: BoxConstraints(maxHeight: (media.size.height - media.padding.top - 14 - 96).clamp(0.0, 640.0)),
                  child: NotificationDropdownContent(module: widget.module, onClose: _close),
                ),
              ),
            );
          }),
        ],
      ),
    );
    overlay.insert(_overlayEntry!);
    setState(() {});
  }

  void _close() {
    _overlayEntry?.remove();
    _overlayEntry = null;
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _overlayEntry?.remove();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final unread = ref.watch(unreadCountProvider(widget.module)).valueOrNull ?? 0;
    if (widget.tile) {
      final palette = context.palette;
      return CompositedTransformTarget(
        link: _link,
        child: Pressable(
          onTap: _toggle,
          child: SizedBox(
            width: 36,
            height: 36,
            child: Stack(clipBehavior: Clip.none, children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: palette.surfaceRaised,
                  borderRadius: AppRadii.all(AppRadii.lg),
                  border: Border.all(color: palette.border),
                ),
                child: Icon(Icons.notifications_none, size: 16, color: palette.textMuted),
              ),
              if (unread > 0)
                Positioned(
                  top: -4,
                  right: -4,
                  child: Container(
                    constraints: const BoxConstraints(minWidth: 16),
                    height: 16,
                    padding: const EdgeInsets.symmetric(horizontal: 3),
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: palette.notPaid,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: palette.surfaceRaised, width: 1.5),
                    ),
                    child: Text(unread > 99 ? '99+' : '$unread',
                        style: const TextStyle(fontSize: 9, fontWeight: FontWeight.w800, color: Colors.white, height: 1)),
                  ),
                ),
            ]),
          ),
        ),
      );
    }
    return CompositedTransformTarget(
      link: _link,
      child: IconButton(
        tooltip: 'Notifications',
        onPressed: _toggle,
        icon: Badge(
          isLabelVisible: unread > 0,
          label: Text(unread > 99 ? '99+' : '$unread'),
          child: Icon(_overlayEntry != null ? Icons.notifications : Icons.notifications_outlined),
        ),
      ),
    );
  }
}

