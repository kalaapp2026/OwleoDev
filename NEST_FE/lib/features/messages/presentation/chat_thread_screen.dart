import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:nest_fe/app/theme/app_tokens.dart';
import 'package:nest_fe/app/theme/app_typography.dart';
import 'package:nest_fe/core/design/app_top_bar.dart';
import 'package:nest_fe/core/design/avatar.dart';
import 'package:nest_fe/core/error/api_exception.dart';
import 'package:nest_fe/core/widgets/app_notice.dart';
import 'package:nest_fe/core/widgets/async_value_view.dart';
import 'package:nest_fe/features/messages/data/chat.dart';
import 'package:nest_fe/features/messages/data/messages_api.dart';
import 'package:nest_fe/features/messages/presentation/widgets/messages_common.dart';

const _maxMessageLength = 2000;

/// One conversation: bubbles newest-at-the-bottom, a composer, and a quiet refresh so the other
/// person's replies appear while the screen is open.
class ChatThreadScreen extends ConsumerStatefulWidget {
  const ChatThreadScreen({super.key, required this.conversation});

  final Conversation conversation;

  @override
  ConsumerState<ChatThreadScreen> createState() => _ChatThreadScreenState();
}

class _ChatThreadScreenState extends ConsumerState<ChatThreadScreen> {
  final _controller = TextEditingController();
  Timer? _poll;
  bool _sending = false;

  String get _id => widget.conversation.id;

  @override
  void initState() {
    super.initState();
    _markRead();
    _poll = Timer.periodic(const Duration(seconds: 5), (_) {
      if (mounted) ref.invalidate(chatMessagesProvider(_id));
    });
  }

  @override
  void dispose() {
    _poll?.cancel();
    _controller.dispose();
    super.dispose();
  }

  void _markRead() {
    // Best effort: failing to clear the badge must never get in the way of reading.
    ref.read(messagesApiProvider).markRead(_id).catchError((_) {});
  }

  bool get _canSend => _controller.text.trim().isNotEmpty && !_sending;

  Future<void> _send() async {
    final text = _controller.text.trim();
    if (text.isEmpty || _sending) return;
    setState(() => _sending = true);
    try {
      await ref.read(messagesApiProvider).sendMessage(_id, text);
      _controller.clear();
      ref.invalidate(chatMessagesProvider(_id));
    } on ApiException catch (e) {
      if (mounted) AppNotice.error(context, e.message);
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final contact = widget.conversation.contact;
    final messagesAsync = ref.watch(chatMessagesProvider(_id));

    // A reply that lands while the thread is open should not leave the list badge stuck.
    ref.listen(chatMessagesProvider(_id), (previous, next) {
      final now = next.valueOrNull;
      if (now == null || now.isEmpty || now.last.fromMe) return;
      if ((previous?.valueOrNull?.length ?? 0) != now.length) _markRead();
    });

    return Scaffold(
      backgroundColor: palette.bg,
      resizeToAvoidBottomInset: true,
      body: SafeArea(
        child: Column(
          children: [
            AppTopBar(
              title: contact.name,
              subtitle: contact.subtitle.isEmpty ? null : contact.subtitle,
              actions: [PersonAvatar(name: contact.name, seed: contact.membershipId, size: 34)],
            ),
            Expanded(
              child: AsyncValueView<List<ChatMessage>>(
                value: messagesAsync,
                onRetry: () => ref.invalidate(chatMessagesProvider(_id)),
                data: (context, messages) {
                  if (messages.isEmpty) {
                    return Center(
                      child: Text('No messages yet. Say hello to ${contact.name.split(' ').first}.',
                          style: TextStyle(fontSize: AppType.md, color: palette.textFaint)),
                    );
                  }
                  // reverse: the list is anchored to the bottom, so the newest message is in view
                  // without any scroll-to-end bookkeeping.
                  final newestFirst = messages.reversed.toList();
                  return ListView.builder(
                    reverse: true,
                    padding: const EdgeInsets.fromLTRB(AppSpacing.xxl, AppSpacing.xxl, AppSpacing.xxl, AppSpacing.sm),
                    itemCount: newestFirst.length,
                    itemBuilder: (_, i) => _Bubble(message: newestFirst[i]),
                  );
                },
              ),
            ),
            _Composer(
              controller: _controller,
              canSend: _canSend,
              onChanged: () => setState(() {}),
              onSend: _send,
            ),
          ],
        ),
      ),
    );
  }
}

class _Bubble extends StatelessWidget {
  const _Bubble({required this.message});

  final ChatMessage message;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final own = message.fromMe;
    const big = Radius.circular(16);
    const small = Radius.circular(4);

    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Align(
        alignment: own ? Alignment.centerRight : Alignment.centerLeft,
        child: ConstrainedBox(
          constraints: BoxConstraints(maxWidth: MediaQuery.sizeOf(context).width * 0.76),
          child: Column(
            crossAxisAlignment: own ? CrossAxisAlignment.end : CrossAxisAlignment.start,
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 10),
                decoration: BoxDecoration(
                  color: own ? palette.primary : palette.surfaceRaised,
                  border: own ? null : Border.all(color: palette.border),
                  borderRadius: BorderRadius.only(
                    topLeft: big,
                    topRight: big,
                    bottomLeft: own ? big : small,
                    bottomRight: own ? small : big,
                  ),
                ),
                child: Text(message.body,
                    style: TextStyle(fontSize: AppType.lg, height: 1.45, color: own ? palette.onPrimary : palette.text)),
              ),
              Padding(
                padding: const EdgeInsets.only(top: 3, left: 3, right: 3),
                child: Text(longAgo(message.createdAt), style: TextStyle(fontSize: 10, color: palette.textFaint)),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Composer extends StatelessWidget {
  const _Composer({required this.controller, required this.canSend, required this.onChanged, required this.onSend});

  final TextEditingController controller;
  final bool canSend;
  final VoidCallback onChanged;
  final VoidCallback onSend;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return Container(
      padding: const EdgeInsets.fromLTRB(AppSpacing.xl, AppSpacing.md, AppSpacing.xl, AppSpacing.xl),
      decoration: BoxDecoration(border: Border(top: BorderSide(color: palette.borderSoft))),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Expanded(
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xl),
              decoration: BoxDecoration(
                color: palette.surfaceRaised,
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: palette.border),
              ),
              child: TextField(
                controller: controller,
                onChanged: (_) => onChanged(),
                onSubmitted: (_) => onSend(),
                textInputAction: TextInputAction.send,
                minLines: 1,
                maxLines: 4,
                maxLength: _maxMessageLength,
                style: TextStyle(fontSize: AppType.lg, color: palette.text),
                decoration: InputDecoration(
                  hintText: 'Message',
                  hintStyle: TextStyle(color: palette.textFaint),
                  counterText: '',
                  border: InputBorder.none,
                  enabledBorder: InputBorder.none,
                  focusedBorder: InputBorder.none,
                  filled: false,
                  isDense: true,
                  contentPadding: const EdgeInsets.symmetric(vertical: 12),
                ),
              ),
            ),
          ),
          const SizedBox(width: AppSpacing.md),
          GestureDetector(
            onTap: canSend ? onSend : null,
            child: Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(shape: BoxShape.circle, color: canSend ? palette.primary : palette.surfaceHigh),
              child: Icon(Icons.send_rounded, size: 16, color: canSend ? palette.onPrimary : palette.textFaint),
            ),
          ),
        ],
      ),
    );
  }
}
