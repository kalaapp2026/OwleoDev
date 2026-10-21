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
import '../shell/nav.dart';

final invoicingNextProvider = FutureProvider.autoDispose<Map<String, dynamic>>((ref) => ref.watch(dioClientProvider).getMap('/admin/hq/invoicing/next'));
final invoicingHistoryProvider = FutureProvider.autoDispose<List<Map<String, dynamic>>>((ref) => ref.watch(dioClientProvider).getList('/admin/hq/invoicing/history'));
final invoicingRunProvider = FutureProvider.autoDispose.family<List<Map<String, dynamic>>, String>((ref, period) => ref.watch(dioClientProvider).getList('/admin/hq/invoicing/history/$period'));

String _ordinal(int n) => '$n${n % 10 == 1 && n != 11 ? 'st' : n % 10 == 2 && n != 12 ? 'nd' : n % 10 == 3 && n != 13 ? 'rd' : 'th'}';
String _day(Object? iso) {
  final d = toDate(iso);
  if (d == null) return '';
  const wd = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
  return '${wd[d.weekday - 1]}, ${fd(d)}';
}

String _offerText(Map<String, dynamic> o) => switch (o.str('type')) {
      'PCT' => '${o.number('value').round()}% off',
      'FLAT' => '${inr(o.number('value'))} off',
      _ => 'First month free',
    };

/// What an academy's bill comes to: the same sums the server does when it makes the bill.
({int all, int disc, int sub, int gst, int tot}) _totals(List<Map<String, dynamic>> lines, Map<String, dynamic> disc, List<Map<String, dynamic>> offers, num gstRate) {
  var all = 0, rec = 0, plan = 0;
  for (final l in lines) {
    final a = l.integer('amount');
    all += a;
    final k = l.str('kind');
    if (k == 'PLAN' || k == 'ADDON') rec += a;
    if (k == 'PLAN') plan += a;
  }
  var ds = 0;
  final t = disc.str('t');
  if (t == 'offer' && disc.str('offer').isNotEmpty) {
    final o = offers.where((x) => x.str('id') == disc.str('offer')).toList();
    if (o.isNotEmpty) {
      final v = o.first.number('value');
      ds = switch (o.first.str('type')) { 'PCT' => (rec * v / 100).round(), 'FLAT' => v.round() < rec ? v.round() : rec, _ => plan };
    }
  } else if (t == 'pct') {
    ds = (rec * disc.number('val').clamp(0, 100) / 100).round();
  } else if (t == 'flat') {
    final v = disc.number('val').round();
    ds = v < 0 ? 0 : (v > rec ? rec : v);
  }
  final sub = (all - ds) < 0 ? 0 : all - ds;
  final gst = (sub * gstRate / 100).round();
  return (all: all, disc: ds, sub: sub, gst: gst, tot: sub + gst);
}

/// Invoicing: the monthly bill run to academy admins.
class InvoicingScreen extends ConsumerStatefulWidget {
  const InvoicingScreen({super.key});

  @override
  ConsumerState<InvoicingScreen> createState() => _InvoicingScreenState();
}

class _InvoicingScreenState extends ConsumerState<InvoicingScreen> {
  String _tab = 'nx', _filter = 'all', _q = '';
  bool _more = false;

  bool get _canWrite {
    final u = ref.read(sessionProvider).user;
    return u != null && (u.isSuper || u.role.code == 'FINANCE');
  }

  void _refresh() {
    ref.invalidate(invoicingNextProvider);
    ref.invalidate(invoicingHistoryProvider);
    ref.invalidate(invoicingRunProvider);
  }

  @override
  Widget build(BuildContext context) {
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: SegControl<String>(expand: true, items: const [('nx', 'Next bills'), ('sc', 'Schedule'), ('hs', 'History')], value: _tab, onChanged: (v) => setState(() => _tab = v)),
      ),
      if (_tab == 'hs') _history() else asyncBody(ref.watch(invoicingNextProvider), onRetry: _refresh, data: (d) => _tab == 'nx' ? _next(d) : _schedule(d)),
    ]);
  }

  // ---- next bills ----

  Widget _runCard(Map<String, dynamic> d) {
    final dates = d.obj('dates');
    final days = d.integer('daysToGenerate');
    final auto = d.flag('auto');
    return HqCard(
      margin: const EdgeInsets.only(bottom: 12),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        CardHeader('${d.str('monthLabel')} bills', sub: auto ? 'Runs by itself on the date below' : 'Automatic run is off. You run it by hand.', trailing: Tag(auto ? 'Automatic' : 'By hand', tone: auto ? Tone.green : Tone.gold), bottom: 6),
        HqList([
          Row(children: [Expanded(child: Text('Generated', style: HqText.small)), Text('${_day(dates['generate'])}${auto && days > 0 ? ' · in $days day${days == 1 ? '' : 's'}' : ''}', style: HqText.row)]),
          Row(children: [Expanded(child: Text('Sent to admins', style: HqText.small)), Text(_day(dates['send']), style: HqText.row)]),
          Row(children: [Expanded(child: Text('Due', style: HqText.small)), Text(_day(dates['due']), style: HqText.row)]),
        ]),
        const SizedBox(height: 10),
        Align(alignment: Alignment.centerLeft, child: HqButton('Change schedule', icon: 'clock', small: true, onPressed: () => _editSchedule(d))),
      ]),
    );
  }

  Widget _next(Map<String, dynamic> d) {
    final all = d.maps('academies');
    final offers = d.maps('offers');
    final gst = d.number('gst', 18);
    final active = all.where((a) => !a.flag('skip')).toList();
    int tot(Map<String, dynamic> a) => _totals(a.maps('lines'), a.obj('disc'), offers, gst).tot;
    int dsc(Map<String, dynamic> a) => _totals(a.maps('lines'), a.obj('disc'), offers, gst).disc;
    final total = active.fold<int>(0, (s, a) => s + tot(a));
    final discounts = active.fold<int>(0, (s, a) => s + dsc(a));
    final nDisc = active.where((a) => dsc(a) > 0).length;
    final nEdit = all.where((a) => a.flag('edited')).length;
    final fl = <String, bool Function(Map<String, dynamic>)>{'all': (_) => true, 'edit': (a) => a.flag('edited'), 'disc': (a) => dsc(a) > 0, 'skip': (a) => a.flag('skip')};
    final q = _q.trim().toLowerCase();
    final list = all.where((a) => fl[_filter]!(a) && (q.isEmpty || a.str('name').toLowerCase().contains(q))).toList();
    final shown = _more ? list : list.take(20).toList();

    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      _runCard(d),
      HqGrid(GridKind.g4, [
        Kpi(icon: 'file', tone: Tone.primary, label: 'Bills', value: '${active.length}', foot: 'of ${all.length} academies'),
        Kpi(icon: 'rupee', tone: Tone.gold, label: 'Total', value: short(total), foot: 'with ${gst.round()}% GST'),
        Kpi(icon: 'spark', tone: Tone.green, label: 'Discounts', value: short(discounts), foot: '$nDisc ${nDisc == 1 ? 'academy' : 'academies'}'),
        Kpi(icon: 'edit', tone: Tone.blue, label: 'Edited', value: '$nEdit', foot: 'charges changed'),
      ]),
      Padding(padding: const EdgeInsets.only(bottom: 12), child: SearchBox(hint: 'Search academy', height: 46, onChanged: (v) => setState(() => _q = v))),
      Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: ChipRow([for (final (k, n) in const [('all', 'All'), ('edit', 'Edited'), ('disc', 'Discounted'), ('skip', 'Skipped')]) HqChip(n, selected: _filter == k, count: all.where(fl[k]!).length, onTap: () => setState(() {
              _filter = k;
              _more = false;
            }))]),
      ),
      if (shown.isEmpty) const EmptyNote('No academies match.'),
      LayoutBuilder(builder: (context, c) {
        final cols = c.maxWidth >= 760 ? 2 : 1;
        return Wrap(spacing: 10, runSpacing: 10, children: [for (final a in shown) SizedBox(width: (c.maxWidth - (cols - 1) * 10) / cols, child: _card(d, a, offers, gst))]);
      }),
      if (list.length > 20) Padding(padding: const EdgeInsets.only(top: 10), child: Align(alignment: Alignment.centerLeft, child: HqButton(_more ? 'Show fewer' : 'Show all ${list.length}', small: true, onPressed: () => setState(() => _more = !_more)))),
      if (_canWrite)
        Padding(
          padding: const EdgeInsets.only(top: 14),
          child: Row(children: [
            Expanded(child: HqButton('Generate and send', icon: 'send', kind: BtnKind.primary, expand: true, onPressed: active.isEmpty ? null : () => _runModal(d, true, active.length, all.length - active.length, total, discounts))),
            const SizedBox(width: 8),
            Expanded(child: HqButton('Generate only', expand: true, onPressed: active.isEmpty ? null : () => _runModal(d, false, active.length, all.length - active.length, total, discounts))),
          ]),
        ),
      const PageNote('Tap an academy to change its charges, add a discount or offer, or skip it this month. Event commission is not part of these bills yet; marketing fees and commission can be added to a bill from Collections.'),
    ]);
  }

  Widget _card(Map<String, dynamic> d, Map<String, dynamic> a, List<Map<String, dynamic>> offers, num gst) {
    final t = _totals(a.maps('lines'), a.obj('disc'), offers, gst);
    final skip = a.flag('skip');
    final owes = a.number('owes');
    final n = a.maps('lines').length;
    return Opacity(
      opacity: skip ? .6 : 1,
      child: HqCard(
        radius: 14,
        padding: const EdgeInsets.all(12),
        onTap: () => _openAcademy(d, a),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Row(children: [
            IconTile('file', tone: Tone.byName(_planTone(a.str('plan'))), size: 36),
            const SizedBox(width: 11),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text(a.str('name'), style: HqText.row.copyWith(fontSize: 13.5)), Text('${a.str('planName')} plan · $n item${n == 1 ? '' : 's'}', style: HqText.small)])),
            Text(inr(t.tot), style: HqText.row.copyWith(decoration: skip ? TextDecoration.lineThrough : null)),
          ]),
          if (skip || a.flag('edited') || t.disc > 0 || owes > 0) ...[
            const SizedBox(height: 10),
            Wrap(spacing: 6, runSpacing: 6, children: [
              if (skip) const Tag('Skipped'),
              if (a.flag('edited')) const Tag('Edited', tone: Tone.blue),
              if (t.disc > 0) Tag('Discount ${inr(t.disc)}', tone: Tone.green),
              if (owes > 0) Tag('Owes ${short(owes)}', tone: Tone.red),
            ]),
          ],
        ]),
      ),
    );
  }

  String _planTone(String plan) => switch (plan.toUpperCase()) { 'BASIC' => 'blue', 'STANDARD' => 'primary', 'PREMIUM' => 'gold', _ => 'violet' };

  Future<void> _openAcademy(Map<String, dynamic> d, Map<String, dynamic> a) async {
    final changed = await showHqDrawer<bool>(context, width: 520, builder: (_) => _BillDrawer(next: d, academy: a, canWrite: _canWrite));
    if (changed == true) _refresh();
  }

  Future<void> _editSchedule(Map<String, dynamic> d) async {
    if (!_canWrite) return showToast(context, 'Only a Super admin or Finance admin can change this');
    final done = await showHqModal<bool>(context, builder: (_) => _ScheduleModal(settings: d));
    if (done == true) {
      _refresh();
      if (mounted) showToast(context, 'Schedule saved');
    }
  }

  Future<void> _runModal(Map<String, dynamic> d, bool send, int bills, int skipped, int total, int discounts) async {
    final r = await showHqModal<Map<String, dynamic>>(context, builder: (_) => _RunModal(next: d, send: send, bills: bills, skipped: skipped, total: total, discounts: discounts));
    if (r == null || !mounted) return;
    _refresh();
    final created = r.integer('created'), sent = r.integer('sent');
    showToast(context, send ? (sent > 0 ? '$created bills generated and sent' : '$created bills generated. Not sent: no channel could reach anyone') : '$created bills generated');
  }

  // ---- schedule ----

  Widget _schedule(Map<String, dynamic> d) {
    final dates = d.obj('dates');
    final ch = d.obj('ch'), ready = d.obj('ready');
    final sm = switch (d.str('sm')) {
      'same' => 'The same day it is generated',
      'after' => '${d.integer('after')} day${d.integer('after') == 1 ? '' : 's'} after it is generated',
      _ => 'On the ${_ordinal(d.integer('sday'))} of the month',
    };
    const names = {'em': 'Email', 'app': 'Owleo Nest app', 'wa': 'WhatsApp'};
    final picked = [for (final k in ['em', 'app', 'wa']) if (ch.flag(k)) k];
    final delivered = picked.where((k) => ready.flag(k)).toList(), skipped = picked.where((k) => !ready.flag(k)).toList();
    final tpl = d.obj('template');
    Widget row(String l, String v) => Padding(padding: const EdgeInsets.symmetric(vertical: 6), child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [SizedBox(width: 150, child: Text(l, style: HqText.small)), Expanded(child: Text(v, style: HqText.row.copyWith(fontSize: 13)))]));

    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      HqCard(
        margin: const EdgeInsets.only(bottom: 12),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          CardHeader('Monthly bill run', sub: 'When bills are made and sent', trailing: _canWrite ? HqButton('Edit', icon: 'edit', small: true, onPressed: () => _editSchedule(d)) : null, bottom: 6),
          row('Run automatically', d.flag('auto') ? 'Yes' : 'No, I run it by hand'),
          row('Generate bills', 'On the ${_ordinal(d.integer('gen'))} of every month'),
          row('Send to academy admins', sm),
          row('Payment due', '${d.integer('due')} days after sending'),
          row('Sent on', picked.isEmpty ? 'No channel picked' : picked.map((k) => '${names[k]}${ready.flag(k) ? '' : ' (not set up)'}').join(', ')),
          row('Next run', '${d.str('monthLabel')}: generated ${fdShort(dates['generate'])}, sent ${fdShort(dates['send'])}, due ${fdShort(dates['due'])}'),
        ]),
      ),
      if (delivered.isEmpty)
        HqCard(margin: const EdgeInsets.only(bottom: 12), child: Text('None of the channels you picked is set up yet, so bills would be generated but not sent.', style: HqText.body.copyWith(fontSize: 12.5, color: Hq.gold, height: 1.5)))
      else if (skipped.isNotEmpty)
        HqCard(margin: const EdgeInsets.only(bottom: 12), child: Text('${skipped.map((k) => names[k]).join(' and ')} ${skipped.length > 1 ? 'are' : 'is'} not set up yet, so ${skipped.length > 1 ? 'those are' : 'that is'} skipped. Bills still go out on ${delivered.map((k) => names[k]).join(' and ')}.', style: HqText.muted.copyWith(fontSize: 12.5, height: 1.5))),
      HqCard(
        margin: const EdgeInsets.only(bottom: 12),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          const CardHeader('What is on each bill', sub: "Built from the academy's plan", bottom: 6),
          row('Plan', 'The monthly price of the academy plan'),
          row('Add-ons', 'Each add-on the academy has, from the month it started'),
          row('Setup fee', 'Once, in the month the academy goes live'),
          row('Your changes', 'Charges you edit, add or waive for one academy'),
          row('Discount or offer', 'Taken off the plan and add-ons, then ${d.number('gst', 18).round()}% GST is added'),
          const SizedBox(height: 10),
          Wrap(spacing: 8, runSpacing: 8, children: [
            HqButton('Manage offers', small: true, onPressed: () => hqGo(context, '/collections')),
            HqButton('Manage add-ons', small: true, onPressed: () => hqGo(context, '/collections')),
            HqButton('Plan prices', small: true, onPressed: () => hqGo(context, '/plans')),
          ]),
        ]),
      ),
      HqCard(
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          CardHeader('Message to admins', sub: tpl.flag('on') ? 'Sent with every bill' : 'The template is off, so plain default wording is used', trailing: HqButton('Edit', icon: 'edit', small: true, onPressed: () => hqGo(context, '/notifs')), bottom: 8),
          if (!tpl.flag('exists'))
            const EmptyNote('No template yet.')
          else ...[
            Text(tpl.str('title'), style: HqText.row.copyWith(fontSize: 13)),
            const SizedBox(height: 4),
            Text(tpl.str('body'), style: HqText.small.copyWith(fontSize: 12.5, height: 1.5)),
          ],
        ]),
      ),
    ]);
  }

  // ---- history ----

  Widget _history() {
    return asyncBody(ref.watch(invoicingHistoryProvider), onRetry: _refresh, data: (rows) {
      return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        if (rows.isEmpty) const HqCard(child: EmptyNote('No bills yet.')) else HqCard(
          child: HqList([
            for (final r in rows)
              HqRow(
                title: r.str('monthLabel'),
                sub: '${fd(r['at'])} · ${r.str('mode')} · ${r.integer('bills')} bills · ${inr(r.number('total'))}',
                wrap: true,
                trailing: Tag(r.integer('sent') >= r.integer('bills') ? 'All sent' : '${r.integer('bills') - r.integer('sent')} not sent', tone: r.integer('sent') >= r.integer('bills') ? Tone.green : Tone.gold),
                onTap: () async {
                  final changed = await showHqModal<bool>(context, builder: (_) => _RunBills(run: r, canWrite: _canWrite));
                  if (changed == true) _refresh();
                },
              ),
          ]),
        ),
        const PageNote('Tap a month to see its bills. Bills that were generated but not sent can be sent from there.'),
      ]);
    });
  }
}

// ---------------------------------------------------------------------------------------------------------

class _RunBills extends ConsumerStatefulWidget {
  const _RunBills({required this.run, required this.canWrite});
  final Map<String, dynamic> run;
  final bool canWrite;

  @override
  ConsumerState<_RunBills> createState() => _RunBillsState();
}

class _RunBillsState extends ConsumerState<_RunBills> {
  bool _busy = false, _changed = false;
  String? _error;

  Future<void> _send({String? bill}) async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final api = ref.read(dioClientProvider);
      if (bill != null) {
        await api.postMap('/admin/hq/invoicing/bills/$bill/send');
      } else {
        final r = await api.postMap('/admin/hq/invoicing/history/${widget.run.str('period')}/send');
        if (r.integer('sent') == 0 && mounted) setState(() => _error = 'Nobody could be reached. Check that a sending channel is set up in the schedule.');
      }
      _changed = true;
      ref.invalidate(invoicingRunProvider);
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final period = widget.run.str('period');
    final bills = ref.watch(invoicingRunProvider(period));
    final list = bills.valueOrNull ?? const <Map<String, dynamic>>[];
    final unsent = list.where((b) => !b.flag('sent')).length;
    return ModalFrame(
      title: '${widget.run.str('monthLabel')} bills',
      sub: '${fd(widget.run['at'])} · ${widget.run.str('mode')} · ${list.length} bills',
      error: _error,
      actions: [
        HqButton(unsent > 0 && widget.canWrite ? 'Close' : 'Done', onPressed: () => Navigator.of(context).pop(_changed)),
        if (unsent > 0 && widget.canWrite) HqButton('Send $unsent unsent', kind: BtnKind.primary, busy: _busy, onPressed: _send),
      ],
      children: [
        if (bills.isLoading && list.isEmpty) const HqLoading() else ConstrainedBox(
          constraints: const BoxConstraints(maxHeight: 360),
          child: SingleChildScrollView(
            child: HqList([
              for (final b in list)
                HqRow(
                  title: b.str('academy'),
                  sub: '${b.str('number')} · ${inr(b.number('total'))}${b.str('via').isEmpty ? '' : ' · ${b.str('via')}'}',
                  wrap: true,
                  trailing: b.flag('sent') ? const Tag('Sent', tone: Tone.green) : (widget.canWrite ? HqButton('Send', small: true, busy: _busy, onPressed: () => _send(bill: b.str('id'))) : const Tag('Not sent', tone: Tone.gold)),
                ),
            ]),
          ),
        ),
        if (unsent > 0) Padding(padding: const EdgeInsets.only(top: 10, bottom: 12), child: Text('$unsent not sent yet.', style: HqText.sub)),
      ],
    );
  }
}

class _RunModal extends ConsumerStatefulWidget {
  const _RunModal({required this.next, required this.send, required this.bills, required this.skipped, required this.total, required this.discounts});
  final Map<String, dynamic> next;
  final bool send;
  final int bills, skipped, total, discounts;

  @override
  ConsumerState<_RunModal> createState() => _RunModalState();
}

class _RunModalState extends ConsumerState<_RunModal> {
  bool _busy = false;
  String? _error;

  Future<void> _go() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final r = await ref.read(dioClientProvider).postMap('/admin/hq/invoicing/run', body: {'send': widget.send});
      if (mounted) Navigator.of(context).pop(r);
    } on ApiException catch (e) {
      setState(() {
        _busy = false;
        _error = e.message;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final n = widget.next;
    final ch = n.obj('ch'), ready = n.obj('ready');
    const names = {'em': 'Email', 'app': 'Owleo Nest app', 'wa': 'WhatsApp'};
    final picked = [for (final k in ['em', 'app', 'wa']) if (ch.flag(k)) k];
    final dl = picked.where((k) => ready.flag(k)).map((k) => names[k]!).toList();
    final sx = picked.where((k) => !ready.flag(k)).map((k) => names[k]!).toList();
    final today = DateTime.now();
    final due = today.add(Duration(days: n.integer('due')));
    Widget row(String l, String v) => Padding(padding: const EdgeInsets.symmetric(vertical: 5), child: Row(children: [Expanded(child: Text(l, style: HqText.small)), Text(v, style: HqText.row)]));
    return ModalFrame(
      title: widget.send ? 'Generate and send' : 'Generate bills',
      sub: n.str('monthLabel'),
      error: _error,
      actions: [HqButton('Cancel', onPressed: () => Navigator.of(context).pop()), HqButton(widget.send ? 'Generate and send' : 'Generate', kind: BtnKind.primary, busy: _busy, onPressed: _go)],
      children: [
        HqCard(
          margin: const EdgeInsets.only(bottom: 12),
          child: Column(children: [
            row('Bills', '${widget.bills}${widget.skipped > 0 ? ' (${widget.skipped} skipped)' : ''}'),
            row('Total with GST', inr(widget.total)),
            row('Discounts', inr(widget.discounts)),
            row('Issued', 'Today, ${fd(today)}'),
            row('Due', fd(due)),
          ]),
        ),
        if (widget.send)
          Text(
            dl.isEmpty
                ? 'None of your channels is set up yet. The bills will be created but not sent.'
                : 'Sent to the owner and the admin logins of each academy on ${dl.join(' and ')}.${sx.isEmpty ? '' : ' ${sx.join(' and ')} is not set up, so it is skipped.'}',
            style: HqText.body.copyWith(fontSize: 12.5, height: 1.5, color: dl.isEmpty ? Hq.gold : Hq.text),
          )
        else
          Text('The bills are created and shown in Collections. Nothing is sent until you send them from History.', style: HqText.muted.copyWith(fontSize: 12.5, height: 1.5)),
        const SizedBox(height: 8),
        Text("This uses today's date as the bill date. Once created, bills can be changed from Collections.", style: HqText.sub.copyWith(height: 1.5)),
        const SizedBox(height: 12),
      ],
    );
  }
}

class _ScheduleModal extends ConsumerStatefulWidget {
  const _ScheduleModal({required this.settings});
  final Map<String, dynamic> settings;

  @override
  ConsumerState<_ScheduleModal> createState() => _ScheduleModalState();
}

class _ScheduleModalState extends ConsumerState<_ScheduleModal> {
  late bool _auto = widget.settings.flag('auto');
  late int _gen = widget.settings.integer('gen', 1), _after = widget.settings.integer('after', 2), _sday = widget.settings.integer('sday', 5), _due = widget.settings.integer('due', 14);
  late String _sm = widget.settings.str('sm', 'same');
  late final Map<String, bool> _ch = {for (final k in ['em', 'app', 'wa']) k: widget.settings.obj('ch').flag(k)};
  bool _busy = false;
  String? _error;

  Future<void> _save() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await ref.read(dioClientProvider).putMap('/admin/hq/invoicing/settings', body: {'auto': _auto, 'gen': _gen, 'sm': _sm, 'after': _after, 'sday': _sday, 'due': _due, 'ch': _ch});
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
    final ready = widget.settings.obj('ready');
    const names = {'em': 'Email', 'app': 'Owleo Nest app', 'wa': 'WhatsApp'};
    final days = [for (var i = 1; i <= 28; i++) SelectOption(i, '${_ordinal(i)} of the month')];
    final period = widget.settings.str('period');
    final gen = DateTime.parse('$period-${_gen.toString().padLeft(2, '0')}');
    final send = switch (_sm) { 'after' => gen.add(Duration(days: _after)), 'day' => DateTime.parse('$period-${_sday.toString().padLeft(2, '0')}'), _ => gen };
    return ModalFrame(
      title: 'Bill schedule',
      sub: 'Dates for the monthly bill run',
      error: _error,
      actions: [HqButton('Cancel', onPressed: () => Navigator.of(context).pop()), HqButton('Save schedule', kind: BtnKind.primary, busy: _busy, onPressed: _save)],
      children: [
        Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: Row(children: [
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text('Run automatically', style: HqText.row), Text('Off: you generate and send from the Next bills tab', style: HqText.small)])),
            HqSwitch(value: _auto, onChanged: (v) => setState(() => _auto = v)),
          ]),
        ),
        HqSelect<int>(label: 'Generate bills on', value: _gen, searchable: false, options: days, onChanged: (v) => setState(() => _gen = v)),
        HqSelect<String>(label: 'Send to academy admins', value: _sm, searchable: false, options: const [SelectOption('same', 'The same day'), SelectOption('after', 'A few days after generating'), SelectOption('day', 'On a fixed day of the month')], onChanged: (v) => setState(() => _sm = v)),
        if (_sm == 'after') HqSelect<int>(label: 'Days after generating', value: _after, searchable: false, options: [for (final n in [1, 2, 3, 4, 5, 7, 10]) SelectOption(n, '$n day${n == 1 ? '' : 's'}')], onChanged: (v) => setState(() => _after = v)),
        if (_sm == 'day') HqSelect<int>(label: 'Day to send', value: _sday, searchable: false, options: days, onChanged: (v) => setState(() => _sday = v)),
        HqSelect<int>(label: 'Payment is due', value: _due, searchable: false, options: [for (final n in [7, 10, 14, 15, 21, 30]) SelectOption(n, '$n days after sending')], onChanged: (v) => setState(() => _due = v)),
        Text('Send through', style: HqText.label),
        const SizedBox(height: 8),
        ChipRow([for (final k in ['em', 'app', 'wa']) HqChip('${names[k]}${ready.flag(k) ? '' : ' · not set up'}', selected: _ch[k] == true, onTap: () => setState(() => _ch[k] = !(_ch[k] == true)))]),
        const SizedBox(height: 14),
        HqCard(
          margin: const EdgeInsets.only(bottom: 12),
          child: Text.rich(TextSpan(style: HqText.muted.copyWith(fontSize: 12.5, height: 1.6), children: [
            TextSpan(text: '${widget.settings.str('monthLabel')} would go like this:\nGenerated '),
            TextSpan(text: _day(gen), style: const TextStyle(color: Hq.text, fontWeight: FontWeight.w800)),
            const TextSpan(text: '\nSent '),
            TextSpan(text: _day(send), style: const TextStyle(color: Hq.text, fontWeight: FontWeight.w800)),
            const TextSpan(text: '\nDue '),
            TextSpan(text: _day(send.add(Duration(days: _due))), style: const TextStyle(color: Hq.text, fontWeight: FontWeight.w800)),
          ])),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------------------------------------

class _Line {
  _Line({required this.kind, required String label, required int amount, required this.standard})
      : label = TextEditingController(text: label),
        amount = TextEditingController(text: '$amount');

  String kind;
  final TextEditingController label, amount;
  final int standard;

  int get value => int.tryParse(amount.text.replaceAll(RegExp(r'[^\d]'), '')) ?? 0;

  Map<String, dynamic> toJson() => {'kind': kind, 'label': label.text.trim(), 'amount': value, 'standard': standard};

  void dispose() {
    label.dispose();
    amount.dispose();
  }
}

class _BillDrawer extends ConsumerStatefulWidget {
  const _BillDrawer({required this.next, required this.academy, required this.canWrite});
  final Map<String, dynamic> next, academy;
  final bool canWrite;

  @override
  ConsumerState<_BillDrawer> createState() => _BillDrawerState();
}

class _BillDrawerState extends ConsumerState<_BillDrawer> {
  late final List<_Line> _lines = [for (final l in widget.academy.maps('lines')) _Line(kind: l.str('kind'), label: l.str('label'), amount: l.integer('amount'), standard: l.integer('standard'))];
  late String _dt = widget.academy.obj('disc').str('t', 'none');
  late String _offer = widget.academy.obj('disc').str('offer');
  late final _val = TextEditingController(text: widget.academy.obj('disc').integer('val') == 0 ? '' : '${widget.academy.obj('disc').integer('val')}');
  late final _reason = TextEditingController(text: widget.academy.obj('disc').str('reason'));
  late int _months = widget.academy.obj('disc').integer('months', 1);
  late final _note = TextEditingController(text: widget.academy.str('note'));
  late bool _keep = widget.academy.flag('keep');
  bool _adding = false, _busy = false;
  final _newLabel = TextEditingController(), _newAmount = TextEditingController();
  String? _error, _addError;

  @override
  void dispose() {
    for (final l in _lines) {
      l.dispose();
    }
    for (final c in [_val, _reason, _note, _newLabel, _newAmount]) {
      c.dispose();
    }
    super.dispose();
  }

  List<Map<String, dynamic>> get _offers {
    final plan = widget.academy.str('plan');
    return [for (final o in widget.next.maps('offers')) if (o.str('applies_to') == 'all' || o.str('applies_to') == plan) o];
  }

  Map<String, dynamic> get _disc => {'t': _dt, 'offer': _offer, 'val': int.tryParse(_val.text.trim()) ?? 0, 'reason': _reason.text.trim(), 'months': _months};
  List<Map<String, dynamic>> get _lineJson => [for (final l in _lines) l.toJson()];
  ({int all, int disc, int sub, int gst, int tot}) get _t => _totals(_lineJson, _disc, widget.next.maps('offers'), widget.next.number('gst', 18));

  Future<void> _call(Future<void> Function() f, String ok) async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await f();
      if (!mounted) return;
      Navigator.of(context).pop(true);
      showToast(context, ok);
    } on ApiException catch (e) {
      if (mounted) {
        setState(() {
          _busy = false;
          _error = e.message;
        });
      }
    }
  }

  Map<String, dynamic> _body({bool? skip}) => {'skip': skip ?? widget.academy.flag('skip'), 'keep': _keep, 'note': _note.text.trim(), 'lines': _lineJson, 'disc': _disc};

  void _done() {
    if (!widget.canWrite) return Navigator.of(context).pop();
    _call(() => ref.read(dioClientProvider).putMap('/admin/hq/invoicing/drafts/${widget.academy.str('id')}', body: _body()).then((_) {}), 'Saved');
  }

  void _skip() {
    final skip = !widget.academy.flag('skip');
    _call(() => ref.read(dioClientProvider).putMap('/admin/hq/invoicing/drafts/${widget.academy.str('id')}', body: _body(skip: skip)).then((_) {}), skip ? 'Skipped this month' : 'Included again');
  }

  void _reset() => _call(() => ref.read(dioClientProvider).delete('/admin/hq/invoicing/drafts/${widget.academy.str('id')}'), 'Back to the standard bill');

  void _addCharge() {
    final label = _newLabel.text.trim();
    final amt = int.tryParse(_newAmount.text.replaceAll(RegExp(r'[^\d]'), '')) ?? 0;
    if (label.length < 3) return setState(() => _addError = 'Say what the charge is for.');
    if (amt <= 0) return setState(() => _addError = 'Enter an amount above zero.');
    setState(() {
      _lines.add(_Line(kind: 'CUSTOM', label: label, amount: amt, standard: amt));
      _adding = false;
      _addError = null;
      _newLabel.clear();
      _newAmount.clear();
    });
  }

  String _preview(String text) {
    final a = widget.academy;
    final t = _t;
    final period = widget.next.str('period');
    final owner = (a.maps('to').firstOrNull?.str('name') ?? '').split(' ').first;
    final v = {
      'owner': owner.isEmpty ? 'there' : owner,
      'academy': a.str('name'),
      'month': widget.next.str('monthLabel'),
      'invoice': 'INV-${period.substring(2, 4)}${period.substring(5, 7)}-###',
      'amount': inr(t.tot),
      'due_date': fdShort(widget.next.obj('dates')['due']),
      'plan': a.str('planName'),
      'discount': inr(t.disc),
    };
    return text.replaceAllMapped(RegExp(r'\{(\w+)\}'), (m) => v[m.group(1)] ?? m.group(0)!);
  }

  Widget _section(String title, String? sub, List<Widget> children) => HqCard(
        margin: const EdgeInsets.only(top: 12),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [CardHeader(title, sub: sub, bottom: 8), ...children]),
      );

  @override
  Widget build(BuildContext context) {
    final a = widget.academy;
    final write = widget.canWrite;
    final t = _t;
    final skip = a.flag('skip');
    final owes = a.number('owes');
    final to = a.maps('to');
    final tpl = widget.next.obj('template');
    final useTpl = tpl.flag('exists') && tpl.flag('on');
    final title = useTpl ? tpl.str('title') : 'Your {month} Owleo bill';
    final body = useTpl ? tpl.str('body') : 'Hi {owner}, the {month} bill {invoice} for {academy} is ready. Amount to pay {amount}, due on {due_date}.';
    final offers = _offers;
    final intFmt = [FilteringTextInputFormatter.digitsOnly];

    return DrawerShell(
      coverColors: const [Color(0xFF4D3E1E), Color(0xFF1E2A4D)],
      logo: const DrawerLogo('', color: Hq.gold, icon: 'file'),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Wrap(spacing: 6, runSpacing: 6, children: [Tag('${a.str('planName')} plan', tone: Tone.primary), if (skip) const Tag('Skipped this month'), if (owes > 0) Tag('Owes ${inr(owes)}', tone: Tone.red)]),
        const SizedBox(height: 8),
        Text('${widget.next.str('monthLabel')} bill', style: HqText.h2.copyWith(fontSize: 19)),
        const SizedBox(height: 3),
        Text(a.str('name'), style: HqText.muted.copyWith(fontSize: 12.5)),
        _section('Goes to', 'Academy admins who get this bill', [
          if (to.isEmpty) Text('This academy has no email on file, so it can only be reached in the app.', style: HqText.small.copyWith(color: Hq.gold)),
          HqList([for (final r in to) HqRow(title: r.str('name').isEmpty ? r.str('role') : r.str('name'), sub: '${r.str('email')}${r.str('phone').isEmpty ? '' : ' · ${r.str('phone')}'} · ${r.str('role')}', wrap: true)]),
        ]),
        _section('Charges', 'Change an amount, remove an item or add a charge', [
          for (var i = 0; i < _lines.length; i++)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Row(crossAxisAlignment: CrossAxisAlignment.center, children: [
                Expanded(
                  child: _lines[i].kind == 'CUSTOM'
                      ? HqField(label: 'Charge name', controller: _lines[i].label, maxLength: 40, bottom: 0, readOnly: !write, onChanged: (_) => setState(() {}))
                      : Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text(_lines[i].label.text, style: HqText.row), Text(_lines[i].value != _lines[i].standard ? 'Changed from ${inr(_lines[i].standard)}' : 'Standard price', style: HqText.small)]),
                ),
                const SizedBox(width: 8),
                SizedBox(width: 108, child: HqField(label: 'Amount', controller: _lines[i].amount, keyboard: TextInputType.number, formatters: intFmt, bottom: 0, readOnly: !write, onChanged: (_) => setState(() {}))),
                if (_lines[i].kind != 'PLAN' && write) ...[
                  const SizedBox(width: 4),
                  HqIconButton('x', size: 34, onTap: () => setState(() => _lines.removeAt(i).dispose())),
                ],
              ]),
            ),
          if (write)
            if (_adding) ...[
              const SizedBox(height: 4),
              HqField(label: 'What is it for', controller: _newLabel, maxLength: 40, hint: 'For example: Setup help'),
              HqField(label: 'Amount (₹)', controller: _newAmount, keyboard: TextInputType.number, formatters: intFmt),
              if (_addError != null) Padding(padding: const EdgeInsets.only(bottom: 8), child: Text(_addError!, style: HqText.small.copyWith(color: Hq.red, fontSize: 12.5))),
              Row(children: [HqButton('Add charge', small: true, kind: BtnKind.primary, onPressed: _addCharge), const SizedBox(width: 8), HqButton('Cancel', small: true, onPressed: () => setState(() => _adding = false))]),
            ] else
              Align(alignment: Alignment.centerLeft, child: HqButton('Add a charge', icon: 'plus', small: true, onPressed: () => setState(() => _adding = true))),
        ]),
        _section('Discount or offer', 'Taken off before GST', [
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: SegControl<String>(
              expand: true,
              items: const [('none', 'None'), ('offer', 'Offer'), ('pct', 'Percent'), ('flat', 'Amount')],
              value: _dt,
              onChanged: (v) {
                if (!write) return;
                setState(() {
                  _dt = v;
                  if (v == 'none') {
                    _offer = '';
                    _val.clear();
                  } else if (v == 'pct' || v == 'flat') {
                    _val.clear();
                  }
                });
              },
            ),
          ),
          if (_dt == 'offer') ...[
            HqSelect<String>(label: 'Offer', value: _offer.isEmpty ? null : _offer, hint: 'Choose an offer', searchable: false, options: [for (final o in offers) SelectOption(o.str('id'), '${o.str('name')} · ${_offerText(o)}')], onChanged: (v) => setState(() => _offer = v)),
            if (offers.isEmpty) Padding(padding: const EdgeInsets.only(bottom: 10), child: Text('No active offer fits this plan. Create one in Collections.', style: HqText.small)),
          ],
          if (_dt == 'pct' || _dt == 'flat') ...[
            HqField(label: _dt == 'pct' ? 'Percent off' : 'Amount off (₹)', controller: _val, keyboard: TextInputType.number, formatters: intFmt, maxLength: 6, readOnly: !write, onChanged: (_) => setState(() {})),
            HqField(label: 'Reason (shown on the bill)', controller: _reason, maxLength: 40, hint: 'For example: Loyalty discount', readOnly: !write),
          ],
          if (_dt != 'none') ...[
            HqSelect<int>(label: 'Applies to', value: _months, searchable: false, options: const [SelectOption(1, 'This bill only'), SelectOption(2, 'This and the next bill'), SelectOption(3, 'The next 3 bills'), SelectOption(6, 'The next 6 bills'), SelectOption(12, 'The next 12 bills')], onChanged: (v) => setState(() => _months = v)),
            Text('Takes ${inr(t.disc)} off the plan and add-ons', style: HqText.row.copyWith(fontSize: 12.5, color: Hq.green)),
          ],
          const SizedBox(height: 10),
          Align(alignment: Alignment.centerLeft, child: HqButton('Manage offers', small: true, onPressed: () => hqGo(context, '/collections'))),
        ]),
        _section('Bill total', null, [
          HqList([
            HqRow(title: 'Charges', trailing: Text(inr(t.all), style: HqText.row)),
            if (t.disc > 0) HqRow(title: 'Discount', trailing: Text('-${inr(t.disc)}', style: HqText.row.copyWith(color: Hq.green))),
            HqRow(title: 'GST (${widget.next.number('gst', 18).round()}%)', trailing: Text(inr(t.gst), style: HqText.row)),
            HqRow(title: 'Total', sub: 'Due ${fd(widget.next.obj('dates')['due'])}', titleStyle: HqText.row.copyWith(fontSize: 15), trailing: Text(inr(t.tot), style: HqText.row.copyWith(fontSize: 17))),
          ]),
        ]),
        _section('Note on the bill', 'Optional. The academy sees it.', [
          HqField(label: 'Note', controller: _note, maxLines: 2, maxLength: 140, hint: 'For example: Discount for being with us two years', readOnly: !write),
          GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: write ? () => setState(() => _keep = !_keep) : null,
            child: Row(children: [
              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text('Keep these charges for later bills', style: HqText.row), Text('Off: next month starts from the standard price again', style: HqText.small)])),
              HqSwitch(value: _keep, onChanged: write ? (v) => setState(() => _keep = v) : null),
            ]),
          ),
        ]),
        _section('What the admin gets', 'The message that goes with the bill', [
          Container(
            decoration: BoxDecoration(color: Hq.high, borderRadius: BorderRadius.circular(16), border: Border.all(color: Hq.border)),
            clipBehavior: Clip.antiAlias,
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Container(
                padding: const EdgeInsets.all(12),
                decoration: const BoxDecoration(border: Border(bottom: BorderSide(color: Hq.border))),
                child: Text.rich(TextSpan(style: HqText.small.copyWith(fontSize: 11.5, height: 1.5), children: [
                  const TextSpan(text: 'From '),
                  const TextSpan(text: 'Owleo\n', style: TextStyle(color: Hq.text, fontWeight: FontWeight.w800)),
                  const TextSpan(text: 'Subject '),
                  TextSpan(text: _preview(title), style: const TextStyle(color: Hq.text, fontWeight: FontWeight.w800)),
                ])),
              ),
              Padding(padding: const EdgeInsets.all(12), child: Text(_preview(body), style: HqText.body.copyWith(height: 1.5))),
            ]),
          ),
          if (!useTpl) Padding(padding: const EdgeInsets.only(top: 8), child: Text('The Monthly bill template is off, so this plain wording is used.', style: HqText.small.copyWith(color: Hq.gold))),
        ]),
        if (_error != null) Padding(padding: const EdgeInsets.only(top: 12), child: Text(_error!, style: HqText.small.copyWith(color: Hq.red, fontSize: 12.5))),
        if (write) ...[
          const SizedBox(height: 14),
          Row(children: [
            Expanded(child: HqButton(skip ? 'Include this month' : 'Skip this month', expand: true, onPressed: _busy ? null : _skip)),
            const SizedBox(width: 8),
            Expanded(child: HqButton('Reset to standard', expand: true, onPressed: _busy ? null : _reset)),
          ]),
        ],
        const SizedBox(height: 8),
        HqButton(write ? 'Save and close' : 'Close', kind: BtnKind.primary, expand: true, busy: _busy, onPressed: _done),
      ]),
    );
  }
}
