import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/theme.dart';
import '../../core/api/api_exception.dart';
import '../../core/auth/session.dart';
import '../../core/format.dart';
import '../../core/json.dart';
import '../../core/ui/async.dart';
import '../../core/ui/charts.dart';
import '../../core/ui/controls.dart';
import '../../core/ui/icons.dart';
import '../../core/ui/layout.dart';
import '../../core/ui/overlays.dart';
import '../../core/ui/primitives.dart';
import '../shell/shell_data.dart';

final financeProvider = FutureProvider.autoDispose<Map<String, dynamic>>(
  (ref) => ref.watch(dioClientProvider).getMap('/admin/hq/finance'),
);

const _revenueLines = [
  ('Subscriptions', 'plan', Tone.primary),
  ('Setup and onboarding', 'setup', Tone.gold),
  ('Add-ons', 'addon', Tone.violet),
  ('Event commission', 'commission', Tone.blue),
  ('Other charges and credits', 'adjustment', Tone.mute),
];

const _expenseLines = [
  ('Team salaries', 'salary', Tone.violet),
  ('Cloud and infrastructure', 'cloud', Tone.blue),
  ('Marketing and sales', 'marketing', Tone.gold),
  ('Support and success', 'support', Tone.primary),
  ('WhatsApp, SMS and gateway', 'messaging', Tone.coral),
  ('Office, tools and misc', 'misc', Tone.mute),
];

/// Finance: revenue (billed), expenses (entered here) and profit, month by month.
class FinanceScreen extends ConsumerStatefulWidget {
  const FinanceScreen({super.key});

  @override
  ConsumerState<FinanceScreen> createState() => _FinanceScreenState();
}

class _FinanceScreenState extends ConsumerState<FinanceScreen> {
  int? _m;

  @override
  Widget build(BuildContext context) {
    final fin = ref.watch(financeProvider);
    return asyncBody(fin, onRetry: () => ref.invalidate(financeProvider), data: _content);
  }

  Widget _content(Map<String, dynamic> d) {
    final months = d.strings('months');
    final n = months.length;
    final m = (_m ?? n - 1).clamp(0, n - 1);
    final labels = months.map(monthShort).toList(), tips = months.map(monthLong).toList();
    final revenue = d.doubles('revenue'), expenses = d.doubles('expenses'), profit = d.doubles('profit');
    final streams = d.obj('streams'), exp = d.obj('expenseLines');
    final academies = d.doubles('academies'), paying = d.doubles('paying');
    final rev = revenue[m], ex = expenses[m], pr = profit[m];
    final prev = m == 0 ? 0 : m - 1;
    final ytd = profit.fold<double>(0, (a, b) => a + b);
    final subs = streams.doubles('plan')[m];
    final cost2serve = exp.doubles('cloud')[m] + exp.doubles('support')[m] + exp.doubles('messaging')[m];
    final overdue = d.maps('overdue');
    final canEdit = d.flag('canEdit');
    final wide = MediaQuery.sizeOf(context).width >= 760;
    double dlt(List<double> a, int i) => i == 0 || a[i - 1] == 0 ? 0 : (a[i] - a[i - 1]) / a[i - 1].abs() * 100;

    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: Row(children: [
          HqIconButton('left', onTap: m == 0 ? null : () => setState(() => _m = m - 1)),
          SizedBox(width: 120, child: Center(child: Text(monthLong(months[m]), style: HqText.h3.copyWith(fontSize: 15)))),
          HqIconButton('chev', onTap: m == n - 1 ? null : () => setState(() => _m = m + 1)),
          const Spacer(),
          if (canEdit)
            HqButton('Edit expenses', icon: 'edit', small: true, onPressed: () async {
              final done = await showHqModal<bool>(context, builder: (_) => _ExpensesModal(month: months[m], current: {for (final l in _expenseLines) l.$2: exp.doubles(l.$2)[m]}));
              if (done == true) {
                ref.invalidate(financeProvider);
                ref.invalidate(alertsProvider);
                if (mounted) showToast(context, 'Expenses saved for ${monthLong(months[m])}');
              }
            }),
        ]),
      ),
      HqGrid(GridKind.g4, [
        Kpi(
          tone: Tone.primary, icon: 'trend', label: 'Revenue', value: short(rev), foot: '${short(subs)} from subscriptions',
          delta: m > 0 ? Delta(dlt(revenue, m)) : null, spark: m > 0 ? Spark(revenue.sublist(0, m + 1), Hq.primary) : null,
        ),
        Kpi(
          tone: Tone.coral, icon: 'wallet', label: 'Expenses', value: short(ex),
          foot: ex == 0 ? 'No expenses entered' : '${pct(exp.doubles('salary')[m] / ex * 100)} is team salaries',
          delta: m > 0 && expenses[prev] > 0 ? Delta(dlt(expenses, m), good: false) : null,
          spark: m > 0 ? Spark(expenses.sublist(0, m + 1), Hq.coral) : null,
        ),
        Kpi(
          tone: pr >= 0 ? Tone.green : Tone.red, icon: 'rupee', label: 'Net profit', value: short(pr),
          valueColor: pr >= 0 ? Hq.green : Hq.red, foot: rev > 0 ? '${pct(pr / rev * 100)} margin' : 'No revenue billed',
          delta: m > 0
              ? Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                  decoration: BoxDecoration(color: (pr >= profit[prev] ? Tone.green : Tone.red).soft, borderRadius: BorderRadius.circular(9)),
                  child: Row(mainAxisSize: MainAxisSize.min, children: [
                    ic(pr >= profit[prev] ? 'up' : 'down', 12, pr >= profit[prev] ? Hq.green : Hq.red),
                    const SizedBox(width: 3),
                    Text(short((pr - profit[prev]).abs()), style: HqText.tag(pr >= profit[prev] ? Hq.green : Hq.red).copyWith(fontSize: 11.5, letterSpacing: 0)),
                  ]),
                )
              : null,
        ),
        Kpi(
          tone: ytd >= 0 ? Tone.green : Tone.gold, icon: 'layers', label: '12-month net', value: short(ytd), valueColor: ytd >= 0 ? Hq.green : Hq.gold,
          foot: ytd < 0 ? 'still recovering early losses' : 'cumulative profit',
        ),
      ]),
      HqGrid(GridKind.g21, [
        HqCard(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const CardHeader('Revenue vs expenses', sub: 'Profit line crosses zero when revenue beats expenses'),
            HqChart(
              labels: labels, tipLabels: tips, height: 270, axisFmt: short, tipFmt: inr,
              series: [
                ChartSeries('Revenue', Hq.primary, SeriesType.bar, revenue),
                ChartSeries('Expenses', Hq.coral, SeriesType.bar, expenses),
                ChartSeries('Profit', Hq.gold, SeriesType.line, profit),
              ],
            ),
          ]),
        ),
        HqCard(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            CardHeader('Where the money went', sub: '${monthLong(months[m])} expenses'),
            if (ex == 0)
              const EmptyNote('No expenses entered for this month.')
            else
              Wrap(spacing: 16, runSpacing: 12, crossAxisAlignment: WrapCrossAlignment.center, children: [
                Donut(
                  [for (final l in _expenseLines) DonutSegment(exp.doubles(l.$2)[m], l.$3.color)],
                  size: 118, stroke: 15,
                  center: Column(mainAxisSize: MainAxisSize.min, children: [
                    Text(short(ex), style: HqText.h2.copyWith(fontSize: 16)),
                    Text('total', style: HqText.small.copyWith(fontSize: 10, fontWeight: FontWeight.w600)),
                  ]),
                ),
                ConstrainedBox(
                  constraints: const BoxConstraints(minWidth: 190, maxWidth: 300),
                  child: Column(children: [
                    for (final l in _expenseLines)
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 4),
                        child: Row(children: [
                          Container(width: 9, height: 9, decoration: BoxDecoration(color: l.$3.color, borderRadius: BorderRadius.circular(3))),
                          const SizedBox(width: 8),
                          Expanded(child: Text(l.$1, style: HqText.small.copyWith(color: Hq.text))),
                          Text(short(exp.doubles(l.$2)[m]), style: HqText.row),
                        ]),
                      ),
                  ]),
                ),
              ]),
          ]),
        ),
      ]),
      HqGrid(GridKind.g21, [
        HqCard(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const CardHeader('Revenue streams', sub: 'Stacked by source'),
            HqChart(
              labels: labels, tipLabels: tips, height: 220, stack: true, axisFmt: short, tipFmt: inr,
              series: [for (final l in _revenueLines) ChartSeries(l.$1, l.$3.color, SeriesType.bar, streams.doubles(l.$2))],
            ),
          ]),
        ),
        HqCard(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            CardHeader('Unit economics', sub: monthLong(months[m])),
            HqList([
              HqRow(title: 'Revenue per paying academy', trailing: Text(paying[m] == 0 ? '–' : inr(subs / paying[m]), style: HqText.row)),
              HqRow(title: 'Cost to serve per academy', sub: 'Cloud, support, messaging', trailing: Text(academies[m] == 0 ? '–' : inr(cost2serve / academies[m]), style: HqText.row)),
              HqRow(title: 'Gross margin', trailing: Text(rev <= 0 ? '–' : pct((rev - cost2serve) / rev * 100), style: HqText.row.copyWith(color: Hq.green))),
              HqRow(title: 'Break-even revenue', sub: 'Expenses this month', trailing: Text(short(ex), style: HqText.row)),
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
      ]),
      if (!wide)
        HqCard(
          margin: const EdgeInsets.only(bottom: 14),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            CardHeader('Profit and loss', sub: monthLong(months[m])),
            const SectionLabel('Revenue'),
            HqList([for (final l in _revenueLines) HqRow(title: l.$1, trailing: Text(inr(streams.doubles(l.$2)[m]), style: HqText.row))]),
            HqRow(title: 'Total revenue', trailing: Text(inr(rev), style: HqText.row)),
            const SectionLabel('Expenses', top: 12),
            HqList([for (final l in _expenseLines) HqRow(title: l.$1, trailing: Text(inr(exp.doubles(l.$2)[m]), style: HqText.row))]),
            HqRow(title: 'Total expenses', trailing: Text(inr(ex), style: HqText.row)),
            const SizedBox(height: 10),
            HqRow(title: 'Net profit', trailing: Text(inr(pr), style: HqText.row.copyWith(color: pr >= 0 ? Hq.green : Hq.red))),
          ]),
        )
      else
        HqCard(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const CardHeader('Profit and loss', sub: 'Month by month. Selected month is highlighted.'),
            _PlTable(months: months, selected: m, revenue: revenue, expenses: expenses, profit: profit, streams: streams, exp: exp),
          ]),
        ),
      const PageNote('Revenue is what has been billed, before GST. Expenses are entered by Finance for each month.'),
    ]);
  }
}

class _PlTable extends StatelessWidget {
  const _PlTable({required this.months, required this.selected, required this.revenue, required this.expenses, required this.profit, required this.streams, required this.exp});

  final List<String> months;
  final int selected;
  final List<double> revenue, expenses, profit;
  final Map<String, dynamic> streams, exp;

  static const _first = 190.0, _col = 84.0;

  @override
  Widget build(BuildContext context) {
    Widget cells(String label, List<double> v, {bool total = false, bool colored = false}) {
      return Container(
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
              child: Text(inr(v[i]), maxLines: 1, style: HqText.row.copyWith(fontSize: 12.5, fontWeight: total ? FontWeight.w800 : FontWeight.w500, color: colored ? (v[i] >= 0 ? Hq.green : Hq.red) : Hq.text)),
            ),
        ]),
      );
    }

    Widget section(String t) => Padding(padding: const EdgeInsets.fromLTRB(12, 16, 0, 6), child: Text(t.toUpperCase(), style: HqText.section));

    return SingleChildScrollView(
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
          section('Revenue'),
          for (final l in _revenueLines) cells(l.$1, streams.doubles(l.$2)),
          cells('Total revenue', revenue, total: true),
          section('Expenses'),
          for (final l in _expenseLines) cells(l.$1, exp.doubles(l.$2)),
          cells('Total expenses', expenses, total: true),
          section('Result'),
          cells('Net profit', profit, total: true, colored: true),
        ]),
      ),
    );
  }
}

class _ExpensesModal extends ConsumerStatefulWidget {
  const _ExpensesModal({required this.month, required this.current});
  final String month;
  final Map<String, double> current;

  @override
  ConsumerState<_ExpensesModal> createState() => _ExpensesModalState();
}

class _ExpensesModalState extends ConsumerState<_ExpensesModal> {
  late final Map<String, TextEditingController> _c = {
    for (final l in _expenseLines) l.$2: TextEditingController(text: (widget.current[l.$2] ?? 0) == 0 ? '' : widget.current[l.$2]!.round().toString()),
  };
  String? _error;
  bool _busy = false;

  @override
  void dispose() {
    for (final c in _c.values) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _save() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await ref.read(dioClientProvider).putMap('/admin/hq/finance/expenses', body: {'month': widget.month, for (final e in _c.entries) e.key: e.value.text.trim()});
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
      title: 'Expenses for ${monthLong(widget.month)}',
      sub: 'What it cost to run Owleo this month, in ₹',
      error: _error,
      actions: [
        HqButton('Cancel', onPressed: () => Navigator.of(context).pop()),
        HqButton('Save expenses', kind: BtnKind.primary, busy: _busy, onPressed: _save),
      ],
      children: [
        for (final l in _expenseLines)
          HqField(
            label: l.$1,
            controller: _c[l.$2],
            hint: '0',
            keyboard: TextInputType.number,
            formatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9,.]'))],
          ),
      ],
    );
  }
}
