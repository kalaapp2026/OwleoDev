import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:nest_fe/app/theme/app_tokens.dart';
import 'package:nest_fe/app/theme/app_typography.dart';
import 'package:nest_fe/core/design/app_text_field.dart';
import 'package:nest_fe/core/design/buttons.dart';
import 'package:nest_fe/core/design/pressable.dart';
import 'package:nest_fe/core/error/api_exception.dart';
import 'package:nest_fe/core/widgets/app_notice.dart';
import 'package:nest_fe/features/academy/data/academy_settings_api.dart';
import 'package:nest_fe/features/academy/presentation/academy_settings_kit.dart';
import 'package:nest_fe/features/platform/data/device_install_service.dart' show kAppVersion;

const _faqs = [
  (
    'How do I transfer academy ownership?',
    'Go to Academy Settings → Ownership → Request ownership transfer. Ownership affects billing and access for '
        'everyone, so the Owleo team verifies the request and completes the handover instead of it changing instantly.',
  ),
  (
    'How do I change my plan?',
    'Open Academy Settings → Billing → Subscription plan and request the plan you want. The team confirms it and it '
        'applies to future invoices - invoices already raised keep their amount.',
  ),
  (
    'How do I export my academy\'s data?',
    'Academy Settings → Data → Export data. You can download students, the fees ledger and attendance as CSV files '
        'that open in Excel or Google Sheets.',
  ),
  (
    'How do I change the email I sign in with?',
    'Academy Settings → Account → Login email. We send a code to the new address, and the change only takes effect '
        'once you enter it.',
  ),
  (
    'I don\'t remember my password.',
    'Academy Settings → Account → Login password, then choose "Don\'t remember it? Verify with a code". A code is '
        'emailed to the address on your account, and you can set a new password with it.',
  ),
  (
    'What happens when I request academy closure?',
    'Nothing closes automatically. The request goes to the Owleo team, who review it and get in touch before '
        'anything changes for you, your trainers or your students.',
  ),
];

/// Answers to the questions an Academy Admin actually asks, with a route to the team when they
/// aren't enough.
class HelpSupportScreen extends StatefulWidget {
  const HelpSupportScreen({super.key});

  @override
  State<HelpSupportScreen> createState() => _HelpSupportScreenState();
}

class _HelpSupportScreenState extends State<HelpSupportScreen> {
  int _open = 0;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return SettingsPage(
      title: 'Help & Support',
      children: [
        const SettingsSectionLabel('Frequently asked questions'),
        SettingsCard(
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xl),
          child: Column(
            children: [
              for (var i = 0; i < _faqs.length; i++)
                Container(
                  decoration: BoxDecoration(border: i == _faqs.length - 1 ? null : Border(bottom: BorderSide(color: palette.borderSoft))),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Pressable(
                        onTap: () => setState(() => _open = _open == i ? -1 : i),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(vertical: 13),
                          child: Row(
                            children: [
                              Expanded(
                                child: Text(_faqs[i].$1,
                                    style: TextStyle(fontSize: AppType.lg, fontWeight: AppType.semi, color: palette.text)),
                              ),
                              Icon(_open == i ? Icons.expand_less : Icons.expand_more, size: 18, color: palette.textFaint),
                            ],
                          ),
                        ),
                      ),
                      if (_open == i)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 14),
                          child: Text(_faqs[i].$2, style: TextStyle(fontSize: AppType.base, height: 1.6, color: palette.textMuted)),
                        ),
                    ],
                  ),
                ),
            ],
          ),
        ),
        const SettingsSectionLabel('Still need help?'),
        SettingsCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text('Send us a message and the Owleo team will reply.',
                  style: TextStyle(fontSize: AppType.base, height: 1.5, color: palette.textMuted)),
              const SizedBox(height: AppSpacing.xl),
              AppPrimaryButton(
                label: 'Contact Owleo Support',
                icon: Icons.mark_email_unread_outlined,
                onPressed: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const ContactSupportScreen())),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

/// A message to the Owleo team. It is stored as a request the Super Admin team reads and answers,
/// so it reaches a real inbox - there is no placeholder address here.
class ContactSupportScreen extends ConsumerStatefulWidget {
  const ContactSupportScreen({super.key});

  @override
  ConsumerState<ContactSupportScreen> createState() => _ContactSupportScreenState();
}

class _ContactSupportScreenState extends ConsumerState<ContactSupportScreen> {
  final _subject = TextEditingController();
  final _message = TextEditingController();
  bool _sending = false;

  @override
  void dispose() {
    _subject.dispose();
    _message.dispose();
    super.dispose();
  }

  static final _subjectRule = FieldPreset.text(label: 'subject', min: 3, max: 200);
  static final _messageRule = FieldPreset.text(label: 'message', min: 5, max: 2000);

  bool get _valid => _subjectRule.check(_subject.text) == null && _messageRule.check(_message.text) == null;

  Future<void> _send() async {
    setState(() => _sending = true);
    try {
      await ref.read(academySettingsApiProvider).submitRequest(
            kind: AcademyRequestKind.support,
            subject: _subject.text.trim(),
            details: _message.text.trim(),
          );
      ref.invalidate(myAcademyRequestsProvider);
      if (!mounted) return;
      AppNotice.success(context, 'Message sent to the Owleo team.');
      Navigator.of(context).pop();
    } on ApiException catch (e) {
      if (mounted) AppNotice.error(context, e.message);
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return SettingsPage(
      title: 'Contact Us',
      footer: AppPrimaryButton(label: 'Send Message', icon: Icons.send_rounded, busy: _sending, onPressed: _valid ? _send : null),
      children: [
        const SettingsNote(text: 'You can follow the reply under Academy Settings → My requests.'),
        const SizedBox(height: AppSpacing.x4l),
        const SettingsFieldLabel('Subject'),
        CheckedField(
          controller: _subject,
          preset: _subjectRule,
          builder: (context, hasError) => TextField(
            controller: _subject,
            maxLength: 200,
            onChanged: (_) => setState(() {}),
            textCapitalization: _subjectRule.textCapitalization,
            style: TextStyle(color: palette.text),
            decoration: settingsInput(context, 'What is this about?').copyWith(counterText: ''),
          ),
        ),
        const SizedBox(height: AppSpacing.x4l),
        const SettingsFieldLabel('Message'),
        CheckedField(
          controller: _message,
          preset: _messageRule,
          builder: (context, hasError) => TextField(
            controller: _message,
            maxLines: 6,
            maxLength: 2000,
            onChanged: (_) => setState(() {}),
            textCapitalization: _messageRule.textCapitalization,
            style: TextStyle(color: palette.text),
            decoration: settingsInput(context, 'Tell us what you need').copyWith(counterText: ''),
          ),
        ),
      ],
    );
  }
}

/// What this app is and which version is running. No legal links: the app has no pages to point
/// them at, and a link that goes nowhere is worse than none.
class AboutOwleoScreen extends StatelessWidget {
  const AboutOwleoScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return SettingsPage(
      title: 'About Owleo',
      children: [
        SettingsCard(
          padding: const EdgeInsets.all(AppSpacing.x5l),
          child: Column(
            children: [
              SettingsIconTile(icon: Icons.account_balance_outlined, color: palette.primary, soft: palette.primarySoft, size: 56),
              const SizedBox(height: AppSpacing.lg),
              Text('Owleo N.E.S.T.', style: TextStyle(fontSize: 17, fontWeight: AppType.heavy, color: palette.text)),
              const SizedBox(height: AppSpacing.sm),
              Text(
                'The all-in-one suite for performing arts academies - courses, batches, schedules, fees, '
                'attendance and more, in one place.',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: AppType.base, height: 1.5, color: palette.textMuted),
              ),
              const SizedBox(height: AppSpacing.lg),
              Text('Version $kAppVersion', style: TextStyle(fontSize: AppType.xs, color: palette.textFaint)),
            ],
          ),
        ),
      ],
    );
  }
}
