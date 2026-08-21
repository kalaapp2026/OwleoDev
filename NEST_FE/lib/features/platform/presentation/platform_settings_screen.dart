import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:nest_fe/core/error/api_exception.dart';
import 'package:nest_fe/core/widgets/app_notice.dart';
import 'package:nest_fe/core/widgets/async_value_view.dart';
import 'package:nest_fe/features/platform/data/platform_settings_api.dart';
import 'package:nest_fe/features/platform/presentation/console_layout.dart';

/// Super Admin control over which half of the app everyone sees. Exists because rollout is
/// ERP-first: showing an unfinished Social side to an academy being onboarded invites questions
/// nobody wants to field yet, and rebuilding the app with a flag to change that is too slow.
class PlatformSettingsScreen extends ConsumerStatefulWidget {
  const PlatformSettingsScreen({super.key, this.embedded = false});

  final bool embedded;

  @override
  ConsumerState<PlatformSettingsScreen> createState() => _PlatformSettingsScreenState();
}

class _PlatformSettingsScreenState extends ConsumerState<PlatformSettingsScreen> {
  bool _saving = false;

  Future<void> _select(AppModeSetting mode, AppModeSetting current) async {
    if (mode == current || _saving) return;

    // Hiding half the product from every user on the platform is worth one deliberate tap.
    if (mode == AppModeSetting.erpOnly || mode == AppModeSetting.socialOnly) {
      final hidden = mode == AppModeSetting.erpOnly ? 'Social' : 'ERP';
      final ok = await AppNotice.confirm(
        context,
        title: 'Hide $hidden for everyone?',
        message: 'Every user on the platform loses access to the $hidden side and the centre '
            'toggle disappears. Existing data is untouched, and switching back restores it '
            'immediately.',
        confirmLabel: 'Hide $hidden',
      );
      if (!ok) return;
    }

    setState(() => _saving = true);
    try {
      await ref.read(platformSettingsApiProvider).update(mode);
      // Refresh the shared provider so the shell re-reads it - this changes the nav for everyone,
      // including the Super Admin making the change.
      ref.invalidate(platformSettingsProvider);
      if (mounted) AppNotice.success(context, 'App mode set to ${mode.label}.');
    } on ApiException catch (e) {
      if (mounted) AppNotice.error(context, e.message);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final async = ref.watch(platformSettingsProvider);

    return Scaffold(
      appBar: widget.embedded ? null : AppBar(title: const Text('Settings')),
      body: AsyncValueView<PlatformSettings>(
        value: async,
        onRetry: () => ref.invalidate(platformSettingsProvider),
        data: (context, settings) => ConsolePage(
          children: [
            Text('Platform settings', style: Theme.of(context).textTheme.headlineSmall),
            const SizedBox(height: 4),
            Text(
              'Applies to every user on the platform, immediately.',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: 24),
            const ConsoleSectionTitle('App mode'),
            Text(
              'Controls which side the app opens on, and whether the centre toggle in the bottom '
              'bar is available at all.',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: 12),
            ...AppModeSetting.values.map((mode) => _ModeOption(
                  mode: mode,
                  selected: mode == settings.appMode,
                  enabled: !_saving,
                  onTap: () => _select(mode, settings.appMode),
                )),
            const SizedBox(height: 16),
            Card(
              margin: EdgeInsets.zero,
              child: Padding(
                padding: const EdgeInsets.all(14),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Icon(Icons.info_outline, size: 18),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        'Guests and Artists have no ERP access, so "ERP only" still leaves them '
                        'the Social side - otherwise they would open the app to a blank screen. '
                        'Everyone with an academy membership sees only ERP, as intended.',
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ModeOption extends StatelessWidget {
  const _ModeOption({
    required this.mode,
    required this.selected,
    required this.enabled,
    required this.onTap,
  });

  final AppModeSetting mode;
  final bool selected;
  final bool enabled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final restricts = mode == AppModeSetting.erpOnly || mode == AppModeSetting.socialOnly;

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      color: selected ? colorScheme.primaryContainer.withValues(alpha: 0.35) : null,
      child: ListTile(
        onTap: enabled ? onTap : null,
        leading: Icon(
          selected ? Icons.radio_button_checked : Icons.radio_button_unchecked,
          color: selected ? colorScheme.primary : null,
        ),
        title: Row(
          children: [
            Text(mode.label, style: const TextStyle(fontWeight: FontWeight.w600)),
            if (restricts) ...[
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: colorScheme.tertiary.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text('hides one side',
                    style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: colorScheme.tertiary)),
              ),
            ],
          ],
        ),
        subtitle: Text(mode.description),
      ),
    );
  }
}
