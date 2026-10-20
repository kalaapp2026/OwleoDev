import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/theme.dart';
import '../../core/auth/session.dart';
import '../../core/format.dart';
import '../../core/json.dart';
import '../../core/ui/async.dart';
import '../../core/ui/charts.dart';
import '../../core/ui/controls.dart';
import '../../core/ui/icons.dart';
import '../../core/ui/layout.dart';
import '../../core/ui/primitives.dart';
import '../academies/academy_meta.dart';
import '../shell/nav.dart';
import '../shell/shell_data.dart';
import 'platform_status.dart';

final dashboardProvider = FutureProvider.autoDispose<Map<String, dynamic>>(
  (ref) => ref.watch(dioClientProvider).getMap('/admin/hq/dashboard'),
);

/// Dashboard > Business: the owner's morning view of the whole platform.
class DashboardScreen extends ConsumerStatefulWidget {
  const DashboardScreen({super.key});

  @override
  ConsumerState<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends ConsumerState<DashboardScreen> {
  String _metric = 'users';
  String _tab = 'biz';

  @override
  Widget build(BuildContext context) {
    final dash = ref.watch(dashboardProvider);
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: SegControl<String>(expand: true, items: const [('biz', 'Business'), ('ops', 'Platform status')], value: _tab, onChanged: (v) => setState(() => _tab = v)),
      ),
      if (_tab == 'ops') const PlatformStatus() else asyncBody(dash, onRetry: () => ref.invalidate(dashboardProvider), data: _content),
    ]);
  }

  double _delta(List<double> a) {
    if (a.length < 2 || a[a.length - 2] == 0) return 0;
    return (a.last - a[a.length - 2]) / a[a.length - 2].abs() * 100;
  }

  Widget _content(Map<String, dynamic> d) {
    final months = d.strings('months');
    final labels = months.map(monthShort).toList();
    final tips = months.map(monthLong).toList();
    final users = d.doubles('users'), academies = d.doubles('academies'), mrr = d.doubles('mrr');
    final revenue = d.doubles('revenue'), expenses = d.doubles('expenses'), profit = d.doubles('profit');
    final now = d.obj('now');
    final alerts = ref.watch(alertsProvider).valueOrNull ?? const <HqAlert>[];
    final cur = months.length - 1;
    final p = cur >= 0 && profit.isNotEmpty ? profit[cur] : 0.0;
    final rev = cur >= 0 && revenue.isNotEmpty ? revenue[cur] : 0.0;
    final inProfit = profit.length >= 6 ? profit.sublist(profit.length - 6).where((x) => x > 0).length : 0;

    final metric = switch (_metric) {
      'academies' => (name: 'Academies', values: academies, color: Hq.primary, axis: (double v) => num0(v), tip: (double v) => num0(v)),
      'mrr' => (name: 'MRR', values: mrr, color: Hq.gold, axis: (double v) => short(v), tip: (double v) => inr(v)),
      _ => (name: 'Owleo users', values: users, color: Hq.blue, axis: (double v) => num0(v), tip: (double v) => num0(v)),
    };

    final mix = d.maps('planMix');
    final payingTotal = mix.fold<int>(0, (s, m) => s + m.integer('count'));
    final top = d.maps('top');
    final activity = d.maps('activity');

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _Cover(alertCount: alerts.length),
        const SizedBox(height: 14),
        HqGrid(GridKind.g4, [
          Kpi(
            tone: Tone.blue,
            icon: 'users',
            label: 'Owleo users',
            value: num0(users.isEmpty ? 0 : users.last),
            foot: '${num0(now.integer('students'))} students · ${num0(now.integer('trainers'))} trainers',
            delta: Delta(_delta(users)),
            spark: Spark(users, Hq.blue),
          ),
          Kpi(
            tone: Tone.primary,
            icon: 'bld',
            label: 'Active academies',
            value: '${now.integer('activeAcademies')}',
            foot: '+${now.integer('newThisMonth')} this month · ${now.integer('churned12')} churned',
            delta: Delta(_delta(academies)),
            spark: Spark(academies, Hq.primary),
          ),
          Kpi(
            tone: Tone.gold,
            icon: 'rupee',
            label: 'Monthly recurring revenue',
            value: short(mrr.isEmpty ? 0 : mrr.last),
            foot: 'ARR ${short((mrr.isEmpty ? 0 : mrr.last) * 12)}',
            delta: Delta(_delta(mrr)),
            spark: Spark(mrr, Hq.gold),
          ),
          Kpi(
            tone: p >= 0 ? Tone.green : Tone.red,
            icon: 'wallet',
            label: 'Net profit · ${months.isEmpty ? '' : monthShort(months.last)}',
            value: short(p),
            valueColor: p >= 0 ? Hq.green : Hq.red,
            foot: rev > 0 ? '${pct(p / rev * 100)} margin · $inProfit of last 6 months in profit' : 'Add expenses in Finance to see profit',
            spark: Spark(profit, p >= 0 ? Hq.green : Hq.red),
          ),
        ]),
        HqGrid(GridKind.g21, [
          HqCard(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              CardHeader(
                'Growth',
                sub: 'Last 12 months',
                trailing: SegControl<String>(
                  items: const [('users', 'Users'), ('academies', 'Academies'), ('mrr', 'MRR')],
                  value: _metric,
                  onChanged: (v) => setState(() => _metric = v),
                ),
              ),
              HqChart(
                key: ValueKey(_metric),
                labels: labels,
                tipLabels: tips,
                height: 250,
                showLegend: false,
                axisFmt: metric.axis,
                tipFmt: metric.tip,
                series: [ChartSeries(metric.name, metric.color, SeriesType.area, metric.values)],
              ),
            ]),
          ),
          HqCard(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              CardHeader('Needs attention', sub: '${alerts.length} open'),
              if (alerts.isEmpty)
                const EmptyNote('Nothing needs a look right now.')
              else
                HqList([
                  for (final a in alerts.take(5))
                    HqRow(
                      leading: IconTile(a.icon, tone: Tone.byName(a.tone), size: 32),
                      title: a.title,
                      sub: a.text,
                      wrap: true,
                      onTap: () => hqGo(context, a.academyId != null ? '/academies?open=${a.academyId}' : '/alerts'),
                    ),
                ]),
            ]),
          ),
        ]),
        HqGrid(GridKind.g21, [
          HqCard(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const CardHeader('Revenue, expenses and profit', sub: 'Monthly, in ₹'),
              HqChart(
                labels: labels,
                tipLabels: tips,
                height: 250,
                axisFmt: short,
                tipFmt: inr,
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
              CardHeader('Plan mix', sub: '$payingTotal paying academies'),
              if (mix.isEmpty)
                const EmptyNote('No paying academies yet.')
              else
                Wrap(
                  spacing: 18,
                  runSpacing: 14,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    Donut(
                      [for (final m in mix) DonutSegment(m.integer('count').toDouble(), Tone.byName(m.strOrNull('tone')).color)],
                      size: 128,
                      stroke: 16,
                      center: Column(mainAxisSize: MainAxisSize.min, children: [
                        Text('$payingTotal', style: HqText.h2),
                        Text('paying', style: HqText.small.copyWith(fontSize: 10, fontWeight: FontWeight.w600)),
                      ]),
                    ),
                    ConstrainedBox(
                      constraints: const BoxConstraints(minWidth: 160, maxWidth: 300),
                      child: HqList([
                        for (final m in mix)
                          HqRow(
                            leading: Container(width: 10, height: 10, decoration: BoxDecoration(color: Tone.byName(m.strOrNull('tone')).color, borderRadius: BorderRadius.circular(3))),
                            title: m.str('name'),
                            sub: '${inr(m.number('price'))} / month',
                            trailing: Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
                              Text('${m.integer('count')}', style: HqText.row),
                              Text(short(m.integer('count') * m.number('price')), style: HqText.small),
                            ]),
                          ),
                      ]),
                    ),
                  ],
                ),
            ]),
          ),
        ]),
        HqGrid(GridKind.g2, [
          HqCard(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              CardHeader('Top performing academies',
                  sub: 'Health = attendance, fee collection and weekly activity',
                  trailing: HqButton('View all', small: true, onPressed: () => hqGo(context, '/academies'))),
              if (top.isEmpty)
                const EmptyNote('No live academies yet.')
              else
                HqList([
                  for (final a in top)
                    HqRow(
                      leading: Avatar(initials(a.str('name')), tone: AcademyMeta.typeTone(a.str('type'))),
                      title: a.str('name'),
                      sub: '${a.str('city')} · ${num0(a.integer('students') + a.integer('trainers') + a.integer('admins'))} users',
                      trailing: HealthRing(a.integer('health'), size: 42),
                      onTap: () => hqGo(context, '/academies?open=${a.str('id')}'),
                    ),
                ]),
            ]),
          ),
          HqCard(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const CardHeader('Recent activity', sub: 'Across all academies'),
              if (activity.isEmpty)
                const EmptyNote('Nothing yet.')
              else
                HqList([
                  for (final a in activity)
                    HqRow(
                      leading: IconTile(a.str('icon'), tone: Tone.byName(a.str('tone')), size: 32, iconSize: 15),
                      title: a.str('who'),
                      sub: a.str('text'),
                      wrap: true,
                      trailing: Text(ago(a['at']), style: HqText.sub),
                    ),
                ]),
            ]),
          ),
        ]),
        const PageNote('Figures are live from the platform. Revenue is what has been billed, before GST.'),
      ],
    );
  }
}

class _Cover extends StatelessWidget {
  const _Cover({required this.alertCount});
  final int alertCount;

  @override
  Widget build(BuildContext context) {
    final n = DateTime.now();
    const wd = ['Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday', 'Sunday'];
    const mo = ['January', 'February', 'March', 'April', 'May', 'June', 'July', 'August', 'September', 'October', 'November', 'December'];
    final greeting = n.hour < 12 ? 'Good morning' : (n.hour < 17 ? 'Good afternoon' : 'Good evening');
    return Container(
      padding: const EdgeInsets.all(22),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: const Color(0x14FFFFFF)),
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF0F3D37), Color(0xFF14544A), Color(0xFF1B8F7C)],
          stops: [0, .45, 1],
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(greeting, style: HqText.h2),
          const SizedBox(height: 3),
          Text('${wd[n.weekday - 1]}, ${n.day} ${mo[n.month - 1]} ${n.year}',
              style: HqText.muted.copyWith(color: const Color(0xBFEDF1F9))),
          const SizedBox(height: 16),
          MouseRegion(
            cursor: SystemMouseCursors.click,
            child: GestureDetector(
              onTap: () => hqGo(context, '/alerts'),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: BoxDecoration(
                  color: const Color(0x6604070E),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: const Color(0x33FFFFFF)),
                ),
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  ic('warn', 14, Hq.gold),
                  const SizedBox(width: 7),
                  Text('$alertCount items need a look', style: HqText.button.copyWith(fontSize: 12)),
                  const SizedBox(width: 4),
                  ic('chev', 13, Hq.text),
                ]),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
