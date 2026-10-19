import 'package:flutter/material.dart';
import 'package:nest_fe/app/i18n/app_languages.dart';
import 'package:nest_fe/app/theme/app_tokens.dart';
import 'package:nest_fe/app/theme/app_typography.dart';
import 'package:nest_fe/core/design/app_top_bar.dart';
import 'package:nest_fe/core/design/pressable.dart';

/// The small pieces every Academy Settings screen is built from, so the home, billing, export and
/// request screens read as one set.

class SettingsCard extends StatelessWidget {
  const SettingsCard({super.key, required this.child, this.padding = const EdgeInsets.all(14), this.color, this.borderColor});

  final Widget child;
  final EdgeInsets padding;
  final Color? color;
  final Color? borderColor;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return Container(
      width: double.infinity,
      padding: padding,
      decoration: BoxDecoration(
        color: color ?? palette.surfaceRaised,
        borderRadius: AppRadii.all(AppRadii.xxl),
        border: Border.all(color: borderColor ?? palette.border),
      ),
      child: child,
    );
  }
}

class SettingsSectionLabel extends StatelessWidget {
  const SettingsSectionLabel(this.text, {super.key});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(6, AppSpacing.x4l, 6, AppSpacing.md),
      child: Text(text.toUpperCase(),
          style: TextStyle(fontSize: AppType.sm, fontWeight: AppType.heavy, letterSpacing: 0.6, color: context.palette.textFaint)),
    );
  }
}

class SettingsIconTile extends StatelessWidget {
  const SettingsIconTile({super.key, required this.icon, required this.color, required this.soft, this.size = 34, this.image});

  final IconData icon;
  final Color color;
  final Color soft;
  final double size;
  final String? image;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: soft,
        // The prototype's small tiles are flat and soft-filled; only the big identity tile has a rim.
        borderRadius: AppRadii.all(size > 40 ? 14 : 10),
        border: size > 40 ? Border.all(color: color.withValues(alpha: 0.27)) : null,
      ),
      child: image != null
          ? Image.network(image!, width: size, height: size, fit: BoxFit.cover,
              errorBuilder: (_, _, _) => Icon(icon, size: size * 0.5, color: color))
          : Icon(icon, size: size > 40 ? size * 0.45 : 16, color: color),
    );
  }
}

/// A tappable row: tile, title, subtitle, optional trailing value, chevron.
class SettingsNavRow extends StatelessWidget {
  const SettingsNavRow({
    super.key,
    required this.icon,
    required this.color,
    required this.soft,
    required this.title,
    required this.subtitle,
    required this.onTap,
    this.value,
    this.danger = false,
  });

  final IconData icon;
  final Color color;
  final Color soft;
  final String title;
  final String? subtitle;
  final VoidCallback onTap;
  final String? value;
  final bool danger;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return Pressable(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 13, horizontal: 4),
        child: Row(
          children: [
            SettingsIconTile(icon: icon, color: danger ? palette.notPaid : color, soft: danger ? palette.notPaidSoft : soft),
            const SizedBox(width: AppSpacing.lg),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title,
                      style: TextStyle(fontSize: AppType.xl, fontWeight: AppType.semi, color: danger ? palette.notPaid : palette.text)),
                  if (subtitle != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 1),
                      child: Text(subtitle!, style: TextStyle(fontSize: AppType.sm, color: palette.textFaint)),
                    ),
                ],
              ),
            ),
            if (value != null) ...[
              Text(value!, style: TextStyle(fontSize: AppType.base, fontWeight: AppType.semi, color: palette.textMuted)),
              const SizedBox(width: 2),
            ],
            Icon(Icons.chevron_right_rounded, size: 16, color: palette.textFaint),
          ],
        ),
      ),
    );
  }
}

/// A group of [SettingsNavRow]s in one card with hairlines between them.
class SettingsRowGroup extends StatelessWidget {
  const SettingsRowGroup({super.key, required this.rows});

  final List<Widget> rows;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return SettingsCard(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 2),
      child: Column(
        children: [
          for (var i = 0; i < rows.length; i++) ...[
            if (i > 0) Divider(height: 1, color: palette.borderSoft),
            rows[i],
          ],
        ],
      ),
    );
  }
}

/// A faint explanatory note with an icon - the "this is why" line under a section.
class SettingsNote extends StatelessWidget {
  const SettingsNote({super.key, required this.text, this.icon = Icons.info_outline, this.color});

  final String text;
  final IconData icon;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg, vertical: 10),
      decoration: BoxDecoration(color: palette.surfaceHigh, borderRadius: AppRadii.all(AppRadii.lg)),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(padding: const EdgeInsets.only(top: 1.5), child: Icon(icon, size: 13, color: color ?? palette.textFaint)),
          const SizedBox(width: AppSpacing.md),
          Expanded(child: Text(text, style: TextStyle(fontSize: AppType.xs, height: 1.5, color: palette.textFaint))),
        ],
      ),
    );
  }
}

/// A settings sub-screen: top bar, scrolling body, and an optional pinned footer (the action).
class SettingsPage extends StatelessWidget {
  const SettingsPage({super.key, required this.title, required this.children, this.subtitle, this.footer, this.onRefresh, this.actions = const []});

  final String title;
  final String? subtitle;
  final List<Widget> children;
  final Widget? footer;
  final Future<void> Function()? onRefresh;
  final List<Widget> actions;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    Widget list = ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(AppSpacing.page, AppSpacing.xl, AppSpacing.page, AppSpacing.x6l),
      children: children,
    );
    if (onRefresh != null) list = RefreshIndicator(onRefresh: onRefresh!, child: list);

    return Scaffold(
      backgroundColor: palette.bg,
      body: SafeArea(
        child: Column(
          children: [
            AppTopBar(title: title, subtitle: subtitle, actions: actions),
            Expanded(child: list),
            if (footer != null)
              Container(
                padding: const EdgeInsets.fromLTRB(AppSpacing.page, AppSpacing.lg, AppSpacing.page, AppSpacing.x3l),
                decoration: BoxDecoration(border: Border(top: BorderSide(color: palette.borderSoft))),
                child: footer,
              ),
          ],
        ),
      ),
    );
  }
}

/// UPPERCASE field heading used above inputs.
class SettingsFieldLabel extends StatelessWidget {
  const SettingsFieldLabel(this.text, {super.key});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.sm),
      child: Text(text.toUpperCase(),
          style: TextStyle(fontSize: AppType.xs, fontWeight: AppType.bold, color: context.palette.textMuted, letterSpacing: 0.5)),
    );
  }
}

/// The filled, rounded text-field look used across the settings forms.
InputDecoration settingsInput(BuildContext context, String hint, {Widget? suffix}) {
  final palette = context.palette;
  OutlineInputBorder border(Color color) =>
      OutlineInputBorder(borderRadius: BorderRadius.circular(AppRadii.xl), borderSide: BorderSide(color: color));
  return InputDecoration(
    hintText: hint,
    hintStyle: TextStyle(color: palette.textFaint),
    filled: true,
    fillColor: palette.surfaceRaised,
    suffixIcon: suffix,
    contentPadding: const EdgeInsets.symmetric(horizontal: AppSpacing.xl, vertical: AppSpacing.xl),
    border: border(palette.border),
    enabledBorder: border(palette.border),
    focusedBorder: border(palette.primary),
  );
}

/// "5 Sep 2026" from an ISO timestamp, or an empty string if it cannot be read.
String shortDate(String? iso) {
  final d = iso == null ? null : DateTime.tryParse(iso)?.toLocal();
  if (d == null) return '';
  const months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
  return '${d.day} ${months[d.month - 1]} ${d.year}';
}


/// A settings row with an on/off switch on the right: tile, title, subtitle, switch.
class SettingsSwitchRow extends StatelessWidget {
  const SettingsSwitchRow({
    super.key,
    required this.icon,
    required this.color,
    required this.soft,
    required this.title,
    this.subtitle,
    required this.value,
    required this.onChanged,
  });

  final IconData icon;
  final Color color;
  final Color soft;
  final String title;
  final String? subtitle;
  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 13, horizontal: 4),
      child: Row(
        children: [
          SettingsIconTile(icon: icon, color: color, soft: soft),
          const SizedBox(width: AppSpacing.lg),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: TextStyle(fontSize: AppType.xl, fontWeight: AppType.semi, color: palette.text)),
                if (subtitle != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 1),
                    child: Text(subtitle!, style: TextStyle(fontSize: AppType.sm, color: palette.textFaint)),
                  ),
              ],
            ),
          ),
          const SizedBox(width: AppSpacing.md),
          Pressable(
            onTap: () => onChanged(!value),
            child: AnimatedContainer(
              duration: AppMotion.fade,
              width: 42,
              height: 25,
              decoration: BoxDecoration(
                color: value ? palette.primary : palette.border,
                borderRadius: BorderRadius.circular(13),
              ),
              child: AnimatedAlign(
                duration: AppMotion.fade,
                curve: Curves.easeOutBack,
                alignment: value ? Alignment.centerRight : Alignment.centerLeft,
                child: Container(
                  width: 20,
                  height: 20,
                  margin: const EdgeInsets.symmetric(horizontal: 2.5),
                  decoration: const BoxDecoration(
                    color: Colors.white,
                    shape: BoxShape.circle,
                    boxShadow: [BoxShadow(color: Color(0x40000000), blurRadius: 6, offset: Offset(0, 2))],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// System / Light / Dark: a flat raised track, the selected option filled gold, each with its icon.
class SettingsThemeTabs extends StatelessWidget {
  const SettingsThemeTabs({super.key, required this.selected, required this.onChanged, this.lightFirst = false});

  final ThemeMode selected;
  final ValueChanged<ThemeMode> onChanged;

  /// The student screens list Light, Dark, System; the admin one lists System first.
  final bool lightFirst;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    const system = (ThemeMode.system, 'System', Icons.monitor_outlined);
    const light = (ThemeMode.light, 'Light', Icons.wb_sunny_outlined);
    const dark = (ThemeMode.dark, 'Dark', Icons.dark_mode_outlined);
    final options = lightFirst ? [light, dark, system] : [system, light, dark];
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(color: palette.surfaceRaised, borderRadius: BorderRadius.circular(12)),
      child: Row(
        children: [
          for (var i = 0; i < options.length; i++) ...[
            if (i > 0) const SizedBox(width: 4),
            Expanded(
              child: Pressable(
                onTap: () => onChanged(options[i].$1),
                child: AnimatedContainer(
                  duration: AppMotion.fade,
                  padding: const EdgeInsets.symmetric(vertical: 9),
                  decoration: BoxDecoration(
                    color: options[i].$1 == selected ? palette.gold : Colors.transparent,
                    borderRadius: BorderRadius.circular(9),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(options[i].$3, size: 13, color: options[i].$1 == selected ? palette.onGold : palette.textMuted),
                      const SizedBox(width: 6),
                      Text(options[i].$2,
                          style: TextStyle(
                              fontSize: AppType.base,
                              fontWeight: options[i].$1 == selected ? AppType.heavy : AppType.semi,
                              color: options[i].$1 == selected ? palette.onGold : palette.textMuted)),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// "English ⌄" chip that opens a panel of languages under it, the selected one ticked.
class SettingsLanguageDropdown extends StatelessWidget {
  const SettingsLanguageDropdown({super.key, required this.selected, required this.onSelected});

  final AppLanguage selected;
  final ValueChanged<AppLanguage> onSelected;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return PopupMenuButton<AppLanguage>(
      onSelected: onSelected,
      color: palette.surfaceHigh,
      elevation: 8,
      padding: EdgeInsets.zero,
      offset: const Offset(0, 38),
      constraints: const BoxConstraints(minWidth: 190),
      shape: RoundedRectangleBorder(borderRadius: AppRadii.all(AppRadii.xl), side: BorderSide(color: palette.border)),
      itemBuilder: (context) => [
        for (final l in AppLanguage.values)
          PopupMenuItem<AppLanguage>(
            value: l,
            height: 40,
            child: Row(
              children: [
                Expanded(
                  child: Text(l.nativeName, style: TextStyle(fontSize: AppType.md, fontWeight: AppType.semi, color: palette.text)),
                ),
                if (l == selected) Icon(Icons.check, size: 13, color: palette.primary),
              ],
            ),
          ),
      ],
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
        decoration: BoxDecoration(
          color: palette.surfaceHigh,
          borderRadius: AppRadii.all(AppRadii.md),
          border: Border.all(color: palette.border),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(selected.nativeName, style: TextStyle(fontSize: AppType.base, fontWeight: AppType.bold, color: palette.text)),
            const SizedBox(width: 6),
            Icon(Icons.keyboard_arrow_down_rounded, size: 14, color: palette.textFaint),
          ],
        ),
      ),
    );
  }
}
