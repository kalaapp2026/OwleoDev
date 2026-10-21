import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/theme.dart';
import '../../core/auth/session.dart';
import '../../core/format.dart';
import '../../core/json.dart';
import '../../core/ui/async.dart';
import '../../core/ui/charts.dart';
import '../../core/ui/controls.dart';
import '../../core/ui/layout.dart';
import '../../core/ui/primitives.dart';

final financeProvider = FutureProvider.autoDispose<Map<String, dynamic>>(
  (ref) => ref.watch(dioClientProvider).getMap('/admin/hq/finance'),
);

/// One revenue group: a name, what it covers, a colour, and the stream keys it adds up.
class _Group {
  const _Group(this.title, this.sub, this.tone, this.lines);
  final String title, sub;
  final Tone tone;
  final List<(String, String)> lines;
}

const _groups = [
  _Group('Platform fees', 'Plan subscriptions and one-time setup', Tone.primary, [('Plan subscriptions', 'plan'), ('Setup and onboarding', 'setup'), ('Credits and other charges', 'adjustment')]),
  _Group('Marketing fees', 'What academies pay for promotion', Tone.gold, [('Campaigns and promotion', 'marketing')]),
  _Group('Other service fees', 'Add-ons and event commission', Tone.violet, [('Add-ons (WhatsApp credits, storage)', 'addon'), ('Event commission', 'commission')]),
];

/// Finance: where Owleo's revenue comes from, month by month. Revenue only: costs and profit are not tracked here.
class FinanceScreen extends ConsumerStatefulWidget {
  const FinanceScreen({super.key});

  @override
  ConsumerState<FinanceScreen> createState() => _FinanceScreenState();
}

class _FinanceScreenState extends ConsumerState<FinanceScreen> {
  int? _m;

  @override
  Widget build(BuildContext context) => asyncBody(ref.watch(financeProvider), onRetry: () => ref.invalidate(financeProvider), data: _content);

  Widget _content(Map<String, dynamic> d) {
    final months = d.strings('months');
    final n = months.length;
    final m = (_m ?? n - 1).clamp(0, n - 1);
    final labels = months.map(monthShort).toList(), tips = months.map(monthLong).toList();
    final revenue = d.doubles('revenue');
    final streams = d.obj('streams');
    final paying = d.doubles('paying');
    final rev = revenue[m];
    final overdue = d.maps('overdue');
    final wide = MediaQuery.sizeOf(context).width >= 760;

    double line(String k, int i) => streams.doubles(k)[i];
    double groupAt(_Group g, int i) => g.lines.fold<double>(0, (s, l) => s + line(l.$2, i));
    List<double> groupSeries(_Group g) => [for (var i = 0; i < n; i++) groupAt(g, i)];
    double dlt(List<double> a, int i) => i == 0 || a[i - 1] == 0 ? 0 : (a[i] - a[i - 1]) / a[i - 1].abs() * 100;
    Widget? spark(List<double> a, Color c) => m > 0 ? Spark(a.sublist(0, m + 1), c) : null;
    final pay = paying[m] < 1 ? 1.0 : paying[m];
    final subs = line('plan', m), repeats = rev <= 0 ? 0.0 : (subs + line('addon', m)) / rev * 100;

    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: Row(children: [
          HqIconButton('left', onTap: m == 0 ? null : () => setState(() => _m = m - 1)),
          SizedBox(width: 120, child: Center(child: Text(monthLong(months[m]), style: HqText.h3.copyWith(fontSize: 15)))),
          HqIconButton('chev', onTap: m == n - 1 ? null : () => setState(() => _m = m + 1)),
        ]),
      ),
      HqGrid(GridKind.g4, [
        Kpi(tone: Tone.primary, icon: 'trend', label: 'Total revenue', value: short(rev), foot: 'all sources', delta: m > 0 ? Delta(dlt(revenue, m)) : null, spark: spark(revenue, Hq.primary)),
        for (final g in _groups)
          Kpi(
            tone: g.tone,
            icon: 'rupee',
            label: g.title,
            value: short(groupAt(g, m)),
            foot: '${rev <= 0 ? '0%' : pct(groupAt(g, m) / rev * 100)} of revenue',
            delta: m > 0 ? Delta(dlt(groupSeries(g), m)) : null,
            spark: spark(groupSeries(g), g.tone.color),
          ),
      ]),
      HqGrid(GridKind.g21, [
        HqCard(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const CardHeader('Revenue by source', sub: 'Monthly, in ₹'),
            HqChart(
              labels: labels, tipLabels: tips, height: 270, stack: true, axisFmt: short, tipFmt: inr,
              series: [for (final g in _groups) ChartSeries(g.title, g.tone.color, SeriesType.bar, groupSeries(g))],
            ),
          ]),
        ),
        HqCard(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            CardHeader('Where revenue came from', sub: monthLong(months[m])),
            if (rev <= 0)
              const EmptyNote('Nothing billed for this month.')
            else
              Wrap(spacing: 16, runSpacing: 12, crossAxisAlignment: WrapCrossAlignment.center, children: [
                Donut(
                  [for (final g in _groups) DonutSegment(groupAt(g, m), g.tone.color)],
                  size: 118, stroke: 15,
                  center: Column(mainAxisSize: MainAxisSize.min, children: [
                    Text(short(rev), style: HqText.h2.copyWith(fontSize: 16)),
                    Text('revenue', style: HqText.small.copyWith(fontSize: 10, fontWeight: FontWeight.w600)),
                  ]),
                ),
                ConstrainedBox(
                  constraints: const BoxConstraints(minWidth: 190, maxWidth: 300),
                  child: Column(children: [
                    for (final g in _groups)
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 4),
                        child: Row(children: [
                          Container(width: 9, height: 9, decoration: BoxDecoration(color: g.tone.color, borderRadius: BorderRadius.circular(3))),
                          const SizedBox(width: 8),
                          Expanded(child: Text(g.title, style: HqText.small.copyWith(color: Hq.text))),
                          Text(short(groupAt(g, m)), style: HqText.row),
                        ]),
                      ),
                  ]),
                ),
              ]),
          ]),
        ),
      ]),
      HqCard(
        margin: const EdgeInsets.only(bottom: 14),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          CardHeader('Per academy', sub: monthLong(months[m])),
          HqList([
            HqRow(title: 'Revenue per paying academy', sub: 'All sources', trailing: Text(paying[m] < 1 ? '–' : inr(rev / pay), style: HqText.row)),
            HqRow(title: 'Platform fee per paying academy', sub: 'Subscriptions only', trailing: Text(paying[m] < 1 ? '–' : inr(subs / pay), style: HqText.row)),
            HqRow(title: 'Repeats every month', sub: 'Subscriptions and add-ons', trailing: Text(pct(repeats), style: HqText.row)),
          ]),
          if (m == n - 1 && overdue.isNotEmpty)
            Container(
              margin: const EdgeInsets.only(top: 12),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(color: Hq.tint(Hq.red), borderRadius: BorderRadius.circular(14), border: Border.all(color: Hq.red.withValues(alpha: .3))),
              child: Text.rich(TextSpan(style: HqText.body.copyWith(fontSize: 12.5), children: [
                TextSpan(text: '${inr(overdue.fold<double>(0, (s, o) => s + o.number('amount')))} overdue', style: const TextStyle(color: Hq.red, fontWeight: FontWeight.w800)),
                TextSpan(text: ' from ${overdue.length} ${overdue.length == 1 ? 'academy' : 'academies'}: ${overdue.take(4).map((o) => o.str('name')).join(', ')}${overdue.length > 4 ? ' and ${overdue.length - 4} more' : ''}.'),
              ])),
            ),
        ]),
      ),
      if (!wide)
        HqCard(
          margin: const EdgeInsets.only(bottom: 14),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            CardHeader('Revenue statement', sub: monthLong(months[m])),
            for (final (i, g) in _groups.indexed) ...[
              SectionLabel(g.title, top: i == 0 ? 0 : 12),
              HqList([for (final l in g.lines) HqRow(title: l.$1, trailing: Text(inr(line(l.$2, m)), style: HqText.row))]),
              HqRow(title: 'Total ${g.title.toLowerCase()}', trailing: Text(inr(groupAt(g, m)), style: HqText.row)),
            ],
            const SizedBox(height: 10),
            HqRow(title: 'Total revenue', trailing: Text(inr(rev), style: HqText.row.copyWith(fontWeight: FontWeight.w800))),
          ]),
        )
      else
        HqCard(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const CardHeader('Revenue by month', sub: 'Selected month is highlighted.'),
            _RevenueTable(months: months, selected: m, revenue: revenue, line: (k) => streams.doubles(k), groups: _groups),
          ]),
        ),
      const PageNote('Revenue is what has been billed, before GST. This page shows revenue only: costs and profit are not tracked in this console. Marketing fees and event commission appear once they are billed on an academy\'s bill.'),
    ]);
  }
}

class _RevenueTable extends StatefulWidget {
  const _RevenueTable({required this.months, required this.selected, required this.revenue, required this.line, required this.groups});

  final List<String> months;
  final int selected;
  final List<double> revenue;
  final List<double> Function(String key) line;
  final List<_Group> groups;

  @override
  State<_RevenueTable> createState() => _RevenueTableState();
}

class _RevenueTableState extends State<_RevenueTable> {
  static const _first = 220.0, _col = 100.0;
  final _scroll = ScrollController();

  @override
  void initState() {
    super.initState();
    // The newest months are the ones that matter: open scrolled to the right.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scroll.hasClients) _scroll.jumpTo(_scroll.position.maxScrollExtent);
    });
  }

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  List<String> get months => widget.months;
  int get selected => widget.selected;
  List<double> get revenue => widget.revenue;
  List<double> Function(String key) get line => widget.line;
  List<_Group> get groups => widget.groups;

  @override
  Widget build(BuildContext context) {
    Widget cells(String label, List<double> v, {bool total = false}) => Container(
          padding: const EdgeInsets.symmetric(vertical: 9),
          decoration: BoxDecoration(color: total ? const Color(0x731C2740) : null, border: const Border(top: BorderSide(color: Hq.soft))),
          child: Row(children: [
            SizedBox(width: _first, child: Padding(padding: const EdgeInsets.symmetric(horizontal: 12), child: Text(label, style: HqText.row.copyWith(fontSize: 12.5, fontWeight: total ? FontWeight.w800 : FontWeight.w500)))),
            for (var i = 0; i < v.length; i++)
              Container(
                width: _col,
                color: i == selected ? const Color(0x122FE0C6) : null,
                padding: const EdgeInsets.symmetric(horizontal: 12),
                alignment: Alignment.centerRight,
                child: Text(inr(v[i]), maxLines: 1, style: HqText.row.copyWith(fontSize: 12.5, fontWeight: total ? FontWeight.w800 : FontWeight.w500)),
              ),
          ]),
        );

    Widget section(String t) => Padding(padding: const EdgeInsets.fromLTRB(12, 16, 0, 6), child: Text(t.toUpperCase(), style: HqText.section));
    List<double> sum(_Group g) => [for (var i = 0; i < months.length; i++) g.lines.fold<double>(0, (s, l) => s + line(l.$2)[i])];

    return SingleChildScrollView(
      controller: _scroll,
      scrollDirection: Axis.horizontal,
      child: SizedBox(
        width: _first + _col * months.length,
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Row(children: [
            const SizedBox(width: _first, child: Padding(padding: EdgeInsets.symmetric(horizontal: 12), child: Text('₹', style: TextStyle(color: Hq.faint, fontWeight: FontWeight.w800)))),
            for (var i = 0; i < months.length; i++)
              Container(
                width: _col,
                color: i == selected ? const Color(0x122FE0C6) : null,
                padding: const EdgeInsets.fromLTRB(12, 0, 12, 10),
                alignment: Alignment.centerRight,
                child: Text(monthShort(months[i]).toUpperCase(), style: HqText.th),
              ),
          ]),
          for (final g in groups) ...[
            section(g.title),
            for (final l in g.lines) cells(l.$1, line(l.$2)),
            cells('Total ${g.title.toLowerCase()}', sum(g), total: true),
          ],
          section('All sources'),
          cells('Total revenue', revenue, total: true),
        ]),
      ),
    );
  }
}
