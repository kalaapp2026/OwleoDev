import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:nest_fe/app/i18n/app_languages.dart';
import 'package:nest_fe/app/i18n/locale_controller.dart';
import 'package:nest_fe/app/theme/theme_controller.dart';
import 'package:nest_fe/core/widgets/app_notice.dart';
import 'package:nest_fe/l10n/app_localizations.dart';

/// Per-user preferences: theme and UI language. Both are stored on the account rather than the
/// device, so they follow the person to whatever they next sign in on.
class UserSettingsScreen extends ConsumerWidget {
  const UserSettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = AppLocalizations.of(context);
    final themeMode = ref.watch(themeModeProvider);
    final language = ref.watch(localeProvider);

    return Scaffold(
      appBar: AppBar(title: Text(t.settingsTitle)),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          _SectionLabel(t.settingsAppearance),
          Card(
            child: RadioGroup<ThemeMode>(
              groupValue: themeMode,
              onChanged: (m) => ref.read(themeModeProvider.notifier).setThemeMode(m!),
              child: Column(
                children: [
                  RadioListTile<ThemeMode>(title: Text(t.settingsThemeSystem), value: ThemeMode.system),
                  RadioListTile<ThemeMode>(title: Text(t.settingsThemeLight), value: ThemeMode.light),
                  RadioListTile<ThemeMode>(title: Text(t.settingsThemeDark), value: ThemeMode.dark),
                ],
              ),
            ),
          ),
          const SizedBox(height: 24),

          _SectionLabel(t.settingsLanguage),
          Text(t.settingsLanguageSubtitle, style: Theme.of(context).textTheme.bodySmall),
          const SizedBox(height: 8),
          Card(
            child: Column(
              children: AppLanguage.values.map((option) {
                final selected = option == language;
                return ListTile(
                  // Native name first - someone hunting for their own language scans for "தமிழ்",
                  // not "Tamil". The English name stays as a subtitle so a support person helping
                  // them can still identify the row.
                  title: Text(option.nativeName,
                      style: TextStyle(fontWeight: selected ? FontWeight.w700 : FontWeight.w400)),
                  subtitle: option.englishName == option.nativeName ? null : Text(option.englishName),
                  trailing: selected
                      ? Icon(Icons.check_circle, color: Theme.of(context).colorScheme.primary, size: 20)
                      : null,
                  onTap: selected
                      ? null
                      : () async {
                          await ref.read(localeProvider.notifier).setLanguage(option);
                          if (context.mounted) {
                            // Read the string AFTER the switch so the confirmation itself appears
                            // in the language just chosen.
                            AppNotice.success(context, AppLocalizations.of(context).languageChanged);
                          }
                        },
                );
              }).toList(),
            ),
          ),
        ],
      ),
    );
  }
}

class _SectionLabel extends StatelessWidget {
  const _SectionLabel(this.text);
  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8, top: 4),
      child: Text(
        text.toUpperCase(),
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.6,
          color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.5),
        ),
      ),
    );
  }
}
