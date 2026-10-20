import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/theme.dart';
import '../../core/auth/session.dart';
import '../../core/download.dart';
import '../../core/format.dart';
import '../../core/json.dart';
import '../../core/ui/async.dart';
import '../../core/ui/charts.dart';
import '../../core/ui/controls.dart';
import '../../core/ui/overlays.dart';
import '../../core/ui/primitives.dart';
import '../../core/ui/table.dart';
import 'academy_drawer.dart';
import 'bulk_import.dart';
import 'academy_meta.dart';

final academiesProvider = FutureProvider.autoDispose<List<Map<String, dynamic>>>(
  (ref) => ref.watch(dioClientProvider).getList('/admin/hq/academies'),
);

/// Entities: every academy with how it is doing. Rows open the academy's profile.
class AcademiesScreen extends ConsumerStatefulWidget {
  const AcademiesScreen({super.key});

  @override
  ConsumerState<AcademiesScreen> createState() => _AcademiesScreenState();
}

class _AcademiesScreenState extends ConsumerState<AcademiesScreen> {
  String _filter = 'all';
  String _sort = 'health';
  String _q = '';
  int _limit = 12;
  String? _handledOpen;

  bool _isRisk(Map<String, dynamic> a) {
    final s = a.str('status');
    return s == 'pastdue' || (s != 'churned' && a.integer('health') < 62);
  }

  bool _matches(Map<String, dynamic> a, String f) => switch (f) {
        'live' => a.str('status') == 'live',
        'trial' => a.str('status') == 'trial',
        'risk' => _isRisk(a),
        'churned' => a.str('status') == 'churned',
        _ => true,
      };

  int _users(Map<String, dynamic> a) => a.integer('students') + a.integer('trainers') + a.integer('admins');

  List<Map<String, dynamic>> _filtered(List<Map<String, dynamic>> all) {
    final q = _q.trim().toLowerCase();
    final r = all.where((a) => _matches(a, _filter) && (q.isEmpty || ('${a.str('name')}${a.str('city')}${a.str('type')}${a.str('owner')}').toLowerCase().contains(q))).toList();
    int cmp(Map<String, dynamic> a, Map<String, dynamic> b) => switch (_sort) {
          'users' => _users(b) - _users(a),
          'mrr' => b.number('planPrice').compareTo(a.number('planPrice')),
          'new' => b.str('joined').compareTo(a.str('joined')),
          'name' => a.str('name').toLowerCase().compareTo(b.str('name').toLowerCase()),
          _ => b.integer('health') - a.integer('health'),
        };
    r.sort(cmp);
    return r;
  }

  void _export(List<Map<String, dynamic>> all) {
    final rows = <List<Object?>>[
      ['ID', 'Academy', 'City', 'Type', 'Plan', 'Status', 'Students', 'Trainers', 'Health'],
      for (final a in all)
        [a.str('id'), a.str('name'), a.str('city'), a.str('type'), a.str('planName'), AcademyMeta.status(a.str('status')).$2, a.integer('students'), a.integer('trainers'), a.integer('health')],
    ];
    downloadText('owleo-academies-${DateTime.now().toIso8601String().substring(0, 10)}.csv', csvText(rows));
    showToast(context, 'Exported ${all.length} academies');
  }

  @override
  Widget build(BuildContext context) {
    final data = ref.watch(academiesProvider);
    final user = ref.watch(sessionProvider).user;

    // `?open=<id>` (from an alert, the dashboard or a ticket) opens that academy's profile once.
    final open = GoRouterState.of(context).uri.queryParameters['open'];
    if (open != null && open != _handledOpen) {
      _handledOpen = open;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) showAcademyDrawer(context, ref, open);
      });
    }

    return asyncBody(data, onRetry: () => ref.invalidate(academiesProvider), data: (all) {
      final list = _filtered(all);
      final shown = list.take(_limit).toList();
      final wide = MediaQuery.sizeOf(context).width >= 760;
      int count(String f) => all.where((a) => _matches(a, f)).length;

      return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: Wrap(spacing: 8, runSpacing: 8, children: [
            HqButton('Export academies', icon: 'dl', small: true, onPressed: user?.canExport == true ? () => _export(all) : null),
            if (user?.canWrite == true) HqButton('Bulk import', icon: 'ul', small: true, onPressed: () => showBulkImport(context, all.where((a) => a.str('status') != 'churned').toList())),
          ]),
        ),
        Padding(
          padding: const EdgeInsets.only(bottom: 14),
          child: SearchBox(hint: 'Search academies, cities, owners', height: 46, onChanged: (v) => setState(() {
                _q = v;
                _limit = 12;
              })),
        ),
        _wrap(
          wide,
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Padding(
              padding: EdgeInsets.only(bottom: wide ? 12 : 12),
              child: Wrap(
                alignment: WrapAlignment.spaceBetween,
                crossAxisAlignment: WrapCrossAlignment.center,
                spacing: 10,
                runSpacing: 10,
                children: [
                  ChipRow([
                    for (final (k, l) in const [('all', 'All'), ('live', 'Live'), ('trial', 'Demo'), ('risk', 'At risk'), ('churned', 'Churned')])
                      HqChip(l, selected: _filter == k, count: count(k), onTap: () => setState(() {
                            _filter = k;
                            _limit = 12;
                          })),
                  ]),
                  Row(mainAxisSize: MainAxisSize.min, children: [
                    Text('Sort by', style: HqText.label),
                    const SizedBox(width: 10),
                    SizedBox(
                      width: 170,
                      child: HqSelect<String>(
                        bottom: 0,
                        compact: true,
                        searchable: false,
                        value: _sort,
                        options: const [
                          SelectOption('health', 'Health score'),
                          SelectOption('users', 'Most users'),
                          SelectOption('mrr', 'Highest plan'),
                          SelectOption('new', 'Newest'),
                          SelectOption('name', 'Name A–Z'),
                        ],
                        onChanged: (v) => setState(() => _sort = v),
                      ),
                    ),
                  ]),
                ],
              ),
            ),
            if (list.isEmpty)
              const EmptyNote('No academies match this filter. Clear the search or pick another filter.')
            else if (wide)
              _table(shown)
            else
              Column(children: [for (final a in shown) Padding(padding: const EdgeInsets.only(bottom: 10), child: _card(a))]),
            if (list.length > _limit)
              Padding(
                padding: const EdgeInsets.only(top: 12),
                child: HqButton('Show ${(list.length - _limit).clamp(0, 12)} more of ${list.length - _limit} left', expand: true, onPressed: () => setState(() => _limit += 12)),
              ),
          ]),
        ),
        PageNote('Showing ${shown.length} of ${list.length} academies.'),
      ]);
    });
  }

  /// On a wide window the list sits in a card; on a phone it is a plain stack of cards.
  Widget _wrap(bool wide, {required Widget child}) => wide ? HqCard(child: child) : child;

  void _open(String id) => showAcademyDrawer(context, ref, id);

  Widget _table(List<Map<String, dynamic>> rows) {
    Color feeColor(num v) => v >= 80 ? Hq.green : (v >= 60 ? Hq.gold : Hq.red);
    final cols = const [
      HqCol('Academy', flex: 3, width: 220),
      HqCol('Plan', width: 90),
      HqCol('Users', width: 150),
      HqCol('Plan usage', width: 118),
      HqCol('Fee collection', width: 100, numeric: true),
      HqCol('Attendance', width: 98, numeric: true),
      HqCol('Weekly active', width: 98, numeric: true),
      HqCol('Health', width: 76, numeric: true),
      HqCol('MRR', width: 86, numeric: true),
      HqCol('Status', width: 118),
    ];
    return HqTable(
      columns: cols,
      onRowTap: (i) => _open(rows[i].str('id')),
      rows: [
        for (final a in rows)
          [
            Row(children: [
              Avatar(initials(a.str('name')), tone: AcademyMeta.typeTone(a.str('type'))),
              const SizedBox(width: 11),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(a.str('name'), maxLines: 1, overflow: TextOverflow.ellipsis, style: HqText.row),
                  Text('${a.str('city')} · ${a.str('type')}', maxLines: 1, overflow: TextOverflow.ellipsis, style: HqText.small),
                ]),
              ),
            ]),
            _planTag(a),
            Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
              Text(num0(_users(a)), style: HqText.row),
              Text('${a.integer('students')} students · ${a.integer('trainers')} trainers', style: HqText.small),
            ]),
            _usage(a),
            a['feeCollection'] == null
                ? Text('–', style: HqText.row.copyWith(color: Hq.faint))
                : Text(pct(a.number('feeCollection')), style: HqText.row.copyWith(color: feeColor(a.number('feeCollection')), fontWeight: FontWeight.w800)),
            Text(a['attendance'] == null ? '–' : pct(a.number('attendance')), style: HqText.row),
            Text(a['weeklyActive'] == null ? '–' : pct(a.number('weeklyActive')), style: HqText.row),
            HealthRing(a.integer('health'), size: 38),
            Text(a.str('status') == 'trial' || a.str('status') == 'churned' || a['planPrice'] == null ? '–' : inr(a.number('planPrice')), style: HqText.row),
            _statusTag(a),
          ],
      ],
    );
  }

  Widget _usage(Map<String, dynamic> a) {
    final lim = a.integerOrNull('maxStudents');
    if (lim == null) return Text('Unlimited', style: HqText.small);
    final use = (a.integer('students') / lim * 100).clamp(0, 100).toDouble();
    return Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
      SizedBox(width: 100, child: HqBar(use, tone: use >= 90 ? Tone.gold : Tone.primary)),
      const SizedBox(height: 3),
      Text('${a.integer('students')}/$lim', style: HqText.small),
    ]);
  }

  Widget _planTag(Map<String, dynamic> a) => a.strOrNull('planName') == null ? Text('–', style: HqText.small) : Tag(a.str('planName'), tone: Tone.blue);

  Widget _statusTag(Map<String, dynamic> a) {
    final (t, l) = AcademyMeta.status(a.str('status'));
    return Tag(l, tone: t);
  }

  Widget _card(Map<String, dynamic> a) {
    Color feeColor(num v) => v >= 80 ? Hq.green : (v >= 60 ? Hq.gold : Hq.red);
    Widget box(String v, String l, [Color? c]) => Expanded(
          child: Container(
            padding: const EdgeInsets.symmetric(vertical: 7, horizontal: 4),
            decoration: BoxDecoration(color: Hq.surface, borderRadius: BorderRadius.circular(10)),
            child: Column(children: [
              Text(v, style: HqText.row.copyWith(fontWeight: FontWeight.w800, color: c ?? Hq.text)),
              Text(l, style: HqText.sub.copyWith(fontSize: 10, fontWeight: FontWeight.w600)),
            ]),
          ),
        );
    return HqCard(
      radius: 16,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      onTap: () => _open(a.str('id')),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(children: [
          Avatar(initials(a.str('name')), tone: AcademyMeta.typeTone(a.str('type'))),
          const SizedBox(width: 11),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(a.str('name'), maxLines: 1, overflow: TextOverflow.ellipsis, style: HqText.row.copyWith(fontSize: 13.5)),
              Text('${a.str('city')} · ${a.str('type')} · ${num0(_users(a))} users', maxLines: 1, overflow: TextOverflow.ellipsis, style: HqText.small),
            ]),
          ),
          HealthRing(a.integer('health'), size: 40),
        ]),
        const SizedBox(height: 10),
        Row(children: [
          _planTag(a),
          const SizedBox(width: 6),
          _statusTag(a),
          const Spacer(),
          if (a['planPrice'] != null && (a.str('status') == 'live' || a.str('status') == 'pastdue'))
            Text('${inr(a.number('planPrice'))}/mo', style: HqText.small.copyWith(fontWeight: FontWeight.w700)),
        ]),
        const SizedBox(height: 10),
        Row(children: [
          box(a['feeCollection'] == null ? '–' : pct(a.number('feeCollection')), 'Fees', a['feeCollection'] == null ? null : feeColor(a.number('feeCollection'))),
          const SizedBox(width: 6),
          box(a['attendance'] == null ? '–' : pct(a.number('attendance')), 'Attendance'),
          const SizedBox(width: 6),
          box(a['weeklyActive'] == null ? '–' : pct(a.number('weeklyActive')), 'Active'),
        ]),
      ]),
    );
  }
}
