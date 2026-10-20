import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/theme.dart';
import '../../core/api/api_exception.dart';
import '../../core/auth/session.dart';
import '../../core/format.dart';
import '../../core/json.dart';
import '../../core/ui/async.dart';
import '../../core/ui/controls.dart';
import '../../core/ui/icons.dart';
import '../../core/ui/overlays.dart';
import '../../core/ui/primitives.dart';
import '../users/users_screen.dart' show FieldRow2;

final settingsProvider = FutureProvider.autoDispose<Map<String, dynamic>>((ref) => ref.watch(dioClientProvider).getMap('/admin/hq/settings'));
final teamProvider = FutureProvider.autoDispose<Map<String, dynamic>>((ref) => ref.watch(dioClientProvider).getMap('/admin/hq/team'));

const _modes = [
  ('ERP_FIRST', 'ERP first', 'Both sides are available. The app opens on the ERP side: fees, attendance and batches.', false),
  ('SOCIAL_FIRST', 'Social first', 'Both sides are available. The app opens on Owleo Social.', false),
  ('ERP_ONLY', 'ERP only', 'Social is hidden for everyone and the centre toggle goes away. Use this while Social is not ready for academies.', true),
  ('SOCIAL_ONLY', 'Social only', 'ERP is hidden for everyone and the centre toggle goes away.', true),
];

/// Platform settings: which side of the app people get, and who works in this console.
class SettingsScreen extends ConsumerStatefulWidget {
  const SettingsScreen({super.key});

  @override
  ConsumerState<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends ConsumerState<SettingsScreen> {
  Future<void> _set(String mode, String name, bool hides) async {
    final isSuper = ref.read(sessionProvider).user?.isSuper ?? false;
    if (!isSuper) return showToast(context, 'Only a Super admin can change this');
    if (hides) {
      final side = mode == 'ERP_ONLY' ? 'Social' : 'ERP';
      final ok = await confirmHq(
        context,
        title: 'Switch to $name?',
        body: '$side disappears from the app and the centre toggle goes away, for every user, right now.${mode == 'ERP_ONLY' ? ' Guests and Artists keep the Social side so they do not land on a blank screen.' : ' Members of an academy will open the app with no ERP, so they cannot reach fees or attendance.'} You can switch back at any time.',
        confirmLabel: 'Switch now',
        danger: true,
      );
      if (!ok) return;
    }
    try {
      await ref.read(dioClientProvider).putMap('/admin/hq/settings/app-mode', body: {'mode': mode});
      ref.invalidate(settingsProvider);
      if (mounted) showToast(context, 'App mode is now $name');
    } on ApiException catch (e) {
      if (mounted) showToast(context, e.message);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isSuper = ref.watch(sessionProvider).user?.isSuper ?? false;
    return asyncBody(ref.watch(settingsProvider), onRetry: () => ref.invalidate(settingsProvider), data: (d) {
      final mode = d.str('mode');
      final history = d.maps('history');
      return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        const SectionLabel('App mode'),
        Padding(padding: const EdgeInsets.fromLTRB(2, 0, 2, 12), child: Text("Controls which side the app opens on, and whether the centre toggle in the bottom bar is available at all.", style: HqText.muted.copyWith(fontSize: 12.5))),
        for (final (k, n, desc, hides) in _modes)
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: HqCard(
              radius: 16,
              padding: const EdgeInsets.all(16),
              color: mode == k ? Hq.primary.withValues(alpha: .12) : null,
              borderColor: mode == k ? Hq.primary : null,
              onTap: mode == k ? null : () => _set(k, n, hides),
              child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Container(
                  width: 22,
                  height: 22,
                  margin: const EdgeInsets.only(top: 2),
                  decoration: BoxDecoration(shape: BoxShape.circle, border: Border.all(color: mode == k ? Hq.primary : Hq.muted, width: 2)),
                  child: mode == k ? Center(child: Container(width: 11, height: 11, decoration: const BoxDecoration(shape: BoxShape.circle, color: Hq.primary))) : null,
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Row(children: [Text(n, style: HqText.row.copyWith(fontSize: 15)), if (hides) ...[const SizedBox(width: 8), const Tag('hides one side', tone: Tone.gold)]]),
                    const SizedBox(height: 4),
                    Text(desc, style: HqText.muted.copyWith(fontSize: 13, height: 1.4)),
                  ]),
                ),
              ]),
            ),
          ),
        HqCard(
          margin: const EdgeInsets.only(top: 6),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            ic('flag', 15, Hq.muted),
            const SizedBox(width: 10),
            Expanded(child: Text('Guests and Artists have no ERP access, so "ERP only" still leaves them the Social side. Otherwise they would open the app to a blank screen. Everyone with an academy membership sees only ERP, as intended.', style: HqText.muted.copyWith(fontSize: 12.5, height: 1.5))),
          ]),
        ),
        HqCard(
          margin: const EdgeInsets.only(top: 12),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            CardHeader('Change history', sub: 'Now: ${_modes.firstWhere((m) => m.$1 == mode, orElse: () => _modes.first).$2}', bottom: 6),
            if (history.isEmpty) const EmptyNote('No changes yet', padding: 14),
            HqList([for (final h in history) HqRow(title: h.str('text'), wrap: true, sub: '${h.str('who')} · ${ago(h['at'])}')]),
          ]),
        ),
        const SizedBox(height: 18),
        const _Team(),
        if (!isSuper) Padding(padding: const EdgeInsets.fromLTRB(2, 12, 2, 0), child: Text('Only a Super admin can change settings or manage the team.', style: HqText.sub)),
      ]);
    });
  }
}

class _Team extends ConsumerWidget {
  const _Team();

  Future<void> _call(BuildContext context, WidgetRef ref, Future<void> Function() f, String ok) async {
    try {
      await f();
      ref.invalidate(teamProvider);
      if (context.mounted && ok.isNotEmpty) showToast(context, ok);
    } on ApiException catch (e) {
      if (context.mounted) showToast(context, e.message);
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isSuper = ref.watch(sessionProvider).user?.isSuper ?? false;
    final me = ref.watch(sessionProvider).user;
    final dio = ref.read(dioClientProvider);
    return asyncBody(ref.watch(teamProvider), onRetry: () => ref.invalidate(teamProvider), data: (d) {
      final members = d.maps('members');
      final roles = d.maps('roles');
      return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        const SectionLabel('HQ team'),
        Padding(padding: const EdgeInsets.fromLTRB(2, 0, 2, 12), child: Text('The people who sign in to this console, and what each may do.', style: HqText.muted.copyWith(fontSize: 12.5))),
        if (isSuper)
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: HqButton('Add a team member', icon: 'plus', kind: BtnKind.primary, expand: true, onPressed: () async {
              final done = await showHqModal<Map<String, dynamic>>(context, builder: (_) => _Invite(roles: roles));
              if (done != null) {
                ref.invalidate(teamProvider);
                if (context.mounted) {
                  await showHqModal<void>(context, width: 440, builder: (_) => _Credentials(username: done.str('username'), password: done.str('password')));
                }
              }
            }),
          ),
        HqCard(
          child: HqList([
            for (final m in members)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Row(children: [
                  Avatar(initials(m.str('name')), tone: m.flag('active') ? Tone.primary : Tone.mute),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text('${m.str('name')}${m.str('id') == me?.id ? ' (you)' : ''}', style: HqText.row, maxLines: 1, overflow: TextOverflow.ellipsis),
                      Text('${m.str('username')} · ${m['lastSeen'] == null ? 'Never signed in' : 'Seen ${ago(m['lastSeen'])}'}', style: HqText.small, maxLines: 1, overflow: TextOverflow.ellipsis),
                    ]),
                  ),
                  if (isSuper)
                    SizedBox(
                      width: 150,
                      child: HqSelect<String>(
                        value: m.str('role'),
                        searchable: false,
                        compact: true,
                        bottom: 0,
                        options: [for (final r in roles) SelectOption(r.str('code'), r.str('label'))],
                        onChanged: (v) => _call(context, ref, () async => await dio.putMap('/admin/hq/team/${m.str('id')}/role', body: {'role': v}), 'Role changed'),
                      ),
                    )
                  else
                    Tag(m.str('roleLabel'), tone: Tone.primary),
                  if (isSuper && m.str('id') != me?.id) ...[
                    const SizedBox(width: 8),
                    HqSwitch(value: m.flag('active'), onChanged: (v) => _call(context, ref, () async => await dio.putMap('/admin/hq/team/${m.str('id')}/active', body: {'active': v}), v ? 'Reactivated' : 'Deactivated')),
                  ],
                ]),
              ),
          ]),
        ),
        HqCard(
          margin: const EdgeInsets.only(top: 12),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            const CardHeader('Roles', sub: 'What each role can open and do', bottom: 6),
            HqList([
              for (final r in roles)
                HqRow(
                  title: r.str('label'),
                  wrap: true,
                  sub: '${r.str('description')}\n${r.flag('write') ? 'Can make changes' : 'View only, plus actions in its own area'}${r.flag('export') ? ' · Can export' : ''}',
                ),
            ]),
          ]),
        ),
      ]);
    });
  }
}

class _Invite extends ConsumerStatefulWidget {
  const _Invite({required this.roles});
  final List<Map<String, dynamic>> roles;

  @override
  ConsumerState<_Invite> createState() => _InviteState();
}

class _InviteState extends ConsumerState<_Invite> {
  final _name = TextEditingController(), _user = TextEditingController(), _phone = TextEditingController(), _email = TextEditingController();
  String _role = 'OPS';
  String? _error;
  bool _busy = false;

  @override
  void dispose() {
    for (final c in [_name, _user, _phone, _email]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _go() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final r = await ref.read(dioClientProvider).postMap('/admin/hq/team', body: {'name': _name.text.trim(), 'username': _user.text.trim(), 'phone': _phone.text.trim(), 'email': _email.text.trim(), 'role': _role});
      if (mounted) Navigator.of(context).pop(r);
    } on ApiException catch (e) {
      setState(() {
        _busy = false;
        _error = e.message;
      });
    }
  }

  @override
  Widget build(BuildContext context) => ModalFrame(
        title: 'Add a team member',
        sub: 'They sign in to this console with the username and a temporary password',
        error: _error,
        actions: [HqButton('Cancel', onPressed: () => Navigator.of(context).pop()), HqButton('Create login', kind: BtnKind.primary, busy: _busy, onPressed: _go)],
        children: [
          HqField(label: 'Full name', controller: _name),
          FieldRow2([HqField(label: 'Username', controller: _user, hint: 'letters, numbers, dots'), HqSelect<String>(label: 'Role', value: _role, searchable: false, options: [for (final r in widget.roles) SelectOption(r.str('code'), r.str('label'))], onChanged: (v) => setState(() => _role = v))]),
          FieldRow2([HqField(label: 'Mobile', controller: _phone, keyboard: TextInputType.phone, formatters: [FilteringTextInputFormatter.digitsOnly, LengthLimitingTextInputFormatter(10)]), HqField(label: 'Email', controller: _email, keyboard: TextInputType.emailAddress)]),
        ],
      );
}

class _Credentials extends StatelessWidget {
  const _Credentials({required this.username, required this.password});
  final String username, password;

  @override
  Widget build(BuildContext context) {
    Widget row(String l, String v) => Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: Row(children: [
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text(l, style: HqText.small), Text(v, style: HqText.row.copyWith(fontSize: 15, letterSpacing: .5))])),
            HqButton('Copy', small: true, onPressed: () {
              Clipboard.setData(ClipboardData(text: v));
              showToast(context, 'Copied');
            }),
          ]),
        );
    return ModalFrame(
      title: 'Login created',
      sub: 'Give these to the new team member',
      actions: [HqButton('Done', kind: BtnKind.primary, onPressed: () => Navigator.of(context).pop())],
      children: [row('Username', username), row('Temporary password', password), Text('Shown once. They are asked to change it at first sign in.', style: HqText.sub), const SizedBox(height: 14)],
    );
  }
}
