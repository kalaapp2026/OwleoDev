import 'package:flutter/material.dart';
import 'package:nest_fe/core/format/money.dart';
import 'package:nest_fe/core/design/pressable.dart';
import 'package:nest_fe/app/theme/app_typography.dart';
import 'package:nest_fe/app/theme/app_tokens.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:nest_fe/core/auth/session_controller.dart';
import 'package:nest_fe/core/providers/core_providers.dart';
import 'package:nest_fe/core/push/push_service.dart';
import 'package:nest_fe/core/widgets/async_value_view.dart';
import 'package:nest_fe/features/notification/data/notification_api.dart';
import 'package:nest_fe/features/notification/presentation/broadcast_screen.dart';

final notificationApiProvider = Provider((ref) => NotificationApi(ref.watch(dioClientProvider)));

/// Per-module so the ERP bell and Social bell are genuinely separate feeds. Keyed by the wire
/// value ('SOCIAL'/'ERP') since the enum isn't a valid family key on its own here.
final notificationsProvider =
    FutureProvider.autoDispose.family<List<AppNotification>, NotificationModule>((ref, module) {
  return ref.watch(notificationApiProvider).list(module);
});

/// Drives the app-bar bell's unread badge without fetching the whole list each time.
final unreadCountProvider =
    FutureProvider.autoDispose.family<int, NotificationModule>((ref, module) {
  return ref.watch(notificationApiProvider).unreadCount(module);
});

/// Whether the device already shows pushes. Only ever false-and-supported on Android with the
/// permission refused, which is when the panel offers to turn them on.
final _pushEnabledProvider = FutureProvider.autoDispose<bool>((ref) => PushService.instance.isEnabled());

/// The bell's panel content: "Notifications / N unread" with Mark all read and a close tile, an
/// optional "Turn on notifications" card, then a row per notification with a coloured icon tile and
/// an unread dot. A Super Admin additionally gets a "Broadcast" action in the header, which still
/// opens as its own screen since composing an announcement is a real form, not a quick glance.
class NotificationDropdownContent extends ConsumerWidget {
  const NotificationDropdownContent({super.key, required this.module, required this.onClose});

  final NotificationModule module;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final palette = context.palette;
    final notificationsAsync = ref.watch(notificationsProvider(module));
    final user = ref.watch(sessionControllerProvider).user;
    final isSuperAdmin = user?.isSuperAdmin ?? false;
    final unread = notificationsAsync.valueOrNull?.where((n) => !n.read).length ?? 0;
    final offerPush = PushService.instance.isSupported && (ref.watch(_pushEnabledProvider).valueOrNull == false);

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Notifications',
                        style: TextStyle(fontSize: 15.5, fontWeight: AppType.heavy, color: palette.text)),
                    const SizedBox(height: 1),
                    Text(unread > 0 ? '$unread unread' : "You're all caught up",
                        style: TextStyle(fontSize: 11, color: palette.textFaint)),
                  ],
                ),
              ),
              if (unread > 0)
                Pressable(
                  onTap: () async {
                    final api = ref.read(notificationApiProvider);
                    for (final n in notificationsAsync.value!.where((n) => !n.read)) {
                      await api.markRead(n.id);
                    }
                    ref.invalidate(notificationsProvider(module));
                    ref.invalidate(unreadCountProvider(module));
                  },
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 4),
                    child: Row(mainAxisSize: MainAxisSize.min, children: [
                      Icon(Icons.done_all, size: 13, color: palette.primary),
                      const SizedBox(width: 4),
                      Text('Mark all read',
                          style: TextStyle(fontSize: 11.5, fontWeight: AppType.bold, color: palette.primary)),
                    ]),
                  ),
                ),
              if (isSuperAdmin) ...[
                const SizedBox(width: 6),
                Pressable(
                  onTap: () async {
                    onClose();
                    await Navigator.of(context).push(
                      MaterialPageRoute(builder: (_) => BroadcastScreen(initialModule: module)),
                    );
                    ref.invalidate(notificationsProvider(module));
                    ref.invalidate(unreadCountProvider(module));
                  },
                  child: Icon(Icons.campaign_outlined, size: 20, color: palette.textMuted),
                ),
              ],
              const SizedBox(width: 10),
              Pressable(
                onTap: onClose,
                child: Container(
                  width: 30,
                  height: 30,
                  decoration: BoxDecoration(
                    color: palette.surfaceRaised,
                    borderRadius: AppRadii.all(AppRadii.lg),
                    border: Border.all(color: palette.border),
                  ),
                  child: Icon(Icons.close, size: 14, color: palette.text),
                ),
              ),
            ],
          ),
        ),
        Divider(height: 1, color: palette.borderSoft),
        Flexible(
          child: ListView(
            shrinkWrap: true,
            padding: const EdgeInsets.fromLTRB(10, 6, 10, 12),
            children: [
              if (offerPush) _EnablePushCard(onEnabled: () => ref.invalidate(_pushEnabledProvider)),
              AsyncValueView<List<AppNotification>>(
                value: notificationsAsync,
                onRetry: () => ref.invalidate(notificationsProvider(module)),
                data: (context, notifications) {
                  if (notifications.isEmpty) {
                    return Padding(
                      padding: const EdgeInsets.symmetric(vertical: 40, horizontal: 20),
                      child: Center(
                        child: Text('No notifications yet.',
                            style: TextStyle(fontSize: 12.5, color: palette.textFaint)),
                      ),
                    );
                  }
                  return Column(children: [
                    for (final n in notifications)
                      _NotificationRow(
                        notification: n,
                        onOpen: () async {
                          if (!n.read) {
                            await ref.read(notificationApiProvider).markRead(n.id);
                            ref.invalidate(notificationsProvider(module));
                            ref.invalidate(unreadCountProvider(module));
                          }
                        },
                      ),
                  ]);
                },
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _EnablePushCard extends ConsumerStatefulWidget {
  const _EnablePushCard({required this.onEnabled});
  final VoidCallback onEnabled;

  @override
  ConsumerState<_EnablePushCard> createState() => _EnablePushCardState();
}

class _EnablePushCardState extends ConsumerState<_EnablePushCard> {
  bool _busy = false;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return Container(
      margin: const EdgeInsets.fromLTRB(0, 4, 0, 4),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: palette.primarySoft,
        borderRadius: AppRadii.all(AppRadii.xxl),
        border: Border.all(color: palette.primary.withValues(alpha: 0.27)),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Container(
            width: 34,
            height: 34,
            decoration: BoxDecoration(color: palette.surface, borderRadius: AppRadii.all(11)),
            child: Icon(Icons.notifications_active_outlined, size: 16, color: palette.primary),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('Turn on notifications',
                  style: TextStyle(fontSize: 13, fontWeight: AppType.heavy, color: palette.text)),
              const SizedBox(height: 2),
              Text('Get alerts for attendance, fee reminders, messages, and events as they happen.',
                  style: TextStyle(fontSize: 11.5, height: 1.5, color: palette.textMuted)),
            ]),
          ),
        ]),
        const SizedBox(height: 10),
        Pressable(
          onTap: _busy
              ? null
              : () async {
                  setState(() => _busy = true);
                  await PushService.instance.enable(ref.read(dioClientProvider));
                  if (mounted) setState(() => _busy = false);
                  widget.onEnabled();
                },
          child: Container(
            padding: const EdgeInsets.symmetric(vertical: 10),
            alignment: Alignment.center,
            decoration: BoxDecoration(color: palette.primary, borderRadius: AppRadii.all(AppRadii.lg)),
            child: Text('Enable notifications',
                style: TextStyle(fontSize: 13, fontWeight: AppType.bold, color: palette.onPrimary)),
          ),
        ),
      ]),
    );
  }
}

class _NotificationRow extends StatelessWidget {
  const _NotificationRow({required this.notification, required this.onOpen});

  final AppNotification notification;
  final VoidCallback onOpen;

  /// The prototype's five kinds - attendance, fees, messages, events, study material - mapped from
  /// what the server actually sends. Template events are told apart by their title.
  (IconData, Color, Color) _tone(AppPalette palette) {
    final title = notification.title.toLowerCase();
    return switch (notification.type) {
      'ACADEMY_BROADCAST' || 'ADMIN_BROADCAST' => (Icons.chat_bubble_outline, palette.coral, palette.coralSoft),
      'MEMBERSHIP_CONFIRMATION' => (Icons.verified_user_outlined, palette.primary, palette.primarySoft),
      _ when title.contains('absent') || title.contains('present') || title.contains('attendance') =>
        (Icons.fact_check_outlined, palette.primary, palette.primarySoft),
      _ when title.contains('payment') || title.contains('fee') =>
        (Icons.account_balance_wallet_outlined, palette.notPaid, palette.notPaidSoft),
      _ when title.contains('material') => (Icons.description_outlined, palette.violet, palette.violetSoft),
      _ => (Icons.calendar_today_outlined, palette.gold, palette.goldSoft),
    };
  }

  /// "just now", "5 min ago", "3 hr ago", "Yesterday", "3 days ago", then the date.
  String _ago() {
    final at = DateTime.tryParse(notification.createdAt)?.toLocal();
    if (at == null) return '';
    final diff = DateTime.now().difference(at);
    if (diff.inMinutes < 1) return 'just now';
    if (diff.inMinutes < 60) return '${diff.inMinutes} min ago';
    if (diff.inHours < 24) return '${diff.inHours} hr ago';
    if (diff.inDays == 1) return 'Yesterday';
    if (diff.inDays < 7) return '${diff.inDays} days ago';
    return formatFeeDate(DateTime(at.year, at.month, at.day));
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final (icon, color, soft) = _tone(palette);
    final unread = !notification.read;

    return Pressable(
      onTap: onOpen,
      child: Container(
        margin: const EdgeInsets.only(bottom: 2),
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
        decoration: BoxDecoration(
          color: unread ? palette.surfaceHigh : Colors.transparent,
          borderRadius: AppRadii.all(AppRadii.xl),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 32,
              height: 32,
              margin: const EdgeInsets.only(top: 1),
              decoration: BoxDecoration(color: soft, borderRadius: AppRadii.all(AppRadii.md)),
              child: Icon(icon, size: 15, color: color),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(children: [
                    Expanded(
                      child: Text(notification.title,
                          style: TextStyle(
                              fontSize: 12.5,
                              height: 1.4,
                              fontWeight: unread ? AppType.heavy : AppType.semi,
                              color: palette.text)),
                    ),
                    if (unread)
                      Container(
                        width: 6,
                        height: 6,
                        margin: const EdgeInsets.only(left: 6),
                        decoration: BoxDecoration(color: palette.primary, shape: BoxShape.circle),
                      ),
                  ]),
                  if (notification.body.isNotEmpty) ...[
                    const SizedBox(height: 2),
                    Text(notification.body,
                        style: TextStyle(fontSize: 11.5, height: 1.4, color: palette.textMuted)),
                  ],
                  if (notification.actionCode != null) ...[
                    const SizedBox(height: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                      decoration: BoxDecoration(
                        color: palette.primarySoft,
                        borderRadius: AppRadii.all(AppRadii.md),
                        border: Border.all(color: palette.primary.withValues(alpha: 0.35)),
                      ),
                      child: Row(mainAxisSize: MainAxisSize.min, children: [
                        Icon(Icons.pin_outlined, size: 16, color: palette.primary),
                        const SizedBox(width: 8),
                        Text(notification.actionCode!,
                            style: TextStyle(
                                color: palette.primary, fontWeight: AppType.heavy, fontSize: 18, letterSpacing: 3)),
                      ]),
                    ),
                  ],
                  const SizedBox(height: 2),
                  Text(_ago(), style: TextStyle(fontSize: 10.5, color: palette.textFaint)),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
