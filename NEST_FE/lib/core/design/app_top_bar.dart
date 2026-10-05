import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:nest_fe/app/theme/app_tokens.dart';
import 'package:nest_fe/app/theme/app_typography.dart';
import 'package:nest_fe/app/theme/theme_controller.dart';
import 'package:nest_fe/core/design/pressable.dart';

/// The rebuilt screens' header: a square back button, a title with a muted subtitle beneath, and
/// optional trailing widgets, over a hairline divider. Used in place of a Material AppBar where a
/// design calls for this exact treatment.
class AppTopBar extends StatelessWidget {
  const AppTopBar({super.key, required this.title, this.subtitle, this.onBack, this.actions = const []});

  final String title;
  final String? subtitle;

  /// Defaults to popping the route; pass null-returning behaviour by supplying your own.
  final VoidCallback? onBack;
  final List<Widget> actions;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final canPop = Navigator.of(context).canPop();
    return Container(
      padding: const EdgeInsets.fromLTRB(AppSpacing.x4l, AppSpacing.x4l, AppSpacing.x4l, AppSpacing.xxl),
      decoration: BoxDecoration(border: Border(bottom: BorderSide(color: palette.borderSoft))),
      child: Row(
        children: [
          if (canPop || onBack != null) ...[
            Pressable(
              onTap: onBack ?? () => Navigator.of(context).maybePop(),
              child: Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: palette.surfaceRaised,
                  borderRadius: AppRadii.all(AppRadii.lg),
                  border: Border.all(color: palette.border),
                ),
                child: Icon(Icons.arrow_back, size: 18, color: palette.text),
              ),
            ),
            const SizedBox(width: AppSpacing.lg),
          ],
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                        fontSize: AppType.title,
                        fontWeight: AppType.bold,
                        letterSpacing: AppType.titleTracking,
                        color: palette.text)),
                if (subtitle != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: Text(subtitle!,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(fontSize: AppType.smd, color: palette.textMuted)),
                  ),
              ],
            ),
          ),
          for (final a in actions) ...[const SizedBox(width: AppSpacing.md), a],
        ],
      ),
    );
  }
}

const _modes = [
  (mode: ThemeMode.system, icon: Icons.brightness_auto_outlined),
  (mode: ThemeMode.light, icon: Icons.light_mode_outlined),
  (mode: ThemeMode.dark, icon: Icons.dark_mode_outlined),
];

/// Collapsed: one circular icon for the current theme. Tapped: expands into a system / light /
/// dark pill with the active mode picked out in gold; choosing one applies it and collapses.
/// Writes through [themeModeProvider], so it is the same setting as the Settings screen.
class ThemeModeButton extends ConsumerStatefulWidget {
  const ThemeModeButton({super.key});

  @override
  ConsumerState<ThemeModeButton> createState() => _ThemeModeButtonState();
}

class _ThemeModeButtonState extends ConsumerState<ThemeModeButton> {
  bool _open = false;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final current = ref.watch(themeModeProvider);
    final currentIcon = _modes.firstWhere((m) => m.mode == current).icon;
    return AnimatedContainer(
      duration: AppMotion.sheet,
      curve: Curves.easeOutBack,
      width: _open ? 104 : 36,
      height: 36,
      decoration: BoxDecoration(
        color: palette.surfaceRaised,
        borderRadius: AppRadii.all(AppRadii.pill),
        border: Border.all(color: palette.border),
      ),
      clipBehavior: Clip.antiAlias,
      child: _open
          ? Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                for (final m in _modes)
                  InkWell(
                    customBorder: const CircleBorder(),
                    onTap: () {
                      ref.read(themeModeProvider.notifier).setThemeMode(m.mode);
                      setState(() => _open = false);
                    },
                    child: Container(
                      width: 28,
                      height: 28,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: m.mode == current ? palette.gold : Colors.transparent,
                      ),
                      child: Icon(m.icon, size: 14, color: m.mode == current ? palette.onGold : palette.textMuted),
                    ),
                  ),
              ],
            )
          : InkWell(
              onTap: () => setState(() => _open = true),
              child: Center(child: Icon(currentIcon, size: 16, color: palette.textMuted)),
            ),
    );
  }
}
