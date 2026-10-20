import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/theme.dart';
import '../../core/api/api_exception.dart';
import '../../core/auth/session.dart';
import '../../core/format.dart';
import '../../core/json.dart';
import '../../core/ui/controls.dart';
import '../../core/ui/icons.dart';
import '../../core/ui/layout.dart';
import '../../core/ui/overlays.dart';
import '../../core/ui/primitives.dart';
import '../academies/academy_meta.dart';
import 'users_screen.dart';

final userDetailProvider = FutureProvider.autoDispose.family<Map<String, dynamic>, String>(
  (ref, id) => ref.watch(dioClientProvider).getMap('/admin/hq/users/$id'),
);

Future<void> showUserDrawer(BuildContext context, WidgetRef ref, String id) {
  return showHqDrawer(context, builder: (_) => _UserDrawer(id: id));
}

const _deactivateReasons = ['Left the academy', 'Duplicate account', 'Requested by the academy', 'Non-payment', 'Security concern'];
const _reactivateReasons = ['Rejoined the academy', 'Deactivated by mistake', 'Dues cleared'];

class _UserDrawer extends ConsumerStatefulWidget {
  const _UserDrawer({required this.id});
  final String id;

  @override
  ConsumerState<_UserDrawer> createState() => _UserDrawerState();
}

class _UserDrawerState extends ConsumerState<_UserDrawer> {
  final Map<String, String> _revealed = {};
  bool _editing = false;
  bool _deact = false;

  void _refresh() {
    ref.invalidate(userDetailProvider(widget.id));
    ref.invalidate(usersProvider);
  }

  Future<void> _reveal(String field) async {
    try {
      final r = await ref.read(dioClientProvider).postMap('/admin/hq/users/${widget.id}/reveal', body: {'field': field});
      if (mounted) setState(() => _revealed[field] = r.str('value'));
    } on ApiException catch (e) {
      if (mounted) showToast(context, e.message);
    }
  }

  @override
  Widget build(BuildContext context) {
    final detail = ref.watch(userDetailProvider(widget.id));
    return detail.when(
      loading: () => const Center(child: CircularProgressIndicator(color: Hq.primary, strokeWidth: 2.5)),
      error: (e, _) => Padding(padding: const EdgeInsets.all(24), child: HqError(e is ApiException ? e.message : 'Could not load this person.')),
      data: (d) {
        final tone = roleTone(d.str('role'));
        final cover = AcademyMeta.coverColors(d.str('role') == 'Student' ? 'Dance' : d.str('role') == 'Trainer' ? 'Music' : 'Multi').map(Color.new).toList();
        return DrawerShell(
          coverColors: cover,
          logo: DrawerLogo(initials(d.str('name')), color: tone.color),
          child: _body(d),
        );
      },
    );
  }

  Widget _body(Map<String, dynamic> d) {
    final user = ref.watch(sessionProvider).user;
    final canWrite = user?.canWrite ?? false;
    final missing = d.strings('missing');
    final active = d.str('status') == 'Active';
    final f = d.obj('fields');
    final academies = d.maps('academies');
    final changes = d.maps('changes');
    final history = d.maps('statusHistory');
    final joined = toDate(d['joined']);

    Widget contact(String key, String label, Map<String, dynamic> c) {
      final present = c.flag('present');
      final shown = _revealed[key] ?? c.strOrNull('masked');
      return HqRow(
        title: present ? shown! : 'Missing',
        titleStyle: present ? null : HqText.row.copyWith(color: Hq.red),
        sub: label,
        trailing: present
            ? (_revealed.containsKey(key) ? null : HqButton('Reveal', icon: 'lock', small: true, onPressed: () => _reveal(key)))
            : const Tag('Required', tone: Tone.red),
      );
    }

    Widget value(String label, String? v, {String Function(String)? fmt}) => HqRow(
          title: v == null || v.isEmpty ? 'Missing' : (fmt?.call(v) ?? v),
          titleStyle: v == null || v.isEmpty ? HqText.row.copyWith(color: Hq.red) : null,
          sub: label,
          wrap: true,
          trailing: v == null || v.isEmpty ? const Tag('Required', tone: Tone.red) : null,
        );

    final required = d.obj('required');
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Text(d.str('name'), style: HqText.h2.copyWith(fontSize: 19)),
      const SizedBox(height: 2),
      Text('${d.str('ref')} · ${d.str('role')} · ${academies.isEmpty ? '' : academies.first.str('academy')}', style: HqText.muted),
      const SizedBox(height: 10),
      Wrap(spacing: 6, runSpacing: 6, children: [
        Tag(d.str('status'), tone: active ? Tone.green : Tone.mute),
        Tag(d.str('access'), tone: Tone.mute),
        if (missing.isEmpty) const Tag('Profile complete', tone: Tone.green) else Tag('${missing.length} missing', tone: Tone.red),
      ]),
      MiniStats([
        ('${academies.length}', 'Academies', null),
        (joined == null ? '' : monthLong('${joined.year}-${joined.month.toString().padLeft(2, '0')}'), 'Joined', null),
        ('${changes.length}', 'Changes', null),
      ]),
      if (!canWrite)
        HqCard(
          margin: const EdgeInsets.only(bottom: 12),
          padding: const EdgeInsets.all(12),
          child: Row(children: [
            ic('lock', 13, Hq.muted),
            const SizedBox(width: 8),
            Expanded(child: Text('Your role can view profiles but not change them.', style: HqText.muted.copyWith(fontSize: 12.5))),
          ]),
        ),
      if (missing.isNotEmpty && !_editing)
        HqCard(
          margin: const EdgeInsets.only(bottom: 12),
          color: Hq.red.withValues(alpha: .07),
          borderColor: Hq.red.withValues(alpha: .4),
          padding: const EdgeInsets.all(14),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const IconTile('warn', tone: Tone.red),
              const SizedBox(width: 10),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text('Mandatory details are missing', style: HqText.row.copyWith(fontSize: 13.5)),
                  const SizedBox(height: 3),
                  Text(missing.join(', '), style: HqText.muted.copyWith(fontSize: 12.5)),
                ]),
              ),
            ]),
            if (canWrite) Padding(padding: const EdgeInsets.only(top: 10), child: Align(alignment: Alignment.centerLeft, child: HqButton('Fill in now', small: true, kind: BtnKind.primary, onPressed: () => setState(() => _editing = true)))),
          ]),
        ),
      if (_editing)
        _EditForm(
          id: widget.id,
          required: required.keys.toSet(),
          onCancel: () => setState(() => _editing = false),
          onSaved: () {
            setState(() {
              _editing = false;
              _revealed.clear();
            });
            _refresh();
            showToast(context, 'Profile updated');
          },
        )
      else ...[
        HqCard(
          margin: const EdgeInsets.only(bottom: 12),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            CardHeader('Personal details',
                sub: 'Contact details are hidden until revealed. Each reveal is logged.',
                bottom: 4,
                trailing: canWrite ? HqButton('Edit', icon: 'edit', small: true, onPressed: () => setState(() => _editing = true)) : null),
            HqList([
              contact('mobile', 'Mobile', f.obj('mobile')),
              contact('email', 'Email', f.obj('email')),
              value('Address', f.strOrNull('addr')),
              value('Date of birth', f.strOrNull('dob'), fmt: fd),
              contact('emer', 'Emergency contact', f.obj('emer')),
              if (f.flag('minor')) value('Guardian', f.strOrNull('guard')),
            ]),
          ]),
        ),
        HqCard(
          margin: const EdgeInsets.only(bottom: 12),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            CardHeader('Academy and mapping', sub: academies.length > 1 ? 'This person works in ${academies.length} academies' : 'Course, batch and trainer', bottom: 4),
            if (academies.isEmpty) const EmptyNote('Not in any academy'),
            HqList([
              for (final a in academies)
                HqRow(
                  leading: const IconTile('bld', tone: Tone.violet),
                  title: '${a.str('academy')} · ${a.str('role')}${a.str('status') == 'Active' ? '' : ' (removed)'}',
                  wrap: true,
                  sub: a.maps('batches').isEmpty
                      ? 'No course or batch yet'
                      : a.maps('batches').map((b) => '${b.str('course')} · ${b.str('batch')}${b.strOrNull('trainer') == null ? '' : ' · Trainer ${b.str('trainer')}'}').join('\n'),
                ),
            ]),
          ]),
        ),
      ],
      if (_deact)
        _StatusPanel(
          id: widget.id,
          active: active,
          onCancel: () => setState(() => _deact = false),
          onDone: () {
            setState(() => _deact = false);
            _refresh();
            showToast(context, active ? 'Account deactivated' : 'Account reactivated');
          },
        ),
      HqCard(
        margin: const EdgeInsets.only(bottom: 12),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          const CardHeader('Activity history', sub: 'Previous and updated values', bottom: 6),
          if (changes.isEmpty) const EmptyNote('No changes recorded yet', padding: 14),
          HqList([for (final c in changes) HqRow(title: c.str('f'), wrap: true, sub: '${c.str('from')} → ${c.str('to')}\n${c.str('by')} · ${ago(c['at'])}')]),
        ]),
      ),
      HqCard(
        margin: const EdgeInsets.only(bottom: 12),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          CardHeader('Account status',
              sub: 'History of activations and deactivations',
              bottom: 6,
              trailing: canWrite && !_deact ? HqButton(active ? 'Deactivate' : 'Reactivate', small: true, onPressed: () => setState(() => _deact = true)) : null),
          if (history.isEmpty) const EmptyNote('No status changes recorded', padding: 14),
          HqList([
            for (final s in history)
              HqRow(
                leading: Tag(s.str('s'), tone: s.str('s') == 'Active' ? Tone.green : Tone.mute),
                title: s.str('why'),
                wrap: true,
                sub: '${s.str('by')} · ${ago(s['at'])}',
              ),
          ]),
        ]),
      ),
    ]);
  }
}

// ---------------------------------------------------------------------------------------------

class _EditForm extends ConsumerStatefulWidget {
  const _EditForm({required this.id, required this.required, required this.onCancel, required this.onSaved});
  final String id;
  final Set<String> required;
  final VoidCallback onCancel, onSaved;

  @override
  ConsumerState<_EditForm> createState() => _EditFormState();
}

class _EditFormState extends ConsumerState<_EditForm> {
  final _name = TextEditingController(), _mobile = TextEditingController(), _email = TextEditingController();
  final _addr = TextEditingController(), _emer = TextEditingController(), _guard = TextEditingController();
  String? _dob;
  bool _minor = false;
  bool _loaded = false;
  bool _busy = false;
  String? _error;
  Map<String, String> _errs = {};

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    for (final c in [_name, _mobile, _email, _addr, _emer, _guard]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final e = await ref.read(dioClientProvider).getMap('/admin/hq/users/${widget.id}/edit');
      if (!mounted) return;
      setState(() {
        _name.text = e.str('name');
        _mobile.text = e.str('mobile');
        _email.text = e.str('email');
        _addr.text = e.str('addr');
        _emer.text = e.str('emer');
        _guard.text = e.str('guard');
        _dob = e.strOrNull('dob');
        _minor = e.flag('minor');
        _loaded = true;
      });
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    }
  }

  bool _req(String k) => widget.required.contains(k);

  Future<void> _save() async {
    final errs = <String, String>{};
    if (_name.text.trim().length < 3) errs['name'] = 'Enter the full name.';
    if (!RegExp(r'^[6-9]\d{9}$').hasMatch(_mobile.text.replaceAll(' ', ''))) errs['mobile'] = 'Enter a valid 10-digit mobile number.';
    final email = _email.text.trim();
    if (email.isNotEmpty && !RegExp(r'^\S+@\S+\.\S+$').hasMatch(email)) errs['email'] = 'Enter a valid email address.';
    if (_req('email') && email.isEmpty) errs['email'] = 'Email is required.';
    if (_req('addr') && _addr.text.trim().isEmpty) errs['addr'] = 'Address is required.';
    if (_req('dob') && _dob == null) errs['dob'] = 'Date of birth is required.';
    final emer = _emer.text.replaceAll(' ', '');
    if (emer.isNotEmpty && !RegExp(r'^[6-9]\d{9}$').hasMatch(emer)) errs['emer'] = 'Enter a 10-digit mobile number.';
    if (_req('emer') && emer.isEmpty) errs['emer'] = 'Emergency contact is required.';
    if (_minor && _req('guard') && _guard.text.trim().isEmpty) errs['guard'] = 'Guardian details are required under 18.';
    if (errs.isNotEmpty) return setState(() => _errs = errs);
    setState(() {
      _busy = true;
      _errs = {};
      _error = null;
    });
    try {
      await ref.read(dioClientProvider).putMap('/admin/hq/users/${widget.id}', body: {
        'name': _name.text.trim(),
        'mobile': _mobile.text.replaceAll(' ', ''),
        'email': email,
        'addr': _addr.text.trim(),
        'dob': _dob ?? '',
        'emer': emer,
        'guard': _guard.text.trim(),
      });
      widget.onSaved();
    } on ApiException catch (e) {
      setState(() {
        _busy = false;
        _error = e.message;
      });
    }
  }

  Future<void> _pickDob() async {
    final cur = _dob == null ? null : DateTime.tryParse(_dob!);
    final d = await pickHqDate(context, initial: cur ?? DateTime(2005), first: DateTime(1940), last: DateTime.now());
    if (d == null) return;
    setState(() {
      _dob = '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
      _minor = d.isAfter(DateTime(DateTime.now().year - 18, DateTime.now().month, DateTime.now().day));
    });
  }

  @override
  Widget build(BuildContext context) {
    if (!_loaded) {
      return Padding(padding: const EdgeInsets.all(24), child: _error == null ? const Center(child: CircularProgressIndicator(color: Hq.primary, strokeWidth: 2.5)) : HqError(_error!));
    }
    String star(String k, String l) => _req(k) ? '$l *' : l;
    return HqCard(
      margin: const EdgeInsets.only(bottom: 12),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        const CardHeader('Edit profile', sub: 'Fields marked * are mandatory for every academy'),
        HqField(label: 'Full name *', controller: _name, error: _errs['name']),
        HqField(label: 'Mobile *', controller: _mobile, keyboard: TextInputType.phone, error: _errs['mobile'], formatters: [FilteringTextInputFormatter.digitsOnly, LengthLimitingTextInputFormatter(10)]),
        HqField(label: star('email', 'Email'), controller: _email, keyboard: TextInputType.emailAddress, error: _errs['email']),
        HqField(label: star('addr', 'Address'), controller: _addr, error: _errs['addr']),
        GestureDetector(
          onTap: _pickDob,
          behavior: HitTestBehavior.opaque,
          child: AbsorbPointer(
            child: HqField(
              label: star('dob', 'Date of birth'),
              controller: TextEditingController(text: _dob == null ? '' : fd(_dob)),
              hint: 'Choose a date',
              readOnly: true,
              error: _errs['dob'],
              suffix: ic('cal', 16, Hq.muted),
            ),
          ),
        ),
        HqField(label: star('emer', 'Emergency contact'), controller: _emer, keyboard: TextInputType.phone, error: _errs['emer'], formatters: [FilteringTextInputFormatter.digitsOnly, LengthLimitingTextInputFormatter(10)]),
        if (_minor) HqField(label: star('guard', 'Guardian'), controller: _guard, error: _errs['guard']),
        if (_error != null) Padding(padding: const EdgeInsets.only(bottom: 10), child: Text(_error!, style: HqText.small.copyWith(color: Hq.red))),
        Row(children: [
          Expanded(child: HqButton('Cancel', expand: true, onPressed: widget.onCancel)),
          const SizedBox(width: 8),
          Expanded(child: HqButton('Save changes', icon: 'check', kind: BtnKind.primary, expand: true, busy: _busy, onPressed: _save)),
        ]),
      ]),
    );
  }
}

class _StatusPanel extends ConsumerStatefulWidget {
  const _StatusPanel({required this.id, required this.active, required this.onCancel, required this.onDone});
  final String id;
  final bool active;
  final VoidCallback onCancel, onDone;

  @override
  ConsumerState<_StatusPanel> createState() => _StatusPanelState();
}

class _StatusPanelState extends ConsumerState<_StatusPanel> {
  late String _reason = widget.active ? _deactivateReasons.first : _reactivateReasons.first;
  final _note = TextEditingController();
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _note.dispose();
    super.dispose();
  }

  Future<void> _go() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await ref.read(dioClientProvider).postMap('/admin/hq/users/${widget.id}/status', body: {'active': !widget.active, 'reason': _reason, 'note': _note.text.trim()});
      widget.onDone();
    } on ApiException catch (e) {
      setState(() {
        _busy = false;
        _error = e.message;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return HqCard(
      margin: const EdgeInsets.only(bottom: 12),
      borderColor: Hq.red.withValues(alpha: .4),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        CardHeader(widget.active ? 'Deactivate account' : 'Reactivate account', sub: widget.active ? 'They are signed out everywhere and lose academy access. The reason is recorded.' : 'Access to their academies returns. The reason is recorded.', bottom: 10),
        HqSelect<String>(
          label: 'Reason',
          value: _reason,
          searchable: false,
          options: [for (final r in widget.active ? _deactivateReasons : _reactivateReasons) SelectOption(r, r)],
          onChanged: (v) => setState(() => _reason = v),
        ),
        HqField(label: 'Note', controller: _note, hint: 'Optional detail'),
        if (_error != null) Padding(padding: const EdgeInsets.only(bottom: 10), child: Text(_error!, style: HqText.small.copyWith(color: Hq.red))),
        Row(children: [
          Expanded(child: HqButton('Cancel', expand: true, onPressed: widget.onCancel)),
          const SizedBox(width: 8),
          Expanded(child: HqButton(widget.active ? 'Deactivate' : 'Reactivate', kind: widget.active ? BtnKind.danger : BtnKind.primary, expand: true, busy: _busy, onPressed: _go)),
        ]),
      ]),
    );
  }
}
