import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:nest_fe/app/theme/app_tokens.dart';
import 'package:nest_fe/app/theme/app_typography.dart';
import 'package:nest_fe/core/design/avatar.dart';
import 'package:nest_fe/core/widgets/async_value_view.dart';
import 'package:nest_fe/features/messages/data/chat.dart';
import 'package:nest_fe/features/messages/data/messages_api.dart';
import 'package:nest_fe/features/messages/presentation/chat_thread_screen.dart';
import 'package:nest_fe/features/messages/presentation/widgets/messages_common.dart';

/// The Chats tab: every conversation the caller is in, newest first, searchable by name. Refreshes
/// itself while open so a reply shows up without leaving and re-entering.
class ChatListTab extends ConsumerStatefulWidget {
  const ChatListTab({super.key});

  @override
  ConsumerState<ChatListTab> createState() => _ChatListTabState();
}

class _ChatListTabState extends ConsumerState<ChatListTab> {
  Timer? _poll;
  String _query = '';

  @override
  void initState() {
    super.initState();
    _poll = Timer.periodic(const Duration(seconds: 12), (_) {
      if (mounted) ref.invalidate(conversationsProvider);
    });
  }

  @override
  void dispose() {
    _poll?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final conversationsAsync = ref.watch(conversationsProvider);

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(AppSpacing.page, AppSpacing.lg, AppSpacing.page, AppSpacing.md),
          child: MessagesSearchField(hint: 'Search chats', onChanged: (v) => setState(() => _query = v)),
        ),
        Expanded(
          child: AsyncValueView<List<Conversation>>(
            value: conversationsAsync,
            onRetry: () => ref.invalidate(conversationsProvider),
            data: (context, conversations) {
              final q = _query.trim().toLowerCase();
              final rows = conversations.where((c) => q.isEmpty || c.contact.name.toLowerCase().contains(q)).toList();
              if (rows.isEmpty) {
                return Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.chat_bubble_outline, size: 28, color: palette.textFaint),
                        const SizedBox(height: AppSpacing.md),
                        Text(
                          conversations.isEmpty ? 'No conversations yet. Tap + to start one.' : 'No conversations found',
                          textAlign: TextAlign.center,
                          style: TextStyle(fontSize: AppType.md, color: palette.textFaint),
                        ),
                      ],
                    ),
                  ),
                );
              }
              return RefreshIndicator(
                onRefresh: () async => ref.refresh(conversationsProvider.future),
                child: ListView.builder(
                  padding: const EdgeInsets.fromLTRB(AppSpacing.md, 0, AppSpacing.md, AppSpacing.x6l * 3),
                  itemCount: rows.length,
                  itemBuilder: (_, i) => _ConversationRow(conversation: rows[i]),
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}

class _ConversationRow extends ConsumerWidget {
  const _ConversationRow({required this.conversation});

  final Conversation conversation;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final palette = context.palette;
    final unread = conversation.unreadCount;
    final preview = conversation.lastMessage;

    return InkWell(
      borderRadius: AppRadii.all(AppRadii.xl),
      onTap: () async {
        await Navigator.push(context, MaterialPageRoute(builder: (_) => ChatThreadScreen(conversation: conversation)));
        ref.invalidate(conversationsProvider);
      },
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg, vertical: 11),
        child: Row(
          children: [
            PersonAvatar(name: conversation.contact.name, seed: conversation.contact.membershipId, size: 42),
            const SizedBox(width: AppSpacing.xl),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Flexible(
                        child: Text(conversation.contact.name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(fontSize: AppType.xxl, fontWeight: AppType.bold, color: palette.text)),
                      ),
                      if (conversation.contact.isTrainer) ...[const SizedBox(width: 6), const TrainerTag()],
                    ],
                  ),
                  const SizedBox(height: 2),
                  Text(
                    preview == null ? 'No messages yet' : '${conversation.lastMessageFromMe ? 'You: ' : ''}$preview',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: AppType.base,
                      fontWeight: unread > 0 ? AppType.semi : AppType.regular,
                      color: unread > 0 ? palette.text : palette.textMuted,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: AppSpacing.md),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                if (preview != null)
                  Text(shortAgo(conversation.lastMessageAt),
                      style: TextStyle(
                          fontSize: AppType.xs,
                          fontWeight: unread > 0 ? AppType.bold : AppType.regular,
                          color: unread > 0 ? palette.primary : palette.textFaint)),
                if (unread > 0) ...[const SizedBox(height: 6), CountBadge(count: unread)],
              ],
            ),
          ],
        ),
      ),
    );
  }
}
