import 'package:flutter/material.dart';
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

typedef CourseQuery = ({String? academy, String status, String issue, String q});

final coursesProvider = FutureProvider.autoDispose.family<Map<String, dynamic>, CourseQuery>(
  (ref, q) => ref.watch(dioClientProvider).getMap('/admin/hq/courses', query: {
    'academy': ?q.academy,
    'status': q.status,
    'issue': q.issue,
    if (q.q.trim().isNotEmpty) 'q': q.q.trim(),
  }),
);

Tone _statusTone(String s) => switch (s) { 'Running' => Tone.green, 'Upcoming' => Tone.blue, _ => Tone.mute };

/// Courses: every batch across academies, and the ones that need chasing.
class CoursesScreen extends ConsumerStatefulWidget {
  const CoursesScreen({super.key});

  @override
  ConsumerState<CoursesScreen> createState() => _CoursesScreenState();
}

class _CoursesScreenState extends ConsumerState<CoursesScreen> {
  CourseQuery _q = (academy: null, status: 'all', issue: 'all', q: '');
  int _limit = 12;
  Map<String, dynamic>? _last;

  void _set(CourseQuery q) => setState(() {
        _q = q;
        _limit = 12;
      });

  void _refresh() => ref.invalidate(coursesProvider);

  @override
  Widget build(BuildContext context) {
    final data = ref.watch(coursesProvider(_q));
    if (data.hasValue) _last = data.value;
    final d = data.valueOrNull ?? _last;
    if (d == null) return asyncBody(data, onRetry: _refresh, data: (_) => const SizedBox.shrink());
    final canWrite = ref.watch(sessionProvider).user?.canWrite ?? false;
    final items = d.maps('items');
    final shown = items.take(_limit).toList();
    final academies = d.maps('academies');

    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      HqGrid(GridKind.g4, [
        Kpi(icon: 'book', tone: Tone.blue, label: 'Batches', value: '${d.integer('total')}', foot: '${d.integer('running')} running now'),
        Kpi(icon: 'users', tone: Tone.green, label: 'Enrolled', value: num0(d.integer('enrolled')), foot: 'students in running batches'),
        Kpi(icon: 'warn', tone: Tone.red, label: 'No trainer', value: '${d.integer('noTrainer')}', valueColor: Hq.red, foot: 'running or upcoming batches'),
        Kpi(icon: 'clock', tone: Tone.gold, label: 'Incomplete or outdated', value: '${d.integer('incomplete') + d.integer('outdated')}', foot: '${d.integer('incomplete')} incomplete, ${d.integer('outdated')} outdated'),
      ]),
      HqCard(
        padding: const EdgeInsets.all(12),
        margin: const EdgeInsets.only(bottom: 12),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Padding(padding: const EdgeInsets.only(bottom: 10), child: SearchBox(hint: 'Search course or batch', initial: _q.q, onChanged: (v) => _set((academy: _q.academy, status: _q.status, issue: _q.issue, q: v)))),
          FieldRow2([
            HqSelect<String>(
              label: 'Academy',
              value: _q.academy ?? '*',
              bottom: 0,
              options: [const SelectOption('*', 'All'), for (final a in academies) SelectOption(a.str('id'), a.str('name'))],
              onChanged: (v) => _set((academy: v == '*' ? null : v, status: _q.status, issue: _q.issue, q: _q.q)),
            ),
            HqSelect<String>(
              label: 'Status',
              value: _q.status,
              bottom: 0,
              searchable: false,
              options: const [SelectOption('all', 'All'), SelectOption('Running', 'Running'), SelectOption('Upcoming', 'Upcoming'), SelectOption('Ended', 'Ended')],
              onChanged: (v) => _set((academy: _q.academy, status: v, issue: _q.issue, q: _q.q)),
            ),
          ]),
        ]),
      ),
      Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: ChipRow([
          for (final (k, l, n) in [('all', 'All', d.integer('total')), ('No trainer', 'No trainer', d.integer('noTrainer')), ('Incomplete', 'Incomplete', d.integer('incomplete')), ('Outdated', 'Outdated', d.integer('outdated'))])
            HqChip(l, selected: _q.issue == k, count: n, onTap: () => _set((academy: _q.academy, status: _q.status, issue: k, q: _q.q))),
        ], scroll: true),
      ),
      if (items.isEmpty) const EmptyNote('No batches match'),
      LayoutBuilder(builder: (context, c) {
        final cols = c.maxWidth >= 900 ? 3 : c.maxWidth >= 600 ? 2 : 1;
        return Wrap(spacing: 10, runSpacing: 10, children: [
          for (final b in shown) SizedBox(width: (c.maxWidth - (cols - 1) * 10) / cols, child: _card(b, canWrite)),
        ]);
      }),
      if (items.length > _limit) Padding(padding: const EdgeInsets.only(top: 12), child: HqButton('Show more (${items.length - _limit} left)', expand: true, onPressed: () => setState(() => _limit += 12))),
    ]);
  }

  Widget _card(Map<String, dynamic> b, bool canWrite) {
    final flags = b.strings('flags');
    final st = b.str('status');
    final tone = _statusTone(st);
    final trainer = b.strOrNull('trainer');
    return HqCard(
      radius: 14,
      padding: const EdgeInsets.all(12),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(children: [
          Avatar('', tone: tone, icon: 'book'),
          const SizedBox(width: 10),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('${b.str('course')} · ${b.str('batch')}', maxLines: 1, overflow: TextOverflow.ellipsis, style: HqText.row),
              Text(b.str('academy'), maxLines: 1, overflow: TextOverflow.ellipsis, style: HqText.small),
            ]),
          ),
          Tag(st, tone: tone),
        ]),
        const SizedBox(height: 9),
        Text.rich(
          TextSpan(children: [
            if (trainer == null) TextSpan(text: 'No trainer assigned', style: HqText.muted.copyWith(color: Hq.red, fontWeight: FontWeight.w700, fontSize: 12.5)) else TextSpan(text: 'Trainer $trainer'),
            TextSpan(text: ' · ${b['start'] == null ? '' : fd(b['start'])}${b['end'] == null ? '' : ' to ${fd(b['end'])}'}${b.str('schedule').isEmpty ? '' : ' · ${b.str('schedule')}'}'),
          ]),
          style: HqText.muted.copyWith(fontSize: 12.5),
        ),
        const SizedBox(height: 9),
        Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
          Text('Enrolment', style: HqText.muted.copyWith(fontSize: 11.5)),
          Text('${b.integer('enrolled')} students', style: HqText.row.copyWith(fontSize: 11.5)),
        ]),
        if (flags.isNotEmpty) ...[
          const SizedBox(height: 9),
          Wrap(spacing: 6, runSpacing: 6, children: [for (final f in flags) Tag(f, tone: Tone.red)]),
          if (canWrite)
            Padding(
              padding: const EdgeInsets.only(top: 9),
              child: Wrap(spacing: 6, runSpacing: 6, children: [
                if (flags.contains('No trainer')) HqButton('Assign trainer', small: true, kind: BtnKind.primary, onPressed: () => _assign(b)),
                if (flags.contains('Incomplete')) HqButton('Set schedule', small: true, onPressed: () => _schedule(b)),
                if (flags.contains('Outdated')) HqButton('Mark as ended', small: true, onPressed: () => _end(b)),
              ]),
            ),
        ],
      ]),
    );
  }

  Future<void> _assign(Map<String, dynamic> b) async {
    final done = await showHqModal<bool>(context, builder: (_) => _AssignTrainer(batch: b));
    if (done == true) {
      _refresh();
      if (mounted) showToast(context, 'Trainer assigned to ${b.str('course')} ${b.str('batch')}');
    }
  }

  Future<void> _schedule(Map<String, dynamic> b) async {
    final done = await showHqModal<bool>(context, builder: (_) => _SetSchedule(batch: b));
    if (done == true) {
      _refresh();
      if (mounted) showToast(context, 'Schedule set for ${b.str('course')} ${b.str('batch')}');
    }
  }

  Future<void> _end(Map<String, dynamic> b) async {
    final ok = await confirmHq(context, title: 'Mark as ended?', body: '${b.str('course')} ${b.str('batch')} at ${b.str('academy')} stops appearing as running. Its history is kept.', confirmLabel: 'Mark as ended');
    if (!ok) return;
    try {
      await ref.read(dioClientProvider).postMap('/admin/hq/courses/batches/${b.str('id')}/end');
      _refresh();
      if (mounted) showToast(context, 'Marked as ended');
    } on ApiException catch (e) {
      if (mounted) showToast(context, e.message);
    }
  }
}

class _AssignTrainer extends ConsumerStatefulWidget {
  const _AssignTrainer({required this.batch});
  final Map<String, dynamic> batch;

  @override
  ConsumerState<_AssignTrainer> createState() => _AssignTrainerState();
}

class _AssignTrainerState extends ConsumerState<_AssignTrainer> {
  List<Map<String, dynamic>>? _options;
  String? _sel;
  String? _error;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    ref.read(dioClientProvider).getList('/admin/hq/courses/batches/${widget.batch.str('id')}/trainers').then((l) {
      if (mounted) setState(() => _options = l);
    }).catchError((Object e) {
      if (mounted) setState(() => _error = e is ApiException ? e.message : 'Could not load trainers.');
    });
  }

  Future<void> _go() async {
    if (_sel == null) return setState(() => _error = 'Choose a trainer.');
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await ref.read(dioClientProvider).postMap('/admin/hq/courses/batches/${widget.batch.str('id')}/trainer', body: {'membershipId': _sel});
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
    final b = widget.batch;
    return ModalFrame(
      title: 'Assign trainer',
      sub: '${b.str('course')} · ${b.str('batch')} · ${b.str('academy')}',
      error: _error,
      actions: [
        HqButton('Cancel', onPressed: () => Navigator.of(context).pop()),
        HqButton('Assign', kind: BtnKind.primary, busy: _busy, onPressed: _go),
      ],
      children: [
        if (_options == null && _error == null)
          const Padding(padding: EdgeInsets.all(20), child: Center(child: CircularProgressIndicator(color: Hq.primary, strokeWidth: 2.5)))
        else if (_options != null && _options!.isEmpty)
          const EmptyNote('This academy has no active trainers yet')
        else if (_options != null)
          HqSelect<String>(label: 'Trainer', value: _sel, hint: 'Choose a trainer', options: [for (final t in _options!) SelectOption(t.str('id'), t.str('name'))], onChanged: (v) => setState(() => _sel = v)),
      ],
    );
  }
}

const _days = [('MONDAY', 'Mon'), ('TUESDAY', 'Tue'), ('WEDNESDAY', 'Wed'), ('THURSDAY', 'Thu'), ('FRIDAY', 'Fri'), ('SATURDAY', 'Sat'), ('SUNDAY', 'Sun')];

List<SelectOption<String>> _times() => [
      for (var m = 6 * 60; m <= 22 * 60; m += 30)
        SelectOption(
          '${(m ~/ 60).toString().padLeft(2, '0')}:${(m % 60).toString().padLeft(2, '0')}',
          '${(m ~/ 60) % 12 == 0 ? 12 : (m ~/ 60) % 12}:${(m % 60).toString().padLeft(2, '0')} ${m ~/ 60 < 12 ? 'am' : 'pm'}',
        ),
    ];

class _SetSchedule extends ConsumerStatefulWidget {
  const _SetSchedule({required this.batch});
  final Map<String, dynamic> batch;

  @override
  ConsumerState<_SetSchedule> createState() => _SetScheduleState();
}

class _SetScheduleState extends ConsumerState<_SetSchedule> {
  final Set<String> _sel = {};
  String _start = '17:00';
  String _end = '18:00';
  String? _error;
  bool _busy = false;

  Future<void> _go() async {
    if (_sel.isEmpty) return setState(() => _error = 'Pick at least one day.');
    if (_end.compareTo(_start) <= 0) return setState(() => _error = 'The class must end after it starts.');
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await ref.read(dioClientProvider).postMap('/admin/hq/courses/batches/${widget.batch.str('id')}/schedule', body: {'days': _sel.toList(), 'start': _start, 'end': _end});
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
    final b = widget.batch;
    final times = _times();
    return ModalFrame(
      title: 'Set schedule',
      sub: '${b.str('course')} · ${b.str('batch')} · ${b.str('academy')}',
      error: _error,
      actions: [
        HqButton('Cancel', onPressed: () => Navigator.of(context).pop()),
        HqButton('Save schedule', kind: BtnKind.primary, busy: _busy, onPressed: _go),
      ],
      children: [
        Text('DAYS', style: HqText.th),
        const SizedBox(height: 8),
        Wrap(spacing: 8, runSpacing: 8, children: [
          for (final (k, l) in _days) HqChip(l, selected: _sel.contains(k), onTap: () => setState(() => _sel.contains(k) ? _sel.remove(k) : _sel.add(k))),
        ]),
        const SizedBox(height: 14),
        FieldRow2([
          HqSelect<String>(label: 'Starts', value: _start, options: times, onChanged: (v) => setState(() => _start = v)),
          HqSelect<String>(label: 'Ends', value: _end, options: times, onChanged: (v) => setState(() => _end = v)),
        ]),
      ],
    );
  }
}
