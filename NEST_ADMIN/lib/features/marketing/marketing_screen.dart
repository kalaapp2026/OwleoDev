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
import '../../core/ui/layout.dart';
import '../../core/ui/overlays.dart';
import '../../core/ui/primitives.dart';
import '../users/users_screen.dart' show FieldRow2;

final marketingProvider = FutureProvider.autoDispose.family<Map<String, dynamic>, String>(
  (ref, channel) => ref.watch(dioClientProvider).getMap('/admin/hq/marketing', query: {'channel': channel}),
);

const _categories = ['Dance', 'Music', 'Fine Arts', 'Theatre'];

Tone _channelTone(String c) => switch (c) { 'META' => Tone.blue, 'INAPP' => Tone.primary, _ => Tone.violet };
String _channelLabel(String c) => switch (c) { 'META' => 'Meta ads', 'INAPP' => 'In-app ads', _ => 'Meta + In-app' };
Tone _statusTone(String s) => switch (s) { 'live' => Tone.green, 'draft' => Tone.gold, 'paused' => Tone.coral, _ => Tone.mute };

/// Marketing: campaigns run for academies, and the rules that decide who may be reached.
class MarketingScreen extends ConsumerStatefulWidget {
  const MarketingScreen({super.key});

  @override
  ConsumerState<MarketingScreen> createState() => _MarketingScreenState();
}

class _MarketingScreenState extends ConsumerState<MarketingScreen> {
  String _channel = 'all';

  void _refresh() => ref.invalidate(marketingProvider);

  Future<void> _act(String id, String action, String ok) async {
    try {
      await ref.read(dioClientProvider).postMap('/admin/hq/marketing/$id/$action');
      _refresh();
      if (mounted) showToast(context, ok);
    } on ApiException catch (e) {
      if (mounted) showToast(context, e.message);
    }
  }

  @override
  Widget build(BuildContext context) {
    final user = ref.watch(sessionProvider).user;
    final canRun = user != null && (user.isSuper || user.role.code == 'FINANCE');
    return asyncBody(ref.watch(marketingProvider(_channel)), onRetry: _refresh, data: (d) {
      final items = d.maps('items');
      return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        HqGrid(GridKind.g4, [
          Kpi(icon: 'mega', tone: Tone.primary, label: 'Live campaigns', value: '${d.integer('live')}', foot: 'across ${d.integer('academies')} academies'),
          Kpi(icon: 'rupee', tone: Tone.gold, label: 'Ad spend', value: short(d.number('spend')), foot: 'all campaigns'),
          Kpi(icon: 'users', tone: Tone.green, label: 'Leads', value: num0(d.integer('leads')), foot: 'enquiries and demo bookings'),
          Kpi(icon: 'target', tone: Tone.violet, label: 'Cost per lead', value: d['costPerLead'] == null ? '–' : inr(d.number('costPerLead')), foot: 'average'),
        ]),
        Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: Row(children: [
            Expanded(child: SegControl<String>(items: const [('all', 'All'), ('META', 'Meta ads'), ('INAPP', 'In-app ads')], value: _channel, onChanged: (v) => setState(() => _channel = v))),
            const SizedBox(width: 10),
            if (canRun)
              HqButton('New campaign', icon: 'plus', small: true, kind: BtnKind.primary, onPressed: () async {
                final done = await showHqModal<bool>(context, builder: (_) => _NewCampaign(academies: d.maps('academyList')));
                if (done == true) {
                  _refresh();
                  if (context.mounted) showToast(context, 'Saved as a draft');
                }
              }),
          ]),
        ),
        if (items.isEmpty) const EmptyNote('No campaigns on this channel yet.'),
        LayoutBuilder(builder: (context, c) {
          final cols = c.maxWidth >= 760 ? 2 : 1;
          return Wrap(spacing: 14, runSpacing: 14, children: [for (final x in items) SizedBox(width: (c.maxWidth - (cols - 1) * 14) / cols, child: _card(x, canRun))]);
        }),
        HqCard(
          margin: const EdgeInsets.only(top: 14),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            const CardHeader('How audiences are built', sub: 'Rules applied to every campaign', bottom: 6),
            HqList([
              for (final t in [
                ('shield', 'Only students and parents who gave marketing consent are included.'),
                ('users', 'Under-18s are never targeted. Ads for their courses go to the guardian.'),
                ('lock', "Phone numbers and emails are hashed before they are matched on Meta. Academies never see other academies' data."),
                ('eye', 'Every reveal of contact details is logged against the admin who viewed it.'),
              ])
                HqRow(leading: IconTile(t.$1, tone: Tone.green), title: t.$2, wrap: true, titleStyle: HqText.body.copyWith(fontSize: 12.5)),
            ]),
          ]),
        ),
      ]);
    });
  }

  Widget _card(Map<String, dynamic> c, bool canRun) {
    final status = c.str('status');
    final budget = c.number('budget');
    final p = budget == 0 ? 0.0 : (c.number('spend') / budget * 100).clamp(0, 100).toDouble();
    return HqCard(
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text(c.str('name'), style: HqText.row.copyWith(fontSize: 14)), Text(c.str('academy'), style: HqText.small)]),
          ),
          Tag(status, tone: _statusTone(status)),
        ]),
        const SizedBox(height: 11),
        Wrap(spacing: 6, runSpacing: 6, children: [Tag(_channelLabel(c.str('channel')), tone: _channelTone(c.str('channel'))), Tag(c.str('audience'), tone: Tone.mute, lowercase: true)]),
        const SizedBox(height: 11),
        Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
          Text('${inr(c.number('spend'))} of ${inr(budget)}', style: HqText.small),
          Text(c['endsOn'] == null ? 'Not started' : 'Ends ${fdShort(c['endsOn'])}', style: HqText.small),
        ]),
        const SizedBox(height: 5),
        HqBar(p, tone: Tone.gold),
        MiniStats([(num0(c.integer('reach')), 'Reach', null), (num0(c.integer('clicks')), 'Clicks', null), ('${c.integer('leads')}', 'Leads', null)]),
        if (canRun)
          Wrap(spacing: 6, runSpacing: 6, children: [
            if (status == 'draft') HqButton('Launch', small: true, kind: BtnKind.primary, onPressed: () => _act(c.str('id'), 'launch', 'Campaign launched')),
            if (status == 'live') HqButton('Pause', small: true, onPressed: () => _act(c.str('id'), 'pause', 'Campaign paused')),
            if (status == 'paused') HqButton('Resume', small: true, kind: BtnKind.primary, onPressed: () => _act(c.str('id'), 'resume', 'Campaign resumed')),
            if (status != 'draft' && status != 'ended') HqButton('Update results', small: true, onPressed: () async {
                  final done = await showHqModal<bool>(context, builder: (_) => _Results(campaign: c));
                  if (done == true) {
                    _refresh();
                    if (mounted) showToast(context, 'Figures updated');
                  }
                }),
            if (status != 'ended') HqButton('End', small: true, color: Hq.red, onPressed: () => _act(c.str('id'), 'end', 'Campaign ended')),
          ]),
      ]),
    );
  }
}

class _Results extends ConsumerStatefulWidget {
  const _Results({required this.campaign});
  final Map<String, dynamic> campaign;

  @override
  ConsumerState<_Results> createState() => _ResultsState();
}

class _ResultsState extends ConsumerState<_Results> {
  late final _spend = TextEditingController(text: widget.campaign.number('spend').round().toString());
  late final _reach = TextEditingController(text: '${widget.campaign.integer('reach')}');
  late final _clicks = TextEditingController(text: '${widget.campaign.integer('clicks')}');
  late final _leads = TextEditingController(text: '${widget.campaign.integer('leads')}');
  String? _error;
  bool _busy = false;

  @override
  void dispose() {
    for (final c in [_spend, _reach, _clicks, _leads]) {
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
      await ref.read(dioClientProvider).putMap('/admin/hq/marketing/${widget.campaign.str('id')}/results', body: {'spend': _spend.text.trim(), 'reach': _reach.text.trim(), 'clicks': _clicks.text.trim(), 'leads': _leads.text.trim()});
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
    final f = [FilteringTextInputFormatter.digitsOnly];
    return ModalFrame(
      title: 'Update results',
      sub: '${widget.campaign.str('name')}: figures from the ad platform',
      error: _error,
      actions: [HqButton('Cancel', onPressed: () => Navigator.of(context).pop()), HqButton('Save', kind: BtnKind.primary, busy: _busy, onPressed: _go)],
      children: [
        FieldRow2([HqField(label: 'Spend so far (₹)', controller: _spend, keyboard: TextInputType.number, formatters: f), HqField(label: 'Reach', controller: _reach, keyboard: TextInputType.number, formatters: f)]),
        FieldRow2([HqField(label: 'Clicks', controller: _clicks, keyboard: TextInputType.number, formatters: f), HqField(label: 'Leads', controller: _leads, keyboard: TextInputType.number, formatters: f)]),
      ],
    );
  }
}

class _NewCampaign extends ConsumerStatefulWidget {
  const _NewCampaign({required this.academies});
  final List<Map<String, dynamic>> academies;

  @override
  ConsumerState<_NewCampaign> createState() => _NewCampaignState();
}

class _NewCampaignState extends ConsumerState<_NewCampaign> {
  final _name = TextEditingController(), _budget = TextEditingController();
  String? _academy;
  String _channel = 'META', _who = 'GUARD';
  String _days = '14';
  final Set<String> _interests = {};
  Map<String, dynamic>? _est;
  String? _error;
  bool _busy = false;
  int _seq = 0;

  @override
  void dispose() {
    _name.dispose();
    _budget.dispose();
    super.dispose();
  }

  Future<void> _estimate() async {
    final a = _academy;
    if (a == null) return;
    final mine = ++_seq;
    try {
      final r = await ref.read(dioClientProvider).getMap('/admin/hq/marketing/estimate', query: {'academy': a, 'audience': _who, 'interests': _interests.toList()});
      if (mounted && mine == _seq) setState(() => _est = r);
    } on ApiException {
      // The estimate is a hint; the form still works without it.
    }
  }

  Future<void> _go() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await ref.read(dioClientProvider).postMap('/admin/hq/marketing', body: {'name': _name.text.trim(), 'academyId': _academy ?? '', 'channel': _channel, 'audience': _who, 'interests': _interests.toList(), 'budget': _budget.text.trim(), 'days': int.parse(_days)});
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
    return ModalFrame(
      title: 'New campaign',
      sub: 'Run ads on behalf of an academy',
      error: _error,
      actions: [HqButton('Cancel', onPressed: () => Navigator.of(context).pop()), HqButton('Save as draft', kind: BtnKind.primary, busy: _busy, onPressed: _go)],
      children: [
        HqField(label: 'Campaign name', controller: _name, hint: 'e.g. Free demo class for kids'),
        HqSelect<String>(label: 'Academy', value: _academy, hint: 'Choose an academy', options: [for (final a in widget.academies) SelectOption(a.str('id'), a.str('name'))], onChanged: (v) {
          setState(() => _academy = v);
          _estimate();
        }),
        FieldRow2([
          HqSelect<String>(label: 'Channel', value: _channel, searchable: false, options: const [SelectOption('META', 'Meta ads'), SelectOption('INAPP', 'In-app ads'), SelectOption('BOTH', 'Meta and in-app')], onChanged: (v) => setState(() => _channel = v)),
          HqSelect<String>(label: 'Who sees it', value: _who, searchable: false, options: const [SelectOption('GUARD', 'Parents of under-18s'), SelectOption('ADULT', 'Adult students'), SelectOption('ALL', 'Both')], onChanged: (v) {
            setState(() => _who = v);
            _estimate();
          }),
        ]),
        Text('INTERESTS', style: HqText.th),
        const SizedBox(height: 8),
        Wrap(spacing: 8, runSpacing: 8, children: [
          for (final c in _categories)
            HqChip(c, selected: _interests.contains(c), onTap: () {
              setState(() => _interests.contains(c) ? _interests.remove(c) : _interests.add(c));
              _estimate();
            }),
        ]),
        const SizedBox(height: 13),
        FieldRow2([
          HqField(label: 'Budget (₹)', controller: _budget, keyboard: TextInputType.number, hint: 'e.g. 10000', formatters: [FilteringTextInputFormatter.digitsOnly]),
          HqSelect<String>(label: 'Runs for', value: _days, searchable: false, options: const [SelectOption('7', '7 days'), SelectOption('14', '14 days'), SelectOption('30', '30 days')], onChanged: (v) => setState(() => _days = v)),
        ]),
        if (_est != null)
          Container(
            padding: const EdgeInsets.all(12),
            margin: const EdgeInsets.only(bottom: 12),
            decoration: BoxDecoration(color: Hq.surface, borderRadius: BorderRadius.circular(14), border: Border.all(color: Hq.border)),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text("${num0(_est!.integer('reachable'))} people can be reached from this academy's own list", style: HqText.row.copyWith(fontSize: 14)),
              const SizedBox(height: 3),
              Text('${_est!.integer('excluded')} of ${_est!.integer('total')} profiles are left out because they have not given marketing consent.${_est!.integer('reachable') > 0 ? ' Meta lookalike audiences can widen this to about ${num0(_est!.integer('lookalike'))} people nearby.' : ''}', style: HqText.small),
            ]),
          ),
      ],
    );
  }
}
