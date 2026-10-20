import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/theme.dart';
import '../../core/api/api_exception.dart';
import '../../core/api/dio_client.dart';
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
import '../shell/shell_data.dart';
import '../users/users_screen.dart' show FieldRow2;

typedef ArtistQuery = ({String f, String q});

final artistsProvider = FutureProvider.autoDispose.family<Map<String, dynamic>, ArtistQuery>(
  (ref, q) => ref.watch(dioClientProvider).getMap('/admin/hq/artists', query: {'f': q.f, if (q.q.trim().isNotEmpty) 'q': q.q.trim()}),
);

final artistProvider = FutureProvider.autoDispose.family<Map<String, dynamic>, String>(
  (ref, id) => ref.watch(dioClientProvider).getMap('/admin/hq/artists/$id'),
);

void refreshArtists(WidgetRef ref) {
  ref.invalidate(artistsProvider);
  ref.invalidate(artistProvider);
  ref.invalidate(badgesProvider);
}

const _status = {
  'pending': ('Pending', Tone.gold),
  'info': ('More info asked', Tone.blue),
  'approved': ('Approved', Tone.green),
  'rejected': ('Rejected', Tone.red),
  'suspended': ('Suspended', Tone.coral),
  'banned': ('Rejected for good', Tone.red),
};
const _platform = {
  'instagram': ('Instagram', Tone.magenta),
  'youtube': ('YouTube', Tone.red),
  'facebook': ('Facebook', Tone.blue),
  'x': ('X', Tone.mute),
  'spotify': ('Spotify', Tone.green),
  'website': ('Website', Tone.gold),
};

String _profileUrl(String pl, String h) {
  final handle = h.replaceFirst('@', '');
  final n = handle.replaceAll(RegExp(r'\s+'), '');
  return switch (pl) {
    'instagram' => 'https://www.instagram.com/$n/',
    'youtube' => 'https://www.youtube.com/@$n',
    'facebook' => 'https://www.facebook.com/$n',
    'x' => 'https://x.com/$n',
    'spotify' => 'https://open.spotify.com/search/${Uri.encodeComponent(handle)}',
    _ => handle.startsWith('http') ? handle : 'https://$handle',
  };
}

/// Artist verification: check a Guest's profiles, then allow them to post, and moderate afterwards.
class ArtistsScreen extends ConsumerStatefulWidget {
  const ArtistsScreen({super.key});

  @override
  ConsumerState<ArtistsScreen> createState() => _ArtistsScreenState();
}

class _ArtistsScreenState extends ConsumerState<ArtistsScreen> {
  ArtistQuery _q = (f: 'pending', q: '');
  Map<String, dynamic>? _last;

  @override
  Widget build(BuildContext context) {
    final data = ref.watch(artistsProvider(_q));
    if (data.hasValue) _last = data.value;
    final d = data.valueOrNull ?? _last;
    if (d == null) return asyncBody(data, onRetry: () => ref.invalidate(artistsProvider), data: (_) => const SizedBox.shrink());
    final canWrite = ref.watch(sessionProvider).user?.canWrite ?? false;
    final items = d.maps('items');

    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      HqGrid(GridKind.g4, [
        Kpi(icon: 'shield', tone: Tone.gold, label: 'Waiting for review', value: '${d.integer('pending')}', foot: 'oldest first below'),
        Kpi(icon: 'check', tone: Tone.green, label: 'Verified artists', value: '${d.integer('approved')}', foot: 'can post in Social'),
        Kpi(icon: 'flag', tone: Tone.coral, label: 'Open reports', value: '${d.integer('openReports')}', foot: 'on verified artists'),
        Kpi(icon: 'lock', tone: Tone.red, label: 'Suspended or rejected', value: '${d.integer('suspended') + d.integer('banned')}', foot: '${d.integer('suspended')} suspended, ${d.integer('banned')} no access'),
      ]),
      HqCard(
        padding: const EdgeInsets.all(12),
        margin: const EdgeInsets.only(bottom: 12),
        child: SearchBox(hint: 'Search name, art form, city or request number', initial: _q.q, onChanged: (v) => setState(() => _q = (f: _q.f, q: v))),
      ),
      Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: SegControl<String>(
          expand: true,
          dense: true,
          items: const [('pending', 'Pending'), ('approved', 'Approved'), ('suspended', 'Suspended'), ('closed', 'Rejected'), ('all', 'All')],
          value: _q.f,
          onChanged: (v) => setState(() => _q = (f: v, q: _q.q)),
        ),
      ),
      if (!canWrite)
        HqCard(
          margin: const EdgeInsets.only(bottom: 12),
          padding: const EdgeInsets.all(12),
          child: Row(children: [ic('lock', 13, Hq.muted), const SizedBox(width: 8), Expanded(child: Text('Your role can view requests but not decide them.', style: HqText.muted.copyWith(fontSize: 12.5)))]),
        ),
      if (items.isEmpty) const EmptyNote('No requests here'),
      LayoutBuilder(builder: (context, c) {
        final cols = c.maxWidth >= 900 ? 3 : c.maxWidth >= 600 ? 2 : 1;
        return Wrap(spacing: 10, runSpacing: 10, children: [
          for (final a in items) SizedBox(width: (c.maxWidth - (cols - 1) * 10) / cols, child: _card(a)),
        ]);
      }),
      Padding(padding: const EdgeInsets.fromLTRB(2, 14, 2, 0), child: Text('Approval lets the artist post in Owleo Social. Follower counts come from the profile as submitted.', style: HqText.sub)),
    ]);
  }

  Widget _card(Map<String, dynamic> a) {
    final (sl, st) = _status[a.str('status')] ?? ('', Tone.mute);
    final days = a.integer('days');
    final reports = a.integer('openReports');
    final strikes = a.integer('strikes');
    return HqCard(
      radius: 14,
      padding: const EdgeInsets.all(12),
      onTap: () => showArtistDrawer(context, ref, a.str('id')),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(children: [
          Avatar(initials(a.str('name')), tone: Tone.violet),
          const SizedBox(width: 10),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(a.str('name'), maxLines: 1, overflow: TextOverflow.ellipsis, style: HqText.row),
              Text('${a.str('ref')} · ${a.str('form')}${a.str('city').isEmpty ? '' : ' · ${a.str('city')}'}', maxLines: 1, overflow: TextOverflow.ellipsis, style: HqText.small),
            ]),
          ),
        ]),
        const SizedBox(height: 9),
        Wrap(spacing: 6, runSpacing: 6, crossAxisAlignment: WrapCrossAlignment.center, children: [
          Tag(sl, tone: st),
          for (final p in a.strings('platforms')) Tag(_platform[p]?.$1 ?? p, tone: _platform[p]?.$2 ?? Tone.mute),
          if (a.flag('minor')) const Tag('Under 18', tone: Tone.violet),
          if (a.str('status') == 'approved' && reports > 0) Tag('$reports report${reports > 1 ? 's' : ''}', tone: Tone.coral),
          if (strikes > 0 && a.str('status') != 'banned') Tag('$strikes of 3 chances used', tone: Tone.mute),
          Text(days == 0 ? 'Today' : '${days}d', style: HqText.sub.copyWith(fontSize: 11.5)),
        ]),
      ]),
    );
  }
}

Future<void> showArtistDrawer(BuildContext context, WidgetRef ref, String id) => showHqDrawer(context, builder: (_) => _ArtistDrawer(id: id));

class _ArtistDrawer extends ConsumerStatefulWidget {
  const _ArtistDrawer({required this.id});
  final String id;

  @override
  ConsumerState<_ArtistDrawer> createState() => _ArtistDrawerState();
}

class _ArtistDrawerState extends ConsumerState<_ArtistDrawer> {
  String? _mode; // approve | reject | info | suspend | report | uphold:<id> | ban | edit
  final _note = TextEditingController();
  final _by = TextEditingController();
  String _role = 'User';
  String? _category;
  bool _post = true, _events = true;
  String? _error;
  bool _busy = false;

  @override
  void dispose() {
    _note.dispose();
    _by.dispose();
    super.dispose();
  }

  Future<void> _run(Future<dynamic> Function() f, String ok, {bool resetMode = true}) async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final r = await f();
      refreshArtists(ref);
      if (!mounted) return;
      if (resetMode) {
        _mode = null;
        _note.clear();
        _by.clear();
      }
      showToast(context, r is Map && r['message'] != null ? r['message'].toString() : ok);
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final detail = ref.watch(artistProvider(widget.id));
    return detail.when(
      loading: () => const Center(child: CircularProgressIndicator(color: Hq.primary, strokeWidth: 2.5)),
      error: (e, _) => Padding(padding: const EdgeInsets.all(24), child: HqError(e is ApiException ? e.message : 'Could not load this request.')),
      data: (a) => DrawerShell(
        coverColors: const [Color(0xFF4C3A8F), Color(0xFF2B3470), Color(0xFF1E2A4D)],
        logo: const DrawerLogo('', color: Hq.violet, icon: 'shield'),
        child: _body(a),
      ),
    );
  }

  Widget _body(Map<String, dynamic> a) {
    final canWrite = ref.watch(sessionProvider).user?.canWrite ?? false;
    final dio = ref.read(dioClientProvider);
    final id = widget.id;
    final status = a.str('status');
    final open = status == 'pending' || status == 'info';
    final (sl, st) = _status[status] ?? ('', Tone.mute);
    final profiles = a.maps('profiles');
    final okCount = profiles.where((p) => p.str('s') == 'ok').length;
    final checklist = a.maps('checklist');
    final reports = a.maps('reports');
    final log = a.maps('log');
    final strikes = a.integer('strikes');

    Widget card(String title, String sub, Widget child, {Widget? trailing}) => HqCard(
          margin: const EdgeInsets.only(top: 12),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [CardHeader(title, sub: sub, bottom: 6, trailing: trailing), child]),
        );

    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Wrap(spacing: 6, runSpacing: 6, children: [
        Tag(sl, tone: st),
        if (a.flag('minor')) const Tag('Under 18', tone: Tone.violet),
        if (status == 'approved') ...[
          Tag(a.flag('canPost') ? 'Can post' : 'No posting', tone: a.flag('canPost') ? Tone.green : Tone.mute),
          Tag(a.flag('canEvents') ? 'Can host events' : 'No events', tone: a.flag('canEvents') ? Tone.green : Tone.mute),
        ],
      ]),
      if (status == 'suspended' || status == 'banned')
        Padding(
          padding: const EdgeInsets.only(top: 12),
          child: HqCard(
            padding: const EdgeInsets.all(12),
            child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              ic('lock', 13, status == 'banned' ? Hq.red : Hq.coral),
              const SizedBox(width: 8),
              Expanded(child: Text(status == 'banned' ? 'Rejected for good. No access to Social posting or events, and this artist cannot apply again.' : 'Suspended. Posting and events are off until you reinstate access.', style: HqText.muted.copyWith(fontSize: 12.5, color: status == 'banned' ? Hq.red : Hq.coral))),
            ]),
          ),
        ),
      const SizedBox(height: 10),
      Text(a.str('name'), style: HqText.h2.copyWith(fontSize: 19)),
      const SizedBox(height: 3),
      Text('${a.str('ref')} · ${a.str('form')}${a.str('city').isEmpty ? '' : ' · ${a.str('city')}'}', style: HqText.muted.copyWith(fontSize: 12.5)),
      if (a.strOrNull('bio') != null) Padding(padding: const EdgeInsets.only(top: 10), child: Text(a.str('bio'), style: HqText.muted.copyWith(fontSize: 13))),
      if (a.strOrNull('note') != null && (status == 'info' || status == 'rejected'))
        Padding(padding: const EdgeInsets.only(top: 10), child: Text('${status == 'info' ? 'Asked' : 'Reason'}: ${a.str('note')}', style: HqText.muted.copyWith(fontSize: 12.5, color: Hq.gold))),

      card(
        'Linked profiles',
        '$okCount of ${profiles.length} confirmed as theirs',
        profiles.isEmpty
            ? const EmptyNote('No profiles linked yet', padding: 12)
            : HqList([
                for (final (i, p) in profiles.indexed)
                  _profileRow(a, p, i, open && canWrite, dio),
              ]),
        trailing: open && canWrite ? HqButton('Add details', icon: 'edit', small: true, onPressed: () => setState(() => _mode = _mode == 'edit' ? null : 'edit')) : null,
      ),
      if (_mode == 'edit') _EditDetails(artist: a, onDone: () => setState(() => _mode = null)),

      if (open)
        card(
          'Review checklist',
          'Starred items are needed to approve',
          HqList([
            for (final c in checklist)
              HqCheckRow(
                checked: c.flag('done'),
                title: '${c.str('label')}${c.flag('required') ? ' *' : ''}',
                onChanged: canWrite ? (v) => _run(() => dio.putMap('/admin/hq/artists/$id/checklist/${c.str('key')}', body: {'done': v}), '', resetMode: false) : null,
              ),
            if (a.flag('minor'))
              HqCheckRow(
                checked: a.flag('guardian'),
                title: 'Guardian consent on file *',
                sub: 'Under 18. A parent or guardian must agree before posting or events.',
                onChanged: canWrite ? (v) => _run(() => dio.putMap('/admin/hq/artists/$id/guardian', body: {'done': v}), '', resetMode: false) : null,
              ),
          ]),
        ),

      if (status == 'approved' && canWrite)
        card(
          'Access',
          'What this artist can do in Owleo Social',
          HqList([
            HqRow(title: 'Post in Social', trailing: HqSwitch(value: a.flag('canPost'), onChanged: (v) => _run(() => dio.putMap('/admin/hq/artists/$id/access/post', body: {'on': v}), '', resetMode: false))),
            HqRow(title: 'Create events', sub: 'Recorded for when artists can host events', trailing: HqSwitch(value: a.flag('canEvents'), onChanged: (v) => _run(() => dio.putMap('/admin/hq/artists/$id/access/events', body: {'on': v}), '', resetMode: false))),
          ]),
        ),

      if (status == 'approved' || status == 'suspended' || status == 'banned' || strikes > 0)
        card(
          'Chances',
          '$strikes of 3 used. A third upheld report rejects the artist for good.',
          Row(children: [
            for (var i = 0; i < 3; i++) Expanded(child: Container(height: 10, margin: EdgeInsets.only(right: i < 2 ? 8 : 0), decoration: BoxDecoration(color: i < strikes ? (strikes >= 3 ? Hq.red : Hq.coral) : Hq.high, borderRadius: BorderRadius.circular(6)))),
          ]),
        ),

      if (reports.isNotEmpty)
        card(
          'Reports',
          '${reports.where((r) => r.str('st') == 'open').length} open of ${reports.length}',
          HqList([
            for (final r in reports)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                  Wrap(spacing: 6, runSpacing: 6, crossAxisAlignment: WrapCrossAlignment.center, children: [
                    Tag(const {'open': 'Open', 'upheld': 'Upheld', 'dismissed': 'Dismissed'}[r.str('st')] ?? '', tone: const {'open': Tone.gold, 'upheld': Tone.red, 'dismissed': Tone.mute}[r.str('st')] ?? Tone.mute),
                    Tag(r.str('cat'), tone: Tone.mute),
                    Text(ago(r['at']), style: HqText.sub.copyWith(fontSize: 11.5)),
                  ]),
                  const SizedBox(height: 6),
                  Text(r.str('x'), style: HqText.body.copyWith(fontSize: 13)),
                  Text('${r.str('by')} · ${r.str('role')}', style: HqText.small),
                  if (r.strOrNull('note') != null) Text('Decision note: ${r.str('note')}', style: HqText.small),
                  if (r.str('st') == 'open' && canWrite && status == 'approved')
                    Padding(
                      padding: const EdgeInsets.only(top: 8),
                      child: Row(children: [
                        Expanded(child: HqButton('Dismiss', small: true, expand: true, onPressed: () => _run(() => dio.postMap('/admin/hq/artists/$id/reports/${r.str('id')}/dismiss', body: {'note': ''}), 'Report dismissed'))),
                        const SizedBox(width: 8),
                        Expanded(child: HqButton('Uphold', small: true, expand: true, color: Hq.red, onPressed: () => setState(() => _mode = 'uphold:${r.str('id')}'))),
                      ]),
                    ),
                ]),
              ),
          ]),
        ),

      card('History', 'Newest first', log.isEmpty ? const EmptyNote('Nothing yet', padding: 12) : HqList([for (final m in log.take(10)) HqRow(title: m.str('x'), wrap: true, sub: '${m.str('who')} · ${ago(m['at'])}', titleStyle: HqText.row.copyWith(fontSize: 12.5, fontWeight: FontWeight.w600))])),

      if (canWrite) _actions(a, open),
    ]);
  }

  Widget _profileRow(Map<String, dynamic> a, Map<String, dynamic> p, int i, bool canCheck, DioClient dio) {
    final (pn, pt) = _platform[p.str('pl')] ?? (p.str('pl'), Tone.mute);
    final s = p.str('s');
    final (label, tone) = switch (s) { 'ok' => ('Verified', Tone.green), 'bad' => ('Does not match', Tone.red), _ => ('To check', Tone.gold) };
    final url = _profileUrl(p.str('pl'), p.str('h'));
    return HqRow(
      title: p.str('h'),
      wrap: true,
      leading: Tag(pn, tone: pt),
      sub: '${p.str('f')}${p.str('m') != 'Not yet' && p.str('m').isNotEmpty ? ' · ${p.str('m')}' : ''}${p.strOrNull('note') == null ? '' : '\n${p.str('note')}'}\n${url.replaceFirst(RegExp(r'^https://(www\.)?'), '')}',
      trailing: Column(crossAxisAlignment: CrossAxisAlignment.end, mainAxisSize: MainAxisSize.min, children: [
        Tag(label, tone: tone),
        if (canCheck) ...[
          const SizedBox(height: 6),
          Row(mainAxisSize: MainAxisSize.min, children: [
            HqButton('Open', small: true, onPressed: () => openUrl(url)),
            const SizedBox(width: 6),
            if (s != 'ok') HqButton('Verify', small: true, onPressed: () async {
                  final m = await showHqModal<String>(context, builder: (_) => const _VerifyMethod());
                  if (m != null) _run(() => dio.putMap('/admin/hq/artists/${widget.id}/profiles/$i', body: {'state': 'ok', 'method': m}), 'Confirmed', resetMode: false);
                }),
            if (s == 'ok' || s == 'bad') HqButton('Undo', small: true, onPressed: () => _run(() => dio.putMap('/admin/hq/artists/${widget.id}/profiles/$i', body: {'state': 'pending'}), '', resetMode: false)),
            if (s == 'pending') ...[
              const SizedBox(width: 6),
              HqButton('No match', small: true, color: Hq.red, onPressed: () async {
                final note = await showHqModal<String>(context, builder: (_) => const _NoMatch());
                if (note != null) _run(() => dio.putMap('/admin/hq/artists/${widget.id}/profiles/$i', body: {'state': 'bad', 'note': note}), 'Flagged', resetMode: false);
              }),
            ],
          ]),
        ],
      ]),
    );
  }

  Widget _formCard(String title, String sub, List<Widget> fields, String confirm, Future<void> Function() go) => HqCard(
        margin: const EdgeInsets.only(top: 12),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          CardHeader(title, sub: sub, bottom: 8),
          ...fields,
          if (_error != null) Padding(padding: const EdgeInsets.only(bottom: 8), child: Text(_error!, style: HqText.small.copyWith(color: Hq.red))),
          Row(children: [
            Expanded(child: HqButton('Cancel', expand: true, onPressed: () => setState(() {
                  _mode = null;
                  _error = null;
                }))),
            const SizedBox(width: 8),
            Expanded(child: HqButton(confirm, kind: BtnKind.primary, expand: true, busy: _busy, onPressed: go)),
          ]),
        ]),
      );

  Widget _actions(Map<String, dynamic> a, bool open) {
    final dio = ref.read(dioClientProvider);
    final id = widget.id;
    final status = a.str('status');
    final m = _mode;
    final next = a.integer('strikes') + 1;
    if (m == 'approve') {
      return _formCard('Approve', 'Choose what the artist can do', [
        HqList([
          HqRow(title: 'Post in Social', trailing: HqSwitch(value: _post, onChanged: (v) => setState(() => _post = v))),
          HqRow(title: 'Create events', trailing: HqSwitch(value: _events, onChanged: (v) => setState(() => _events = v))),
        ]),
        const SizedBox(height: 10),
      ], 'Confirm', () => _run(() => dio.postMap('/admin/hq/artists/$id/approve', body: {'post': _post, 'events': _events}), 'Approved'));
    }
    if (m == 'reject' || m == 'info' || m == 'suspend' || m == 'ban' || (m?.startsWith('uphold:') ?? false)) {
      final title = switch (m) { 'reject' => 'Reject', 'info' => 'Ask for more', 'suspend' => 'Suspend artist', 'ban' => 'Reject for good', _ => 'Uphold report' };
      final sub = switch (m) {
        'reject' => 'The artist sees this reason',
        'info' => 'The artist is asked to update their profile',
        'suspend' => 'Posting and events stop right away',
        'ban' => 'The artist loses access and cannot apply again',
        _ => 'The report is confirmed and counts as a chance',
      };
      final costs = m == 'suspend' || (m?.startsWith('uphold:') ?? false);
      return _formCard(title, sub, [
        if (costs) Padding(padding: const EdgeInsets.only(bottom: 10), child: Text(next >= 3 ? 'This is the third chance. Confirming rejects the artist for good, with no access afterwards.' : 'This uses chance $next of 3.', style: HqText.small.copyWith(color: next >= 3 ? Hq.red : Hq.gold, fontSize: 12.5))),
        HqField(label: m == 'info' ? 'What is needed' : 'Reason', controller: _note, maxLines: 3, hint: m == 'info' ? 'For example, add the code to the Instagram bio' : 'Why, in a few words'),
      ], 'Confirm', () {
        final n = _note.text.trim();
        return switch (m) {
          'reject' => _run(() => dio.postMap('/admin/hq/artists/$id/reject', body: {'note': n}), 'Rejected'),
          'info' => _run(() => dio.postMap('/admin/hq/artists/$id/ask', body: {'note': n}), 'Asked for more'),
          'suspend' => _run(() => dio.postMap('/admin/hq/artists/$id/suspend', body: {'note': n}), 'Suspended'),
          'ban' => _run(() => dio.postMap('/admin/hq/artists/$id/ban', body: {'note': n}), 'Rejected for good'),
          _ => _run(() => dio.postMap('/admin/hq/artists/$id/reports/${m!.substring(7)}/uphold', body: {'note': n}), 'Upheld'),
        };
      });
    }
    if (m == 'report') {
      final cats = a.strings('categories');
      return _formCard('Log a report', 'From a user, an academy, another artist or staff', [
        FieldRow2([
          HqField(label: 'Reported by', controller: _by, hint: 'Name'),
          HqSelect<String>(label: 'Who', value: _role, searchable: false, options: [for (final r in a.strings('reporters')) SelectOption(r, r)], onChanged: (v) => setState(() => _role = v)),
        ]),
        HqSelect<String>(label: 'Reason', value: _category ?? cats.first, searchable: false, options: [for (final c in cats) SelectOption(c, c)], onChanged: (v) => setState(() => _category = v)),
        HqField(label: 'What happened', controller: _note, maxLines: 3, hint: 'Describe the problem'),
      ], 'Confirm', () => _run(() => dio.postMap('/admin/hq/artists/$id/reports', body: {'by': _by.text.trim(), 'role': _role, 'category': _category ?? cats.first, 'details': _note.text.trim()}), 'Report logged'));
    }

    Widget btn(String label, VoidCallback f, {String? icon, BtnKind kind = BtnKind.normal, Color? color}) => Padding(padding: const EdgeInsets.only(bottom: 8), child: HqButton(label, icon: icon, kind: kind, color: color, expand: true, onPressed: f));
    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        if (open) ...[
          btn('Approve artist', () => setState(() => _mode = 'approve'), icon: 'check', kind: BtnKind.primary),
          Row(children: [
            Expanded(child: btn('Ask for more', () => setState(() => _mode = 'info'))),
            const SizedBox(width: 8),
            Expanded(child: btn('Reject', () => setState(() => _mode = 'reject'), color: Hq.red)),
          ]),
        ],
        if (status == 'suspended') ...[
          btn('Reinstate access', () => _run(() => dio.postMap('/admin/hq/artists/$id/reinstate'), 'Reinstated'), kind: BtnKind.primary),
          btn('Reject for good', () => setState(() => _mode = 'ban'), color: Hq.red),
        ],
        if (status == 'approved') btn('Suspend artist', () => setState(() => _mode = 'suspend'), icon: 'lock', color: Hq.coral),
        if (status != 'rejected' && !open) btn('Log a report', () => setState(() => _mode = 'report'), icon: 'flag'),
        if (status == 'rejected') btn('Reopen for review', () => _run(() => dio.postMap('/admin/hq/artists/$id/reopen'), 'Reopened')),
      ]),
    );
  }
}

class _VerifyMethod extends StatefulWidget {
  const _VerifyMethod();

  @override
  State<_VerifyMethod> createState() => _VerifyMethodState();
}

class _VerifyMethodState extends State<_VerifyMethod> {
  String _m = 'Code in bio';

  @override
  Widget build(BuildContext context) => ModalFrame(
        title: 'Confirm this profile',
        sub: 'How did you confirm it belongs to them?',
        actions: [HqButton('Cancel', onPressed: () => Navigator.of(context).pop()), HqButton('Confirm', kind: BtnKind.primary, onPressed: () => Navigator.of(context).pop(_m))],
        children: [
          Wrap(spacing: 8, runSpacing: 8, children: [for (final m in const ['Code in bio', 'Link back', 'DM reply']) HqChip(m, selected: _m == m, onTap: () => setState(() => _m = m))]),
          const SizedBox(height: 14),
        ],
      );
}

class _NoMatch extends StatefulWidget {
  const _NoMatch();

  @override
  State<_NoMatch> createState() => _NoMatchState();
}

class _NoMatchState extends State<_NoMatch> {
  final _c = TextEditingController();
  String? _err;

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => ModalFrame(
        title: 'Profile does not match',
        sub: 'Say what you found',
        error: _err,
        actions: [
          HqButton('Cancel', onPressed: () => Navigator.of(context).pop()),
          HqButton('Flag it', kind: BtnKind.danger, onPressed: () => _c.text.trim().length < 3 ? setState(() => _err = 'Say why it does not match.') : Navigator.of(context).pop(_c.text.trim())),
        ],
        children: [HqField(label: 'What you found', controller: _c, hint: 'For example, account created 3 weeks ago')],
      );
}

/// Adds what HQ learned from the applicant: art form, city, bio, and one more linked profile.
class _EditDetails extends ConsumerStatefulWidget {
  const _EditDetails({required this.artist, required this.onDone});
  final Map<String, dynamic> artist;
  final VoidCallback onDone;

  @override
  ConsumerState<_EditDetails> createState() => _EditDetailsState();
}

class _EditDetailsState extends ConsumerState<_EditDetails> {
  late final _form = TextEditingController(text: widget.artist.strOrNull('form') == 'Artist' ? '' : widget.artist.str('form'));
  late final _city = TextEditingController(text: widget.artist.str('city'));
  late final _bio = TextEditingController(text: widget.artist.str('bio'));
  final _handle = TextEditingController(), _followers = TextEditingController();
  String _pl = 'instagram';
  String? _error;
  bool _busy = false;

  @override
  void dispose() {
    for (final c in [_form, _city, _bio, _handle, _followers]) {
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
      await ref.read(dioClientProvider).putMap('/admin/hq/artists/${widget.artist.str('id')}/details', body: {
        'form': _form.text.trim(),
        'city': _city.text.trim(),
        'bio': _bio.text.trim(),
        if (_handle.text.trim().isNotEmpty) 'addProfile': {'pl': _pl, 'h': _handle.text.trim(), 'f': _followers.text.trim()},
      });
      refreshArtists(ref);
      widget.onDone();
    } on ApiException catch (e) {
      setState(() {
        _busy = false;
        _error = e.message;
      });
    }
  }

  @override
  Widget build(BuildContext context) => HqCard(
        margin: const EdgeInsets.only(top: 12),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          const CardHeader('Details', sub: 'What the artist told you, and one more profile to check', bottom: 8),
          FieldRow2([HqField(label: 'Art form', controller: _form, hint: 'e.g. Kathak dancer'), HqField(label: 'City', controller: _city)]),
          HqField(label: 'About', controller: _bio, maxLines: 2),
          Text('ADD A PROFILE', style: HqText.th),
          const SizedBox(height: 8),
          FieldRow2([
            HqSelect<String>(label: 'Platform', value: _pl, searchable: false, options: [for (final e in _platform.entries) SelectOption(e.key, e.value.$1)], onChanged: (v) => setState(() => _pl = v)),
            HqField(label: 'Followers', controller: _followers, hint: 'e.g. 12K'),
          ]),
          HqField(label: 'Handle or link', controller: _handle, hint: '@name or website'),
          if (_error != null) Padding(padding: const EdgeInsets.only(bottom: 8), child: Text(_error!, style: HqText.small.copyWith(color: Hq.red))),
          Row(children: [
            Expanded(child: HqButton('Cancel', expand: true, onPressed: widget.onDone)),
            const SizedBox(width: 8),
            Expanded(child: HqButton('Save', kind: BtnKind.primary, expand: true, busy: _busy, onPressed: _save)),
          ]),
        ]),
      );
}
