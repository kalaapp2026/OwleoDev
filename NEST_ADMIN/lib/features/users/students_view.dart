import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/theme.dart';
import '../../core/api/api_exception.dart';
import '../../core/auth/session.dart';
import '../../core/format.dart';
import '../../core/json.dart';
import '../../core/ui/async.dart';
import '../../core/ui/charts.dart';
import '../../core/ui/controls.dart';
import '../../core/ui/layout.dart';
import '../../core/ui/overlays.dart';
import '../../core/ui/primitives.dart';
import '../shell/nav.dart';
import 'user_drawer.dart' show userDetailProvider;

typedef StudentQuery = ({String academy, String q, String flt, int limit});

final studentsProvider = FutureProvider.autoDispose.family<Map<String, dynamic>, StudentQuery>(
  (ref, q) => ref.watch(dioClientProvider).getMap('/admin/hq/students', query: {'academy': q.academy, if (q.q.trim().isNotEmpty) 'q': q.q.trim(), 'flt': q.flt, 'limit': '${q.limit}'}),
);

final studentInsightsProvider = FutureProvider.autoDispose.family<Map<String, dynamic>, String>(
  (ref, academy) => ref.watch(dioClientProvider).getMap('/admin/hq/students/insights', query: {'academy': academy}),
);

final studentProvider = FutureProvider.autoDispose.family<Map<String, dynamic>, String>(
  (ref, id) => ref.watch(dioClientProvider).getMap('/admin/hq/students/$id'),
);

Tone _feeTone(String s) => switch (s) { 'paid' => Tone.green, 'due' => Tone.gold, _ => Tone.red };
String _feeLabel(String s) => switch (s) { 'paid' => 'Paid', 'due' => 'Due', _ => 'Overdue' };
Tone _attTone(num? v) => v == null ? Tone.mute : v >= 80 ? Tone.green : v >= 65 ? Tone.gold : Tone.red;
Tone _catTone(String c) => switch (c) { 'Dance' => Tone.gold, 'Music' => Tone.primary, 'Fine Arts' => Tone.violet, 'Theatre' => Tone.magenta, _ => Tone.mute };
Tone _tone(String t) => switch (t) { 'blue' => Tone.blue, 'red' => Tone.red, 'green' => Tone.green, _ => Tone.primary };

/// Students of one academy: who needs a nudge, and what the academy's audience looks like.
class StudentsView extends ConsumerStatefulWidget {
  const StudentsView({super.key});

  @override
  ConsumerState<StudentsView> createState() => _StudentsViewState();
}

class _StudentsViewState extends ConsumerState<StudentsView> {
  String? _academy;
  String _tab = 'list';
  String _q = '', _flt = 'all';
  int _limit = 12;
  Map<String, dynamic>? _last;

  @override
  Widget build(BuildContext context) {
    final filters = ref.watch(_academiesProvider);
    return filters.when(
      loading: () => const HqLoading(),
      error: (e, _) => HqError(e is ApiException ? e.message : 'Could not load academies.', onRetry: () => ref.invalidate(_academiesProvider)),
      data: (academies) {
        if (academies.isEmpty) return const EmptyNote('No academies yet');
        _academy ??= academies.first.str('id');
        return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          HqSelect<String>(label: 'Academy', value: _academy, options: [for (final a in academies) SelectOption(a.str('id'), a.str('name'))], onChanged: (v) => setState(() {
                _academy = v;
                _limit = 12;
              })),
          Padding(padding: const EdgeInsets.only(bottom: 12), child: SegControl<String>(expand: true, items: const [('list', 'Students'), ('ins', 'Insights')], value: _tab, onChanged: (v) => setState(() => _tab = v))),
          if (_tab == 'ins') _Insights(academy: _academy!) else _list(),
        ]);
      },
    );
  }

  Widget _list() {
    final q = (academy: _academy!, q: _q, flt: _flt, limit: _limit);
    final data = ref.watch(studentsProvider(q));
    if (data.hasValue) _last = data.value;
    final d = data.valueOrNull ?? _last;
    if (d == null) return asyncBody(data, onRetry: () => ref.invalidate(studentsProvider), data: (_) => const SizedBox.shrink());
    final items = d.maps('items');
    final counts = d.obj('counts');
    final total = d.integer('total');
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      HqCard(padding: const EdgeInsets.all(12), margin: const EdgeInsets.only(bottom: 12), child: SearchBox(hint: 'Search students or courses', initial: _q, onChanged: (v) => setState(() {
            _q = v;
            _limit = 12;
          }))),
      Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: ChipRow([
          for (final (k, l) in const [('all', 'All'), ('due', 'Fees due'), ('low', 'Low attendance'), ('mkt', 'Marketing consent'), ('minor', 'Under 18')])
            HqChip(l, selected: _flt == k, count: counts.integer(k), onTap: () => setState(() {
                  _flt = k;
                  _limit = 12;
                })),
        ], scroll: true),
      ),
      if (items.isEmpty) const EmptyNote('No students match. Clear the search or pick another filter.'),
      LayoutBuilder(builder: (context, c) {
        final cols = c.maxWidth >= 900 ? 3 : c.maxWidth >= 600 ? 2 : 1;
        return Wrap(spacing: 10, runSpacing: 10, children: [for (final s in items) SizedBox(width: (c.maxWidth - (cols - 1) * 10) / cols, child: _card(s))]);
      }),
      if (total > _limit) Padding(padding: const EdgeInsets.only(top: 12), child: HqButton('Show more (${total - _limit} left)', expand: true, onPressed: () => setState(() => _limit += 12))),
      Padding(padding: const EdgeInsets.fromLTRB(2, 14, 2, 0), child: Text('Showing ${items.length} of $total students. Contact details stay hidden until you reveal them, and each reveal is logged.', style: HqText.sub)),
    ]);
  }

  Widget _card(Map<String, dynamic> s) {
    final cats = s.strings('cats');
    final att = s['att'] == null ? null : s.integer('att');
    return HqCard(
      radius: 14,
      padding: const EdgeInsets.all(12),
      onTap: () => showHqDrawer(context, builder: (_) => _StudentDrawer(id: s.str('id'), userId: s.str('userId'))),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(children: [
          Avatar(initials(s.str('name')), tone: cats.isEmpty ? Tone.blue : _catTone(cats.first)),
          const SizedBox(width: 10),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(s.str('name'), maxLines: 1, overflow: TextOverflow.ellipsis, style: HqText.row),
              Text('${s['age'] == null ? '' : '${s.integer('age')} yrs · '}${s.strings('courses').isEmpty ? 'No course yet' : s.strings('courses').join(', ')}', maxLines: 1, overflow: TextOverflow.ellipsis, style: HqText.small),
            ]),
          ),
          Tag(att == null ? '–' : '$att%', tone: _attTone(att)),
        ]),
        const SizedBox(height: 9),
        Wrap(spacing: 6, runSpacing: 6, children: [
          Tag('${_feeLabel(s.str('fee'))}${s.number('due') > 0 ? ' · ${inr(s.number('due'))}' : ''}', tone: _feeTone(s.str('fee'))),
          if (s.flag('minor')) const Tag('Under 18', tone: Tone.violet),
          Tag(s.flag('consent') ? 'Marketing OK' : 'No consent', tone: s.flag('consent') ? Tone.green : Tone.mute),
        ]),
      ]),
    );
  }
}

final _academiesProvider = FutureProvider.autoDispose<List<Map<String, dynamic>>>((ref) async {
  final r = await ref.watch(dioClientProvider).getMap('/admin/hq/users/filters');
  return r.maps('academies');
});

class _Insights extends ConsumerWidget {
  const _Insights({required this.academy});
  final String academy;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return asyncBody(ref.watch(studentInsightsProvider(academy)), onRetry: () => ref.invalidate(studentInsightsProvider), data: (d) {
      final bands = d.maps('bands');
      final courses = d.maps('courses');
      final ints = d.maps('interests');
      final segs = d.maps('segments');
      final maxC = courses.isEmpty ? 1 : courses.first.integer('v');
      return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        HqGrid(GridKind.g4, [
          Kpi(icon: 'users', tone: Tone.primary, label: 'Students', value: num0(d.integer('students')), foot: 'active in this academy'),
          Kpi(icon: 'check', tone: Tone.green, label: 'Avg attendance', value: d['avgAttendance'] == null ? '–' : pct(d.number('avgAttendance')), foot: 'last 60 days'),
          Kpi(icon: 'rupee', tone: Tone.gold, label: 'Fees paid on time', value: d['paidPct'] == null ? '–' : pct(d.number('paidPct')), foot: '${d.integer('withDues')} with dues'),
          Kpi(icon: 'shield', tone: Tone.violet, label: 'Marketing consent', value: d['consentPct'] == null ? '–' : pct(d.number('consentPct')), foot: '${d.integer('consent')} profiles'),
        ]),
        HqGrid(GridKind.g2, [
          HqCard(child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            const CardHeader('Age groups', sub: 'Students by age'),
            HqChart(labels: [for (final b in bands) b.str('label')], height: 190, noRange: true, series: [ChartSeries('Students', Hq.blue, SeriesType.bar, [for (final b in bands) b.number('v')])]),
          ])),
          HqCard(child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            const CardHeader('Popular courses', sub: 'Enrolments'),
            if (courses.isEmpty) const EmptyNote('No enrolments yet'),
            for (final c in courses) Meter(c.str('label'), '${c.integer('v')}', c.integer('v') / maxC * 100),
          ])),
        ]),
        HqCard(
          margin: const EdgeInsets.only(bottom: 14),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            const CardHeader('What they are interested in', sub: 'From the courses they are enrolled in'),
            if (ints.isEmpty) const EmptyNote('Nothing to show yet'),
            Wrap(spacing: 8, runSpacing: 8, children: [for (final i in ints) Tag('${i.str('label')}  ${i.integer('v')}', tone: _catTone(i.str('label')), lowercase: true)]),
          ]),
        ),
        HqCard(child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          const CardHeader('Opportunities', sub: 'Groups worth acting on', bottom: 6),
          HqList([
            for (final s in segs)
              HqRow(
                leading: IconTile(s.str('tone') == 'red' ? 'warn' : s.str('tone') == 'green' ? 'mega' : 'spark', tone: _tone(s.str('tone'))),
                title: s.str('head'),
                sub: s.str('text'),
                wrap: true,
                trailing: HqButton('Campaign', small: true, onPressed: () => hqGo(context, '/marketing')),
              ),
          ]),
        ])),
      ]);
    });
  }
}

class _StudentDrawer extends ConsumerStatefulWidget {
  const _StudentDrawer({required this.id, required this.userId});
  final String id, userId;

  @override
  ConsumerState<_StudentDrawer> createState() => _StudentDrawerState();
}

class _StudentDrawerState extends ConsumerState<_StudentDrawer> {
  final Map<String, String> _revealed = {};

  Future<void> _reveal(String field) async {
    try {
      final r = await ref.read(dioClientProvider).postMap('/admin/hq/users/${widget.userId}/reveal', body: {'field': field});
      if (mounted) setState(() => _revealed[field] = r.str('value'));
    } on ApiException catch (e) {
      if (mounted) showToast(context, e.message);
    }
  }

  @override
  Widget build(BuildContext context) {
    final detail = ref.watch(studentProvider(widget.id));
    final user = ref.watch(userDetailProvider(widget.userId)).valueOrNull;
    return detail.when(
      loading: () => const Center(child: CircularProgressIndicator(color: Hq.primary, strokeWidth: 2.5)),
      error: (e, _) => Padding(padding: const EdgeInsets.all(24), child: HqError(e is ApiException ? e.message : 'Could not load this student.')),
      data: (s) {
        final cats = s.strings('cats');
        final att = s['att'] == null ? null : s.integer('att');
        final weekly = (s['weekly'] as List? ?? const []);
        final slips = s.maps('slips');
        final fields = user?.obj('fields');

        Widget contact(String key, String label, Map<String, dynamic>? c) {
          if (c == null) return const SizedBox.shrink();
          final present = c.flag('present');
          return HqRow(
            leading: const IconTile('lock', tone: Tone.mute),
            title: present ? (_revealed[key] ?? c.str('masked')) : 'Not on file',
            sub: label,
            trailing: present && !_revealed.containsKey(key) ? HqButton('Reveal', small: true, onPressed: () => _reveal(key)) : null,
          );
        }

        return DrawerShell(
          logo: DrawerLogo(initials(s.str('name')), color: (cats.isEmpty ? Tone.blue : _catTone(cats.first)).color),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Wrap(alignment: WrapAlignment.spaceBetween, spacing: 10, runSpacing: 8, children: [
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(s.str('name'), style: HqText.h2.copyWith(fontSize: 19)),
                Text('${s['age'] == null ? '' : '${s.integer('age')} yrs · '}${s.str('academy')}', style: HqText.muted.copyWith(fontSize: 12.5)),
              ]),
              Row(mainAxisSize: MainAxisSize.min, children: [if (s.flag('minor')) const Tag('Under 18', tone: Tone.violet), const SizedBox(width: 6), Tag(_feeLabel(s.str('fee')), tone: _feeTone(s.str('fee')))]),
            ]),
            MiniStats([('${s.maps('enrolled').length}', 'Courses', null), (att == null ? '–' : '$att%', 'Attendance', _attTone(att).color), (s.number('due') > 0 ? short(s.number('due')) : 'Nil', 'Due', null), (s['joined'] == null ? '' : fd(s['joined']).split(' ').skip(1).join(' '), 'Joined', null)]),
            HqCard(margin: const EdgeInsets.only(bottom: 12), child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              const CardHeader('Courses enrolled', bottom: 6),
              if (s.maps('enrolled').isEmpty) const EmptyNote('Not enrolled in a course', padding: 12),
              HqList([
                for (final c in s.maps('enrolled'))
                  HqRow(leading: IconTile('book', tone: _catTone(HqCategory.label(c.str('category')))), title: c.str('course'), sub: '${c.str('batch')}${c.strOrNull('trainer') == null ? '' : ' · ${c.str('trainer')}'}', trailing: Text(c['att'] == null ? '–' : '${c.integer('att')}%', style: HqText.row.copyWith(color: _attTone(c['att'] as num?).color))),
              ]),
            ])),
            HqCard(margin: const EdgeInsets.only(bottom: 12), child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              CardHeader('Attendance', sub: 'Last 8 weeks', trailing: Text(att == null ? '–' : '$att%', style: HqText.h3.copyWith(fontSize: 18))),
              if (weekly.where((w) => w != null).length < 2)
                const EmptyNote('Not enough classes yet to draw a trend', padding: 18)
              else
                HqChart(
                  labels: [for (var i = 0; i < weekly.length; i++) if (weekly[i] != null) 'W${i + 1}'],
                  height: 140,
                  leftPad: 34,
                  noRange: true,
                  axisFmt: (v) => '${v.round()}%',
                  tipFmt: (v) => '${v.round()}%',
                  series: [ChartSeries('Attended', Hq.primary, SeriesType.area, [for (final w in weekly) if (w != null) (w as num).toDouble()])],
                ),
            ])),
            HqCard(margin: const EdgeInsets.only(bottom: 12), child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              const CardHeader('Fees', bottom: 6),
              HqList([
                KeyValueRow('Paid so far', inr(s.number('paidTotal'))),
                KeyValueRow('Pending', s.number('due') > 0 ? inr(s.number('due')) : 'Nothing due'),
                for (final f in slips) KeyValueRow(monthLong(f.str('period')), f.number('paid') >= f.number('amount') ? 'Paid ${inr(f.number('amount'))}' : 'Unpaid ${inr(f.number('amount') - f.number('paid'))}', valueColor: f.number('paid') >= f.number('amount') ? Hq.green : Hq.red),
              ]),
            ])),
            HqCard(margin: const EdgeInsets.only(bottom: 12), child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              const CardHeader('Contact details', sub: 'Hidden until revealed. Each reveal is logged against you.', bottom: 6),
              HqList([contact('mobile', 'Mobile', fields?.obj('mobile')), contact('email', 'Email', fields?.obj('email')), contact('emer', 'Emergency contact', fields?.obj('emer'))]),
            ])),
            HqCard(margin: const EdgeInsets.only(bottom: 12), child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              const CardHeader('Interests and marketing', bottom: 6),
              Wrap(spacing: 8, runSpacing: 8, children: [for (final c in cats) Tag(HqCategory.label(c), tone: _catTone(HqCategory.label(c)), lowercase: true)]),
              const SizedBox(height: 10),
              HqList([
                KeyValueRow('Marketing consent', s.flag('consent') ? 'Given' : 'Not given'),
                KeyValueRow('Can be included in ads', s.flag('consent') ? (s.flag('minor') ? 'Yes, ads go to the guardian only' : 'Yes') : 'No'),
              ]),
            ])),
          ]),
        );
      },
    );
  }
}

/// Category codes from the server ("FINE_ARTS") as the labels the console uses.
abstract final class HqCategory {
  static String label(String c) => switch (c) { 'DANCE' => 'Dance', 'MUSIC' => 'Music', 'FINE_ARTS' => 'Fine Arts', 'THEATRE' => 'Theatre', _ => c };
}
