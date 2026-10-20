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
import '../events/events_screen.dart';
import '../shell/nav.dart';

final socialFeedProvider = FutureProvider.autoDispose<Map<String, dynamic>>((ref) => ref.watch(dioClientProvider).getMap('/admin/hq/social/feed'));
final socialProfileProvider = FutureProvider.autoDispose<Map<String, dynamic>>((ref) => ref.watch(dioClientProvider).getMap('/admin/hq/social/profile'));
final socialSearchProvider = FutureProvider.autoDispose.family<Map<String, dynamic>, ({String q, String filter})>(
  (ref, a) => ref.watch(dioClientProvider).getMap('/admin/hq/social/search', query: {'q': a.q, 'filter': a.filter}),
);

Tone _kindTone(String k) => switch (k) { 'hq' => Tone.gold, 'artist' => Tone.violet, _ => Tone.blue };

/// Post tab: the feed across academies, and posting as the official Owleo account.
class SocialPostScreen extends ConsumerStatefulWidget {
  const SocialPostScreen({super.key});

  @override
  ConsumerState<SocialPostScreen> createState() => _SocialPostScreenState();
}

class _SocialPostScreenState extends ConsumerState<SocialPostScreen> {
  final _c = TextEditingController();
  bool _busy = false;

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  Future<void> _publish() async {
    setState(() => _busy = true);
    try {
      await ref.read(dioClientProvider).postMap('/admin/hq/social/posts', body: {'text': _c.text.trim()});
      _c.clear();
      ref.invalidate(socialFeedProvider);
      ref.invalidate(socialProfileProvider);
      if (mounted) showToast(context, 'Posted as Owleo');
    } on ApiException catch (e) {
      if (mounted) showToast(context, e.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _remove(Map<String, dynamic> p) async {
    final ok = await confirmHq(context, title: 'Remove this post?', body: 'It disappears from Owleo Social for everyone. This cannot be undone.', confirmLabel: 'Remove', danger: true);
    if (!ok) return;
    try {
      await ref.read(dioClientProvider).delete('/admin/hq/social/posts/${p.str('id')}');
      ref.invalidate(socialFeedProvider);
      if (mounted) showToast(context, 'Post removed');
    } on ApiException catch (e) {
      if (mounted) showToast(context, e.message);
    }
  }

  @override
  Widget build(BuildContext context) {
    final canWrite = ref.watch(sessionProvider).user?.canWrite ?? false;
    return asyncBody(ref.watch(socialFeedProvider), onRetry: () => ref.invalidate(socialFeedProvider), data: (d) {
      final posts = d.maps('posts');
      return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        if (canWrite)
          HqCard(
            margin: const EdgeInsets.only(bottom: 12),
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              const CardHeader('Post as Owleo', sub: 'Public. Everyone on Owleo Social can see it', bottom: 10),
              HqField(label: 'Post', controller: _c, maxLines: 3, hint: 'Share an update, a festival date or a tip for academy owners', bottom: 10),
              Align(alignment: Alignment.centerRight, child: HqButton('Post', icon: 'send', kind: BtnKind.primary, busy: _busy, onPressed: _publish)),
            ]),
          ),
        MiniStats([(num0(d.integer('socialUsers')), 'Social users', null), ('${d.integer('postsWeek')}', 'Posts this week', null), (num0(d.integer('postsTotal')), 'Posts in all', null)]),
        if (!d.flag('socialVisible'))
          HqCard(margin: const EdgeInsets.only(bottom: 12), padding: const EdgeInsets.all(12), child: Text('Social is currently hidden from the app (see Platform settings), so these posts are not being shown to anyone.', style: HqText.muted.copyWith(fontSize: 12.5, color: Hq.gold))),
        if (posts.isEmpty) const EmptyNote('No posts yet'),
        for (final p in posts)
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: HqCard(
              child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                Row(children: [
                  p.flag('official') ? Container(width: 38, height: 38, decoration: BoxDecoration(shape: BoxShape.circle, color: Hq.gold.withValues(alpha: .18)), child: const Center(child: Text('O', style: TextStyle(color: Hq.gold, fontWeight: FontWeight.w800)))) : Avatar(initials(p.str('author')), tone: _kindTone(p.str('kind'))),
                  const SizedBox(width: 10),
                  Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text(p.str('author'), maxLines: 1, overflow: TextOverflow.ellipsis, style: HqText.row), Text('${p.str('sub')} · ${ago(p['at'])}', style: HqText.small)])),
                  if (canWrite) HqIconButton('trash', size: 32, tooltip: 'Remove post', onTap: () => _remove(p)),
                ]),
                const SizedBox(height: 10),
                Text(p.str('text'), style: HqText.body.copyWith(fontSize: 14, height: 1.5)),
                const SizedBox(height: 8),
                Wrap(spacing: 6, children: [Tag(p.flag('public') ? 'Public' : 'Academy only', tone: p.flag('public') ? Tone.primary : Tone.mute), if (p.integer('media') > 0) Tag('${p.integer('media')} media', tone: Tone.mute), if (p.integer('interested') > 0) Tag('${p.integer('interested')} interested', tone: Tone.blue)]),
              ]),
            ),
          ),
      ]);
    });
  }
}

/// Event tab: the public events on Owleo, upcoming and past, reusing the events list.
class SocialEventScreen extends ConsumerStatefulWidget {
  const SocialEventScreen({super.key});

  @override
  ConsumerState<SocialEventScreen> createState() => _SocialEventScreenState();
}

class _SocialEventScreenState extends ConsumerState<SocialEventScreen> {
  bool _up = true;

  @override
  Widget build(BuildContext context) {
    final q = (when: _up ? 'upcoming' : 'past', day: null as String?, q: '');
    return asyncBody(ref.watch(eventsProvider(q)), onRetry: () => ref.invalidate(eventsProvider), data: (d) {
      final items = d.maps('items').where((e) => e.flag('public') && e.str('state') != 'Cancelled').toList();
      return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Padding(padding: const EdgeInsets.only(bottom: 12), child: ChipRow([HqChip('Upcoming', selected: _up, onTap: () => setState(() => _up = true)), HqChip('Past', selected: !_up, onTap: () => setState(() => _up = false))])),
        if (items.isEmpty) const EmptyNote('No public events here'),
        for (final e in items)
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: HqCard(
              onTap: () => showEventDrawer(context, ref, e.str('id')),
              child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Container(
                  width: 52,
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  decoration: BoxDecoration(color: Hq.gold.withValues(alpha: .14), borderRadius: BorderRadius.circular(12)),
                  child: Column(children: [
                    Text('${(toDate(e['date']) ?? DateTime.now()).day}', style: HqText.h3.copyWith(fontSize: 18, color: Hq.gold)),
                    Text(monthShort('${(toDate(e['date']) ?? DateTime.now()).year}-${(toDate(e['date']) ?? DateTime.now()).month.toString().padLeft(2, '0')}'), style: HqText.small.copyWith(color: Hq.gold, fontSize: 11)),
                  ]),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(e.str('title'), style: HqText.row.copyWith(fontSize: 14.5)),
                    const SizedBox(height: 2),
                    Text('${e.str('academy')}${e.strOrNull('venue') == null ? '' : ' · ${e.str('venue')}'}', style: HqText.small),
                    const SizedBox(height: 8),
                    Wrap(spacing: 6, children: [Tag(e.str('state'), tone: e.str('state') == 'Today' ? Tone.green : Tone.mute), Tag('${e.integer('interested')} interested', tone: Tone.blue)]),
                  ]),
                ),
              ]),
            ),
          ),
      ]);
    });
  }
}

/// Search tab: academies, people, posts and events.
class SocialSearchScreen extends ConsumerStatefulWidget {
  const SocialSearchScreen({super.key});

  @override
  ConsumerState<SocialSearchScreen> createState() => _SocialSearchScreenState();
}

class _SocialSearchScreenState extends ConsumerState<SocialSearchScreen> {
  String _q = '', _f = 'all';

  @override
  Widget build(BuildContext context) {
    final res = ref.watch(socialSearchProvider((q: _q, filter: _f)));
    const names = {'academies': 'Academies', 'people': 'People', 'posts': 'Posts', 'events': 'Events'};
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      SearchBox(hint: 'Search Owleo Social', initial: _q, height: 46, onChanged: (v) => setState(() => _q = v)),
      const SizedBox(height: 12),
      Padding(padding: const EdgeInsets.only(bottom: 12), child: ChipRow([for (final (k, l) in const [('all', 'All'), ('academies', 'Academies'), ('people', 'People'), ('posts', 'Posts'), ('events', 'Events')]) HqChip(l, selected: _f == k, onTap: () => setState(() => _f = k))], scroll: true)),
      asyncBody(res, data: (d) {
        var total = 0;
        final cards = <Widget>[];
        for (final g in ['academies', 'people', 'posts', 'events']) {
          final list = d.maps(g);
          total += list.length;
          if (list.isEmpty) continue;
          cards.add(HqCard(
            margin: const EdgeInsets.only(bottom: 12),
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              CardHeader(names[g]!, trailing: Text('${list.length} found', style: HqText.sub), bottom: 8),
              HqList([
                for (final r in list)
                  HqRow(
                    leading: Avatar(initials(r.str('name')), tone: g == 'events' ? Tone.gold : Tone.blue, square: g == 'events', size: 34),
                    title: r.str('name'),
                    sub: r.str('sub'),
                    onTap: r.strOrNull('id') != null && g == 'academies' ? () => hqGo(context, '/academies?open=${r.str('id')}') : r.strOrNull('academyId') != null ? () => hqGo(context, '/academies?open=${r.str('academyId')}') : g == 'events' ? () => showEventDrawer(context, ref, r.str('id')) : null,
                  ),
              ]),
            ]),
          ));
        }
        return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [...cards, if (total == 0) const EmptyNote('Nothing found. Try a city, an academy name or a person.')]);
      }),
    ]);
  }
}

/// Profile tab: how the official Owleo page is doing.
class SocialProfileScreen extends ConsumerWidget {
  const SocialProfileScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return asyncBody(ref.watch(socialProfileProvider), onRetry: () => ref.invalidate(socialProfileProvider), data: (d) {
      final weeks = d.maps('weeks');
      return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        HqCard(
          padding: EdgeInsets.zero,
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Container(height: 96, decoration: const BoxDecoration(borderRadius: BorderRadius.vertical(top: Radius.circular(Hq.radiusCard)), gradient: LinearGradient(colors: [Color(0xFF0F3D37), Color(0xFF14544A), Color(0xFF1B8F7C)]))),
            Padding(
              padding: const EdgeInsets.fromLTRB(18, 0, 18, 18),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Transform.translate(offset: const Offset(0, -34), child: Container(width: 72, height: 72, decoration: BoxDecoration(borderRadius: BorderRadius.circular(22), color: Hq.surface, border: Border.all(color: Hq.surface, width: 3)), clipBehavior: Clip.antiAlias, child: Image.asset('assets/brand/logo_face.jpg', fit: BoxFit.cover))),
                Transform.translate(
                  offset: const Offset(0, -22),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text('Owleo', style: HqText.h2.copyWith(fontSize: 20)),
                    Text('@owleo · Verified platform account', style: HqText.muted.copyWith(fontSize: 12.5)),
                    const SizedBox(height: 12),
                    Text('The home for performing and fine arts academies across India. Fees, attendance, batches and a community in one place.', style: HqText.muted.copyWith(fontSize: 13.5, height: 1.55)),
                  ]),
                ),
                MiniStats([(num0(d.integer('followers')), 'People', null), ('${d.integer('academies')}', 'Academies', null), ('${d.integer('officialPosts')}', 'Official posts', null)]),
              ]),
            ),
          ]),
        ),
        HqCard(
          margin: const EdgeInsets.only(top: 12),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            const CardHeader('Posts, last 12 weeks', sub: 'Posts published on Owleo Social each week'),
            HqChart(labels: [for (final w in weeks) fdShort(w['week'])], height: 210, noRange: true, series: [ChartSeries('Posts', Hq.primary, SeriesType.area, [for (final w in weeks) w.number('posts')])]),
          ]),
        ),
        HqCard(
          margin: const EdgeInsets.only(top: 12),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            const CardHeader('Most interest', sub: 'Posts people marked interest in', bottom: 6),
            if (d.maps('top').isEmpty) const EmptyNote('Nothing yet', padding: 14),
            HqList([for (final p in d.maps('top')) HqRow(leading: const IconTile('eye', tone: Tone.primary), title: '${p.str('text')}…', wrap: true, sub: '${p.integer('interested')} interested')]),
          ]),
        ),
        Padding(padding: const EdgeInsets.fromLTRB(2, 14, 2, 0), child: Text('Reach, likes and comments are not recorded yet, so this page shows posts and interest only.', style: HqText.sub)),
      ]);
    });
  }
}
