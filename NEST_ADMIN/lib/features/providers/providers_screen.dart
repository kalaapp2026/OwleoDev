import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/theme.dart';
import '../../core/api/api_exception.dart';
import '../../core/api/dio_client.dart';
import '../../core/auth/session.dart';
import '../../core/format.dart';
import '../../core/json.dart';
import '../../core/links.dart';
import '../../core/ui/async.dart';
import '../../core/ui/charts.dart';
import '../../core/ui/controls.dart';
import '../../core/ui/icons.dart';
import '../../core/ui/layout.dart';
import '../../core/ui/overlays.dart';
import '../../core/ui/primitives.dart';
import '../shell/shell_data.dart';
import '../users/users_screen.dart' show FieldRow2;

final providersProvider = FutureProvider.autoDispose<Map<String, dynamic>>((ref) => ref.watch(dioClientProvider).getMap('/admin/hq/providers'));
final providerProvider = FutureProvider.autoDispose.family<Map<String, dynamic>, String>((ref, id) => ref.watch(dioClientProvider).getMap('/admin/hq/providers/$id'));
final providerPerfProvider = FutureProvider.autoDispose<Map<String, dynamic>>((ref) => ref.watch(dioClientProvider).getMap('/admin/hq/providers/performance'));
final providerRequestsProvider = FutureProvider.autoDispose.family<List<Map<String, dynamic>>, String>((ref, f) => ref.watch(dioClientProvider).getList('/admin/hq/providers/requests', query: {'filter': f}));

void refreshProviders(WidgetRef ref) {
  ref.invalidate(providersProvider);
  ref.invalidate(providerProvider);
  ref.invalidate(providerPerfProvider);
  ref.invalidate(providerRequestsProvider);
  ref.invalidate(badgesProvider);
}

const _status = {
  'applied': ('Applied', Tone.blue),
  'review': ('Checking links', Tone.gold),
  'verify': ('Verifying identity', Tone.violet),
  'live': ('Live', Tone.green),
  'suspended': ('Suspended', Tone.coral),
  'rejected': ('Rejected', Tone.red),
};
const _reqStatus = {
  'open': ('Open', Tone.blue),
  'matched': ('Sent to providers', Tone.gold),
  'quoted': ('Quote received', Tone.violet),
  'hired': ('Hired', Tone.green),
  'closed': ('Closed', Tone.mute),
};
const _cities = ['Bengaluru', 'Chennai', 'Hyderabad', 'Pune', 'Mumbai', 'Kochi', 'Mysuru', 'Coimbatore', 'Ahmedabad', 'Delhi NCR', 'Kolkata', 'Jaipur'];
const _units = ['per event', 'per hour', 'per day', 'per person', 'per piece per day'];

Tone _tone(String t) => switch (t) {
      'blue' => Tone.blue,
      'gold' => Tone.gold,
      'violet' => Tone.violet,
      'green' => Tone.green,
      'coral' => Tone.coral,
      'magenta' => Tone.magenta,
      'red' => Tone.red,
      'mute' => Tone.mute,
      _ => Tone.primary,
    };

String stars(Object? r) => r == null ? 'New' : '★ ${(r as num).toStringAsFixed(1)}';

Future<void> _post(BuildContext context, WidgetRef ref, Future<void> Function(DioClient) f, String ok) async {
  try {
    await f(ref.read(dioClientProvider));
    refreshProviders(ref);
    if (context.mounted && ok.isNotEmpty) showToast(context, ok);
  } on ApiException catch (e) {
    if (context.mounted) showToast(context, e.message);
  }
}

/// Service providers: vet, list and rate the crews academies hire for events.
class ProvidersScreen extends ConsumerStatefulWidget {
  const ProvidersScreen({super.key});

  @override
  ConsumerState<ProvidersScreen> createState() => _ProvidersScreenState();
}

class _ProvidersScreenState extends ConsumerState<ProvidersScreen> {
  String _tab = 'pv';
  String _q = '', _cat = 'all', _st = 'all', _stage = 'all', _rf = 'open';

  @override
  Widget build(BuildContext context) {
    final canWrite = ref.watch(sessionProvider).user?.canWrite ?? false;
    return asyncBody(ref.watch(providersProvider), onRetry: () => ref.invalidate(providersProvider), data: (d) {
      return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        HqGrid(GridKind.g4, [
          Kpi(icon: 'check', tone: Tone.green, label: 'Live providers', value: '${d.integer('live')}', foot: 'academies can hire them'),
          Kpi(icon: 'rocket', tone: Tone.violet, label: 'Being onboarded', value: '${d.integer('pipeline')}', foot: 'applied, links, verification'),
          Kpi(icon: 'msg', tone: Tone.blue, label: 'Open requests', value: '${d.integer('openRequests')}', foot: 'from academy admins'),
          Kpi(icon: 'pulse', tone: Tone.gold, label: 'Average rating', value: d['avgRating'] == null ? '–' : '${d.number('avgRating')}', foot: '${d.integer('watch')} need a look'),
        ]),
        Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: SegControl<String>(
            expand: true,
            dense: true,
            items: const [('pv', 'Providers'), ('ob', 'Onboarding'), ('rq', 'Requests'), ('pf', 'Performance'), ('ct', 'Types')],
            value: _tab,
            onChanged: (v) => setState(() => _tab = v),
          ),
        ),
        switch (_tab) {
          'pv' => _list(d),
          'ob' => _onboarding(d, canWrite),
          'rq' => _requests(d, canWrite),
          'pf' => const _Performance(),
          _ => _types(d, canWrite),
        },
      ]);
    });
  }

  Widget _card(Map<String, dynamic> p) {
    final (sl, sc) = _status[p.str('status')] ?? ('', Tone.mute);
    final types = p.maps('types');
    final first = types.isEmpty ? <String, dynamic>{} : types.first;
    final perf = p.obj('perf');
    final live = p.str('status') == 'live' || p.str('status') == 'suspended';
    return HqCard(
      radius: 14,
      padding: const EdgeInsets.all(12),
      onTap: () => showProviderDrawer(context, ref, p.str('id')),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(children: [
          Avatar('', tone: _tone(first.str('tone', 'primary')), icon: first.str('icon', 'users')),
          const SizedBox(width: 10),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(p.str('name'), maxLines: 1, overflow: TextOverflow.ellipsis, style: HqText.row),
              Text('${types.map((t) => t.str('name')).join(' · ')} · ${p.str('city')}', maxLines: 1, overflow: TextOverflow.ellipsis, style: HqText.small),
            ]),
          ),
        ]),
        const SizedBox(height: 9),
        Wrap(spacing: 6, runSpacing: 6, children: [
          Tag(sl, tone: sc),
          if (live) ...[Tag(stars(perf['rating']), tone: Tone.gold), Tag('${perf.integer('done')} jobs', tone: Tone.mute)] else Tag('${p.integer('linksChecked')} of ${p.integer('linksTotal')} links checked', tone: Tone.mute),
          if (p.strings('flags').isNotEmpty) const Tag('Needs a look', tone: Tone.red),
        ]),
      ]),
    );
  }

  Widget _cards(List<Map<String, dynamic>> list, String empty) => list.isEmpty
      ? EmptyNote(empty)
      : LayoutBuilder(builder: (context, c) {
          final cols = c.maxWidth >= 900 ? 3 : c.maxWidth >= 600 ? 2 : 1;
          return Wrap(spacing: 10, runSpacing: 10, children: [for (final p in list) SizedBox(width: (c.maxWidth - (cols - 1) * 10) / cols, child: _card(p))]);
        });

  Widget _list(Map<String, dynamic> d) {
    final needle = _q.trim().toLowerCase();
    final list = d.maps('providers').where((p) {
      final s = p.str('status');
      if (s != 'live' && s != 'suspended') return false;
      if (_cat != 'all' && !p.maps('types').any((t) => t.str('code') == _cat)) return false;
      if (_st != 'all' && s != _st) return false;
      return needle.isEmpty || '${p.str('name')} ${p.str('person')} ${p.str('city')}'.toLowerCase().contains(needle);
    }).toList();
    final types = d.maps('types').where((t) => t.flag('active')).toList();
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      HqCard(padding: const EdgeInsets.all(12), margin: const EdgeInsets.only(bottom: 12), child: SearchBox(hint: 'Search name, person or city', initial: _q, onChanged: (v) => setState(() => _q = v))),
      Padding(padding: const EdgeInsets.only(bottom: 8), child: ChipRow([HqChip('All types', selected: _cat == 'all', onTap: () => setState(() => _cat = 'all')), for (final t in types) HqChip(t.str('name'), selected: _cat == t.str('code'), onTap: () => setState(() => _cat = t.str('code')))], scroll: true)),
      Padding(padding: const EdgeInsets.only(bottom: 12), child: ChipRow([for (final (k, l) in const [('all', 'All'), ('live', 'Live'), ('suspended', 'Suspended')]) HqChip(l, selected: _st == k, onTap: () => setState(() => _st = k))])),
      _cards(list, 'No providers match'),
    ]);
  }

  Widget _onboarding(Map<String, dynamic> d, bool canWrite) {
    const stages = ['applied', 'review', 'verify', 'rejected'];
    final all = d.maps('providers').where((p) => stages.contains(p.str('status'))).toList();
    final list = all.where((p) => _stage == 'all' || p.str('status') == _stage).toList();
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      if (canWrite)
        Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: HqButton('Onboard a provider', icon: 'plus', kind: BtnKind.primary, expand: true, onPressed: () async {
            final done = await showHqModal<bool>(context, builder: (_) => _NewProvider(types: d.maps('types').where((t) => t.flag('active')).toList()));
            if (done == true) {
              refreshProviders(ref);
              if (mounted) showToast(context, 'Provider added as an applicant');
            }
          }),
        ),
      Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: ChipRow([
          HqChip('All', selected: _stage == 'all', count: all.length, onTap: () => setState(() => _stage = 'all')),
          for (final k in stages) HqChip(_status[k]!.$1, selected: _stage == k, count: all.where((p) => p.str('status') == k).length, onTap: () => setState(() => _stage = k)),
        ], scroll: true),
      ),
      _cards(list, 'Nobody here'),
      Padding(padding: const EdgeInsets.fromLTRB(2, 14, 2, 0), child: Text('Providers apply with their details and portfolio links. Owleo checks the links, confirms identity on a call, then makes them live. No photos, videos or audio are uploaded here.', style: HqText.sub)),
    ]);
  }

  Widget _requests(Map<String, dynamic> d, bool canWrite) {
    final data = ref.watch(providerRequestsProvider(_rf));
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: Row(children: [
          Expanded(child: ChipRow([for (final (k, l) in const [('open', 'In progress'), ('hired', 'Hired'), ('closed', 'Closed'), ('all', 'All')]) HqChip(l, selected: _rf == k, onTap: () => setState(() => _rf = k))], scroll: true)),
          if (canWrite)
            HqButton('Log', icon: 'plus', small: true, kind: BtnKind.primary, onPressed: () async {
              final done = await showHqModal<bool>(context, builder: (_) => _NewRequest(types: d.maps('types').where((t) => t.flag('active')).toList()));
              if (done == true) {
                refreshProviders(ref);
                if (mounted) showToast(context, 'Request logged');
              }
            }),
        ]),
      ),
      asyncBody(data, data: (list) => list.isEmpty
          ? const EmptyNote('No requests')
          : LayoutBuilder(builder: (context, c) {
              final cols = c.maxWidth >= 900 ? 2 : 1;
              return Wrap(spacing: 10, runSpacing: 10, children: [for (final r in list) SizedBox(width: (c.maxWidth - (cols - 1) * 10) / cols, child: _RequestCard(r: r, canWrite: canWrite))]);
            })),
      Padding(padding: const EdgeInsets.fromLTRB(2, 14, 2, 0), child: Text('Academy admins ask for a service. You pick suitable live providers and pass the request on. Money is settled directly between them.', style: HqText.sub)),
    ]);
  }

  Widget _types(Map<String, dynamic> d, bool canWrite) {
    final types = d.maps('types');
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      if (canWrite)
        Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: HqButton('New type of service', icon: 'plus', kind: BtnKind.primary, expand: true, onPressed: () async {
            final name = await showHqModal<String>(context, builder: (_) => const _NewType());
            if (name != null && mounted) _post(context, ref, (c) async => await c.postMap('/admin/hq/providers/types', body: {'name': name}), 'Type added');
          }),
        ),
      HqCard(
        child: HqList([
          for (final t in types)
            HqRow(
              leading: IconTile(t.str('icon'), tone: _tone(t.str('tone'))),
              title: t.str('name'),
              titleStyle: t.flag('active') ? null : HqText.row.copyWith(color: Hq.faint),
              sub: '${t.integer('live')} live · ${t.integer('applying')} applying',
              trailing: canWrite ? HqButton(t.flag('active') ? 'Hide' : 'Show', small: true, onPressed: () => _post(context, ref, (c) async => await c.putMap('/admin/hq/providers/types/${t.str('code')}', body: {'active': !t.flag('active')}), '')) : null,
            ),
        ]),
      ),
      Padding(padding: const EdgeInsets.fromLTRB(2, 14, 2, 0), child: Text('These are the types academy admins can search and request. Hiding a type stops new requests and applications for it.', style: HqText.sub)),
    ]);
  }
}

// ----------------------------------------------------------------------------- requests

class _RequestCard extends ConsumerWidget {
  const _RequestCard({required this.r, required this.canWrite});
  final Map<String, dynamic> r;
  final bool canWrite;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final (sl, sc) = _reqStatus[r.str('status')] ?? ('', Tone.mute);
    final inProgress = const ['open', 'matched', 'quoted'].contains(r.str('status'));
    final sent = r.maps('sent');
    final quotes = r.maps('quotes');
    return HqCard(
      radius: 14,
      padding: const EdgeInsets.all(12),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('${r.str('academy')} needs ${r.str('type').toLowerCase()}', style: HqText.row),
              Text('${r.str('ref')} · ${r.str('event')} · ${fd(r['date'])} · ${r.str('city')}', style: HqText.small),
            ]),
          ),
          Tag(sl, tone: sc),
        ]),
        const SizedBox(height: 8),
        HqList([
          KeyValueRow('Budget', inr(r.number('budget'))),
          KeyValueRow('Sent to', sent.isEmpty ? 'No one yet' : sent.map((s) => s.str('name')).join(', ')),
          for (final q in quotes) KeyValueRow('Quote from ${q.str('provider')}', inr(q.number('amount'))),
          if (r.strOrNull('hired') != null) KeyValueRow('Hired', r.str('hired'), valueColor: Hq.green),
        ]),
        if (inProgress && canWrite)
          Padding(
            padding: const EdgeInsets.only(top: 10),
            child: Wrap(spacing: 6, runSpacing: 6, children: [
              HqButton(sent.isEmpty ? 'Find providers' : 'Send to more', small: true, kind: BtnKind.primary, onPressed: () async {
                final done = await showHqModal<bool>(context, builder: (_) => _Suggest(request: r));
                if (done == true) {
                  refreshProviders(ref);
                  if (context.mounted) showToast(context, 'Request sent');
                }
              }),
              if (sent.isNotEmpty) HqButton('Quote / hire', small: true, onPressed: () async {
                final done = await showHqModal<bool>(context, builder: (_) => _QuoteHire(request: r));
                if (done == true) refreshProviders(ref);
              }),
              HqButton('Close request', small: true, onPressed: () => _post(context, ref, (c) async => await c.postMap('/admin/hq/providers/requests/${r.str('id')}/close'), 'Request closed')),
            ]),
          ),
      ]),
    );
  }
}

class _Suggest extends ConsumerStatefulWidget {
  const _Suggest({required this.request});
  final Map<String, dynamic> request;

  @override
  ConsumerState<_Suggest> createState() => _SuggestState();
}

class _SuggestState extends ConsumerState<_Suggest> {
  List<Map<String, dynamic>>? _list;
  final Set<String> _pick = {};
  String? _error;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    ref.read(dioClientProvider).getList('/admin/hq/providers/requests/${widget.request.str('id')}/suggestions').then((l) {
      if (mounted) setState(() => _list = l);
    }).catchError((Object e) {
      if (mounted) setState(() => _error = e is ApiException ? e.message : 'Could not load providers.');
    });
  }

  Future<void> _go() async {
    if (_pick.isEmpty) return setState(() => _error = 'Pick at least one provider.');
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await ref.read(dioClientProvider).postMap('/admin/hq/providers/requests/${widget.request.str('id')}/send', body: {'providers': _pick.toList()});
      if (mounted) Navigator.of(context).pop(true);
    } on ApiException catch (e) {
      setState(() {
        _busy = false;
        _error = e.message;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final r = widget.request;
    return ModalFrame(
      title: 'Find providers',
      sub: '${r.str('type')} for ${r.str('academy')}',
      error: _error,
      actions: [HqButton('Cancel', onPressed: () => Navigator.of(context).pop()), HqButton('Send request', kind: BtnKind.primary, busy: _busy, onPressed: _go)],
      children: [
        if (_list == null && _error == null) const Padding(padding: EdgeInsets.all(20), child: Center(child: CircularProgressIndicator(color: Hq.primary, strokeWidth: 2.5)))
        else if (_list != null && _list!.isEmpty) const EmptyNote('No live provider for this yet')
        else if (_list != null)
          HqList([
            for (final p in _list!)
              HqCheckRow(
                checked: p.flag('sent') || _pick.contains(p.str('id')),
                title: p.str('name'),
                sub: '${p.str('city')}${p.flag('sameCity') ? ' · same city' : ''} · ${stars(p['rating'])} · from ${inr(p.number('price'))} ${p.str('unit')}${p.flag('sent') ? ' · already sent' : ''}',
                onChanged: p.flag('sent') ? null : (v) => setState(() => v ? _pick.add(p.str('id')) : _pick.remove(p.str('id'))),
              ),
          ]),
        const SizedBox(height: 10),
      ],
    );
  }
}

class _QuoteHire extends ConsumerStatefulWidget {
  const _QuoteHire({required this.request});
  final Map<String, dynamic> request;

  @override
  ConsumerState<_QuoteHire> createState() => _QuoteHireState();
}

class _QuoteHireState extends ConsumerState<_QuoteHire> {
  String? _provider;
  final _amount = TextEditingController();
  String? _error;
  bool _busy = false;

  @override
  void dispose() {
    _amount.dispose();
    super.dispose();
  }

  Future<void> _call(Future<void> Function(DioClient) f, String ok, {bool close = true}) async {
    if (_provider == null) return setState(() => _error = 'Choose a provider.');
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await f(ref.read(dioClientProvider));
      if (!mounted) return;
      showToast(context, ok);
      if (close) Navigator.of(context).pop(true);
      refreshProviders(ref);
      setState(() => _busy = false);
    } on ApiException catch (e) {
      setState(() {
        _busy = false;
        _error = e.message;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final r = widget.request;
    final id = r.str('id');
    return ModalFrame(
      title: 'Quote or hire',
      sub: '${r.str('event')} · ${r.str('academy')}',
      error: _error,
      actions: [
        HqButton('Close', onPressed: () => Navigator.of(context).pop()),
        HqButton('Hire', kind: BtnKind.primary, busy: _busy, onPressed: () => _call((c) async => await c.postMap('/admin/hq/providers/requests/$id/hire', body: {'providerId': _provider}), 'Hired', close: true)),
      ],
      children: [
        HqSelect<String>(label: 'Provider', value: _provider, hint: 'Choose a provider', options: [for (final s in r.maps('sent')) SelectOption(s.str('id'), s.str('name'))], onChanged: (v) => setState(() => _provider = v)),
        Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
          Expanded(child: HqField(label: 'Quote received (₹)', controller: _amount, keyboard: TextInputType.number, bottom: 0, formatters: [FilteringTextInputFormatter.digitsOnly])),
          const SizedBox(width: 8),
          HqButton('Save quote', onPressed: () => _call((c) async => await c.postMap('/admin/hq/providers/requests/$id/quote', body: {'providerId': _provider, 'amount': _amount.text.trim()}), 'Quote saved', close: false)),
        ]),
        const SizedBox(height: 10),
        Text('Hiring uses the saved quote, or the budget if there is none. The job then counts toward the provider\'s record.', style: HqText.sub),
        const SizedBox(height: 12),
      ],
    );
  }
}

class _NewRequest extends ConsumerStatefulWidget {
  const _NewRequest({required this.types});
  final List<Map<String, dynamic>> types;

  @override
  ConsumerState<_NewRequest> createState() => _NewRequestState();
}

class _NewRequestState extends ConsumerState<_NewRequest> {
  String? _academy, _type;
  final _event = TextEditingController(), _budget = TextEditingController();
  DateTime _date = DateTime.now().add(const Duration(days: 21));
  List<Map<String, dynamic>> _academies = const [];
  String? _error;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    ref.read(dioClientProvider).getMap('/admin/hq/transfers').then((m) {
      if (mounted) setState(() => _academies = m.maps('academies'));
    }).catchError((Object _) {});
  }

  @override
  void dispose() {
    _event.dispose();
    _budget.dispose();
    super.dispose();
  }

  Future<void> _go() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await ref.read(dioClientProvider).postMap('/admin/hq/providers/requests', body: {
        'academyId': _academy ?? '00000000-0000-0000-0000-000000000000',
        'type': _type ?? '',
        'event': _event.text.trim(),
        'date': '${_date.year}-${_date.month.toString().padLeft(2, '0')}-${_date.day.toString().padLeft(2, '0')}',
        'budget': _budget.text.trim(),
      });
      if (mounted) Navigator.of(context).pop(true);
    } on ApiException catch (e) {
      setState(() {
        _busy = false;
        _error = e.message;
      });
    }
  }

  @override
  Widget build(BuildContext context) => ModalFrame(
        title: 'Log a request',
        sub: 'An academy asked for a service outside the app',
        error: _error,
        actions: [HqButton('Cancel', onPressed: () => Navigator.of(context).pop()), HqButton('Log request', kind: BtnKind.primary, busy: _busy, onPressed: _go)],
        children: [
          HqSelect<String>(label: 'Academy', value: _academy, hint: 'Choose an academy', options: [for (final a in _academies) SelectOption(a.str('id'), a.str('name'))], onChanged: (v) => setState(() => _academy = v)),
          HqSelect<String>(label: 'Service needed', value: _type, hint: 'Choose a service', options: [for (final t in widget.types) SelectOption(t.str('code'), t.str('name'))], onChanged: (v) => setState(() => _type = v)),
          HqField(label: 'Event', controller: _event, hint: 'e.g. Annual Day'),
          Text('EVENT DATE', style: HqText.th),
          const SizedBox(height: 6),
          HqButton(fd('${_date.year}-${_date.month.toString().padLeft(2, '0')}-${_date.day.toString().padLeft(2, '0')}'), icon: 'cal', expand: true, onPressed: () async {
            final d = await pickHqDate(context, initial: _date, first: DateTime.now(), last: DateTime.now().add(const Duration(days: 730)));
            if (d != null) setState(() => _date = d);
          }),
          const SizedBox(height: 13),
          HqField(label: 'Budget (₹)', controller: _budget, keyboard: TextInputType.number, formatters: [FilteringTextInputFormatter.digitsOnly]),
        ],
      );
}

// ------------------------------------------------------------------------------ performance

class _Performance extends ConsumerWidget {
  const _Performance();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return asyncBody(ref.watch(providerPerfProvider), data: (d) {
      final months = d.maps('months');
      final labels = [for (final m in months) monthShort(m.str('month'))];
      final tips = [for (final m in months) monthLong(m.str('month'))];
      Widget card(String title, String sub, Widget body) => HqCard(margin: const EdgeInsets.only(bottom: 12), child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [CardHeader(title, sub: sub), body]));
      return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        card('Jobs done and cancelled', 'All providers, per month', HqChart(labels: labels, tipLabels: tips, height: 220, noRange: true, series: [
          ChartSeries('Done', Hq.primary, SeriesType.bar, [for (final m in months) m.number('done')]),
          ChartSeries('Cancelled', Hq.red, SeriesType.bar, [for (final m in months) m.number('cancelled')]),
        ])),
        card('Rating from academies', 'Average per month, out of 5', HqChart(labels: labels, tipLabels: tips, height: 200, noRange: true, axisFmt: (v) => v.toStringAsFixed(1), tipFmt: (v) => '${v.toStringAsFixed(1)} / 5', series: [
          ChartSeries('Rating', Hq.gold, SeriesType.area, [for (final m in months) m.number('rating')]),
        ])),
        card('Needs a look', 'Slipping on rating, timing, cancellations or complaints', d.maps('watch').isEmpty
            ? const EmptyNote('Everyone is on track')
            : HqList([for (final p in d.maps('watch')) HqRow(title: p.str('name'), sub: p.strings('flags').join(' · '), onTap: () => showProviderDrawer(context, ref, p.str('id')), trailing: ic('chev', 14, Hq.faint))])),
        card('Best rated', 'Live providers', HqList([
          for (final (i, p) in d.maps('best').indexed)
            HqRow(
              leading: Text('${i + 1}', style: HqText.row.copyWith(color: Hq.faint)),
              title: p.str('name'),
              sub: '${p.obj('perf').integer('done')} jobs · ${p.obj('perf').integer('onTime')}% on time',
              trailing: Text(stars(p.obj('perf')['rating']), style: HqText.row.copyWith(color: Hq.gold)),
              onTap: () => showProviderDrawer(context, ref, p.str('id')),
            ),
        ])),
        card('By type', 'Live providers', HqList([
          for (final t in d.maps('byType'))
            HqRow(leading: IconTile(t.str('icon'), tone: _tone(t.str('tone'))), title: t.str('name'), sub: '${t.integer('providers')} providers · ${t.integer('jobs')} jobs', trailing: Text(stars(t['rating']), style: HqText.row.copyWith(color: Hq.gold))),
        ])),
      ]);
    });
  }
}

// ----------------------------------------------------------------------------------- drawer

Future<void> showProviderDrawer(BuildContext context, WidgetRef ref, String id) => showHqDrawer(context, builder: (_) => _ProviderDrawer(id: id));

class _ProviderDrawer extends ConsumerWidget {
  const _ProviderDrawer({required this.id});
  final String id;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final detail = ref.watch(providerProvider(id));
    return detail.when(
      loading: () => const Center(child: CircularProgressIndicator(color: Hq.primary, strokeWidth: 2.5)),
      error: (e, _) => Padding(padding: const EdgeInsets.all(24), child: HqError(e is ApiException ? e.message : 'Could not load this provider.')),
      data: (p) {
        final types = p.maps('types');
        final first = types.isEmpty ? <String, dynamic>{} : types.first;
        return DrawerShell(
          coverColors: const [Color(0xFF3B2A5C), Color(0xFF2A2F66), Color(0xFF1E2A4D)],
          logo: DrawerLogo('', color: _tone(first.str('tone', 'primary')).color, icon: first.str('icon', 'users')),
          child: _Body(p: p),
        );
      },
    );
  }
}

class _Body extends ConsumerWidget {
  const _Body({required this.p});
  final Map<String, dynamic> p;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final canWrite = ref.watch(sessionProvider).user?.canWrite ?? false;
    final id = p.str('id');
    final status = p.str('status');
    final (sl, sc) = _status[status] ?? ('', Tone.mute);
    final live = status == 'live' || status == 'suspended';
    final pre = const ['applied', 'review', 'verify'].contains(status);
    final perf = p.obj('perf');
    final flags = p.strings('flags');
    final links = p.maps('links');
    final jobs = p.maps('jobs');
    final months = p.maps('months');

    String? nextStep() => switch (status) { 'applied' => 'review', 'review' => 'verify', 'verify' => 'live', 'suspended' => 'live', 'rejected' => 'applied', _ => null };
    String stepLabel() => switch (status) { 'applied' => 'Start checking links', 'review' => 'Links are fine, verify identity', 'verify' => 'Approve and go live', 'suspended' => 'Reinstate', _ => 'Reopen application' };

    Widget card(String title, String sub, Widget child) => HqCard(margin: const EdgeInsets.only(top: 12), child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [CardHeader(title, sub: sub.isEmpty ? null : sub, bottom: 6), child]));

    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Wrap(spacing: 6, runSpacing: 6, children: [Tag(sl, tone: sc), for (final t in p.maps('types')) Tag(t.str('name'), tone: _tone(t.str('tone'))), if (flags.isNotEmpty) const Tag('Needs a look', tone: Tone.red)]),
      const SizedBox(height: 8),
      Text(p.str('name'), style: HqText.h2.copyWith(fontSize: 19)),
      const SizedBox(height: 3),
      Text('${p.str('ref')} · ${p.str('city')} · ${p.integer('years')} years · applied ${fd(p['appliedOn'])}', style: HqText.muted.copyWith(fontSize: 12.5)),
      if (canWrite)
        Padding(
          padding: const EdgeInsets.only(top: 12),
          child: Row(children: [
            if (nextStep() != null) Expanded(child: HqButton(stepLabel(), kind: BtnKind.primary, expand: true, onPressed: () => _post(context, ref, (c) async => await c.postMap('/admin/hq/providers/$id/step', body: {'to': nextStep()}), status == 'verify' ? 'Provider is live' : 'Done'))) else Expanded(child: HqButton('Send a warning', expand: true, onPressed: () => _modal(context, ref, 'warn'))),
            const SizedBox(width: 8),
            if (pre) Expanded(child: HqButton('Reject', expand: true, color: Hq.red, onPressed: () => _modal(context, ref, 'rejected')))
            else if (status == 'live') Expanded(child: HqButton('Suspend', expand: true, color: Hq.red, onPressed: () => _modal(context, ref, 'suspended'))),
          ]),
        ),
      if (live) MiniStats([(stars(perf['rating']), 'Rating', Hq.gold), ('${perf.integer('done')}', 'Jobs done', null), ('${perf.integer('onTime')}%', 'On time', null)]),
      if (flags.isNotEmpty) HqCard(margin: const EdgeInsets.only(bottom: 12), padding: const EdgeInsets.all(12), child: Row(children: [ic('warn', 13, Hq.red), const SizedBox(width: 8), Expanded(child: Text(flags.join(' · '), style: HqText.muted.copyWith(color: Hq.red, fontSize: 12.5)))])),
      card(
        'Portfolio links',
        'Their past work lives on these pages. Owleo does not store photos, videos or audio.',
        links.isEmpty
            ? const EmptyNote('No links', padding: 12)
            : HqList([
                for (final (i, l) in links.indexed)
                  HqRow(
                    title: l.str('u').replaceFirst(RegExp(r'^https?://(www\.)?'), ''),
                    wrap: true,
                    sub: l['ok'] == true ? 'Works' : l['ok'] == false ? 'Not working' : 'Not checked',
                    onTap: () => openUrl(l.str('u')),
                    trailing: canWrite
                        ? Row(mainAxisSize: MainAxisSize.min, children: [
                            HqButton('Works', small: true, onPressed: () => _post(context, ref, (c) async => await c.putMap('/admin/hq/providers/$id/links/$i', body: {'ok': true}), '')),
                            const SizedBox(width: 6),
                            HqButton('Broken', small: true, onPressed: () => _post(context, ref, (c) async => await c.putMap('/admin/hq/providers/$id/links/$i', body: {'ok': false}), '')),
                          ])
                        : null,
                  ),
              ]),
      ),
      card('Services and price', '', HqList([for (final s in p.strings('services')) HqRow(title: s, wrap: true), KeyValueRow('Starting price', '${inr(p.number('price'))} ${p.str('unit')}')])),
      if (p.str('bio').isNotEmpty) card('About', '', Text(p.str('bio'), style: HqText.muted.copyWith(fontSize: 13, height: 1.5))),
      card('Contact', 'Visible to Owleo only until an academy hires them', HqList([KeyValueRow('Person', p.str('person')), KeyValueRow('Phone', p.str('phone')), KeyValueRow('Email', p.str('email'))])),
      if (pre || live)
        card(
          'Checks',
          'Needed before going live: ID proof, a verification call and one working link',
          HqList([
            for (final k in p.maps('kyc'))
              HqCheckRow(checked: k.flag('done'), title: k.str('label'), sub: k.str('sub'), onChanged: canWrite && status != 'rejected' ? (v) => _post(context, ref, (c) async => await c.putMap('/admin/hq/providers/$id/kyc/${k.str('key')}', body: {'done': v}), '') : null),
          ]),
        ),
      if (live) ...[
        card('Performance', 'Last 6 months, from jobs booked through Owleo', Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          HqChart(labels: [for (final m in months) monthShort(m.str('month'))], tipLabels: [for (final m in months) monthLong(m.str('month'))], height: 170, noRange: true, series: [
            ChartSeries('Done', Hq.primary, SeriesType.bar, [for (final m in months) m.number('done')]),
            ChartSeries('Cancelled', Hq.red, SeriesType.bar, [for (final m in months) m.number('cancelled')]),
          ]),
          const SizedBox(height: 8),
          HqList([
            KeyValueRow('Jobs completed', '${perf.integer('done')} done, ${perf.integer('cancelled')} cancelled, ${perf.integer('upcoming')} coming up'),
            KeyValueRow('Completion', '${perf.integer('completion')}%'),
            KeyValueRow('Arrived on time', '${perf.integer('onTime')}%'),
            KeyValueRow('Academies that hired again', '${perf.integer('repeat')}%'),
            KeyValueRow('Complaints', '${perf.integer('complaints')}', valueColor: perf.integer('complaints') >= 3 ? Hq.red : null),
            KeyValueRow('Value of jobs', inr(perf.number('value'))),
          ]),
        ])),
        card('Recent jobs', '', jobs.isEmpty ? const EmptyNote('No jobs yet', padding: 12) : HqList([
          for (final j in jobs)
            HqRow(
              title: j.str('academy'),
              wrap: true,
              sub: '${j.str('event')} · ${fd(j['date'])} · ${inr(j.number('amount'))}${j.flag('late') ? ' · arrived late' : ''}${j.flag('issue') ? ' · complaint' : ''}',
              trailing: j.str('status') == 'cancelled'
                  ? const Tag('Cancelled', tone: Tone.red)
                  : j.str('status') == 'upcoming'
                      ? (canWrite ? HqButton('Record outcome', small: true, onPressed: () => _outcome(context, ref, j)) : const Tag('Upcoming', tone: Tone.blue))
                      : Text('★ ${j.integer('rating')}', style: HqText.row.copyWith(color: Hq.gold)),
            ),
        ])),
      ],
      card('History', '', HqList([for (final h in p.maps('log')) HqRow(title: h.str('x'), wrap: true, sub: '${h.str('who')} · ${ago(h['at'])}', titleStyle: HqText.row.copyWith(fontSize: 12.5, fontWeight: FontWeight.w600))])),
    ]);
  }

  Future<void> _modal(BuildContext context, WidgetRef ref, String kind) async {
    final done = await showHqModal<bool>(context, builder: (_) => _ReasonModal(provider: p, kind: kind));
    if (done == true) {
      refreshProviders(ref);
      if (context.mounted) showToast(context, kind == 'warn' ? 'Warning recorded' : kind == 'suspended' ? 'Provider suspended' : 'Application rejected');
    }
  }

  Future<void> _outcome(BuildContext context, WidgetRef ref, Map<String, dynamic> job) async {
    final done = await showHqModal<bool>(context, builder: (_) => _Outcome(job: job));
    if (done == true) refreshProviders(ref);
  }
}

class _ReasonModal extends ConsumerStatefulWidget {
  const _ReasonModal({required this.provider, required this.kind});
  final Map<String, dynamic> provider;
  final String kind; // warn | suspended | rejected

  @override
  ConsumerState<_ReasonModal> createState() => _ReasonModalState();
}

class _ReasonModalState extends ConsumerState<_ReasonModal> {
  late final _c = TextEditingController(
      text: widget.kind == 'warn' ? 'Hi ${widget.provider.str('person').split(' ').first}, we noticed some late arrivals and a few complaints from academies recently. Please arrive on time and reply within a day. Repeated issues can lead to suspension.' : '');
  String? _error;
  bool _busy = false;

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  Future<void> _go() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final id = widget.provider.str('id');
      final dio = ref.read(dioClientProvider);
      if (widget.kind == 'warn') {
        await dio.postMap('/admin/hq/providers/$id/warn', body: {'message': _c.text.trim()});
      } else {
        await dio.postMap('/admin/hq/providers/$id/stop', body: {'kind': widget.kind, 'reason': _c.text.trim()});
      }
      if (mounted) Navigator.of(context).pop(true);
    } on ApiException catch (e) {
      setState(() {
        _busy = false;
        _error = e.message;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final k = widget.kind;
    return ModalFrame(
      title: k == 'warn' ? 'Send a warning' : k == 'suspended' ? 'Suspend provider' : 'Reject application',
      sub: widget.provider.str('name'),
      error: _error,
      actions: [
        HqButton('Cancel', onPressed: () => Navigator.of(context).pop()),
        HqButton(k == 'warn' ? 'Record warning' : k == 'suspended' ? 'Suspend' : 'Reject', kind: k == 'warn' ? BtnKind.primary : BtnKind.danger, busy: _busy, onPressed: _go),
      ],
      children: [
        HqField(label: k == 'warn' ? 'Message' : 'Reason', controller: _c, maxLines: k == 'warn' ? 4 : 3, hint: k == 'suspended' ? 'What went wrong?' : 'Why can they not go live?'),
        Text(k == 'warn' ? 'The warning is recorded in their history. Delivering it is up to you: no message is sent from here.' : k == 'suspended' ? 'They stop appearing to academies. Jobs already booked are not cancelled.' : 'They are told the reason and can reapply.', style: HqText.sub),
        const SizedBox(height: 12),
      ],
    );
  }
}

class _Outcome extends ConsumerStatefulWidget {
  const _Outcome({required this.job});
  final Map<String, dynamic> job;

  @override
  ConsumerState<_Outcome> createState() => _OutcomeState();
}

class _OutcomeState extends ConsumerState<_Outcome> {
  String _status = 'done';
  int _rating = 5;
  bool _late = false, _issue = false;
  String? _error;
  bool _busy = false;

  Future<void> _go() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await ref.read(dioClientProvider).postMap('/admin/hq/providers/jobs/${widget.job.str('id')}/outcome', body: {'status': _status, 'rating': _rating, 'late': _late, 'issue': _issue});
      if (mounted) Navigator.of(context).pop(true);
    } on ApiException catch (e) {
      setState(() {
        _busy = false;
        _error = e.message;
      });
    }
  }

  @override
  Widget build(BuildContext context) => ModalFrame(
        title: 'Record outcome',
        sub: '${widget.job.str('academy')} · ${widget.job.str('event')}',
        error: _error,
        actions: [HqButton('Cancel', onPressed: () => Navigator.of(context).pop()), HqButton('Save', kind: BtnKind.primary, busy: _busy, onPressed: _go)],
        children: [
          SegControl<String>(expand: true, items: const [('done', 'Done'), ('cancelled', 'Cancelled')], value: _status, onChanged: (v) => setState(() => _status = v)),
          if (_status == 'done') ...[
            const SizedBox(height: 14),
            Text("ACADEMY'S RATING", style: HqText.th),
            const SizedBox(height: 8),
            Wrap(spacing: 8, children: [for (var i = 1; i <= 5; i++) HqChip('$i ★', selected: _rating == i, onTap: () => setState(() => _rating = i))]),
            const SizedBox(height: 8),
            HqList([HqCheckRow(checked: _late, title: 'Arrived late', onChanged: (v) => setState(() => _late = v)), HqCheckRow(checked: _issue, title: 'The academy complained', onChanged: (v) => setState(() => _issue = v))]),
          ],
          const SizedBox(height: 12),
        ],
      );
}

// ------------------------------------------------------------------------------ small forms

class _NewType extends StatefulWidget {
  const _NewType();

  @override
  State<_NewType> createState() => _NewTypeState();
}

class _NewTypeState extends State<_NewType> {
  final _c = TextEditingController();
  String? _err;

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => ModalFrame(
        title: 'New type of service',
        error: _err,
        actions: [HqButton('Cancel', onPressed: () => Navigator.of(context).pop()), HqButton('Add', kind: BtnKind.primary, onPressed: () => _c.text.trim().length < 3 ? setState(() => _err = 'Give it a name of at least 3 letters.') : Navigator.of(context).pop(_c.text.trim()))],
        children: [HqField(label: 'Name', controller: _c, hint: 'For example: Lighting rental')],
      );
}

class _NewProvider extends ConsumerStatefulWidget {
  const _NewProvider({required this.types});
  final List<Map<String, dynamic>> types;

  @override
  ConsumerState<_NewProvider> createState() => _NewProviderState();
}

class _NewProviderState extends ConsumerState<_NewProvider> {
  final _name = TextEditingController(), _person = TextEditingController(), _phone = TextEditingController(), _email = TextEditingController();
  final _years = TextEditingController(), _price = TextEditingController(), _services = TextEditingController(), _bio = TextEditingController();
  final _l1 = TextEditingController(), _l2 = TextEditingController(), _l3 = TextEditingController();
  String _city = _cities.first, _unit = _units.first;
  final Set<String> _types = {};
  String? _error;
  bool _busy = false;

  @override
  void dispose() {
    for (final c in [_name, _person, _phone, _email, _years, _price, _services, _bio, _l1, _l2, _l3]) {
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
      await ref.read(dioClientProvider).postMap('/admin/hq/providers', body: {
        'name': _name.text.trim(),
        'person': _person.text.trim(),
        'phone': _phone.text.trim(),
        'email': _email.text.trim(),
        'city': _city,
        'types': _types.toList(),
        'years': _years.text.trim(),
        'price': _price.text.trim(),
        'unit': _unit,
        'services': _services.text.trim(),
        'bio': _bio.text.trim(),
        'links': [_l1.text.trim(), _l2.text.trim(), _l3.text.trim()],
      });
      if (mounted) Navigator.of(context).pop(true);
    } on ApiException catch (e) {
      setState(() {
        _busy = false;
        _error = e.message;
      });
    }
  }

  @override
  Widget build(BuildContext context) => ModalFrame(
        title: 'Onboard a provider',
        sub: 'Enter what they sent. Links are required, files are not.',
        error: _error,
        actions: [HqButton('Cancel', onPressed: () => Navigator.of(context).pop()), HqButton('Add provider', kind: BtnKind.primary, busy: _busy, onPressed: _go)],
        children: [
          HqField(label: 'Business or studio name', controller: _name),
          HqField(label: 'Contact person name', controller: _person),
          FieldRow2([
            HqField(label: 'Phone', controller: _phone, keyboard: TextInputType.phone, formatters: [FilteringTextInputFormatter.digitsOnly, LengthLimitingTextInputFormatter(10)]),
            HqField(label: 'Email', controller: _email, keyboard: TextInputType.emailAddress),
          ]),
          HqSelect<String>(label: 'City', value: _city, options: [for (final c in _cities) SelectOption(c, c)], onChanged: (v) => setState(() => _city = v)),
          Text('WHAT THEY OFFER', style: HqText.th),
          const SizedBox(height: 8),
          Wrap(spacing: 8, runSpacing: 8, children: [for (final t in widget.types) HqChip(t.str('name'), selected: _types.contains(t.str('code')), onTap: () => setState(() => _types.contains(t.str('code')) ? _types.remove(t.str('code')) : _types.add(t.str('code'))))]),
          const SizedBox(height: 13),
          FieldRow2([
            HqField(label: 'Years of work', controller: _years, keyboard: TextInputType.number, formatters: [FilteringTextInputFormatter.digitsOnly]),
            HqField(label: 'Starting price (₹)', controller: _price, keyboard: TextInputType.number, formatters: [FilteringTextInputFormatter.digitsOnly]),
          ]),
          HqSelect<String>(label: 'Price is', value: _unit, searchable: false, options: [for (final u in _units) SelectOption(u, u)], onChanged: (v) => setState(() => _unit = v)),
          HqField(label: 'Services (one per line)', controller: _services, maxLines: 3),
          HqField(label: 'About them', controller: _bio, maxLines: 3),
          Text('PORTFOLIO LINKS (AT LEAST ONE)', style: HqText.th),
          const SizedBox(height: 8),
          HqField(label: 'Instagram', controller: _l1, hint: 'https://instagram.com/...'),
          HqField(label: 'YouTube', controller: _l2, hint: 'https://youtube.com/...'),
          HqField(label: 'Website or portfolio', controller: _l3, hint: 'https://...'),
        ],
      );
}
