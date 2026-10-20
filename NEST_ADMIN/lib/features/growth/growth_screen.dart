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
import '../academies/academy_meta.dart';

final growthProvider = FutureProvider.autoDispose<Map<String, dynamic>>(
  (ref) => ref.watch(dioClientProvider).getMap('/admin/hq/growth'),
);

/// Growth tracker: how fast users, academies and revenue are growing, and when each target lands
/// at the current pace.
class GrowthScreen extends ConsumerWidget {
  const GrowthScreen({super.key});

  double _delta(List<double> a) => a.length < 2 || a[a.length - 2] == 0 ? 0 : (a.last - a[a.length - 2]) / a[a.length - 2].abs() * 100;

  /// "Reached", "No growth", or the month the target is hit if the last 3 months' pace holds.
  String _eta(List<double> s, double target) {
    if (s.isEmpty) return 'No data';
    final cur = s.last;
    final left = target - cur;
    if (left <= 0) return 'Reached';
    final from = s.length > 3 ? s[s.length - 4] : s.first;
    final per = (cur - from) / (s.length > 3 ? 3 : (s.length - 1).clamp(1, 3));
    if (per <= 0) return 'No growth yet';
    final months = (left / per).ceil();
    final d = DateTime(DateTime.now().year, DateTime.now().month + months, 1);
    const mo = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
    return '${mo[d.month - 1]} ${d.year}';
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final g = ref.watch(growthProvider);
    final user = ref.watch(sessionProvider).user;
    return asyncBody(g, onRetry: () => ref.invalidate(growthProvider), data: (d) {
      final months = d.strings('months');
      final labels = months.map(monthShort).toList(), tips = months.map(monthLong).toList();
      final users = d.doubles('users'), academies = d.doubles('academies');
      final added = d.doubles('added'), churned = d.doubles('churned');
      final q = d.obj('quality');
      final cur = months.length - 1;
      final targets = d.maps('targets');
      final types = d.maps('types');
      final cities = d.maps('cities');
      final maxU = cities.isEmpty ? 1 : cities.map((c) => c.integer('users')).reduce((a, b) => a > b ? a : b).clamp(1, 1 << 30);

      return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        HqGrid(GridKind.g4, [
          Kpi(
            tone: Tone.blue, icon: 'users', label: 'Total Owleo users', value: num0(users.last),
            foot: '+${num0(users.length > 1 ? users.last - users[users.length - 2] : users.last)} this month',
            delta: Delta(_delta(users)), spark: Spark(users, Hq.blue),
          ),
          Kpi(
            tone: Tone.primary, icon: 'bld', label: 'Academies', value: num0(academies.last),
            foot: '${added.last.round()} new · ${churned.last.round()} churned this month',
            delta: Delta(_delta(academies)), spark: Spark(academies, Hq.primary),
          ),
          Kpi(tone: Tone.violet, icon: 'layers', label: 'Users per academy', value: num0(q.number('usersPerAcademy')), foot: 'average across open academies'),
          Kpi(tone: Tone.green, icon: 'pulse', label: 'Logo retention', value: pct(q.number('retention')), foot: '${q.integer('lost')} of ${q.integer('total')} academies lost'),
        ]),
        HqGrid(GridKind.g21, [
          HqCard(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const CardHeader('Owleo users by role', sub: 'Students, trainers and academy admins'),
              HqChart(
                labels: labels, tipLabels: tips, height: 260, stack: true,
                series: [
                  ChartSeries('Students', Hq.blue, SeriesType.area, d.doubles('students')),
                  ChartSeries('Trainers', Hq.gold, SeriesType.area, d.doubles('trainers')),
                  ChartSeries('Admins', Hq.violet, SeriesType.area, d.doubles('admins')),
                ],
              ),
            ]),
          ),
          HqCard(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const CardHeader('Academies added and lost', sub: 'New vs churned each month'),
              HqChart(
                labels: labels, tipLabels: tips, height: 260,
                series: [
                  ChartSeries('New', Hq.primary, SeriesType.bar, added),
                  ChartSeries('Churned', Hq.red, SeriesType.bar, churned),
                ],
              ),
            ]),
          ),
        ]),
        HqCard(
          margin: const EdgeInsets.only(bottom: 14),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const CardHeader('Targets', sub: 'Projected from the last 3 months of growth'),
            HqGrid(GridKind.g2, bottom: 0, [
              for (final t in targets) _target(context, ref, t, d, user?.isSuper ?? false, _eta),
            ]),
          ]),
        ),
        HqGrid(GridKind.g3, [
          HqCard(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const CardHeader('Academy types', sub: 'Academies and users'),
              HqList([
                for (final t in types)
                  HqRow(
                    leading: IconTile('book', tone: AcademyMeta.typeTone(t.str('type')), iconSize: 15),
                    title: t.str('type'),
                    sub: '${num0(t.integer('users'))} users',
                    trailing: Text('${t.integer('academies')}', style: HqText.row),
                  ),
              ]),
            ]),
          ),
          HqCard(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const CardHeader('Top cities', sub: 'By number of users'),
              if (cities.isEmpty)
                const EmptyNote('No academies yet.')
              else
                HqList([
                  for (final c in cities)
                    Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                      Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                        Row(children: [ic('pin', 13, Hq.muted), const SizedBox(width: 6), Text(c.str('city'), style: HqText.row)]),
                        Text('${c.integer('academies')} academies · ${num0(c.integer('users'))}', style: HqText.small),
                      ]),
                      const SizedBox(height: 6),
                      HqBar(c.integer('users') / maxU * 100, tone: Tone.blue),
                    ]),
                ]),
            ]),
          ),
          HqCard(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const CardHeader('Revenue quality', sub: 'Per paying academy'),
              HqList([
                HqRow(title: 'Avg revenue per academy', sub: 'Subscriptions and add-ons', trailing: Text(inr(q.number('arpa')), style: HqText.row)),
                HqRow(title: 'Revenue per user', sub: 'MRR ÷ users', trailing: Text(inr(q.number('revenuePerUser')), style: HqText.row)),
                HqRow(title: 'Demo to paid', sub: 'Needs onboarding history', trailing: Text(d['demoToPaid'] == null ? '–' : pct(d.number('demoToPaid')), style: HqText.row)),
                HqRow(title: 'Months of history', sub: 'Since the first academy joined', trailing: Text('${(cur + 1).clamp(0, 12)}', style: HqText.row)),
              ]),
            ]),
          ),
        ]),
        const PageNote('Figures are live from the platform. History is reconstructed from join and closure dates.'),
      ]);
    });
  }

  Widget _target(BuildContext context, WidgetRef ref, Map<String, dynamic> t, Map<String, dynamic> d, bool canEdit, String Function(List<double>, double) eta) {
    final key = t.str('key');
    final s = t.doubles('series');
    final target = t.number('target');
    final v = s.isEmpty ? 0.0 : s.last;
    final p = (v / target * 100).clamp(0, 100).toDouble();
    final money = key == 'mrr' || key == 'revenue';
    String f(double x) => money ? short(x) : num0(x);
    final tone = switch (key) { 'academies' => Tone.primary, 'users' => Tone.blue, 'mrr' => Tone.gold, _ => Tone.green };
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
        Expanded(
          child: Row(children: [
            ic('target', 14, tone.color),
            const SizedBox(width: 7),
            Flexible(child: Text(t.str('label'), style: HqText.row)),
            if (canEdit)
              Padding(
                padding: const EdgeInsets.only(left: 6),
                child: MouseRegion(
                  cursor: SystemMouseCursors.click,
                  child: GestureDetector(
                    onTap: () async {
                      final done = await showHqModal<bool>(context, width: 420, builder: (_) => _TargetModal(target: t));
                      if (done == true) {
                        ref.invalidate(growthProvider);
                        if (context.mounted) showToast(context, 'Target updated');
                      }
                    },
                    child: ic('edit', 13, Hq.faint),
                  ),
                ),
              ),
          ]),
        ),
        Text('${f(v)} of ${f(target)} · ${pct(p)}', style: HqText.small),
      ]),
      const SizedBox(height: 8),
      HqBar(p, tone: tone, height: 9),
      const SizedBox(height: 8),
      Text.rich(TextSpan(children: [
        TextSpan(text: 'At this pace: ', style: HqText.small),
        TextSpan(text: eta(s, target), style: HqText.small.copyWith(color: Hq.text, fontWeight: FontWeight.w700)),
      ])),
    ]);
  }
}

class _TargetModal extends ConsumerStatefulWidget {
  const _TargetModal({required this.target});
  final Map<String, dynamic> target;

  @override
  ConsumerState<_TargetModal> createState() => _TargetModalState();
}

class _TargetModalState extends ConsumerState<_TargetModal> {
  late final _c = TextEditingController(text: widget.target.number('target').round().toString());
  String? _error;
  bool _busy = false;

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final v = double.tryParse(_c.text.replaceAll(',', ''));
    if (v == null || v <= 0) return setState(() => _error = 'Enter a number above zero.');
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await ref.read(dioClientProvider).putMap('/admin/hq/growth/targets/${widget.target.str('key')}', body: {'target': v});
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
      title: 'Change target',
      sub: widget.target.str('label'),
      error: _error,
      actions: [
        HqButton('Cancel', onPressed: () => Navigator.of(context).pop()),
        HqButton('Save', kind: BtnKind.primary, busy: _busy, onPressed: _save),
      ],
      children: [
        HqField(label: 'Target', controller: _c, keyboard: TextInputType.number, formatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9,]'))]),
      ],
    );
  }
}
