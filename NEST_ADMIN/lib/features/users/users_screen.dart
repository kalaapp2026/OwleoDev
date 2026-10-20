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
import 'package:go_router/go_router.dart';
import 'students_view.dart';
import 'user_drawer.dart';

/// What the Users list is currently showing: filters plus how many rows to ask for.
class UsersQuery {
  const UsersQuery({this.q = '', this.academy, this.course, this.batch, this.trainer, this.status, this.flt = 'all', this.limit = 12});
  final String q;
  final String? academy, course, batch, trainer, status;
  final String flt;
  final int limit;

  UsersQuery copy({String? q, Object? academy = _keep, Object? course = _keep, Object? batch = _keep, Object? trainer = _keep, Object? status = _keep, String? flt, int? limit}) => UsersQuery(
        q: q ?? this.q,
        academy: identical(academy, _keep) ? this.academy : academy as String?,
        course: identical(course, _keep) ? this.course : course as String?,
        batch: identical(batch, _keep) ? this.batch : batch as String?,
        trainer: identical(trainer, _keep) ? this.trainer : trainer as String?,
        status: identical(status, _keep) ? this.status : status as String?,
        flt: flt ?? this.flt,
        limit: limit ?? this.limit,
      );

  static const _keep = Object();

  int get activeFilters => [academy, course, batch, trainer, status].where((e) => e != null).length;

  Map<String, String> get params => {
        if (q.trim().isNotEmpty) 'q': q.trim(),
        'academy': ?academy,
        'course': ?course,
        'batch': ?batch,
        'trainer': ?trainer,
        'status': ?status,
        'flt': flt,
        'limit': '$limit',
      };

  @override
  bool operator ==(Object other) => other is UsersQuery && other.q == q && other.academy == academy && other.course == course && other.batch == batch && other.trainer == trainer && other.status == status && other.flt == flt && other.limit == limit;

  @override
  int get hashCode => Object.hash(q, academy, course, batch, trainer, status, flt, limit);
}

final usersProvider = FutureProvider.autoDispose.family<Map<String, dynamic>, UsersQuery>(
  (ref, query) => ref.watch(dioClientProvider).getMap('/admin/hq/users', query: query.params),
);

final usersFiltersProvider = FutureProvider.autoDispose.family<Map<String, dynamic>, String?>(
  (ref, academy) => ref.watch(dioClientProvider).getMap('/admin/hq/users/filters', query: {'academy': ?academy}),
);

Tone roleTone(String role) => switch (role) { 'Student' => Tone.blue, 'Trainer' => Tone.primary, _ => Tone.gold };

/// Users: the audience (everyone on the platform and who is missing required details) and, per academy, its students.
class UsersScreen extends StatefulWidget {
  const UsersScreen({super.key});

  @override
  State<UsersScreen> createState() => _UsersScreenState();
}

class _UsersScreenState extends State<UsersScreen> {
  String? _tab;

  @override
  Widget build(BuildContext context) {
    _tab ??= GoRouterState.of(context).uri.queryParameters['tab'] == 'students' ? 'stu' : 'aud';
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Padding(padding: const EdgeInsets.only(bottom: 12), child: SegControl<String>(expand: true, items: const [('aud', 'Audience'), ('stu', 'Students')], value: _tab!, onChanged: (v) => setState(() => _tab = v))),
      if (_tab == 'stu') const StudentsView() else const _AudienceView(),
    ]);
  }
}

class _AudienceView extends ConsumerStatefulWidget {
  const _AudienceView();

  @override
  ConsumerState<_AudienceView> createState() => _AudienceViewState();
}

class _AudienceViewState extends ConsumerState<_AudienceView> {
  UsersQuery _q = const UsersQuery();
  bool _open = false;
  Map<String, dynamic>? _last;

  void _set(UsersQuery q) => setState(() => _q = q.copy(limit: 12));

  @override
  Widget build(BuildContext context) {
    final data = ref.watch(usersProvider(_q));
    final filters = ref.watch(usersFiltersProvider(_q.academy)).valueOrNull;
    // Keep the previous page on screen while a refinement loads, so typing in search does not flash.
    if (data.hasValue) _last = data.value;
    final d = data.valueOrNull ?? _last;
    if (d == null) return asyncBody(data, onRetry: () => ref.invalidate(usersProvider(_q)), data: (_) => const SizedBox.shrink());
    final counts = d.obj('counts');
    final items = d.maps('items');
    final total = d.integer('total');
    final profiles = d.integer('profiles');
    final nf = _q.activeFilters;

    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      HqGrid(GridKind.g4, [
        Kpi(icon: 'users', tone: Tone.blue, label: 'Profiles', value: num0(profiles), foot: '${d.integer('academiesWithUsers')} academies'),
        Kpi(icon: 'check', tone: Tone.green, label: 'Active accounts', value: num0(d.integer('active')), foot: '${d.integer('inactive')} inactive'),
        Kpi(icon: 'warn', tone: Tone.red, label: 'Missing mandatory data', value: '${d.integer('missing')}', valueColor: Hq.red, foot: '${pct(profiles == 0 ? 0 : d.integer('missing') / profiles * 100)} of profiles'),
        Kpi(icon: 'layers', tone: Tone.violet, label: 'In more than one academy', value: '${d.integer('multi')}', foot: 'access is managed per academy'),
      ]),
      HqCard(
        padding: const EdgeInsets.all(12),
        margin: const EdgeInsets.only(bottom: 12),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Row(children: [
            Expanded(child: SearchBox(hint: 'Search name, user ID or mobile', initial: _q.q, onChanged: (v) => _set(_q.copy(q: v)))),
            const SizedBox(width: 8),
            HqButton(nf == 0 ? 'Filters' : 'Filters · $nf', icon: 'filter', onPressed: () => setState(() => _open = !_open)),
          ]),
          if (_open) ...[
            const SizedBox(height: 12),
            _filterGrid(filters),
            Align(alignment: Alignment.centerLeft, child: HqButton('Clear filters', small: true, onPressed: () => _set(UsersQuery(flt: _q.flt)))),
          ],
        ]),
      ),
      Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: ChipRow([
          for (final (k, l) in const [('all', 'All'), ('miss', 'Missing data'), ('multi', 'Multi-academy'), ('inact', 'Inactive')])
            HqChip(l, selected: _q.flt == k, count: counts.integer(k), onTap: () => _set(_q.copy(flt: k))),
        ], scroll: true),
      ),
      if (items.isEmpty) const EmptyNote('No users match these filters'),
      LayoutBuilder(builder: (context, c) {
        final cols = c.maxWidth >= 900 ? 3 : c.maxWidth >= 600 ? 2 : 1;
        return Wrap(spacing: 10, runSpacing: 10, children: [
          for (final u in items) SizedBox(width: (c.maxWidth - (cols - 1) * 10) / cols, child: _card(u)),
        ]);
      }),
      if (total > _q.limit) Padding(padding: const EdgeInsets.only(top: 12), child: HqButton('Show more (${total - _q.limit} left)', expand: true, onPressed: () => setState(() => _q = _q.copy(limit: _q.limit + 12)))),
      Padding(padding: const EdgeInsets.fromLTRB(2, 14, 2, 0), child: Text('${items.length} of ${num0(total)} profiles shown.', style: HqText.sub)),
    ]);
  }

  Widget _filterGrid(Map<String, dynamic>? f) {
    final academies = f?.maps('academies') ?? const [];
    final hasAcademy = _q.academy != null;
    final trainers = f?.maps('trainers') ?? const [];
    Widget sel(String label, String? value, List<SelectOption<String>> options, ValueChanged<String?> onChanged, {bool enabled = true}) => HqSelect<String>(
          label: label,
          value: value ?? '*',
          enabled: enabled,
          options: [const SelectOption('*', 'All'), ...options],
          onChanged: (v) => onChanged(v == '*' ? null : v),
        );
    final fields = [
      sel('Academy', _q.academy, [for (final a in academies) SelectOption(a.str('id'), a.str('name'))], (v) => _set(UsersQuery(q: _q.q, academy: v, status: _q.status, flt: _q.flt))),
      sel('Course', _q.course, [for (final c in f?.strings('courses') ?? const <String>[]) SelectOption(c, c)], (v) => _set(_q.copy(course: v))),
      sel('Batch', _q.batch, [for (final c in f?.strings('batches') ?? const <String>[]) SelectOption(c, c)], (v) => _set(_q.copy(batch: v))),
      sel('Trainer', hasAcademy ? _q.trainer : null, [for (final t in trainers) SelectOption(t.str('id'), t.str('name'))], (v) => _set(_q.copy(trainer: v)), enabled: hasAcademy),
      sel('Status', _q.status, const [SelectOption('Active', 'Active'), SelectOption('Inactive', 'Inactive')], (v) => _set(_q.copy(status: v))),
    ];
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      for (var i = 0; i < fields.length; i += 2) FieldRow2(fields.sublist(i, (i + 2).clamp(0, fields.length))),
      if (!hasAcademy) Padding(padding: const EdgeInsets.only(bottom: 8), child: Text('Pick an academy to filter by its trainers.', style: HqText.sub)),
    ]);
  }

  Widget _card(Map<String, dynamic> u) {
    final miss = u.integer('missing');
    final status = u.str('status');
    return HqCard(
      radius: 14,
      padding: const EdgeInsets.all(12),
      onTap: () => showUserDrawer(context, ref, u.str('id')),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(children: [
          Avatar(initials(u.str('name')), tone: roleTone(u.str('role'))),
          const SizedBox(width: 10),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(u.str('name'), maxLines: 1, overflow: TextOverflow.ellipsis, style: HqText.row),
              Text('${u.str('ref')} · ${u.str('role')} · ${u.str('academy')}', maxLines: 1, overflow: TextOverflow.ellipsis, style: HqText.small),
            ]),
          ),
          Tag(status, tone: status == 'Active' ? Tone.green : Tone.mute),
        ]),
        const SizedBox(height: 9),
        Wrap(spacing: 6, runSpacing: 6, children: [
          if (u.strOrNull('course') != null) Tag(u.str('course'), tone: Tone.mute),
          if (u.integer('academies') > 1) Tag('${u.integer('academies')} academies', tone: Tone.violet),
          if (miss > 0) Tag('$miss missing', tone: Tone.red),
        ]),
      ]),
    );
  }
}

/// Two controls side by side, collapsing to one column when narrow.
class FieldRow2 extends StatelessWidget {
  const FieldRow2(this.children, {super.key});
  final List<Widget> children;

  @override
  Widget build(BuildContext context) => LayoutBuilder(builder: (context, c) {
        if (c.maxWidth < 420 || children.length == 1) return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: children);
        return Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          for (final (i, w) in children.indexed) ...[if (i > 0) const SizedBox(width: 10), Expanded(child: w)],
        ]);
      });
}
