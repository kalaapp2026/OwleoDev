import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/theme.dart';
import '../../core/auth/session.dart';
import '../../core/format.dart';
import '../../core/json.dart';
import '../../core/ui/async.dart';
import '../../core/ui/controls.dart';
import '../../core/ui/layout.dart';
import '../../core/ui/primitives.dart';
import '../shell/nav.dart';

final platformStatusProvider = FutureProvider.autoDispose<Map<String, dynamic>>((ref) => ref.watch(dioClientProvider).getMap('/admin/hq/platform'));

Tone _tone(String t) => switch (t) { 'green' => Tone.green, 'gold' => Tone.gold, 'red' => Tone.red, _ => Tone.mute };

/// Dashboard > Platform status: dues, data completeness, system health, traffic and what waits on HQ.
class PlatformStatus extends ConsumerStatefulWidget {
  const PlatformStatus({super.key});

  @override
  ConsumerState<PlatformStatus> createState() => _PlatformStatusState();
}

class _PlatformStatusState extends ConsumerState<PlatformStatus> {
  String _traffic = 'owner';

  @override
  Widget build(BuildContext context) {
    return asyncBody(ref.watch(platformStatusProvider), onRetry: () => ref.invalidate(platformStatusProvider), data: (d) {
      final ap = d.obj('approvals');
      final sup = d.obj('support');
      final uo = d.obj('userOverview');
      final health = d.obj('health');
      final tr = d.obj('traffic');
      final open = (ap.integer('pending')) + ap.integer('delayed') + ap.integer('escalated');
      final profiles = uo.integer('profiles');
      final missing = uo.integer('missing');
      final rate = profiles == 0 ? 0.0 : missing / profiles;
      final top = uo.maps('missingTop');
      final topMax = top.isEmpty ? 1 : top.first.integer('n');
      final academies = tr.maps('academies');
      final people = tr.maps(_traffic == 'owner' ? 'owners' : 'students');

      Widget card(String title, String sub, Widget child) => HqCard(child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [CardHeader(title, sub: sub), child]));

      return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        HqGrid(GridKind.g4, [
          Kpi(icon: 'bld', tone: Tone.primary, label: 'Active academies', value: '${d.integer('liveAcademies')}', foot: '${d.integer('demoAcademies')} on demo · ${d.integer('closedAcademies')} closed'),
          Kpi(icon: 'users', tone: Tone.blue, label: 'Active admins', value: '${d.integer('admins')}', foot: 'academy owners and admins, ${d.integer('hqStaff')} at HQ'),
          Kpi(icon: 'warn', tone: d.integer('overdueCount') > 0 ? Tone.red : Tone.green, label: 'Overdue academies', value: '${d.integer('overdueCount')}', foot: d.integer('overdueCount') == 0 ? 'All up to date' : 'Details in Finance'),
          Kpi(icon: 'flow', tone: Tone.violet, label: 'Open approvals', value: '$open', foot: '${ap.integer('delayed')} delayed, ${ap.integer('escalated')} escalated'),
        ]),
        HqGrid(GridKind.g2, [
          card('User overview', 'Active users and profile completeness', Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            MiniStats([(num0(uo.integer('active')), 'Active in 30 days', null), (pct(rate * 100), 'Profiles missing data', rate > .2 ? Hq.red : Hq.gold)]),
            for (final t in top) Meter(t.str('label'), '${t.integer('n')} profiles', t.integer('n') / topMax * 100, tone: Tone.red),
            Padding(padding: const EdgeInsets.only(top: 10), child: Align(alignment: Alignment.centerLeft, child: HqButton('See them in Users', small: true, onPressed: () => hqGo(context, '/users')))),
          ])),
        ]),
        HqGrid(GridKind.g2, [
          card('System health', 'The server and what it is doing right now', Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            HqList([
              for (final c in health.maps('checks'))
                HqRow(leading: IconTile(c.str('tone') == 'green' ? 'check' : 'warn', tone: _tone(c.str('tone'))), title: '${c.str('name')} · ${c.str('value')}', sub: c.str('note'), wrap: true),
            ]),
            if (health.maps('incidents').isNotEmpty) ...[
              const SizedBox(height: 10),
              Text('RECENT PROBLEMS', style: HqText.th),
              HqList([for (final i in health.maps('incidents')) HqRow(leading: const IconTile('warn', tone: Tone.gold), title: i.str('what'), sub: '${i.str('status')} · ${i.str('detail')} · ${ago(i['at'])}', wrap: true)]),
            ],
          ])),
          card('Traffic', 'Most active academies today', Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            if (academies.isEmpty) const EmptyNote('No one has opened the app today', padding: 14),
            for (final a in academies) Meter(a.str('name'), '${a.integer('seen')} active', a.integer('seen') / (academies.first.integer('seen') == 0 ? 1 : academies.first.integer('seen')) * 100, tone: Tone.blue),
            const SizedBox(height: 14),
            SegControl<String>(items: const [('owner', 'Owner-wise'), ('student', 'Student-wise')], value: _traffic, onChanged: (v) => setState(() => _traffic = v)),
            const SizedBox(height: 4),
            if (people.isEmpty) const EmptyNote('No sign-ins in the last 7 days', padding: 14),
            HqList([for (final t in people) HqRow(leading: Avatar(initials(t.str('name')), tone: _traffic == 'owner' ? Tone.gold : Tone.blue), title: t.str('name'), sub: t.strOrNull('academy'), trailing: Text('${t.integer('sessions')} sessions', style: HqText.row.copyWith(fontSize: 13)))]),
          ])),
        ]),
        HqGrid(GridKind.g2, [
          card('Support', 'Tickets from academy admins and student fee issues', Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            MiniStats([('${sup.integer('open')}', 'Open', null), ('${sup.integer('high')}', 'Urgent or high', Hq.red), (sup.str('rating', '–'), 'Feedback', null)]),
            Align(alignment: Alignment.centerLeft, child: HqButton('Open support', small: true, onPressed: () => hqGo(context, '/support'))),
          ])),
          card('Pending approvals', 'Waiting on an approver', Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            MiniStats([('${ap.integer('pending')}', 'Pending', null), ('${ap.integer('delayed')}', 'Delayed', Hq.gold), ('${ap.integer('escalated')}', 'Escalated', Hq.red)]),
            Align(alignment: Alignment.centerLeft, child: HqButton('Open approvals', small: true, onPressed: () => hqGo(context, '/approvals'))),
          ])),
        ]),
      ]);
    });
  }
}
