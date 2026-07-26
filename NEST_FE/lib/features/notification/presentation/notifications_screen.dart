import 'package:flutter/material.dart';
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
                  style: Theme.of(context).textTheme.titleMedium,
                ),
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
        const Divider(height: 1),
        Flexible(
          child: AsyncValueView<List<AppNotification>>(
            value: notificationsAsync,
            onRetry: () => ref.invalidate(notificationsProvider(module)),
            data: (context, notifications) {
              if (notifications.isEmpty) {
                return const Padding(
                  padding: EdgeInsets.all(24),
                  child: Center(child: Text('Nothing here yet.')),
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

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Card(
      elevation: notification.read ? 0 : 1.5,
      color: notification.read ? null : colorScheme.primary.withValues(alpha: 0.06),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onOpen,
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  if (!notification.read)
                    Container(
                      width: 8,
                      height: 8,
                      margin: const EdgeInsets.only(right: 8),
                      decoration: BoxDecoration(color: colorScheme.primary, shape: BoxShape.circle),
                    ),
                  Expanded(
                    child: Text(notification.title,
                        style: Theme.of(context).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700)),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              Text(notification.body, style: Theme.of(context).textTheme.bodyMedium),
              if (notification.actionCode != null) ...[
                const SizedBox(height: 10),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                  decoration: BoxDecoration(
                    color: colorScheme.primaryContainer,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.pin_outlined, size: 16, color: colorScheme.onPrimaryContainer),
                      const SizedBox(width: 8),
                      Text(
                        notification.actionCode!,
                        style: TextStyle(
                          color: colorScheme.onPrimaryContainer,
                          fontWeight: FontWeight.w800,
                          fontSize: 18,
                          letterSpacing: 3,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
