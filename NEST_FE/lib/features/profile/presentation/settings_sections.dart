import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:nest_fe/app/theme/app_tokens.dart';
import 'package:nest_fe/app/theme/app_typography.dart';
import 'package:nest_fe/core/design/buttons.dart';
import 'package:nest_fe/core/auth/session_controller.dart';
import 'package:nest_fe/core/providers/core_providers.dart';
import 'package:nest_fe/core/widgets/app_notice.dart';
import 'package:nest_fe/features/academy/presentation/academy_info_screen.dart' show academyProfileProvider;
import 'package:nest_fe/features/academy/presentation/academy_settings_kit.dart';
import 'package:url_launcher/url_launcher.dart';

final _prefsProvider = FutureProvider.autoDispose((ref) => ref.watch(authApiProvider).notificationPrefs());

/// The three Settings > Notifications switches, saved to the account as they are flipped.
class NotificationPrefsCard extends ConsumerWidget {
  const NotificationPrefsCard({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(_prefsProvider);
    return Card(
      child: async.when(
        loading: () => const Padding(padding: EdgeInsets.all(20), child: Center(child: CircularProgressIndicator())),
        error: (e, _) => Padding(padding: const EdgeInsets.all(16), child: Text(e.toString().replaceFirst('Exception: ', ''))),
        data: (p) {
          Future<void> save({bool? attendance, bool? events, bool? study}) async {
            try {
              await ref.read(authApiProvider).updateNotificationPrefs(
                    attendance: attendance ?? p.attendance,
                    events: events ?? p.events,
                    study: study ?? p.study,
                  );
              ref.invalidate(_prefsProvider);
            } catch (_) {
              if (context.mounted) AppNotice.error(context, "Couldn't save - try again");
            }
          }

          return Column(children: [
            SwitchListTile(
              secondary: const Icon(Icons.fact_check_outlined),
              title: const Text('Attendance updates'),
              subtitle: const Text("When you're marked present or absent"),
              value: p.attendance,
              onChanged: (v) => save(attendance: v),
            ),
            const Divider(height: 1),
            SwitchListTile(
              secondary: const Icon(Icons.event_outlined),
              title: const Text('Event announcements'),
              subtitle: const Text('New events and schedule changes'),
              value: p.events,
              onChanged: (v) => save(events: v),
            ),
            const Divider(height: 1),
            SwitchListTile(
              secondary: const Icon(Icons.description_outlined),
              title: const Text('Study material'),
              subtitle: const Text('When trainers upload new material'),
              value: p.study,
              onChanged: (v) => save(study: v),
            ),
          ]);
        },
      ),
    );
  }
}

/// Change the login email: type the new address, get a code there, enter it. The old address stays
/// until the code proves the new one is reachable.
class ChangeEmailScreen extends ConsumerStatefulWidget {
  const ChangeEmailScreen({super.key});

  @override
  ConsumerState<ChangeEmailScreen> createState() => _ChangeEmailState();
}

class _ChangeEmailState extends ConsumerState<ChangeEmailScreen> {
  final _email = TextEditingController();
  final _code = TextEditingController();
  bool _sent = false;
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _email.dispose();
    _code.dispose();
    super.dispose();
  }

  Future<void> _run(Future<void> Function() action) async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await action();
    } catch (e) {
      if (mounted) setState(() => _error = e.toString().replaceFirst('Exception: ', ''));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final current = ref.watch(sessionControllerProvider).user?.email;
    final valid = RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$').hasMatch(_email.text.trim());
    final canVerify = _code.text.trim().length >= 4 && !_busy;

    Future<void> sendCode() => _run(() async {
          await ref.read(authApiProvider).requestEmailChangeCode(_email.text.trim());
          if (mounted) setState(() => _sent = true);
        });

    Future<void> verify() => _run(() async {
          final nav = Navigator.of(context);
          final messenger = ScaffoldMessenger.of(context);
          await ref.read(authApiProvider).confirmEmailChange(_email.text.trim(), _code.text.trim());
          await ref.read(sessionControllerProvider.notifier).refreshProfile();
          messenger.showSnackBar(const SnackBar(content: Text('Login email updated')));
          nav.pop();
        });

    return SettingsPage(
      title: 'Login Email',
      footer: _sent
          ? AppPrimaryButton(label: 'Verify and Save', icon: Icons.check, busy: _busy, onPressed: canVerify ? verify : null)
          : AppPrimaryButton(label: 'Send code', icon: Icons.send_rounded, busy: _busy, onPressed: valid ? sendCode : null),
      children: [
        if (current != null && current.isNotEmpty)
          SettingsCard(
            child: Row(
              children: [
                Icon(Icons.mail_outline, size: 16, color: palette.textFaint),
                const SizedBox(width: AppSpacing.lg),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Current login email', style: TextStyle(fontSize: AppType.xs, color: palette.textFaint)),
                      Text(current, style: TextStyle(fontSize: AppType.lg, fontWeight: AppType.bold, color: palette.text)),
                    ],
                  ),
                ),
              ],
            ),
          ),
        const SizedBox(height: AppSpacing.x4l),
        const SettingsFieldLabel('New login email'),
        TextField(
          controller: _email,
          enabled: !_sent,
          keyboardType: TextInputType.emailAddress,
          style: TextStyle(color: palette.text),
          decoration: settingsInput(context, 'new-email@example.com'),
          onChanged: (_) => setState(() {}),
        ),
        if (_sent) ...[
          const SizedBox(height: AppSpacing.x4l),
          SettingsNote(
            icon: Icons.check_circle_outline,
            color: palette.primary,
            text: 'We sent a code to ${_email.text.trim()}. Your current email stays in place until you enter it.',
          ),
          const SizedBox(height: AppSpacing.xl),
          const SettingsFieldLabel('Code'),
          TextField(
            controller: _code,
            keyboardType: TextInputType.number,
            style: TextStyle(color: palette.text, letterSpacing: 4, fontSize: AppType.x4l),
            decoration: settingsInput(context, 'Enter the code'),
            onChanged: (_) => setState(() {}),
          ),
          const SizedBox(height: AppSpacing.lg),
          Row(
            children: [
              TextButton(onPressed: _busy ? null : sendCode, child: const Text('Resend code')),
              TextButton(
                onPressed: _busy ? null : () => setState(() => _sent = false),
                child: const Text('Use a different email'),
              ),
            ],
          ),
        ],
        if (_error != null)
          Padding(
            padding: const EdgeInsets.only(top: AppSpacing.xl),
            child: Text(_error!, style: TextStyle(color: palette.notPaid)),
          ),
      ],
    );
  }
}

/// How to reach the academy - the contact details its admin published on the Academy Profile.
class ContactUsScreen extends ConsumerWidget {
  const ContactUsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(academyProfileProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('Contact us')),
      body: async.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text(e.toString().replaceFirst('Exception: ', ''))),
        data: (p) {
          final tiles = <Widget>[
            if ((p.contactNumber ?? '').isNotEmpty)
              ListTile(
                leading: const Icon(Icons.phone_outlined),
                title: const Text('Phone'),
                subtitle: Text(p.contactNumber!),
                onTap: () => launchUrl(Uri(scheme: 'tel', path: p.contactNumber)),
              ),
            if ((p.email ?? '').isNotEmpty)
              ListTile(
                leading: const Icon(Icons.mail_outline),
                title: const Text('Email'),
                subtitle: Text(p.email!),
                onTap: () => launchUrl(Uri(scheme: 'mailto', path: p.email)),
              ),
            if ((p.address ?? '').isNotEmpty || (p.city ?? '').isNotEmpty)
              ListTile(
                leading: const Icon(Icons.place_outlined),
                title: const Text('Address'),
                subtitle: Text([p.address, p.area, p.city, p.state, p.pinCode]
                    .where((s) => (s ?? '').isNotEmpty)
                    .join(', ')),
              ),
          ];
          if (tiles.isEmpty) {
            return const Center(child: Text("Your academy hasn't published contact details yet."));
          }
          return ListView(padding: const EdgeInsets.all(20), children: [Card(child: Column(children: tiles))]);
        },
      ),
    );
  }
}
