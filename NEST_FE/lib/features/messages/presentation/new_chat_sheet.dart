import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:nest_fe/app/theme/app_tokens.dart';
import 'package:nest_fe/app/theme/app_typography.dart';
import 'package:nest_fe/core/design/avatar.dart';
import 'package:nest_fe/core/error/api_exception.dart';
import 'package:nest_fe/core/widgets/app_notice.dart';
import 'package:nest_fe/core/widgets/async_value_view.dart';
import 'package:nest_fe/features/messages/data/chat.dart';
import 'package:nest_fe/features/messages/data/messages_api.dart';
import 'package:nest_fe/features/messages/presentation/chat_thread_screen.dart';
import 'package:nest_fe/features/messages/presentation/widgets/messages_common.dart';

/// Pick someone to chat with. Opens the existing conversation if there is one, otherwise starts it.
Future<void> showNewChatSheet(BuildContext context) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    barrierColor: const Color(0xB8040710),
    builder: (_) => const _NewChatSheet(),
  );
}

class _NewChatSheet extends ConsumerStatefulWidget {
  const _NewChatSheet();

  @override
  ConsumerState<_NewChatSheet> createState() => _NewChatSheetState();
}

class _NewChatSheetState extends ConsumerState<_NewChatSheet> {
  String _query = '';
  bool _opening = false;

  Future<void> _pick(ChatContact contact) async {
    if (_opening) return;
    setState(() => _opening = true);
    final navigator = Navigator.of(context);
    try {
      final conversation = await ref.read(messagesApiProvider).startConversation(contact.membershipId);
      ref.invalidate(conversationsProvider);
      if (!mounted) return;
      navigator.pop();
      await navigator.push(MaterialPageRoute(builder: (_) => ChatThreadScreen(conversation: conversation)));
      ref.invalidate(conversationsProvider);
    } on ApiException catch (e) {
      if (mounted) {
        setState(() => _opening = false);
        AppNotice.error(context, e.message);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final contactsAsync = ref.watch(chatContactsProvider);

    return FractionallySizedBox(
      heightFactor: 0.92,
      child: Container(
        decoration: BoxDecoration(
          color: palette.surface,
          borderRadius: AppRadii.sheetTop,
          border: Border.all(color: palette.border),
        ),
        child: Column(
          children: [
            const SizedBox(height: 12),
            Container(width: 36, height: 4, decoration: BoxDecoration(color: palette.border, borderRadius: BorderRadius.circular(3))),
            Padding(
              padding: const EdgeInsets.fromLTRB(AppSpacing.page, AppSpacing.xxl, AppSpacing.page, AppSpacing.lg),
              child: Row(
                children: [
                  Expanded(
                    child: Text('New chat',
                        style: TextStyle(fontSize: 16.5, fontWeight: AppType.heavy, color: palette.text)),
                  ),
                  IconButton(onPressed: () => Navigator.pop(context), icon: Icon(Icons.close, size: 18, color: palette.text)),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(AppSpacing.page, 0, AppSpacing.page, AppSpacing.lg),
              child: MessagesSearchField(
                hint: 'Search people',
                autofocus: false,
                onChanged: (v) => setState(() => _query = v),
              ),
            ),
            Expanded(
              child: AsyncValueView<List<ChatContact>>(
                value: contactsAsync,
                onRetry: () => ref.invalidate(chatContactsProvider),
                data: (context, contacts) {
                  final q = _query.trim().toLowerCase();
                  final matches = contacts.where((c) => q.isEmpty || c.name.toLowerCase().contains(q)).toList();
                  if (matches.isEmpty) {
                    return Center(
                      child: Text(contacts.isEmpty ? 'No one to message yet.' : 'No matches',
                          style: TextStyle(fontSize: AppType.md, color: palette.textFaint)),
                    );
                  }
                  final admins = matches.where((c) => c.isAdmin).toList();
                  final trainers = matches.where((c) => c.isTrainer).toList();
                  final students = matches.where((c) => !c.isAdmin && !c.isTrainer).toList();
                  return ListView(
                    padding: const EdgeInsets.fromLTRB(AppSpacing.md, 0, AppSpacing.md, AppSpacing.x5l),
                    children: [
                      if (admins.isNotEmpty) ..._section('Academy admins', palette.primary, admins),
                      if (trainers.isNotEmpty) ..._section('Trainers', palette.gold, trainers),
                      if (students.isNotEmpty) ..._section('Students', palette.textMuted, students),
                    ],
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  List<Widget> _section(String label, Color color, List<ChatContact> people) {
    final palette = context.palette;
    return [
      Padding(
        padding: const EdgeInsets.fromLTRB(AppSpacing.xxl, AppSpacing.lg, AppSpacing.xxl, AppSpacing.xxs),
        child: Text(label.toUpperCase(),
            style: TextStyle(fontSize: AppType.tiny, fontWeight: AppType.heavy, letterSpacing: 0.6, color: color)),
      ),
      for (final p in people)
        InkWell(
          borderRadius: AppRadii.all(AppRadii.xl),
          onTap: _opening ? null : () => _pick(p),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg, vertical: 10),
            child: Row(
              children: [
                PersonAvatar(name: p.name, seed: p.membershipId, size: 38),
                const SizedBox(width: AppSpacing.xl),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(p.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(fontSize: AppType.xl, fontWeight: AppType.semi, color: palette.text)),
                      if (p.subtitle.isNotEmpty)
                        Text(p.subtitle,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(fontSize: AppType.xs, color: palette.textMuted)),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
    ];
  }
}
