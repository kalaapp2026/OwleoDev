import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/theme.dart';
import '../../core/api/api_exception.dart';
import '../../core/auth/session.dart';
import '../../core/download.dart';
import '../../core/format.dart';
import '../../core/json.dart';
import '../../core/ui/async.dart';
import '../../core/ui/charts.dart';
import '../../core/ui/controls.dart';
import '../../core/ui/icons.dart';
import '../../core/ui/layout.dart';
import '../../core/ui/overlays.dart';
import '../../core/ui/primitives.dart';
import '../plans/plans_screen.dart';
import 'account_drawer.dart';
import 'bill_widgets.dart';
import 'collections_data.dart';
import 'collections_dialogs.dart';

/// What academy owners pay Owleo: the plan, add-ons and commission. Student fees are not part of this.
class CollectionsScreen extends ConsumerStatefulWidget {
  const CollectionsScreen({super.key});

  @override
  ConsumerState<CollectionsScreen> createState() => _CollectionsScreenState();
}

class _CollectionsScreenState extends ConsumerState<CollectionsScreen> {
  String _tab = 'ov';
  String _mode = 'month';
  String? _ym;
  late DateTime _day = DateTime.now();
  String _lens = 'rec';
  String _billFilter = 'all';
  String _monthFilter = 'all';
  String _q = '';
  bool _more = false;

  bool get _write {
    final u = ref.read(sessionProvider).user;
    return u != null && (u.isSuper || u.role.code == 'FINANCE');
  }

  String get _dayIso => _day.toIso8601String().substring(0, 10);

  @override
  Widget build(BuildContext context) {
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      HqCard(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        margin: const EdgeInsets.only(bottom: 12),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          ic('wallet', 16, Hq.gold),
          const SizedBox(width: 10),
          Expanded(
            child: Text.rich(TextSpan(style: HqText.muted.copyWith(fontSize: 12.5), children: [
              const TextSpan(text: 'What '),
              TextSpan(text: 'academy owners pay Owleo', style: HqText.muted.copyWith(fontSize: 12.5, color: Hq.text, fontWeight: FontWeight.w700)),
              const TextSpan(text: ': the plan, add-ons and event commission. Student fees are not part of this.'),
            ])),
          ),
        ]),
      ),
      Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: SegControl<String>(
          expand: true,
          items: const [('ov', 'Overview'), ('inv', 'Bills'), ('off', 'Offers'), ('add', 'Add-ons')],
          value: _tab,
          onChanged: (v) => setState(() {
            _tab = v;
            _more = false;
          }),
        ),
      ),
      switch (_tab) {
        'inv' => _bills(),
        'off' => _offers(),
        'add' => _addons(),
        _ => _overview(),
      },
    ]);
  }

  // ---------------------------------------------------------------------------- overview

  Widget _overview() {
    final key = (_ym ?? DateTime.now().toIso8601String().substring(0, 7), _mode == 'day' ? _dayIso : null);
    final ov = ref.watch(collectionsOverviewProvider(key));
    return asyncBody(ov, onRetry: () => ref.invalidate(collectionsOverviewProvider), data: (d) => _overviewBody(d, key.$1));
  }

  Widget _overviewBody(Map<String, dynamic> d, String ym) {
    final day = _mode == 'day';
    final kpi = d.obj('kpi');
    final trend = d.maps('trend');
    final daysN = d.integer('days');
    final byDay = d.obj('byDay');
    final modes = d.obj('modes');
    final aging = d.maps('aging');
    final top = d.maps('topOverdue');
    final rs = d.obj('reminderSettings');
    final recents = d.maps('recentReminders');
    final write = _write;
    const modeColors = {
      'Autopay': Hq.primary, 'UPI': Hq.blue, 'Card': Hq.violet, 'Net banking': Hq.gold, 'Bank transfer': Hq.coral, 'Cheque': Hq.magenta, 'Cash': Hq.green,
    };
    final periodLabel = day ? fd(_day) : monthLong(ym);

    Widget lens(String k, Widget kpiCard) => MouseRegion(
          cursor: SystemMouseCursors.click,
          child: GestureDetector(
            onTap: () => setState(() {
              _lens = k;
              _more = false;
            }),
            child: Container(
              decoration: BoxDecoration(borderRadius: BorderRadius.circular(18), boxShadow: _lens == k ? [BoxShadow(color: Hq.primary, spreadRadius: 1.5, blurRadius: 0)] : null),
              child: kpiCard,
            ),
          ),
        );

    final tiles = day
        ? [
            lens('rec', Kpi(icon: 'rupee', tone: Tone.green, label: 'Received', value: inr(kpi.number('received')), foot: '$periodLabel · ${kpi.integer('receivedCount')} payments')),
            lens('bil', Kpi(icon: 'file', tone: Tone.primary, label: 'Billed', value: inr(kpi.number('billed')), foot: 'bills issued on this day')),
            lens('due', Kpi(icon: 'clock', tone: Tone.gold, label: 'Due', value: inr(kpi.number('due')), foot: 'all bills, not yet late')),
            lens('over', Kpi(icon: 'warn', tone: Tone.red, label: 'Overdue', value: inr(kpi.number('overdue')), foot: 'all bills, past the due date')),
          ]
        : [
            lens('rec', Kpi(icon: 'rupee', tone: Tone.green, label: 'Received', value: inr(kpi.number('received')), foot: 'payments in ${monthLong(ym)}')),
            lens('bil', Kpi(icon: 'file', tone: Tone.primary, label: 'Billed', value: inr(kpi.number('billed')), foot: '${kpi.integer('billedCount')} bills for ${monthLong(ym)}')),
            lens('due', Kpi(icon: 'clock', tone: Tone.gold, label: 'Due', value: inr(kpi.number('due')), foot: 'on ${monthShort(ym)} bills')),
            lens('over', Kpi(icon: 'warn', tone: Tone.red, label: 'Overdue', value: inr(kpi.number('overdue')), foot: 'on ${monthShort(ym)} bills')),
          ];

    final listKey = switch (_lens) { 'bil' => 'billedList', 'due' => 'dueList', 'over' => 'overdueList', _ => 'payments' };
    final items = d.maps(listKey);
    final shown = _more ? items : items.take(8).toList();
    final lensTitle = switch (_lens) { 'bil' => 'Bills issued', 'due' => 'Due bills', 'over' => 'Overdue bills', _ => 'Payments received' };
    final unpaidMax = aging.isEmpty ? 1.0 : aging.map((x) => x.number('amount')).reduce((a, b) => a > b ? a : b).clamp(1, double.infinity).toDouble();
    final modeSum = modes.values.fold<double>(0, (s, v) => s + (v as num).toDouble());

    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: Wrap(spacing: 8, runSpacing: 8, crossAxisAlignment: WrapCrossAlignment.center, children: [
          SegControl<String>(
            items: const [('month', 'Month'), ('day', 'Day')],
            value: _mode,
            onChanged: (v) => setState(() {
              _mode = v;
              _more = false;
            }),
          ),
          if (day) ...[
            HqIconButton('left', onTap: () => setState(() => _day = _day.subtract(const Duration(days: 1)))),
            SizedBox(
              width: 150,
              child: DateButton(label: '', value: _day, onTap: () async {
                final p = await pickHqDate(context, initial: _day, first: DateTime(2024), last: DateTime.now());
                if (p != null) setState(() => _day = p);
              }),
            ),
            HqIconButton('chev', onTap: _day.isBefore(DateTime(DateTime.now().year, DateTime.now().month, DateTime.now().day)) ? () => setState(() => _day = _day.add(const Duration(days: 1))) : null),
          ],
          if (write)
            HqButton("Raise this month's bills", icon: 'file', small: true, onPressed: _generate),
        ]),
      ),
      if (!day)
        Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: ChipRow(scroll: true, [
            for (final t in trend) HqChip('${monthShort(t.str('month'))} ${t.str('month').substring(2, 4)}', selected: ym == t.str('month'), onTap: () => setState(() {
                  _ym = t.str('month');
                  _more = false;
                })),
          ]),
        ),
      HqGrid(GridKind.g4, tiles),
      if (!day)
        HqCard(
          margin: const EdgeInsets.only(bottom: 12),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            CardHeader('Received each day', sub: '${monthLong(ym)}, by how the academy paid'),
            HqChart(
              labels: [for (var i = 1; i <= daysN; i++) '$i'],
              height: 230,
              stack: true,
              noRange: true,
              axisFmt: short,
              tipFmt: inr,
              series: [
                for (final e in byDay.entries)
                  if ((e.value as List).any((x) => (x as num) != 0) || modeColors.containsKey(e.key))
                    ChartSeries(e.key, modeColors[e.key] ?? Hq.muted, SeriesType.bar, (e.value as List).map((x) => (x as num).toDouble()).toList()),
              ],
            ),
          ]),
        ),
      HqCard(
        margin: const EdgeInsets.only(bottom: 12),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const CardHeader('Billed, received and unpaid', sub: 'Last 6 months'),
          HqChart(
            labels: trend.map((t) => monthShort(t.str('month'))).toList(),
            tipLabels: trend.map((t) => monthLong(t.str('month'))).toList(),
            height: 230,
            axisFmt: short,
            tipFmt: inr,
            onLegend: (n) => setState(() {
              _lens = {'Billed': 'bil', 'Received': 'rec', 'Unpaid': 'over'}[n] ?? _lens;
              _more = false;
            }),
            series: [
              ChartSeries('Billed', Hq.blue, SeriesType.bar, trend.map((t) => t.number('billed')).toList()),
              ChartSeries('Received', Hq.primary, SeriesType.bar, trend.map((t) => t.number('received')).toList()),
              ChartSeries('Unpaid', Hq.red, SeriesType.bar, trend.map((t) => t.number('unpaid')).toList()),
            ],
          ),
        ]),
      ),
      HqCard(
        margin: const EdgeInsets.only(bottom: 12),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          CardHeader(lensTitle, sub: '$periodLabel · ${items.length} ${_lens == 'rec' ? (items.length == 1 ? 'payment' : 'payments') : (items.length == 1 ? 'bill' : 'bills')}',
              trailing: HqButton('CSV', icon: 'dl', small: true, onPressed: () => _exportLens(lensTitle, items))),
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: ChipRow([
              for (final (k, l) in const [('rec', 'Received'), ('bil', 'Billed'), ('due', 'Due'), ('over', 'Overdue')])
                HqChip(l, selected: _lens == k, onTap: () => setState(() {
                      _lens = k;
                      _more = false;
                    })),
            ]),
          ),
          if (items.isEmpty)
            const EmptyNote('Nothing here for this period')
          else
            HqList([
              for (final r in shown)
                _lens == 'rec'
                    ? HqRow(
                        title: r.str('academy'),
                        sub: '${fdShort(r['paidOn'])} · ${r.str('mode')}${r.strOrNull('reference') == null ? '' : ' · ${r.str('reference')}'}',
                        wrap: true,
                        trailing: Text(inr(r.number('amount')), style: HqText.row.copyWith(color: Hq.green)),
                        onTap: () => showAccountDrawer(context, r.str('academyId')),
                      )
                    : _billRow(r, balanceOnly: _lens != 'bil'),
            ]),
          if (items.length > 8)
            Padding(padding: const EdgeInsets.only(top: 10), child: Align(alignment: Alignment.centerLeft, child: HqButton(_more ? 'Show fewer' : 'Show all ${items.length}', small: true, onPressed: () => setState(() => _more = !_more)))),
        ]),
      ),
      HqGrid(GridKind.g21, [
        HqCard(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const CardHeader('What is unpaid', sub: 'All open bills by how late they are'),
            for (final a in aging)
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: Column(children: [
                  Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                    Text.rich(TextSpan(children: [TextSpan(text: a.str('label'), style: HqText.body.copyWith(fontSize: 12.5)), TextSpan(text: ' · ${a.integer('count')}', style: HqText.sub)])),
                    Text(inr(a.number('amount')), style: HqText.row),
                  ]),
                  const SizedBox(height: 6),
                  HqBar(a.number('amount') / unpaidMax * 100, tone: Tone.byName(a.str('tone')), height: 7),
                ]),
              ),
          ]),
        ),
        HqCard(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            CardHeader('Most overdue', sub: 'Academies owing the most past the due date', trailing: write && top.isNotEmpty ? HqButton('Remind all', icon: 'send', small: true, onPressed: _remindAll) : null),
            if (top.isEmpty)
              const EmptyNote('Nothing is overdue')
            else
              HqList([
                for (final t in top)
                  HqRow(
                    title: t.str('academy'),
                    sub: '${t.integer('bills')} bill${t.integer('bills') == 1 ? '' : 's'} · ${t.integer('maxLate')} days late',
                    onTap: () => showAccountDrawer(context, t.str('academyId')),
                    trailing: Text(inr(t.number('amount')), style: HqText.row.copyWith(color: Hq.red)),
                  ),
              ]),
          ]),
        ),
      ]),
      HqCard(
        margin: const EdgeInsets.only(bottom: 12),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          CardHeader('How academies paid', sub: periodLabel),
          for (final e in modes.entries)
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: Column(children: [
                Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                  Row(children: [
                    Container(width: 9, height: 9, decoration: BoxDecoration(color: modeColors[e.key] ?? Hq.muted, borderRadius: BorderRadius.circular(3))),
                    const SizedBox(width: 6),
                    Text(e.key, style: HqText.body.copyWith(fontSize: 12.5)),
                  ]),
                  Text.rich(TextSpan(children: [
                    TextSpan(text: inr(e.value as num), style: HqText.row),
                    TextSpan(text: ' ${modeSum == 0 ? 0 : ((e.value as num) / modeSum * 100).round()}%', style: HqText.sub.copyWith(fontWeight: FontWeight.w600)),
                  ])),
                ]),
                const SizedBox(height: 5),
                HqBar(modeSum == 0 ? 0 : (e.value as num) / modeSum * 100, height: 6, tone: Tone.primary),
              ]),
            ),
        ]),
      ),
      HqCard(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const CardHeader('Automatic reminders', sub: 'Sent to the academy owner in their Owleo Nest app'),
          HqList([
            for (final (k, l) in const [('b3', '3 days before the due date'), ('d0', 'On the due date'), ('a3', '3 days after the due date'), ('wk', 'Every week while overdue')])
              HqRow(title: l, wrap: true, trailing: HqSwitch(value: rs.flag(k), onChanged: write ? (v) => _auto(rs, k, v) : null)),
          ]),
          if (recents.isNotEmpty) ...[
            const SizedBox(height: 12),
            Text('Recently sent', style: HqText.sub),
            const SizedBox(height: 6),
            HqList([for (final r in recents) HqRow(title: r.str('academy'), sub: '${ago(r['sentAt'])} · ${r.str('channels')}', titleStyle: HqText.row.copyWith(fontSize: 12.5))]),
          ],
        ]),
      ),
    ]);
  }

  Widget _billRow(Map<String, dynamic> b, {bool balanceOnly = false}) {
    return HqRow(
      title: b.str('academy'),
      sub: '${b.str('number')} · due ${fdShort(b['dueOn'])}${b.str('status') == 'overdue' ? ' · ${b.integer('daysLate')}d late' : ''}',
      wrap: true,
      onTap: () => showAccountDrawer(context, b.str('academyId'), billId: b.str('id')),
      trailing: Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
        Text(inr(balanceOnly ? b.number('balance') : b.number('total')), style: HqText.row),
        const SizedBox(height: 4),
        BillStatusTags(b),
      ]),
    );
  }

  Future<void> _generate() async {
    try {
      final r = await ref.read(dioClientProvider).postMap('/admin/hq/collections/generate');
      refreshCollections(ref);
      if (mounted) showToast(context, r.integer('created') == 0 ? 'Every live academy already has a bill for ${monthLong(r.str('period'))}' : '${r.integer('created')} bills raised for ${monthLong(r.str('period'))}');
    } on ApiException catch (e) {
      if (mounted) showToast(context, e.message);
    }
  }

  Future<void> _remindAll() async {
    final ok = await confirmHq(context,
        title: 'Remind all overdue?',
        body: 'Each academy owner gets their own message in the Owleo Nest app with the bill number, amount and how late it is.',
        confirmLabel: 'Send reminders');
    if (!ok) return;
    try {
      final r = await ref.read(dioClientProvider).postMap('/admin/hq/collections/remind-overdue', body: {'channels': 'In-app'});
      refreshCollections(ref);
      if (mounted) showToast(context, 'Reminded ${r.integer('academies')} academies');
    } on ApiException catch (e) {
      if (mounted) showToast(context, e.message);
    }
  }

  Future<void> _auto(Map<String, dynamic> rs, String k, bool v) async {
    final next = {...rs, k: v};
    try {
      await ref.read(dioClientProvider).putMap('/admin/hq/collections/reminder-settings', body: next);
      ref.invalidate(collectionsOverviewProvider);
      if (mounted) showToast(context, 'Automatic reminder turned ${v ? 'on' : 'off'}');
    } on ApiException catch (e) {
      if (mounted) showToast(context, e.message);
    }
  }

  void _exportLens(String title, List<Map<String, dynamic>> items) {
    final rows = <List<Object?>>[
      if (_lens == 'rec') ['Date', 'Academy', 'Bill', 'Mode', 'Reference', 'Amount'] else ['Bill', 'Academy', 'Month', 'Due', 'Total', 'To pay', 'Status'],
      for (final r in items)
        if (_lens == 'rec')
          [r.str('paidOn'), r.str('academy'), r.str('number'), r.str('mode'), r.str('reference'), r.number('amount')]
        else
          [r.str('number'), r.str('academy'), r.str('period'), r.str('dueOn'), r.number('total'), r.number('balance'), r.str('status')],
    ];
    downloadText('owleo-${title.toLowerCase().replaceAll(' ', '-')}.csv', csvText(rows));
    showToast(context, 'Exported ${items.length} rows');
  }

  // ---------------------------------------------------------------------------- bills

  Widget _bills() {
    final all = ref.watch(billsProvider);
    return asyncBody(all, onRetry: () => ref.invalidate(billsProvider), data: (bills) {
      final months = bills.map((b) => b.str('period')).toSet().toList()..sort((a, b) => b.compareTo(a));
      bool inMonth(Map<String, dynamic> b) => _monthFilter == 'all' || b.str('period') == _monthFilter;
      bool match(Map<String, dynamic> b, String f) => switch (f) {
            'due' => b.str('status') == 'due',
            'overdue' => b.str('status') == 'overdue',
            'part' => b.flag('partPaid'),
            'paid' => b.str('status') == 'paid',
            _ => true,
          };
      final q = _q.toLowerCase();
      final list = bills.where((b) => inMonth(b) && match(b, _billFilter) && (q.isEmpty || '${b.str('academy')}${b.str('number')}'.toLowerCase().contains(q))).toList();
      final unpaid = list.fold<double>(0, (s, b) => s + b.number('balance'));
      return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        HqCard(
          padding: const EdgeInsets.all(12),
          margin: const EdgeInsets.only(bottom: 12),
          child: Row(children: [
            Expanded(child: SearchBox(hint: 'Search academy or bill number', onChanged: (v) => setState(() => _q = v))),
            const SizedBox(width: 8),
            HqButton('CSV', icon: 'dl', small: true, onPressed: () {
              downloadText('owleo-bills.csv', csvText([
                ['Bill', 'Academy', 'Month', 'Issued', 'Due', 'Total', 'Paid', 'To pay', 'Status'],
                for (final b in list) [b.str('number'), b.str('academy'), b.str('period'), b.str('issuedOn'), b.str('dueOn'), b.number('total'), b.number('paid'), b.number('balance'), b.str('status')],
              ]));
              showToast(context, 'Exported ${list.length} bills');
            }),
          ]),
        ),
        Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: ChipRow([
            for (final (k, l) in const [('all', 'All'), ('due', 'Due'), ('overdue', 'Overdue'), ('part', 'Part paid'), ('paid', 'Paid')])
              HqChip(l, selected: _billFilter == k, count: bills.where((b) => inMonth(b) && match(b, k)).length, onTap: () => setState(() => _billFilter = k)),
          ]),
        ),
        Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: ChipRow(scroll: true, [
            HqChip('All months', selected: _monthFilter == 'all', onTap: () => setState(() => _monthFilter = 'all')),
            for (final m in months) HqChip(monthShort(m), selected: _monthFilter == m, onTap: () => setState(() => _monthFilter = m)),
          ]),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(2, 0, 2, 8),
          child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
            Text('${list.length} bills · ${inr(unpaid)} unpaid', style: HqText.muted.copyWith(fontSize: 12)),
            if (_write && list.any((b) => b.str('status') == 'overdue')) HqButton('Remind overdue', icon: 'send', small: true, onPressed: _remindAll),
          ]),
        ),
        if (list.isEmpty) const EmptyNote('No bills match. Bills are raised on the 1st of each month, or use "Raise this month\'s bills" on the Overview.'),
        for (final b in list.take(_more ? 999 : 30))
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: HqCard(
              radius: 16,
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              onTap: () => showAccountDrawer(context, b.str('academyId'), billId: b.str('id')),
              child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                Row(children: [
                  const Avatar('', icon: 'file', tone: Tone.blue),
                  const SizedBox(width: 11),
                  Expanded(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text(b.str('academy'), maxLines: 1, overflow: TextOverflow.ellipsis, style: HqText.row.copyWith(fontSize: 13.5)),
                      Text('${b.str('number')} · ${monthLong(b.str('period'))} · due ${fdShort(b['dueOn'])}', style: HqText.small),
                    ]),
                  ),
                  Text(inr(b.number('total')), style: HqText.row),
                ]),
                const SizedBox(height: 10),
                Row(children: [
                  BillStatusTags(b),
                  const Spacer(),
                  if (b.number('balance') > 0)
                    Text('${inr(b.number('balance'))} to pay${b.str('status') == 'overdue' ? ' · ${b.integer('daysLate')}d late' : ''}', style: HqText.small.copyWith(color: b.str('status') == 'overdue' ? Hq.red : Hq.faint, fontSize: 11.5)),
                ]),
              ]),
            ),
          ),
        if (list.length > 30) HqButton(_more ? 'Show fewer' : 'Show all ${list.length}', small: true, onPressed: () => setState(() => _more = !_more)),
      ]);
    });
  }

  // ---------------------------------------------------------------------------- offers

  Widget _offers() {
    final offers = ref.watch(offersProvider);
    final plans = ref.watch(plansProvider).valueOrNull ?? const <Map<String, dynamic>>[];
    final names = {for (final p in plans) p.str('code'): p.str('name')};
    return asyncBody(offers, onRetry: () => ref.invalidate(offersProvider), data: (list) {
      return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        if (_write)
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: HqButton('New offer', icon: 'plus', kind: BtnKind.primary, expand: true, onPressed: () => _editOffer(null)),
          ),
        if (list.isEmpty) const EmptyNote('No offers yet.'),
        for (final o in list)
          Builder(builder: (_) {
            final (sl, st) = offerStatus(o);
            return HqCard(
              margin: const EdgeInsets.only(bottom: 10),
              radius: 14,
              padding: const EdgeInsets.all(12),
              child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Expanded(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text(o.str('name'), style: HqText.row.copyWith(fontSize: 13.5)),
                      Text('${offerText(o)} · ${offerFor(o, names)}', style: HqText.small),
                    ]),
                  ),
                  Tag(sl, tone: st),
                ]),
                const SizedBox(height: 10),
                Row(children: [
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
                    decoration: BoxDecoration(color: Hq.high, borderRadius: BorderRadius.circular(8)),
                    child: Text(o.str('code'), style: const TextStyle(fontFamily: 'monospace', fontWeight: FontWeight.w800, letterSpacing: 1, fontSize: 12, color: Hq.text)),
                  ),
                  const SizedBox(width: 8),
                  HqButton('Copy', small: true, onPressed: () {
                    Clipboard.setData(ClipboardData(text: o.str('code')));
                    showToast(context, 'Code copied');
                  }),
                ]),
                const SizedBox(height: 10),
                for (final (l, v) in [
                  ('Valid', '${fdShort(o['startsOn'])} to ${fdShort(o['endsOn'])}'),
                  ('Used', '${o.integer('used')}${o.integerOrNull('limit') == null ? '' : ' of ${o.integer('limit')}'}'),
                  ('Discount given', inr(o.number('given'))),
                ])
                  Padding(padding: const EdgeInsets.only(bottom: 4), child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [Text(l, style: HqText.small), Text(v, style: HqText.row.copyWith(fontSize: 12.5))])),
                if (_write)
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Row(children: [
                      HqButton('Edit', small: true, onPressed: () => _editOffer(o)),
                      const SizedBox(width: 8),
                      HqButton(o.flag('active') ? 'Pause' : 'Resume', small: true, onPressed: () async {
                        try {
                          await ref.read(dioClientProvider).putMap('/admin/hq/collections/offers/${o.str('id')}/active', body: {'active': !o.flag('active')});
                          ref.invalidate(offersProvider);
                        } on ApiException catch (e) {
                          if (mounted) showToast(context, e.message);
                        }
                      }),
                    ]),
                  ),
              ]),
            );
          }),
        const PageNote('An offer is applied to one bill at a time, from the bill itself. It never changes a bill that is already paid.'),
      ]);
    });
  }

  Future<void> _editOffer(Map<String, dynamic>? o) async {
    final done = await showHqModal<bool>(context, builder: (_) => OfferModal(offer: o));
    if (done == true) {
      ref.invalidate(offersProvider);
      if (mounted) showToast(context, 'Offer saved');
    }
  }

  // ---------------------------------------------------------------------------- add-ons

  Widget _addons() {
    final addons = ref.watch(addonsProvider);
    return asyncBody(addons, onRetry: () => ref.invalidate(addonsProvider), data: (list) {
      return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        if (_write)
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: HqButton('New add-on', icon: 'plus', kind: BtnKind.primary, expand: true, onPressed: () => _editAddon(null)),
          ),
        if (list.isEmpty) const EmptyNote('No add-ons yet.'),
        for (final d in list)
          HqCard(
            margin: const EdgeInsets.only(bottom: 10),
            radius: 14,
            padding: const EdgeInsets.all(12),
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(d.str('name'), style: HqText.row.copyWith(fontSize: 13.5)),
                    Text(d.str('description'), style: HqText.small),
                  ]),
                ),
                Tag(d.flag('onSale') ? 'On sale' : 'Off sale', tone: d.flag('onSale') ? Tone.green : Tone.mute),
              ]),
              const SizedBox(height: 10),
              for (final (l, v) in [
                ('Price', '${inr(d.number('price'))} ${d.str('billing') == 'month' ? '/ month' : 'one time'}'),
                ('Academies using it', '${d.integer('academies')}'),
                if (d.str('billing') == 'month') ('Monthly income', inr(d.integer('academies') * d.number('price'))),
              ])
                Padding(padding: const EdgeInsets.only(bottom: 4), child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [Text(l, style: HqText.small), Text(v, style: HqText.row.copyWith(fontSize: 12.5))])),
              if (_write)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Row(children: [
                    HqButton('Edit', small: true, onPressed: () => _editAddon(d)),
                    const SizedBox(width: 8),
                    HqButton(d.flag('onSale') ? 'Take off sale' : 'Put on sale', small: true, onPressed: () async {
                      try {
                        await ref.read(dioClientProvider).putMap('/admin/hq/collections/addons/${d.str('id')}/sale', body: {'onSale': !d.flag('onSale')});
                        ref.invalidate(addonsProvider);
                      } on ApiException catch (e) {
                        if (mounted) showToast(context, e.message);
                      }
                    }),
                  ]),
                ),
            ]),
          ),
        const PageNote('A new price applies from the next bill. Bills already sent stay as they are. To add one to an academy, open the academy from Overview or Bills.'),
      ]);
    });
  }

  Future<void> _editAddon(Map<String, dynamic>? d) async {
    final done = await showHqModal<bool>(context, builder: (_) => AddonModal(addon: d));
    if (done == true) {
      ref.invalidate(addonsProvider);
      if (mounted) showToast(context, 'Add-on saved');
    }
  }
}

