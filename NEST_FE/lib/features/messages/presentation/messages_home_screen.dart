import 'package:flutter/material.dart';
import 'package:nest_fe/app/theme/app_tokens.dart';
import 'package:nest_fe/core/design/app_top_bar.dart';
import 'package:nest_fe/features/messages/presentation/broadcast_compose_screen.dart';
import 'package:nest_fe/features/messages/presentation/broadcast_list_tab.dart';

/// Messages: an Academy Admin's broadcast history plus the compose affordance. Recipients read a
/// broadcast in their notification bell - this screen is the sender's own view.
class MessagesHomeScreen extends StatelessWidget {
  const MessagesHomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;

    return Scaffold(
      backgroundColor: palette.bg,
      floatingActionButton: FloatingActionButton(
        onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const BroadcastComposeScreen())),
        tooltip: 'New broadcast',
        backgroundColor: palette.gold,
        foregroundColor: palette.onGold,
        shape: const CircleBorder(),
        child: const Icon(Icons.add, size: 26),
      ),
      body: SafeArea(
        child: Column(
          children: [
            AppTopBar(title: 'Messages', actions: const [ThemeModeButton()]),
            const Expanded(child: BroadcastListTab()),
          ],
        ),
      ),
    );
  }
}
