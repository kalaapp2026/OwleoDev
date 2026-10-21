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
import '../../core/ui/layout.dart';
import '../../core/ui/overlays.dart';
import '../../core/ui/primitives.dart';

final notifsProvider = FutureProvider.autoDispose<Map<String, dynamic>>((ref) => ref.watch(dioClientProvider).getMap('/admin/hq/notifications'));

final notifLogProvider = FutureProvider.autoDispose.family<List<Map<String, dynamic>>, String>(
  (ref, status) => ref.watch(dioClientProvider).getList('/admin/hq/notifications/log', query: {'status': status}),
);

const _channelOrder = ['inapp', 'push', 'wa', 'mail'];
const _channelIcon = {'inapp': 'bell', 'push': 'send', 'wa': 'msg', 'mail': 'mail'};
const _channelName = {'inapp': 'In-app', 'push': 'Push', 'wa': 'WhatsApp', 'mail': 'Email'};

/// The details a module can put in a message, as the server lists them.
class _Catalogue {
  _Catalogue(Map<String, dynamic> d) : modules = d.maps('modules'), audiences = d.maps('audiences'), userTypes = d.maps('userTypes');

  final List<Map<String, dynamic>> modules, audiences, userTypes;

  Map<String, dynamic> module(String id) => modules.firstWhere((m) => m.str('id') == id, orElse: () => modules.first);
  Map<String, dynamic> event(String module, String key) {
    final evs = this.module(module).maps('events');
    return evs.firstWhere((e) => e.str('key') == key, orElse: () => evs.first);
  }

  List<Map<String, dynamic>> vars(String module) => this.module(module).maps('vars');
}

bool _security(String module) => module == 'security';

/// Channels a module can use: sign-in messages go by email or WhatsApp only, since the person is not signed in.
List<String> _channelsFor(String module) => _security(module) ? ['mail', 'wa'] : _channelOrder;

(String, Tone) _status(Map<String, dynamic> t) {
  if (t.str('body').isEmpty || t.str('title').isEmpty) return ('Not configured', Tone.mute);
  return t.flag('on') ? ('On', Tone.green) : ('Off', Tone.gold);
}

/// Text with {details} swapped for sample values (bold); a detail the module does not have shows red.
InlineSpan _fill(String text, List<Map<String, dynamic>> vars, TextStyle base) {
  final spans = <InlineSpan>[];
  var last = 0;
  for (final m in RegExp(r'\{(\w+)\}').allMatches(text)) {
    if (m.start > last) spans.add(TextSpan(text: text.substring(last, m.start)));
    final v = vars.where((x) => x.str('key') == m.group(1)).toList();
    spans.add(v.isEmpty
        ? TextSpan(text: m.group(0), style: const TextStyle(color: Hq.red))
        : TextSpan(text: v.first.str('sample'), style: const TextStyle(fontWeight: FontWeight.w800)));
    last = m.end;
  }
  if (last < text.length) spans.add(TextSpan(text: text.substring(last)));
  return TextSpan(style: base, children: spans);
}

/// Notification templates: design what people are told and link it to a module.
class NotificationsScreen extends ConsumerStatefulWidget {
  const NotificationsScreen({super.key});

  @override
  ConsumerState<NotificationsScreen> createState() => _NotificationsScreenState();
}

class _NotificationsScreenState extends ConsumerState<NotificationsScreen> {
  String _tab = 'tp', _mod = 'all', _q = '', _logFilter = 'all';

  void _refresh() {
    ref.invalidate(notifsProvider);
    ref.invalidate(notifLogProvider);
  }

  Future<void> _open(Map<String, dynamic> d, Map<String, dynamic>? template, {bool copy = false}) async {
    final result = await showHqDrawer<Object>(context, width: 520, builder: (_) => _Editor(catalogue: _Catalogue(d), ready: d.obj('ready'), template: template, asNew: template == null || copy, canWrite: _canWrite));
    if (result == true) _refresh();
    // "Duplicate" closes the drawer and hands back the copy to edit as a new template.
    if (result is Map<String, dynamic> && mounted) await _open(d, result, copy: true);
  }

  bool get _canWrite {
    final u = ref.read(sessionProvider).user;
    return u != null && (u.isSuper || u.role.code == 'OPS');
  }

  @override
  Widget build(BuildContext context) {
    return asyncBody(ref.watch(notifsProvider), onRetry: _refresh, data: (d) {
      final counts = d.obj('counts');
      final ready = d.obj('ready');
      final cat = _Catalogue(d);
      final all = d.maps('templates');
      final q = _q.trim().toLowerCase();
      final list = all.where((t) => (_mod == 'all' || t.str('module') == _mod) && (q.isEmpty || '${t.str('name')} ${t.str('title')} ${t.str('body')}'.toLowerCase().contains(q))).toList();

      return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        HqGrid(GridKind.g4, [
          Kpi(icon: 'check', tone: Tone.green, label: 'Templates on', value: '${counts.integer('on')}', foot: '${counts.integer('written')} of ${counts.integer('all')} are written'),
          Kpi(icon: 'send', tone: Tone.blue, label: 'Sent today', value: num0(counts.integer('sentToday')), foot: 'across all channels'),
          Kpi(icon: 'warn', tone: Tone.gold, label: 'Skipped', value: '${counts.integer('skipped')}', foot: 'channel not set up, last 7 days'),
          Kpi(icon: 'bell', tone: Tone.red, label: 'Failed', value: '${counts.integer('failed')}', foot: 'check the log, last 7 days'),
        ]),
        Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: SegControl<String>(expand: true, items: const [('tp', 'Templates'), ('lg', 'Delivery log')], value: _tab, onChanged: (v) => setState(() => _tab = v)),
        ),
        if (_tab == 'tp') ..._templates(d, cat, ready, list, all) else _log(),
      ]);
    });
  }

  List<Widget> _templates(Map<String, dynamic> d, _Catalogue cat, Map<String, dynamic> ready, List<Map<String, dynamic>> list, List<Map<String, dynamic>> all) {
    return [
      HqCard(
        margin: const EdgeInsets.only(bottom: 12),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const CardHeader('Channels', bottom: 8),
          Wrap(spacing: 8, runSpacing: 8, children: [
            for (final c in _channelOrder) Tag('${_channelName[c]} · ${ready.flag(c) ? 'ready' : 'not set up'}', tone: ready.flag(c) ? Tone.green : Tone.mute, icon: _channelIcon[c], lowercase: true),
          ]),
          const SizedBox(height: 10),
          Text(
            'In-app messages always send. Push, WhatsApp and Email send once their credentials are set on the server, and sign-in codes use Email or WhatsApp. Until then you can still design templates; deliveries to a channel that is not set up are logged as skipped. Only a few moments (class changes, absences, fee payments) are wired to send today; the rest are saved for when they are.',
            style: HqText.sub.copyWith(height: 1.5),
          ),
        ]),
      ),
      Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: Row(children: [
          Expanded(child: SearchBox(hint: 'Search templates', height: 46, onChanged: (v) => setState(() => _q = v))),
          const SizedBox(width: 8),
          if (_canWrite) HqButton('New', icon: 'plus', kind: BtnKind.primary, onPressed: () => _open(d, null)),
        ]),
      ),
      Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: ChipRow(scroll: true, [
          HqChip('All modules', selected: _mod == 'all', onTap: () => setState(() => _mod = 'all')),
          for (final m in cat.modules) HqChip(m.str('name'), selected: _mod == m.str('id'), count: all.where((t) => t.str('module') == m.str('id')).length, onTap: () => setState(() => _mod = m.str('id'))),
        ]),
      ),
      if (list.isEmpty) const EmptyNote('No templates match.'),
      for (final m in cat.modules)
        if (list.any((t) => t.str('module') == m.str('id'))) ...[
          SectionLabel(m.str('name'), top: 6),
          LayoutBuilder(builder: (context, c) {
            final cols = c.maxWidth >= 760 ? 2 : 1;
            final items = list.where((t) => t.str('module') == m.str('id')).toList();
            return Wrap(spacing: 10, runSpacing: 10, children: [for (final t in items) SizedBox(width: (c.maxWidth - (cols - 1) * 10) / cols, child: _card(d, cat, t))]);
          }),
        ],
    ];
  }

  Widget _card(Map<String, dynamic> d, _Catalogue cat, Map<String, dynamic> t) {
    final m = cat.module(t.str('module'));
    final e = cat.event(t.str('module'), t.str('event'));
    final (label, tone) = _status(t);
    final ch = t.obj('ch');
    final security = _security(t.str('module'));
    final types = (t['types'] as List?)?.map((x) => x.toString()).toList();
    final audience = cat.audiences.where((a) => a.str('key') == t.str('audience')).map((a) => a.str('label').toLowerCase()).firstOrNull ?? 'them';
    final sentTo = security
        ? (types == null ? 'Sent to every type of user.' : 'Sent to ${types.map((k) => cat.userTypes.firstWhere((u) => u.str('key') == k, orElse: () => {'label': k}).str('label').toLowerCase()).join(', ')}.')
        : 'Sent to $audience.';
    final par = t.obj('par');
    return HqCard(
      radius: 14,
      padding: const EdgeInsets.all(12),
      onTap: () => _open(d, t),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(children: [
          IconTile(m.str('icon'), tone: Tone.byName(m.str('tone')), size: 36),
          const SizedBox(width: 11),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text(t.str('name'), style: HqText.row.copyWith(fontSize: 13.5)), Text('${e.str('text')} $sentTo', style: HqText.small)])),
          ic('chev', 15, Hq.faint),
        ]),
        const SizedBox(height: 10),
        Wrap(spacing: 6, runSpacing: 6, crossAxisAlignment: WrapCrossAlignment.center, children: [
          Tag(label, tone: tone),
          if (label == 'Not configured')
            Text('Nothing is sent', style: HqText.small)
          else ...[
            for (final c in _channelsFor(t.str('module'))) if (ch.flag(c)) Tag(_channelName[c]!, tone: Tone.mute),
            if (_channelsFor(t.str('module')).every((c) => !ch.flag(c))) const Tag('No channel', tone: Tone.red),
            if (par.flag('on')) const Tag('Parent on WhatsApp', tone: Tone.violet),
          ],
        ]),
      ]),
    );
  }

  Widget _log() {
    final log = ref.watch(notifLogProvider(_logFilter));
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: ChipRow([for (final (k, n) in const [('all', 'All'), ('sent', 'Sent'), ('skipped', 'Skipped'), ('failed', 'Failed')]) HqChip(n, selected: _logFilter == k, onTap: () => setState(() => _logFilter = k))]),
      ),
      asyncBody(log, onRetry: () => ref.invalidate(notifLogProvider), data: (rows) {
        if (rows.isEmpty) return const HqCard(child: EmptyNote('Nothing here yet.'));
        return HqCard(
          child: HqList([
            for (final x in rows)
              HqRow(
                title: x.str('name'),
                sub: '${ago(x['at'])} · ${x.str('channel')} · ${x.integer('people')} ${x.integer('people') == 1 ? 'person' : 'people'}${x.str('detail').isEmpty ? '' : ' · ${x.str('detail')}'}',
                wrap: true,
                trailing: Tag(x.str('status') == 'sent' ? 'Sent' : x.str('status') == 'skipped' ? 'Skipped' : 'Failed', tone: x.str('status') == 'sent' ? Tone.green : x.str('status') == 'skipped' ? Tone.gold : Tone.red),
              ),
          ]),
        );
      }),
      const PageNote('Deliveries are what the platform really attempted in the last 14 days, one line per template, channel and minute.'),
    ]);
  }
}

// ---------------------------------------------------------------------------------------------------------

class _Editor extends ConsumerStatefulWidget {
  const _Editor({required this.catalogue, required this.ready, required this.template, required this.asNew, required this.canWrite});

  final _Catalogue catalogue;
  final Map<String, dynamic> ready;
  final Map<String, dynamic>? template;
  final bool asNew, canWrite;

  @override
  ConsumerState<_Editor> createState() => _EditorState();
}

class _EditorState extends ConsumerState<_Editor> {
  late String _module, _event, _audience;
  late bool _on, _parOn, _parMin, _parDiff;
  late Map<String, bool> _ch;
  late Set<String> _types;
  late final TextEditingController _name, _title, _body, _timing, _parTitle, _parBody;
  final _titleFocus = FocusNode(), _bodyFocus = FocusNode(), _parTitleFocus = FocusNode(), _parBodyFocus = FocusNode();
  late TextEditingController _lastField;
  String? _error;
  bool _busy = false, _testing = false;

  _Catalogue get _cat => widget.catalogue;

  @override
  void initState() {
    super.initState();
    final t = widget.template;
    final copy = t != null && widget.asNew;
    final first = _cat.modules.first;
    _module = t?.str('module') ?? first.str('id');
    _event = t?.str('event') ?? first.maps('events').first.str('key');
    _audience = t?.str('audience') ?? 'student';
    _on = copy ? false : (t?.flag('on') ?? false);
    final ch = t?.obj('ch') ?? {'inapp': true, 'push': true};
    _ch = {for (final c in _channelOrder) c: ch.flag(c)};
    final types = (t?['types'] as List?)?.map((x) => x.toString()).toSet();
    _types = types ?? _cat.userTypes.map((u) => u.str('key')).toSet();
    final par = t?.obj('par') ?? const <String, dynamic>{};
    _parOn = par.flag('on');
    _parMin = par['min'] != false;
    _parDiff = par.flag('diff');
    _name = TextEditingController(text: copy ? '${t.str('name')} (copy)' : (t?.str('name') ?? _cat.event(_module, _event).str('name')));
    _title = TextEditingController(text: t?.str('title') ?? '');
    _body = TextEditingController(text: t?.str('body') ?? '');
    _timing = TextEditingController(text: '${t?.integer('timing', _cat.event(_module, _event).integer('timing')) ?? _cat.event(_module, _event).integer('timing')}');
    _parTitle = TextEditingController(text: par.str('title'));
    _parBody = TextEditingController(text: par.str('body'));
    _lastField = _body;
    _titleFocus.addListener(() => _titleFocus.hasFocus ? _lastField = _title : null);
    _bodyFocus.addListener(() => _bodyFocus.hasFocus ? _lastField = _body : null);
    _parTitleFocus.addListener(() => _parTitleFocus.hasFocus ? _lastField = _parTitle : null);
    _parBodyFocus.addListener(() => _parBodyFocus.hasFocus ? _lastField = _parBody : null);
  }

  @override
  void dispose() {
    for (final c in [_name, _title, _body, _timing, _parTitle, _parBody]) {
      c.dispose();
    }
    for (final f in [_titleFocus, _bodyFocus, _parTitleFocus, _parBodyFocus]) {
      f.dispose();
    }
    super.dispose();
  }

  Map<String, dynamic> get _mod => _cat.module(_module);
  Map<String, dynamic> get _ev => _cat.event(_module, _event);
  List<Map<String, dynamic>> get _vars => _cat.vars(_module);
  bool get _isNew => widget.asNew;
  bool get _parentCapable => _mod.flag('parentCapable');
  List<String> get _activeChannels => _channelsFor(_module).where((c) => _ch[c] == true).toList();

  void _changeModule(String id) {
    final was = _module;
    final wasEventName = _ev.str('name');
    setState(() {
      _module = id;
      final ev = _mod.maps('events').first;
      _event = ev.str('key');
      _timing.text = '${ev.integer('timing')}';
      if (_isNew || _name.text.trim().isEmpty || _name.text == wasEventName) _name.text = ev.str('name');
      if (_security(id) && !_security(was)) {
        _audience = 'self';
        _types = _cat.userTypes.map((u) => u.str('key')).toSet();
        _ch = {'inapp': false, 'push': false, 'wa': false, 'mail': true};
      } else if (_security(was) && !_security(id)) {
        _audience = 'student';
        _ch = {'inapp': true, 'push': true, 'wa': false, 'mail': false};
      }
      if (!_parentCapable) _parOn = false;
    });
  }

  void _changeEvent(String key) {
    setState(() {
      _event = key;
      _timing.text = '${_ev.integer('timing')}';
      if (_isNew) _name.text = _ev.str('name');
    });
  }

  void _insert(String key) {
    final c = _lastField;
    final max = c == _title || c == _parTitle ? 60 : 240;
    final tx = '{$key}';
    final sel = c.selection;
    final start = sel.isValid ? sel.start : c.text.length, end = sel.isValid ? sel.end : c.text.length;
    if (c.text.length - (end - start) + tx.length > max) return showToast(context, 'No room left');
    c.value = TextEditingValue(text: c.text.replaceRange(start, end, tx), selection: TextSelection.collapsed(offset: start + tx.length));
    setState(() {});
    (c == _title ? _titleFocus : c == _body ? _bodyFocus : c == _parTitle ? _parTitleFocus : _parBodyFocus).requestFocus();
  }

  Map<String, dynamic> _payload() => {
        'module': _module,
        'event': _event,
        'name': _name.text.trim(),
        'audience': _audience,
        'on': _on,
        'ch': _ch,
        'title': _title.text.trim(),
        'body': _body.text.trim(),
        'timing': int.tryParse(_timing.text.trim()) ?? _timing.text.trim(),
        if (_security(_module)) 'types': _types.toList(),
        'par': {'on': _parOn, 'min': _parMin, 'diff': _parDiff, 'title': _parTitle.text.trim(), 'body': _parBody.text.trim()},
      };

  void _toggleOn(bool v) {
    if (v) {
      if (_title.text.trim().isEmpty || _body.text.trim().isEmpty) return showToast(context, 'Write a title and message first');
      if (_activeChannels.isEmpty) return showToast(context, 'Pick at least one channel first');
    }
    setState(() => _on = v);
  }

  Future<void> _save() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final api = ref.read(dioClientProvider);
      final id = widget.template?.str('id');
      if (_isNew || id == null) {
        await api.postMap('/admin/hq/notifications', body: _payload());
      } else {
        await api.putMap('/admin/hq/notifications/$id', body: _payload());
      }
      if (!mounted) return;
      Navigator.of(context).pop(true);
      showToast(context, _isNew ? 'Template added' : 'Saved. ${_name.text.trim()} is ${_on ? 'on' : 'off'}');
    } on ApiException catch (e) {
      if (mounted) {
        setState(() {
          _busy = false;
          _error = e.message;
        });
      }
    }
  }

  Future<void> _test() async {
    setState(() {
      _testing = true;
      _error = null;
    });
    try {
      final r = await ref.read(dioClientProvider).call<List<dynamic>>((d) => d.post('/admin/hq/notifications/test', data: _payload()), (data) => data as List<dynamic>);
      if (!mounted) return;
      final lines = [for (final x in r) if (x is Map) '${_channelName[x['channel']] ?? x['channel']}: ${x['detail']}'];
      showToast(context, lines.join(' · '));
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _testing = false);
    }
  }

  Future<void> _delete() async {
    final ok = await confirmHq(context, title: 'Delete this template?', body: 'This notification will stop being sent. Past deliveries stay in the log.', confirmLabel: 'Delete', danger: true);
    if (!ok || !mounted) return;
    try {
      await ref.read(dioClientProvider).delete('/admin/hq/notifications/${widget.template!.str('id')}');
      if (!mounted) return;
      Navigator.of(context).pop(true);
      showToast(context, 'Template deleted');
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    }
  }

  void _duplicate() => Navigator.of(context).pop(<String, dynamic>{...?widget.template, ..._payload()});

  Widget _card(String title, String? sub, List<Widget> children) => HqCard(
        margin: const EdgeInsets.only(top: 12),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [CardHeader(title, sub: sub, bottom: 8), ...children]),
      );

  Widget _switchRow(String title, String sub, bool value, ValueChanged<bool> onChanged, {Widget? leading, String? warn}) => GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () => onChanged(!value),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: Row(children: [
            if (leading != null) ...[leading, const SizedBox(width: 11)],
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text(title, style: HqText.row), Text(sub, style: HqText.small.copyWith(color: warn != null ? Hq.gold : null))])),
            HqSwitch(value: value, onChanged: onChanged),
          ]),
        ),
      );

  @override
  Widget build(BuildContext context) {
    final m = _mod, e = _ev;
    final tone = Tone.byName(m.str('tone'));
    final timingLabel = e.strOrNull('timingLabel');
    final security = _security(_module);
    final write = widget.canWrite;
    return DrawerShell(
      coverColors: const [Color(0xFF2A3B5C), Color(0xFF1E2A4D)],
      logo: DrawerLogo('', color: tone.color, icon: m.str('icon')),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Text(_isNew ? 'New template' : widget.template!.str('name'), style: HqText.h2.copyWith(fontSize: 19)),
        const SizedBox(height: 3),
        Text('Linked to ${m.str('name')} · ${e.str('name')}', style: HqText.muted.copyWith(fontSize: 12.5)),
        HqCard(
          margin: const EdgeInsets.only(top: 14),
          child: _switchRow('Send this notification', _on ? 'On. Sent automatically when it happens.' : 'Off. Nothing is sent.', _on, write ? _toggleOn : (_) {}),
        ),
        _card('Link to a module', 'Decides which details you can use in the message', [
          HqField(label: 'Template name', controller: _name, maxLength: 40, readOnly: !write),
          HqSelect<String>(label: 'Module', value: _module, searchable: false, options: [for (final x in _cat.modules) SelectOption(x.str('id'), x.str('name'))], onChanged: write ? _changeModule : (_) {}),
          HqSelect<String>(label: 'When it is sent', value: _event, searchable: false, options: [for (final x in m.maps('events')) SelectOption(x.str('key'), x.str('name'))], onChanged: write ? _changeEvent : (_) {}),
          if (timingLabel != null) HqField(label: timingLabel[0].toUpperCase() + timingLabel.substring(1), controller: _timing, keyboard: TextInputType.number, maxLength: 3, formatters: [FilteringTextInputFormatter.digitsOnly], readOnly: !write),
          if (security) ...[
            Text('Who can get it', style: HqText.label),
            const SizedBox(height: 8),
            ChipRow([
              for (final u in _cat.userTypes)
                HqChip(u.str('label'), selected: _types.contains(u.str('key')), onTap: () {
                  if (!write) return;
                  setState(() {
                    if (_types.contains(u.str('key'))) {
                      if (_types.length == 1) return showToast(context, 'Keep at least one type of user');
                      _types.remove(u.str('key'));
                    } else {
                      _types.add(u.str('key'));
                    }
                  });
                }),
            ]),
            const SizedBox(height: 8),
            Text('Works for every type of user. Parents and guardians have no Owleo app, so their codes and links go on WhatsApp or email.', style: HqText.sub.copyWith(height: 1.5)),
          ] else
            HqSelect<String>(
              label: 'Who gets it',
              value: _audience,
              searchable: false,
              options: [for (final a in _cat.audiences) if (a.str('key') != 'self') SelectOption(a.str('key'), a.str('label'))],
              onChanged: write ? (v) => setState(() => _audience = v) : (_) {},
            ),
        ]),
        _card('Channels', 'Pick where it goes', [
          for (final c in _channelsFor(_module))
            _switchRow(
              _channelName[c]!,
              widget.ready.flag(c) ? 'Ready' : 'Not set up yet. Saved, but skipped until it is.',
              _ch[c] == true,
              write ? (v) => setState(() => _ch[c] = v) : (_) {},
              leading: IconTile(_channelIcon[c]!, tone: widget.ready.flag(c) ? Tone.primary : Tone.mute, size: 34, iconSize: 15),
              warn: widget.ready.flag(c) ? null : 'x',
            ),
          if (security) Padding(padding: const EdgeInsets.only(top: 6), child: Text('Codes and reset links go to people who are not signed in, so they use Email or WhatsApp, not the app.', style: HqText.sub.copyWith(height: 1.5))),
        ]),
        _card('Message', 'Tap a detail to put it in. It is filled in for each person.', [
          HqField(label: 'Title', controller: _title, hint: 'Short and clear', maxLength: 60, bottom: 2, readOnly: !write, onChanged: (_) => setState(() {}), focusNode: _titleFocus),
          Align(alignment: Alignment.centerRight, child: Text('${_title.text.length}/60', style: HqText.sub)),
          const SizedBox(height: 8),
          HqField(label: 'Message', controller: _body, hint: 'What should they know?', maxLength: 240, maxLines: 4, bottom: 2, readOnly: !write, onChanged: (_) => setState(() {}), focusNode: _bodyFocus),
          Align(alignment: Alignment.centerRight, child: Text('${_body.text.length}/240', style: HqText.sub)),
          const SizedBox(height: 8),
          ChipRow([for (final v in _vars) Tooltip(message: v.str('label'), child: HqChip('{${v.str('key')}}', selected: false, onTap: write ? () => _insert(v.str('key')) : () {}))]),
        ]),
        if (_parentCapable) _parent(write),
        _card('Preview', 'With sample details', [_preview()]),
        if (_error != null && _error!.isNotEmpty) Padding(padding: const EdgeInsets.only(top: 12), child: Text(_error!, style: HqText.small.copyWith(color: Hq.red, fontSize: 12.5))),
        const SizedBox(height: 14),
        if (write)
          Row(children: [
            Expanded(child: HqButton(_isNew ? 'Add template' : 'Save changes', kind: BtnKind.primary, busy: _busy, expand: true, onPressed: _save)),
            const SizedBox(width: 8),
            HqButton('Send test', busy: _testing, onPressed: _test),
          ])
        else
          Text('Your role can read these templates but not change them.', style: HqText.sub),
        if (write && !_isNew) ...[
          const SizedBox(height: 8),
          Row(children: [
            Expanded(child: HqButton('Duplicate', expand: true, onPressed: _duplicate)),
            const SizedBox(width: 8),
            Expanded(child: HqButton('Delete', expand: true, color: Hq.red, onPressed: _delete)),
          ]),
        ],
      ]),
    );
  }

  Widget _parent(bool write) {
    final sub = switch (_module) {
      'fees' => 'Tell them when a fee is due or overdue',
      'attendance' => 'Tell them when their child misses a class or attendance drops',
      _ => 'Keep them in the loop on class changes',
    };
    return _card('Parent or guardian', sub, [
      _switchRow('Also message the parent or guardian', "Sent on WhatsApp to the guardian number on the student's profile, since parents do not have the Owleo app", _parOn, write ? (v) => setState(() => _parOn = v) : (_) {}),
      if (_parOn) ...[
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: Text(
            '${widget.ready.flag('wa') ? 'WhatsApp is ready.' : 'WhatsApp is not set up yet, so parent messages are saved but skipped until it is.'} Students with no guardian number are skipped and shown in the delivery log. Keep it plain text: WhatsApp business messages go out as pre-approved templates.',
            style: HqText.sub.copyWith(height: 1.5, color: widget.ready.flag('wa') ? Hq.muted : Hq.gold),
          ),
        ),
        _switchRow('Only for students under 18', 'Adults get it themselves; guardian consent applies to minors', _parMin, write ? (v) => setState(() => _parMin = v) : (_) {}),
        _switchRow('Write a different message for them', 'Off: they get the same text as the student, on WhatsApp', _parDiff, write
            ? (v) => setState(() {
                  _parDiff = v;
                  if (v && _parTitle.text.isEmpty && _parBody.text.isEmpty) {
                    _parTitle.text = _title.text;
                    _parBody.text = _body.text;
                  }
                })
            : (_) {}),
        if (_parDiff) ...[
          const SizedBox(height: 8),
          HqField(label: 'Title for parent', controller: _parTitle, maxLength: 60, hint: 'For example: {student} was absent today', bottom: 2, onChanged: (_) => setState(() {}), focusNode: _parTitleFocus, readOnly: !write),
          Align(alignment: Alignment.centerRight, child: Text('${_parTitle.text.length}/60', style: HqText.sub)),
          const SizedBox(height: 8),
          HqField(label: 'Message for parent', controller: _parBody, maxLength: 240, maxLines: 4, hint: 'Dear {parent}, ...', bottom: 2, onChanged: (_) => setState(() {}), focusNode: _parBodyFocus, readOnly: !write),
          Align(alignment: Alignment.centerRight, child: Text('${_parBody.text.length}/240', style: HqText.sub)),
        ],
      ],
    ]);
  }

  // ---- previews ----

  Widget _preview() {
    final sec = _security(_module);
    final children = <Widget>[];
    if (!sec) {
      children.add(Text('Student sees', style: HqText.small));
      children.add(const SizedBox(height: 6));
      children.add(_appCard(_title.text, _body.text));
    }
    if (_ch['mail'] == true) {
      if (!sec) children.add(_label('By email'));
      children.add(_mail());
    }
    if (sec && _ch['wa'] == true) {
      children.add(_label('On WhatsApp'));
      children.add(_wa(_title.text, _body.text));
    }
    if (sec && _ch['mail'] != true && _ch['wa'] != true) children.add(Text('Pick Email or WhatsApp to see a preview.', style: HqText.muted));
    if (_parentCapable && _parOn) {
      children.add(_label('Parent or guardian sees on WhatsApp'));
      children.add(_wa(_parDiff ? _parTitle.text : _title.text, _parDiff ? _parBody.text : _body.text));
    }
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: children);
  }

  Widget _label(String t) => Padding(padding: const EdgeInsets.fromLTRB(0, 12, 0, 6), child: Text(t, style: HqText.small));

  Widget _appCard(String title, String body) {
    final tone = Tone.byName(_mod.str('tone'));
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(color: Hq.high, borderRadius: BorderRadius.circular(16), border: Border.all(color: Hq.border)),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        IconTile(_mod.str('icon'), tone: tone, size: 34, iconSize: 16),
        const SizedBox(width: 10),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('${_mod.str('sender')} · now', style: HqText.small.copyWith(fontSize: 11)),
            const SizedBox(height: 2),
            title.isEmpty ? Text('Title', style: HqText.row.copyWith(color: Hq.faint)) : Text.rich(_fill(title, _vars, HqText.row.copyWith(fontSize: 13.5))),
            const SizedBox(height: 2),
            body.isEmpty ? Text('Message', style: HqText.small.copyWith(color: Hq.faint)) : Text.rich(_fill(body, _vars, HqText.small.copyWith(fontSize: 12.5, height: 1.4))),
          ]),
        ),
      ]),
    );
  }

  Widget _wa(String title, String body) => Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(color: const Color(0xFF0B141A), borderRadius: BorderRadius.circular(16), border: Border.all(color: Hq.border)),
        child: Container(
          padding: const EdgeInsets.fromLTRB(11, 9, 11, 7),
          decoration: const BoxDecoration(color: Color(0xFF005C4B), borderRadius: BorderRadius.only(topLeft: Radius.circular(4), topRight: Radius.circular(14), bottomLeft: Radius.circular(14), bottomRight: Radius.circular(14))),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(_mod.str('sender'), style: const TextStyle(fontSize: 11, color: Color(0xFF8FD8C8), fontWeight: FontWeight.w700)),
            const SizedBox(height: 3),
            if (title.isNotEmpty) Text.rich(_fill(title, _vars, const TextStyle(fontSize: 13, height: 1.45, color: Color(0xFFE9EDEF), fontWeight: FontWeight.w800))),
            body.isEmpty ? const Text('Message', style: TextStyle(fontSize: 13, color: Color(0x99E9EDEF))) : Text.rich(_fill(body, _vars, const TextStyle(fontSize: 13, height: 1.45, color: Color(0xFFE9EDEF)))),
            const Align(alignment: Alignment.centerRight, child: Text('now', style: TextStyle(fontSize: 10, color: Color(0x99E9EDEF)))),
          ]),
        ),
      );

  Widget _mail() => Container(
        decoration: BoxDecoration(color: Hq.high, borderRadius: BorderRadius.circular(16), border: Border.all(color: Hq.border)),
        clipBehavior: Clip.antiAlias,
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Container(
            padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
            decoration: const BoxDecoration(border: Border(bottom: BorderSide(color: Hq.border))),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text.rich(TextSpan(style: HqText.small.copyWith(fontSize: 11.5), children: [const TextSpan(text: 'From '), TextSpan(text: _mod.str('sender'), style: const TextStyle(color: Hq.text, fontWeight: FontWeight.w800))])),
              const SizedBox(height: 2),
              Text.rich(TextSpan(style: HqText.small.copyWith(fontSize: 11.5), children: [
                const TextSpan(text: 'Subject '),
                _title.text.isEmpty ? const TextSpan(text: 'Your subject', style: TextStyle(color: Hq.faint)) : _fill(_title.text, _vars, const TextStyle(color: Hq.text, fontWeight: FontWeight.w700)),
              ])),
            ]),
          ),
          Padding(
            padding: const EdgeInsets.all(12),
            child: _body.text.isEmpty ? Text('Your message', style: HqText.body.copyWith(color: Hq.faint)) : Text.rich(_fill(_body.text, _vars, HqText.body.copyWith(height: 1.5))),
          ),
        ]),
      );
}
