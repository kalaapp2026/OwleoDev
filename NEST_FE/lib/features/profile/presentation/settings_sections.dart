import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:nest_fe/app/theme/app_tokens.dart';
import 'package:nest_fe/app/theme/app_typography.dart';
import 'package:nest_fe/core/design/app_text_field.dart';
import 'package:nest_fe/core/design/buttons.dart';
import 'package:nest_fe/core/design/pressable.dart';
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
    final palette = context.palette;
    final async = ref.watch(_prefsProvider);
    return async.when(
      loading: () => const SettingsCard(child: Padding(padding: EdgeInsets.all(12), child: Center(child: CircularProgressIndicator()))),
      error: (e, _) => SettingsCard(child: Text(e.toString().replaceFirst('Exception: ', ''))),
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

        return SettingsRowGroup(rows: [
          SettingsSwitchRow(
            icon: Icons.notifications_none,
            color: palette.primary,
            soft: palette.primarySoft,
            title: 'Attendance Updates',
            subtitle: "When you're marked present, late or absent",
            value: p.attendance,
            onChanged: (v) => save(attendance: v),
          ),
          SettingsSwitchRow(
            icon: Icons.notifications_none,
            color: palette.violet,
            soft: palette.violetSoft,
            title: 'Event Announcements',
            subtitle: 'New events and schedule changes',
            value: p.events,
            onChanged: (v) => save(events: v),
          ),
          SettingsSwitchRow(
            icon: Icons.notifications_none,
            color: palette.gateway,
            soft: palette.gatewaySoft,
            title: 'Study Material',
            subtitle: 'When trainers upload new material',
            value: p.study,
            onChanged: (v) => save(study: v),
          ),
        ]);
      },
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
    final emailRule = FieldPreset.email();
    final codeRule = FieldPreset.otp();
    final valid = emailRule.check(_email.text) == null;
    final canVerify = codeRule.check(_code.text) == null && !_busy;

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
        CheckedField(
          controller: _email,
          preset: emailRule,
          builder: (context, hasError) => TextField(
            controller: _email,
            enabled: !_sent,
            keyboardType: emailRule.keyboardType,
            inputFormatters: emailRule.formatters,
            style: TextStyle(color: palette.text),
            decoration: settingsInput(context, 'new-email@example.com'),
            onChanged: (_) => setState(() {}),
          ),
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
            keyboardType: codeRule.keyboardType,
            inputFormatters: codeRule.formatters,
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

/// How to reach the student's own academy - the phone, WhatsApp, email, website and address it has
/// published on its profile, laid out like the reference's Contact Us.
class ContactUsScreen extends ConsumerWidget {
  const ContactUsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final palette = context.palette;
    final async = ref.watch(academyProfileProvider);

    Widget row(IconData icon, Color color, Color soft, String label, String value, {Uri? open, bool last = false}) {
      return Container(
        decoration: BoxDecoration(border: last ? null : Border(bottom: BorderSide(color: palette.borderSoft))),
        padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 4),
        child: Row(children: [
          SettingsIconTile(icon: icon, color: color, soft: soft),
          const SizedBox(width: AppSpacing.lg),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(label, style: TextStyle(fontSize: 11, color: palette.textFaint)),
              const SizedBox(height: 1),
              Text(value, style: TextStyle(fontSize: 13.5, fontWeight: AppType.bold, color: palette.text)),
            ]),
          ),
          if (open != null)
            Pressable(
              onTap: () => launchUrl(open, mode: LaunchMode.externalApplication),
              child: Icon(Icons.open_in_new, size: 15, color: palette.textFaint),
            ),
        ]),
      );
    }

    return SettingsPage(
      title: 'Contact Us',
      children: [
        async.when(
          loading: () => const Padding(padding: EdgeInsets.all(40), child: Center(child: CircularProgressIndicator())),
          error: (e, _) => Text(e.toString().replaceFirst('Exception: ', ''), style: TextStyle(color: palette.textFaint)),
          data: (p) {
            final rows = <Widget Function(bool last)>[
              if ((p.contactNumber ?? '').isNotEmpty)
                (last) => row(Icons.phone_outlined, palette.gateway, palette.gatewaySoft, 'Phone', p.contactNumber!,
                    open: Uri(scheme: 'tel', path: p.contactNumber), last: last),
              if ((p.whatsapp ?? '').isNotEmpty)
                (last) => row(Icons.chat_bubble_outline, palette.paidManual, palette.paidManualSoft, 'WhatsApp', p.whatsapp!,
                    open: Uri.parse('https://wa.me/${p.whatsapp!.replaceAll(RegExp(r'[^0-9]'), '')}'), last: last),
              if ((p.email ?? '').isNotEmpty)
                (last) => row(Icons.mail_outline, palette.primary, palette.primarySoft, 'Email', p.email!,
                    open: Uri(scheme: 'mailto', path: p.email), last: last),
              if ((p.websiteUrl ?? '').isNotEmpty)
                (last) => row(Icons.language, palette.gold, palette.goldSoft, 'Website', p.websiteUrl!,
                    open: Uri.tryParse(p.websiteUrl!.startsWith('http') ? p.websiteUrl! : 'https://${p.websiteUrl}'), last: last),
              if ((p.address ?? '').isNotEmpty || (p.city ?? '').isNotEmpty)
                (last) => row(
                    Icons.place_outlined,
                    palette.violet,
                    palette.violetSoft,
                    'Address',
                    [p.address, p.area, p.city, p.state, p.pinCode].where((s) => (s ?? '').isNotEmpty).join(', '),
                    last: last),
            ];
            if (rows.isEmpty) {
              return SettingsCard(
                child: Text("Your academy hasn't published contact details yet.",
                    style: TextStyle(fontSize: 12.5, color: palette.textMuted)),
              );
            }
            return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Padding(
                padding: const EdgeInsets.only(left: 6, bottom: AppSpacing.md),
                child: Text('GET IN TOUCH',
                    style: TextStyle(fontSize: AppType.sm, fontWeight: AppType.heavy, letterSpacing: 0.6, color: palette.textFaint)),
              ),
              SettingsCard(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 2),
                child: Column(children: [for (var i = 0; i < rows.length; i++) rows[i](i == rows.length - 1)]),
              ),
            ]);
          },
        ),
      ],
    );
  }
}
