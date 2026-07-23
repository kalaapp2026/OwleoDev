import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:nest_fe/core/providers/core_providers.dart';
import 'package:nest_fe/core/widgets/async_value_view.dart';
import 'package:nest_fe/features/notification/data/notification_api.dart';

final notificationApiProvider = Provider((ref) => NotificationApi(ref.watch(dioClientProvider)));

final notificationsProvider = FutureProvider.autoDispose((ref) => ref.watch(notificationApiProvider).list());

class NotificationsTab extends ConsumerWidget {
  const NotificationsTab({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final notificationsAsync = ref.watch(notificationsProvider);

    return AsyncValueView<List<AppNotification>>(
      value: notificationsAsync,
      onRetry: () => ref.invalidate(notificationsProvider),
      data: (context, notifications) {
        if (notifications.isEmpty) {
          return const EmptyState(
            icon: Icons.notifications_none_outlined,
            message: 'Nothing here yet.',
          );
        }
        return RefreshIndicator(
          onRefresh: () => ref.refresh(notificationsProvider.future),
          child: ListView.separated(
            padding: const EdgeInsets.all(16),
            itemCount: notifications.length,
            separatorBuilder: (_, _) => const SizedBox(height: 10),
            itemBuilder: (context, i) => _NotificationCard(
              notification: notifications[i],
              onOpen: () async {
                if (!notifications[i].read) {
                  await ref.read(notificationApiProvider).markRead(notifications[i].id);
                  ref.invalidate(notificationsProvider);
                }
              },
            ),
          ),
        );
      },
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
