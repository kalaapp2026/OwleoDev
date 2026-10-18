import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:nest_fe/app/theme/app_tokens.dart';
import 'package:nest_fe/app/theme/app_typography.dart';
import 'package:nest_fe/core/auth/session_controller.dart';
import 'package:nest_fe/core/design/app_top_bar.dart';
import 'package:nest_fe/features/messages/data/messages_api.dart';
import 'package:nest_fe/features/messages/presentation/broadcast_compose_screen.dart';
import 'package:nest_fe/features/messages/presentation/broadcast_list_tab.dart';
import 'package:nest_fe/features/messages/presentation/chat_list_tab.dart';
import 'package:nest_fe/features/messages/presentation/new_chat_sheet.dart';
import 'package:nest_fe/features/messages/presentation/widgets/messages_common.dart';

/// Messages. Everyone in an academy gets Chats; an Academy Admin also gets Broadcasts - the
/// compose-and-history side, which only an Admin can send. Recipients read a broadcast in their
/// notification bell, so there is no Broadcasts tab for them.
///
/// The two tabs are pages, so swiping anywhere moves between them as well as tapping the pills.
class MessagesHomeScreen extends ConsumerStatefulWidget {
  const MessagesHomeScreen({super.key});

  @override
  ConsumerState<MessagesHomeScreen> createState() => _MessagesHomeScreenState();
}

class _MessagesHomeScreenState extends ConsumerState<MessagesHomeScreen> {
  final _pages = PageController();
  int _tab = 0; // 0 = Chats, 1 = Broadcasts

  @override
  void dispose() {
    _pages.dispose();
    super.dispose();
  }

  void _goToTab(int index) {
    setState(() => _tab = index);
    _pages.animateToPage(index, duration: AppMotion.screen, curve: AppMotion.enter);
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final isAdmin = ref.watch(sessionControllerProvider.select((s) => s.user?.isActiveAcademyAdmin ?? false));
    final onChats = !isAdmin || _tab == 0;
    final accent = onChats ? palette.primary : palette.gold;
    final unread = ref.watch(conversationsProvider).valueOrNull?.fold<int>(0, (sum, c) => sum + c.unreadCount) ?? 0;

    return Scaffold(
      backgroundColor: palette.bg,
      floatingActionButton: FloatingActionButton(
        onPressed: () {
          if (onChats) {
            showNewChatSheet(context);
          } else {
            Navigator.push(context, MaterialPageRoute(builder: (_) => const BroadcastComposeScreen()));
          }
        },
        tooltip: onChats ? 'New chat' : 'New broadcast',
        backgroundColor: accent,
        foregroundColor: onChats ? palette.onPrimary : palette.onGold,
        shape: const CircleBorder(),
        child: const Icon(Icons.add, size: 26),
      ),
      body: SafeArea(
        child: Column(
          children: [
            AppTopBar(title: 'Messages', actions: const [ThemeModeButton()]),
            if (isAdmin)
              Padding(
                padding: const EdgeInsets.fromLTRB(AppSpacing.page, AppSpacing.lg, AppSpacing.page, AppSpacing.xxs),
                child: _MessagesTabs(
                  tab: _tab,
                  chatUnread: unread,
                  onTap: _goToTab,
                ),
              ),
            Expanded(
              child: isAdmin
                  ? PageView(
                      controller: _pages,
                      onPageChanged: (i) => setState(() => _tab = i),
                      children: const [ChatListTab(), BroadcastListTab()],
                    )
                  : const ChatListTab(),
            ),
          ],
        ),
      ),
    );
  }
}

/// Chats | Broadcasts. Each pill takes its own accent - teal for chats, gold for broadcasts - and
/// Chats carries the unread total.
class _MessagesTabs extends StatelessWidget {
  const _MessagesTabs({required this.tab, required this.chatUnread, required this.onTap});

  final int tab;
  final int chatUnread;
  final ValueChanged<int> onTap;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    Widget pill(int index, String label, IconData icon, Color accent, Color onAccent, {int badge = 0}) {
      final active = tab == index;
      final fg = active ? onAccent : palette.textMuted;
      return Expanded(
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: () => onTap(index),
          child: AnimatedContainer(
            duration: AppMotion.fade,
            padding: const EdgeInsets.symmetric(vertical: 9),
            decoration: BoxDecoration(
              color: active ? accent : Colors.transparent,
              borderRadius: BorderRadius.circular(9),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(icon, size: 14, color: fg),
                const SizedBox(width: 6),
                Text(label,
                    style: TextStyle(fontSize: AppType.md, fontWeight: active ? AppType.heavy : AppType.semi, color: fg)),
                if (badge > 0) ...[
                  const SizedBox(width: 6),
                  CountBadge(
                    count: badge,
                    background: active ? onAccent : palette.notPaid,
                    foreground: active ? accent : Colors.white,
                  ),
                ],
              ],
            ),
          ),
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(color: palette.surfaceRaised, borderRadius: BorderRadius.circular(12)),
      child: Row(
        children: [
          pill(0, 'Chats', Icons.chat_bubble_outline, palette.primary, palette.onPrimary, badge: chatUnread),
          const SizedBox(width: 4),
          pill(1, 'Broadcasts', Icons.campaign_outlined, palette.gold, palette.onGold),
        ],
      ),
    );
  }
}
