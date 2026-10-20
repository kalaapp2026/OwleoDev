import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/theme.dart';
import '../../core/api/api_exception.dart';
import '../../core/auth/session.dart';
import '../../core/format.dart';
import '../../core/json.dart';
import '../../core/links.dart';
import '../../core/ui/async.dart';
import '../../core/ui/controls.dart';
import '../../core/ui/icons.dart';
import '../../core/ui/layout.dart';
import '../../core/ui/overlays.dart';
import '../../core/ui/primitives.dart';
import '../shell/nav.dart';

typedef EventQuery = ({String when, String? day, String q});

final eventsProvider = FutureProvider.autoDispose.family<Map<String, dynamic>, EventQuery>(
  (ref, q) => ref.watch(dioClientProvider).getMap('/admin/hq/events', query: {'when': q.when, 'day': ?q.day, if (q.q.trim().isNotEmpty) 'q': q.q.trim()}),
);

final eventProvider = FutureProvider.autoDispose.family<Map<String, dynamic>, String>(
  (ref, id) => ref.watch(dioClientProvider).getMap('/admin/hq/events/$id'),
);

const _stateTone = {'Cancelled': Tone.red, 'Paused': Tone.coral, 'Draft': Tone.mute, 'Completed': Tone.mute, 'Today': Tone.green, 'Scheduled': Tone.blue};

String _typeLabel(String t) => t == 'LOOKING_FOR_ARTIST' ? 'Looking for artist' : 'Programme';

String dayLabel(DateTime d) {
  final now = DateTime.now();
  final today = DateTime(now.year, now.month, now.day);
  final diff = DateTime(d.year, d.month, d.day).difference(today).inDays;
  if (diff == 0) return 'Today';
  if (diff == 1) return 'Tomorrow';
  const wd = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
  return '${wd[d.weekday - 1]}, ${fdShort(d)}';
}

String _time(String hhmm) {
  final p = hhmm.split(':');
  final h = int.parse(p[0]);
  return '${h % 12 == 0 ? 12 : h % 12}:${p[1]} ${h < 12 ? 'am' : 'pm'}';
}

/// Events: everything scheduled across academies, with the power to pause or cancel one.
class EventsScreen extends ConsumerStatefulWidget {
  const EventsScreen({super.key});

  @override
  ConsumerState<EventsScreen> createState() => _EventsScreenState();
}

class _EventsScreenState extends ConsumerState<EventsScreen> {
  EventQuery _q = (when: 'upcoming', day: null, q: '');
  Map<String, dynamic>? _last;

  void _refresh() {
    ref.invalidate(eventsProvider);
    ref.invalidate(eventProvider);
  }

  @override
  Widget build(BuildContext context) {
    final data = ref.watch(eventsProvider(_q));
    if (data.hasValue) _last = data.value;
    final d = data.valueOrNull ?? _last;
    if (d == null) return asyncBody(data, onRetry: _refresh, data: (_) => const SizedBox.shrink());
    final items = d.maps('items');
    String? last;

    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      HqGrid(GridKind.g4, [
        Kpi(icon: 'pulse', tone: Tone.green, label: 'Happening today', value: '${d.integer('today')}', foot: 'published events'),
        Kpi(icon: 'cal', tone: Tone.primary, label: 'Next 7 days', value: '${d.integer('week')}', foot: 'scheduled events'),
        Kpi(icon: 'heart', tone: Tone.blue, label: 'Interested', value: num0(d.integer('interested')), foot: 'across ${d.integer('upcoming')} upcoming'),
        Kpi(icon: 'warn', tone: Tone.gold, label: 'Needs attention', value: '${d.integer('attention')}', foot: 'paused by HQ'),
      ]),
      HqCard(
        padding: const EdgeInsets.all(12),
        margin: const EdgeInsets.only(bottom: 12),
        child: Row(children: [
          Expanded(child: SearchBox(hint: 'Search event, academy, venue or type', initial: _q.q, onChanged: (v) => setState(() => _q = (when: _q.when, day: _q.day, q: v)))),
          const SizedBox(width: 8),
          HqIconButton('cal', tooltip: 'Pick a date', onTap: () async {
            final days = d.obj('days');
            final picked = await pickHqDate(context, initial: DateTime.now(), first: DateTime.now().subtract(const Duration(days: 365)), last: DateTime.now().add(const Duration(days: 365)));
            if (picked != null) {
              setState(() => _q = (when: 'all', day: '${picked.year}-${picked.month.toString().padLeft(2, '0')}-${picked.day.toString().padLeft(2, '0')}', q: _q.q));
              if (days.isEmpty && context.mounted) showToast(context, 'Showing events on that date');
            }
          }),
        ]),
      ),
      Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: SegControl<String>(
          expand: true,
          items: const [('upcoming', 'Upcoming'), ('today', 'Today'), ('past', 'Past'), ('all', 'All')],
          value: _q.when,
          onChanged: (v) => setState(() => _q = (when: v, day: null, q: _q.q)),
        ),
      ),
      if (_q.day != null)
        Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: Align(alignment: Alignment.centerLeft, child: HqButton('${fd(_q.day)}  ✕', small: true, color: Hq.gold, onPressed: () => setState(() => _q = (when: 'upcoming', day: null, q: _q.q)))),
        ),
      if (items.isEmpty) const EmptyNote('No events here'),
      for (final e in items) ...[
        Builder(builder: (_) {
          final date = toDate(e['date']) ?? DateTime.now();
          final label = dayLabel(date);
          final header = label != last;
          last = label;
          return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            if (header) Padding(padding: const EdgeInsets.fromLTRB(2, 10, 2, 8), child: Text(label.toUpperCase(), style: HqText.th)),
            Padding(padding: const EdgeInsets.only(bottom: 10), child: _card(e)),
          ]);
        }),
      ],
      Padding(padding: const EdgeInsets.fromLTRB(2, 14, 2, 0), child: Text('Events come from academies. Interest is the only audience signal Owleo records today: there is no ticketing yet, so no sales or commission to show.', style: HqText.sub)),
    ]);
  }

  Widget _card(Map<String, dynamic> e) {
    final st = e.str('state');
    return HqCard(
      radius: 14,
      padding: const EdgeInsets.all(12),
      onTap: () => showEventDrawer(context, ref, e.str('id')),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(children: [
          const Avatar('', tone: Tone.blue, icon: 'cal'),
          const SizedBox(width: 10),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(e.str('title'), maxLines: 1, overflow: TextOverflow.ellipsis, style: HqText.row),
              Text('${_time(e.str('time'))} · ${e.str('academy')}${e.strOrNull('venue') == null ? '' : ' · ${e.str('venue')}'}', maxLines: 1, overflow: TextOverflow.ellipsis, style: HqText.small),
            ]),
          ),
        ]),
        const SizedBox(height: 9),
        Wrap(spacing: 6, runSpacing: 6, crossAxisAlignment: WrapCrossAlignment.center, children: [
          Tag(st, tone: _stateTone[st] ?? Tone.mute),
          Tag(_typeLabel(e.str('type')), tone: Tone.mute),
          Tag(e.flag('public') ? 'Public' : 'In-house', tone: e.flag('public') ? Tone.primary : Tone.mute),
          Text('${e.integer('interested')} interested', style: HqText.sub.copyWith(fontSize: 11.5)),
        ]),
      ]),
    );
  }
}

Future<void> showEventDrawer(BuildContext context, WidgetRef ref, String id) => showHqDrawer(context, builder: (_) => _EventDrawer(id: id));

class _EventDrawer extends ConsumerStatefulWidget {
  const _EventDrawer({required this.id});
  final String id;

  @override
  ConsumerState<_EventDrawer> createState() => _EventDrawerState();
}

class _EventDrawerState extends ConsumerState<_EventDrawer> {
  String? _mode; // pause | cancel
  final _reason = TextEditingController();
  String? _error;
  bool _busy = false;

  @override
  void dispose() {
    _reason.dispose();
    super.dispose();
  }

  Future<void> _call(Future<void> Function() f, String ok) async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await f();
      ref.invalidate(eventsProvider);
      ref.invalidate(eventProvider);
      if (mounted) {
        setState(() => _mode = null);
        _reason.clear();
        showToast(context, ok);
      }
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final detail = ref.watch(eventProvider(widget.id));
    return detail.when(
      loading: () => const Center(child: CircularProgressIndicator(color: Hq.primary, strokeWidth: 2.5)),
      error: (e, _) => Padding(padding: const EdgeInsets.all(24), child: HqError(e is ApiException ? e.message : 'Could not load this event.')),
      data: (e) {
        final st = e.str('state');
        final start = toDate(e['start']) ?? DateTime.now();
        final end = toDate(e['end']);
        final canWrite = ref.watch(sessionProvider).user?.canWrite ?? false;
        final upcoming = !start.isBefore(DateTime.now().subtract(const Duration(hours: 24))) && st != 'Cancelled' && st != 'Completed';
        final log = e.maps('log');
        final dio = ref.read(dioClientProvider);
        final id = widget.id;
        final maps = e.strOrNull('mapsUrl');

        Widget kv(String k, String v) => KeyValueRow(k, v);
        return DrawerShell(
          coverColors: const [Color(0xFF1E4D5C), Color(0xFF1E3A5C), Color(0xFF1E2A4D)],
          logo: DrawerLogo('', color: (_stateTone[st] ?? Tone.blue).color, icon: 'cal'),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Wrap(spacing: 6, runSpacing: 6, children: [
              Tag(st, tone: _stateTone[st] ?? Tone.mute),
              Tag(_typeLabel(e.str('type')), tone: Tone.mute),
              Tag(e.flag('public') ? 'Public' : 'In-house', tone: e.flag('public') ? Tone.primary : Tone.mute),
            ]),
            const SizedBox(height: 8),
            Text(e.str('title'), style: HqText.h2.copyWith(fontSize: 19)),
            const SizedBox(height: 3),
            Text('${dayLabel(start)}, ${fd(start)} · ${_time('${start.hour.toString().padLeft(2, '0')}:${start.minute.toString().padLeft(2, '0')}')}', style: HqText.muted.copyWith(fontSize: 12.5)),
            if (st == 'Paused') Padding(padding: const EdgeInsets.only(top: 12), child: HqCard(padding: const EdgeInsets.all(12), child: Row(children: [ic('warn', 13, Hq.gold), const SizedBox(width: 8), Expanded(child: Text('Paused by HQ. Hidden from the feed until resumed.', style: HqText.muted.copyWith(color: Hq.gold, fontSize: 12.5)))]))),
            HqCard(
              margin: const EdgeInsets.only(top: 14),
              child: HqList([
                HqRow(title: e.str('academy'), sub: 'Host', trailing: HqButton('Open', small: true, onPressed: () {
                  Navigator.of(context).pop();
                  hqGo(context, '/academies?open=${e.str('academyId')}');
                })),
                HqRow(title: '${e.integer('interested')} interested', sub: 'People who marked interest in this event'),
              ]),
            ),
            if (e.strOrNull('description') != null) _section('About', [Padding(padding: const EdgeInsets.symmetric(vertical: 4), child: Text(e.str('description'), style: HqText.muted.copyWith(fontSize: 13, height: 1.5)))]),
            _section('Schedule', [
              kv('Date', '${dayLabel(start)}, ${fd(start)}'),
              kv('Starts', _time('${start.hour.toString().padLeft(2, '0')}:${start.minute.toString().padLeft(2, '0')}')),
              if (end != null) kv('Ends', _time('${end.hour.toString().padLeft(2, '0')}:${end.minute.toString().padLeft(2, '0')}')),
              if (e['interestDeadline'] != null) kv('Interest closes', fd(e['interestDeadline'])),
            ]),
            _section('Venue', [
              kv('Where', e.strOrNull('venue') ?? 'Not given'),
              if (maps != null) Padding(padding: const EdgeInsets.only(top: 8), child: Align(alignment: Alignment.centerLeft, child: HqButton('Open in Google Maps', icon: 'pin', small: true, onPressed: () => openUrl(maps)))),
            ]),
            _section('Audience', [kv('Who sees it', _audience(e.str('audience'))), kv('Visibility', e.flag('public') ? 'Public, on the Social feed' : 'In-house, not on the Social feed')]),
            if (log.isNotEmpty) _section('History', [for (final m in log) HqRow(title: m.str('x'), wrap: true, sub: '${m.str('who')} · ${ago(m['at'])}', titleStyle: HqText.row.copyWith(fontSize: 12.5, fontWeight: FontWeight.w600))]),
            const SizedBox(height: 12),
            if (!canWrite)
              HqCard(padding: const EdgeInsets.all(12), child: Row(children: [ic('lock', 13, Hq.muted), const SizedBox(width: 8), Expanded(child: Text('Your role can view events but not change them.', style: HqText.muted.copyWith(fontSize: 12.5)))]))
            else if (upcoming && _mode != null)
              HqCard(
                child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                  CardHeader(_mode == 'cancel' ? 'Cancel event' : 'Pause event', sub: _mode == 'cancel' ? 'It is cancelled for everyone and stays visible, greyed out' : 'Hidden from the feed until you resume it', bottom: 8),
                  HqField(label: 'Reason', controller: _reason, hint: 'Why'),
                  if (_error != null) Padding(padding: const EdgeInsets.only(bottom: 8), child: Text(_error!, style: HqText.small.copyWith(color: Hq.red))),
                  Row(children: [
                    Expanded(child: HqButton('Back', expand: true, onPressed: () => setState(() {
                          _mode = null;
                          _error = null;
                        }))),
                    const SizedBox(width: 8),
                    Expanded(child: HqButton('Confirm', kind: _mode == 'cancel' ? BtnKind.danger : BtnKind.primary, expand: true, busy: _busy, onPressed: () => _call(
                          () async => await dio.postMap('/admin/hq/events/$id/${_mode == 'cancel' ? 'cancel' : 'pause'}', body: {'reason': _reason.text.trim()}),
                          _mode == 'cancel' ? 'Event cancelled' : 'Event paused'))),
                  ]),
                ]),
              )
            else if (upcoming)
              Row(children: [
                Expanded(child: st == 'Paused' ? HqButton('Resume event', kind: BtnKind.primary, expand: true, busy: _busy, onPressed: () => _call(() async => await dio.postMap('/admin/hq/events/$id/resume'), 'Event resumed')) : HqButton('Pause', expand: true, onPressed: () => setState(() => _mode = 'pause'))),
                const SizedBox(width: 8),
                Expanded(child: HqButton('Cancel event', expand: true, color: Hq.red, onPressed: () => setState(() => _mode = 'cancel'))),
              ]),
          ]),
        );
      },
    );
  }

  Widget _section(String title, List<Widget> rows) => HqCard(
        margin: const EdgeInsets.only(top: 12),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [CardHeader(title, bottom: 6), HqList(rows)]),
      );

  String _audience(String a) => switch (a) {
        'ALL_STUDENTS' => 'All students',
        'ALL_TRAINERS' => 'All trainers',
        'EVERYONE' => 'Everyone in the academy',
        'BY_COURSE' => 'Selected courses',
        'BY_BATCH' => 'Selected batches',
        'INDIVIDUALS' => 'Selected people',
        _ => a,
      };
}
