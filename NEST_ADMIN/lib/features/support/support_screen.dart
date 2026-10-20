import 'package:flutter/material.dart';
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
import '../shell/nav.dart';
import '../shell/shell_data.dart';
import '../users/users_screen.dart' show FieldRow2;

typedef TicketQuery = ({String kind, String st, String q});

final ticketsProvider = FutureProvider.autoDispose.family<Map<String, dynamic>, TicketQuery>(
  (ref, q) => ref.watch(dioClientProvider).getMap('/admin/hq/support', query: {'kind': q.kind, 'st': q.st, if (q.q.trim().isNotEmpty) 'q': q.q.trim()}),
);

final ticketProvider = FutureProvider.autoDispose.family<Map<String, dynamic>, String>(
  (ref, id) => ref.watch(dioClientProvider).getMap('/admin/hq/support/$id'),
);

const _kind = {
  'issue': ('Issue', Tone.red, 'flag'),
  'enquiry': ('Enquiry', Tone.blue, 'msg'),
  'feedback': ('Feedback', Tone.violet, 'star'),
  'fee': ('Student fee', Tone.gold, 'rupee'),
};
const _kindChip = {'issue': 'Issues', 'enquiry': 'Enquiries', 'feedback': 'Feedback', 'fee': 'Student fees'};
const _statusInfo = {
  'open': ('Open', Tone.red),
  'progress': ('In progress', Tone.blue),
  'waiting': ('Waiting on academy', Tone.gold),
  'resolved': ('Resolved', Tone.green),
  'closed': ('Closed', Tone.mute),
};
const _priority = {'urgent': Tone.red, 'high': Tone.gold, 'medium': Tone.blue, 'low': Tone.mute};

bool _isOpen(String s) => s != 'resolved' && s != 'closed';

void refreshTickets(WidgetRef ref) {
  ref.invalidate(ticketsProvider);
  ref.invalidate(ticketProvider);
  ref.invalidate(badgesProvider);
}

Widget stars(int n) => Text('★' * n + '☆' * (5 - n), style: const TextStyle(color: Color(0xFFF0B429), fontSize: 13, letterSpacing: 1));

/// Support: tickets from academy admins, plus student fee problems (fees only).
class SupportScreen extends ConsumerStatefulWidget {
  const SupportScreen({super.key});

  @override
  ConsumerState<SupportScreen> createState() => _SupportScreenState();
}

class _SupportScreenState extends ConsumerState<SupportScreen> {
  TicketQuery _q = (kind: 'all', st: 'open', q: '');
  int _limit = 12;
  Map<String, dynamic>? _last;

  void _set(TicketQuery q) => setState(() {
        _q = q;
        _limit = 12;
      });

  @override
  Widget build(BuildContext context) {
    final data = ref.watch(ticketsProvider(_q));
    if (data.hasValue) _last = data.value;
    final d = data.valueOrNull ?? _last;
    if (d == null) return asyncBody(data, onRetry: () => ref.invalidate(ticketsProvider), data: (_) => const SizedBox.shrink());
    final user = ref.watch(sessionProvider).user;
    final items = d.maps('items');
    final byKind = d.obj('byKind');
    final kinds = d.strings('kinds');
    final isFinance = user?.role.code == 'FINANCE';
    final order = ['issue', 'enquiry', 'feedback', 'fee'].where(kinds.contains).toList();

    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      HqGrid(GridKind.g4, [
        Kpi(icon: 'flag', tone: Tone.red, label: 'Open tickets', value: '${d.integer('open')}', foot: '${d.integer('high')} urgent or high'),
        Kpi(icon: 'clock', tone: Tone.gold, label: 'Waiting on academy', value: '${d.integer('waiting')}', foot: 'we replied, they have not'),
        Kpi(icon: 'star', tone: Tone.violet, label: 'Feedback rating', value: d['rating'] == null ? '–' : '${d.number('rating')} / 5', foot: '${d.integer('rated')} responses'),
        Kpi(icon: 'check', tone: Tone.green, label: 'Resolved', value: '${d.integer('resolved')}', foot: 'all time'),
      ]),
      HqCard(
        padding: const EdgeInsets.all(12),
        margin: const EdgeInsets.only(bottom: 12),
        child: Row(children: [
          Expanded(child: SearchBox(hint: 'Search subject, name or ticket number', initial: _q.q, onChanged: (v) => _set((kind: _q.kind, st: _q.st, q: v)))),
          const SizedBox(width: 8),
          HqButton('Log', icon: 'plus', kind: BtnKind.primary, onPressed: () => _log(d)),
        ]),
      ),
      if (isFinance)
        HqCard(
          margin: const EdgeInsets.only(bottom: 12),
          padding: const EdgeInsets.all(12),
          child: Row(children: [ic('lock', 13, Hq.muted), const SizedBox(width: 8), Expanded(child: Text('The Finance admin role sees student fee issues only.', style: HqText.muted.copyWith(fontSize: 12.5)))]),
        ),
      Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: ChipRow([
          HqChip('All', selected: _q.kind == 'all', count: byKind.values.fold<int>(0, (a, b) => a + (b as num).toInt()), onTap: () => _set((kind: 'all', st: _q.st, q: _q.q))),
          for (final k in order) HqChip(_kindChip[k]!, selected: _q.kind == k, count: byKind.integer(k), onTap: () => _set((kind: k, st: _q.st, q: _q.q))),
        ], scroll: true),
      ),
      Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: SegControl<String>(expand: true, items: const [('open', 'Open'), ('done', 'Resolved'), ('all', 'All')], value: _q.st, onChanged: (v) => _set((kind: _q.kind, st: v, q: _q.q))),
      ),
      if (items.isEmpty) const EmptyNote('No tickets here'),
      LayoutBuilder(builder: (context, c) {
        final cols = c.maxWidth >= 900 ? 2 : 1;
        return Wrap(spacing: 10, runSpacing: 10, children: [
          for (final t in items.take(_limit)) SizedBox(width: (c.maxWidth - (cols - 1) * 10) / cols, child: _card(t)),
        ]);
      }),
      if (items.length > _limit) Padding(padding: const EdgeInsets.only(top: 12), child: HqButton('Show more (${items.length - _limit} left)', expand: true, onPressed: () => setState(() => _limit += 12))),
      Padding(padding: const EdgeInsets.fromLTRB(2, 14, 2, 0), child: Text('Student tickets here are about fees only. Any other student topic stays with the academy.', style: HqText.sub)),
    ]);
  }

  Widget _card(Map<String, dynamic> t) {
    final (kl, kt, ki) = _kind[t.str('kind')]!;
    final (sl, st) = _statusInfo[t.str('status')]!;
    final open = _isOpen(t.str('status'));
    final age = t.integer('age');
    return HqCard(
      radius: 14,
      padding: const EdgeInsets.all(12),
      onTap: () => showTicketDrawer(context, ref, t.str('id')),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(children: [
          Avatar('', tone: kt, icon: ki),
          const SizedBox(width: 10),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(t.str('subject'), maxLines: 2, overflow: TextOverflow.ellipsis, style: HqText.row),
              Text('${t.str('ref')} · ${t.strOrNull('academy') ?? 'No academy'} · ${t.str('from')}', maxLines: 1, overflow: TextOverflow.ellipsis, style: HqText.small),
            ]),
          ),
        ]),
        const SizedBox(height: 9),
        Wrap(spacing: 6, runSpacing: 6, crossAxisAlignment: WrapCrossAlignment.center, children: [
          Tag(kl, tone: kt),
          Tag(sl, tone: st),
          if (open && t.str('kind') != 'feedback') Tag(t.str('priority'), tone: _priority[t.str('priority')] ?? Tone.mute),
          if (t['rating'] != null) stars(t.integer('rating')),
          Text(age == 0 ? 'Today' : '${age}d', style: HqText.sub.copyWith(fontSize: 11.5)),
        ]),
      ]),
    );
  }

  Future<void> _log(Map<String, dynamic> d) async {
    final done = await showHqModal<String>(context, builder: (_) => _LogTicket(meta: d));
    if (done != null) {
      refreshTickets(ref);
      if (mounted) showToast(context, 'Ticket logged');
    }
  }
}

Future<void> showTicketDrawer(BuildContext context, WidgetRef ref, String id) => showHqDrawer(context, builder: (_) => _TicketDrawer(id: id));

class _TicketDrawer extends ConsumerStatefulWidget {
  const _TicketDrawer({required this.id});
  final String id;

  @override
  ConsumerState<_TicketDrawer> createState() => _TicketDrawerState();
}

class _TicketDrawerState extends ConsumerState<_TicketDrawer> {
  final _msg = TextEditingController();
  String? _status, _priorityValue;
  String? _error;
  bool _busy = false;

  @override
  void dispose() {
    _msg.dispose();
    super.dispose();
  }

  Future<void> _call(Future<void> Function() f, String ok) async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await f();
      _msg.clear();
      _status = null;
      _priorityValue = null;
      refreshTickets(ref);
      if (mounted) showToast(context, ok);
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final detail = ref.watch(ticketProvider(widget.id));
    return detail.when(
      loading: () => const Center(child: CircularProgressIndicator(color: Hq.primary, strokeWidth: 2.5)),
      error: (e, _) => Padding(padding: const EdgeInsets.all(24), child: HqError(e is ApiException ? e.message : 'Could not load this ticket.')),
      data: (t) {
        final (kl, kt, ki) = _kind[t.str('kind')]!;
        final st = t.str('status');
        final thread = t.maps('thread');
        final kind = t.str('kind');
        final pr = t.str('priority');
        final dio = ref.read(dioClientProvider);
        final id = widget.id;
        return DrawerShell(
          logo: DrawerLogo('', color: kt.color, icon: ki),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Wrap(spacing: 6, runSpacing: 6, children: [
              Tag(kl, tone: kt),
              Tag(_statusInfo[st]!.$1, tone: _statusInfo[st]!.$2),
              if (kind != 'feedback') Tag('$pr priority', tone: _priority[pr] ?? Tone.mute),
              Tag(t.str('category'), tone: Tone.mute),
            ]),
            const SizedBox(height: 8),
            Text(t.str('subject'), style: HqText.h2.copyWith(fontSize: 19)),
            const SizedBox(height: 3),
            Text('${t.str('ref')} · ${t.strOrNull('academy') ?? 'No academy'} · ${t.str('from')} (${t.str('role')})', style: HqText.muted.copyWith(fontSize: 12.5)),
            if (t['rating'] != null) Padding(padding: const EdgeInsets.only(top: 10), child: stars(t.integer('rating'))),
            if (kind == 'fee')
              HqCard(
                margin: const EdgeInsets.only(top: 14),
                child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                  const CardHeader('Fee details', sub: 'HQ handles student issues about fees only', bottom: 6),
                  HqList([
                    KeyValueRow('Student', t.str('from')),
                    if (t['amount'] != null && t.number('amount') > 0) KeyValueRow('Amount involved', inr(t.number('amount'))),
                    KeyValueRow('Academy', t.strOrNull('academy') ?? '—'),
                  ]),
                ]),
              ),
            HqCard(
              margin: const EdgeInsets.fromLTRB(0, 14, 0, 12),
              child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                const CardHeader('Conversation', sub: 'Oldest first', bottom: 6),
                HqList([
                  for (final m in thread)
                    HqRow(
                      leading: Avatar(initials(m.str('who')), tone: m.flag('hq') || m.str('who') == 'System' ? Tone.primary : Tone.blue, size: 32),
                      title: '${m.str('who')} · ${ago(m['at'])}',
                      wrap: true,
                      sub: m.str('x'),
                    ),
                ]),
              ]),
            ),
            HqCard(
              margin: const EdgeInsets.only(bottom: 12),
              child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                const CardHeader('Reply', sub: 'The academy admin is notified', bottom: 8),
                HqField(label: 'Message', controller: _msg, maxLines: 3, hint: 'Write a reply'),
                FieldRow2([
                  HqSelect<String>(
                    label: 'Set status',
                    value: _status ?? (st == 'open' ? 'progress' : st),
                    searchable: false,
                    options: [for (final e in _statusInfo.entries) SelectOption(e.key, e.value.$1)],
                    onChanged: (v) => setState(() => _status = v),
                  ),
                  if (kind != 'feedback')
                    HqSelect<String>(
                      label: 'Priority',
                      value: _priorityValue ?? pr,
                      searchable: false,
                      options: [for (final p in _priority.keys) SelectOption(p, p)],
                      onChanged: (v) => setState(() => _priorityValue = v),
                    ),
                ]),
                if (_error != null) Padding(padding: const EdgeInsets.only(bottom: 10), child: Text(_error!, style: HqText.small.copyWith(color: Hq.red))),
                HqButton('Send reply', icon: 'send', kind: BtnKind.primary, expand: true, busy: _busy, onPressed: () => _call(
                      () => dio.postMap('/admin/hq/support/$id/reply', body: {'message': _msg.text.trim(), 'status': _status ?? (st == 'open' ? 'progress' : st), 'priority': _priorityValue ?? pr}),
                      (_status ?? '') == 'resolved' ? 'Resolved. The academy has been told.' : 'Reply sent',
                    )),
              ]),
            ),
            Wrap(spacing: 8, runSpacing: 8, children: [
              if (kind == 'enquiry' && t.str('category') == 'Plan and pricing')
                HqButton('Open Approvals to change the plan', icon: 'flow', onPressed: () {
                  Navigator.of(context).pop();
                  hqGo(context, '/approvals');
                }),
              if (kind == 'feedback') HqButton('Mark as reviewed', icon: 'check', onPressed: () => _call(() => dio.postMap('/admin/hq/support/$id/review'), 'Feedback marked as reviewed')),
              if (kind == 'issue' && pr != 'urgent') HqButton('Escalate to urgent', icon: 'warn', onPressed: () => _call(() => dio.postMap('/admin/hq/support/$id/escalate'), 'Escalated to urgent')),
            ]),
          ]),
        );
      },
    );
  }
}

class _LogTicket extends ConsumerStatefulWidget {
  const _LogTicket({required this.meta});
  final Map<String, dynamic> meta;

  @override
  ConsumerState<_LogTicket> createState() => _LogTicketState();
}

class _LogTicketState extends ConsumerState<_LogTicket> {
  late String _kindValue = widget.meta.strings('kinds').contains('issue') ? 'issue' : 'fee';
  String? _cat, _academy;
  final _from = TextEditingController(), _subject = TextEditingController(), _body = TextEditingController();
  String? _error;
  bool _busy = false;

  @override
  void dispose() {
    _from.dispose();
    _subject.dispose();
    _body.dispose();
    super.dispose();
  }

  Future<void> _go() async {
    final cats = (widget.meta.obj('categories')[_kindValue] as List).cast<String>();
    final cat = _cat ?? cats.first;
    if (_from.text.trim().length < 2) return setState(() => _error = 'Enter who raised it.');
    if (_subject.text.trim().length < 4) return setState(() => _error = 'Add a short subject.');
    if (_body.text.trim().length < 5) return setState(() => _error = 'Add a few details.');
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final r = await ref.read(dioClientProvider).postMap('/admin/hq/support', body: {
        'kind': _kindValue,
        'category': cat,
        'academy': _academy ?? '',
        'from': _from.text.trim(),
        'subject': _subject.text.trim(),
        'body': _body.text.trim(),
      });
      if (mounted) Navigator.of(context).pop(r.str('id'));
    } on ApiException catch (e) {
      setState(() {
        _busy = false;
        _error = e.message;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final kinds = widget.meta.strings('kinds');
    final cats = (widget.meta.obj('categories')[_kindValue] as List).cast<String>();
    final academies = widget.meta.maps('academies');
    return ModalFrame(
      title: 'Log a ticket',
      sub: 'For a call or message that came in outside the app',
      error: _error,
      actions: [
        HqButton('Cancel', onPressed: () => Navigator.of(context).pop()),
        HqButton('Log ticket', kind: BtnKind.primary, busy: _busy, onPressed: _go),
      ],
      children: [
        FieldRow2([
          HqSelect<String>(
            label: 'Type',
            value: _kindValue,
            searchable: false,
            options: [for (final k in ['issue', 'enquiry', 'feedback', 'fee'].where(kinds.contains)) SelectOption(k, '${_kind[k]!.$1}${k == 'fee' ? ' (students: fees only)' : ''}')],
            onChanged: (v) => setState(() {
              _kindValue = v;
              _cat = null;
            }),
          ),
          HqSelect<String>(label: 'Category', value: _cat ?? cats.first, searchable: false, options: [for (final c in cats) SelectOption(c, c)], onChanged: (v) => setState(() => _cat = v)),
        ]),
        HqSelect<String>(label: 'Academy', value: _academy, hint: 'Choose an academy', options: [for (final a in academies) SelectOption(a.str('id'), a.str('name'))], onChanged: (v) => setState(() => _academy = v)),
        HqField(label: 'Raised by', controller: _from, hint: 'Name of the admin, student or parent'),
        HqField(label: 'Subject', controller: _subject, hint: 'One line summary'),
        HqField(label: 'Details', controller: _body, hint: 'What happened', maxLines: 3),
      ],
    );
  }
}
