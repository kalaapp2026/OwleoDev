import 'package:flutter/material.dart';
import 'package:nest_fe/core/format/money.dart';
import 'package:nest_fe/core/design/pressable.dart';
import 'package:nest_fe/app/theme/app_typography.dart';
import 'package:nest_fe/app/theme/app_tokens.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:nest_fe/core/auth/session_controller.dart';
import 'package:nest_fe/core/providers/core_providers.dart';
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

/// The bell's dropdown content - a compact panel, not a page (tapping the bell toggles it open/
/// closed in place). A Super Admin additionally gets a "Broadcast" action in the header, which
/// still opens as its own screen since composing an announcement is a real form, not a quick glance.
class NotificationDropdownContent extends ConsumerWidget {
  const NotificationDropdownContent({super.key, required this.module, required this.onClose});

  final NotificationModule module;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final notificationsAsync = ref.watch(notificationsProvider(module));
    final user = ref.watch(sessionControllerProvider).user;
    final isSuperAdmin = user?.isSuperAdmin ?? false;

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 8, 8),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  module == NotificationModule.erp ? 'ERP notifications' : 'Notifications',
                  style: TextStyle(fontSize: AppType.x4l, fontWeight: AppType.heavy, color: context.palette.text),
                ),
              ),
              if (notificationsAsync.valueOrNull?.any((n) => !n.read) ?? false)
                TextButton.icon(
                  icon: const Icon(Icons.done_all, size: 15),
                  label: const Text('Mark all read'),
                  onPressed: () async {
                    final api = ref.read(notificationApiProvider);
                    for (final n in notificationsAsync.value!.where((n) => !n.read)) {
                      await api.markRead(n.id);
                    }
                    ref.invalidate(notificationsProvider(module));
                    ref.invalidate(unreadCountProvider(module));
                  },
                ),
              if (isSuperAdmin)
                IconButton(
                  icon: const Icon(Icons.campaign_outlined),
                  tooltip: 'Broadcast',
                  onPressed: () async {
                    onClose();
                    await Navigator.of(context).push(
                      MaterialPageRoute(builder: (_) => BroadcastScreen(initialModule: module)),
                    );
                    ref.invalidate(notificationsProvider(module));
                    ref.invalidate(unreadCountProvider(module));
                  },
                ),
              IconButton(icon: const Icon(Icons.close), tooltip: 'Close', onPressed: onClose),
            ],
          ),
        ),
        Divider(height: 1, color: context.palette.borderSoft),
        Flexible(
          child: AsyncValueView<List<AppNotification>>(
            value: notificationsAsync,
            onRetry: () => ref.invalidate(notificationsProvider(module)),
            data: (context, notifications) {
              if (notifications.isEmpty) {
                return Padding(
                  padding: const EdgeInsets.all(AppSpacing.x5l),
                  child: Center(
                    heightFactor: 1,
                    child: Text('Nothing here yet.',
                        style: TextStyle(fontSize: AppType.md, color: context.palette.textFaint)),
                  ),
                );
              }
              return ListView.separated(
                shrinkWrap: true,
                padding: const EdgeInsets.all(12),
                itemCount: notifications.length,
                separatorBuilder: (_, _) => const SizedBox(height: 8),
                itemBuilder: (context, i) => _NotificationCard(
                  notification: notifications[i],
                  onOpen: () async {
                    if (!notifications[i].read) {
                      await ref.read(notificationApiProvider).markRead(notifications[i].id);
                      ref.invalidate(notificationsProvider(module));
                      ref.invalidate(unreadCountProvider(module));
                    }
                  },
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}

class _NotificationCard extends StatelessWidget {
  const _NotificationCard({required this.notification, required this.onOpen});

  final AppNotification notification;
  final VoidCallback onOpen;

  /// Broadcasts read as announcements, template events (class changes, absences, payments) as
  /// alerts, and the membership code as a verification.
  (IconData, Color, Color) _tone(AppPalette palette) => switch (notification.type) {
        'ACADEMY_BROADCAST' || 'ADMIN_BROADCAST' => (Icons.campaign_outlined, palette.gold, palette.goldSoft),
        'MEMBERSHIP_CONFIRMATION' => (Icons.verified_user_outlined, palette.primary, palette.primarySoft),
        _ => (Icons.notifications_active_outlined, palette.gateway, palette.gatewaySoft),
      };

  /// "just now", "5m ago", "3h ago", "2d ago", then the date.
  String _ago() {
    final at = DateTime.tryParse(notification.createdAt)?.toLocal();
    if (at == null) return '';
    final diff = DateTime.now().difference(at);
    if (diff.inMinutes < 1) return 'just now';
    if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
    if (diff.inHours < 24) return '${diff.inHours}h ago';
    if (diff.inDays < 7) return '${diff.inDays}d ago';
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
        padding: const EdgeInsets.all(AppSpacing.xl),
        decoration: BoxDecoration(
          color: unread ? palette.primarySoft : palette.surfaceRaised,
          borderRadius: AppRadii.all(AppRadii.xl),
          border: Border.all(color: unread ? palette.primary.withValues(alpha: 0.35) : palette.borderSoft),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 34,
              height: 34,
              decoration: BoxDecoration(
                color: soft,
                shape: BoxShape.circle,
                border: Border.all(color: color.withValues(alpha: 0.4)),
              ),
              child: Icon(icon, size: 16, color: color),
            ),
            const SizedBox(width: AppSpacing.lg),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(notification.title,
                            style: TextStyle(
                                fontSize: AppType.lg,
                                fontWeight: unread ? AppType.heavy : AppType.bold,
                                color: palette.text)),
                      ),
                      if (unread)
                        Container(
                          width: 8,
                          height: 8,
                          margin: const EdgeInsets.only(left: AppSpacing.md),
                          decoration: BoxDecoration(color: palette.primary, shape: BoxShape.circle),
                        ),
                    ],
                  ),
                  const SizedBox(height: 3),
                  Text(notification.body,
                      style: TextStyle(fontSize: AppType.md, color: palette.textMuted, height: 1.35)),
                  if (notification.actionCode != null) ...[
                    const SizedBox(height: AppSpacing.lg),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xl, vertical: AppSpacing.md),
                      decoration: BoxDecoration(
                        color: palette.primarySoft,
                        borderRadius: AppRadii.all(AppRadii.md),
                        border: Border.all(color: palette.primary.withValues(alpha: 0.35)),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.pin_outlined, size: 16, color: palette.primary),
                          const SizedBox(width: AppSpacing.md),
                          Text(notification.actionCode!,
                              style: TextStyle(
                                  color: palette.primary, fontWeight: AppType.heavy, fontSize: 18, letterSpacing: 3)),
                        ],
                      ),
                    ),
                  ],
                  const SizedBox(height: AppSpacing.md),
                  Text(_ago(),
                      style: TextStyle(fontSize: AppType.xs, fontWeight: AppType.semi, color: palette.textFaint)),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
