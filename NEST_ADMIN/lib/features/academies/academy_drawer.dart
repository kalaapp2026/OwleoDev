import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/theme.dart';
import '../../core/api/api_exception.dart';
import '../../core/auth/session.dart';
import '../../core/format.dart';
import '../../core/json.dart';
import '../../core/ui/charts.dart';
import '../../core/ui/controls.dart';
import '../../core/ui/icons.dart';
import '../../core/ui/layout.dart';
import '../../core/ui/overlays.dart';
import '../../core/ui/primitives.dart';
import '../../core/ui/sections.dart';
import '../plans/plans_screen.dart';
import '../shell/nav.dart';
import 'academies_screen.dart';
import 'academy_form.dart';
import 'academy_meta.dart';

final academyDetailProvider = FutureProvider.autoDispose.family<Map<String, dynamic>, String>(
  (ref, id) => ref.watch(dioClientProvider).getMap('/admin/hq/academies/$id'),
);

Future<void> showAcademyDrawer(BuildContext context, WidgetRef ref, String id) {
  return showHqDrawer(context, builder: (_) => _AcademyDrawer(id: id));
}

class _AcademyDrawer extends ConsumerStatefulWidget {
  const _AcademyDrawer({required this.id});
  final String id;

  @override
  ConsumerState<_AcademyDrawer> createState() => _AcademyDrawerState();
}

class _AcademyDrawerState extends ConsumerState<_AcademyDrawer> {
  /// null = the profile; otherwise the drill-down list being shown.
  String? _kind;

  @override
  Widget build(BuildContext context) {
    final detail = ref.watch(academyDetailProvider(widget.id));
    return detail.when(
      loading: () => const Center(child: CircularProgressIndicator(color: Hq.primary, strokeWidth: 2.5)),
      error: (e, _) => Padding(padding: const EdgeInsets.all(24), child: HqError(e is ApiException ? e.message : 'Could not load this academy.')),
      data: (d) {
        final a = d.obj('academy');
        final tone = AcademyMeta.typeTone(a.str('type'));
        final cover = AcademyMeta.coverColors(a.str('type')).map(Color.new).toList();
        return DrawerShell(
          coverColors: _kind == null ? cover : cover,
          coverHeight: _kind == null ? 104 : 96,
          logo: _kind == null ? DrawerLogo(initials(a.str('name')), color: tone.color) : null,
          child: _kind == null
              ? _Profile(detail: d, onOpenKind: (k) => setState(() => _kind = k), onChanged: _refresh)
              : _People(academy: a, kind: _kind!, onKind: (k) => setState(() => _kind = k), onBack: () => setState(() => _kind = null)),
        );
      },
    );
  }

  void _refresh() {
    ref.invalidate(academyDetailProvider(widget.id));
    ref.invalidate(academiesProvider);
  }
}

// ---------------------------------------------------------------------------------------------

class _Profile extends ConsumerWidget {
  const _Profile({required this.detail, required this.onOpenKind, required this.onChanged});

  final Map<String, dynamic> detail;
  final ValueChanged<String> onOpenKind;
  final VoidCallback onChanged;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final a = detail.obj('academy');
    final c = detail.obj('contact');
    final user = ref.watch(sessionProvider).user;
    final canWrite = user?.canWrite ?? false;
    final canPlan = user != null && (user.isSuper || user.role.code == 'FINANCE');
    final status = a.str('status');
    final (statusTone, statusLabel) = AcademyMeta.status(status);
    final tone = AcademyMeta.typeTone(a.str('type'));
    final hist = detail.doubles('history');
    final stu = a.integer('students');
    final lim = a.integerOrNull('maxStudents');
    final price = a['planPrice'] == null ? null : a.number('planPrice');
    final invoices = detail.maps('invoices');
    final banks = detail.maps('banks');
    final log = detail.maps('log');
    final joined = a.str('joined');
    final users = stu + a.integer('trainers') + a.integer('admins');

    Tone meterTone(num v, num good, num ok) => v >= good ? Tone.green : (v >= ok ? Tone.gold : Tone.red);
    Widget meter(String label, num? v, Tone t) => v == null ? const SizedBox.shrink() : Meter(label, pct(v), v.toDouble(), tone: t);

    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Wrap(
        alignment: WrapAlignment.spaceBetween,
        crossAxisAlignment: WrapCrossAlignment.start,
        spacing: 10,
        runSpacing: 8,
        children: [
          Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(a.str('name'), style: HqText.h2.copyWith(fontSize: 19)),
            const SizedBox(height: 2),
            Text('${a.str('type')} · ${a.str('city')}${a.strOrNull('owner') == null ? '' : ' · Owner ${a.str('owner')}'}', style: HqText.muted),
          ]),
          Row(mainAxisSize: MainAxisSize.min, children: [
            if (a.strOrNull('planName') != null) Tag(a.str('planName'), tone: Tone.blue),
            const SizedBox(width: 6),
            Tag(statusLabel, tone: statusTone),
          ]),
        ],
      ),
      MiniStats(
        [
          (num0(stu), 'Students', null),
          ('${a.integer('trainers')}', 'Trainers', null),
          ('${a.integer('courses')}', 'Courses', null),
          ('${a.integer('batches')}', 'Batches', null),
        ],
        onTap: (i) => onOpenKind(const ['students', 'trainers', 'courses', 'batches'][i]),
      ),
      HqCard(
        margin: const EdgeInsets.only(bottom: 12),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          CardHeader('Users over 12 months',
              sub: '${num0(users)} now · joined ${joined.isEmpty ? '' : fd(joined)}',
              bottom: 8,
              trailing: HealthRing(a.integer('health'), size: 52)),
          Spark(hist, tone.color, height: 64),
        ]),
      ),
      HqCard(
        margin: const EdgeInsets.only(bottom: 12),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Text('Performance', style: HqText.h3),
          const SizedBox(height: 12),
          meter('Fee collection', a['feeCollection'] == null ? null : a.number('feeCollection'), meterTone(a.number('feeCollection'), 80, 60)),
          meter('Attendance', a['attendance'] == null ? null : a.number('attendance'), meterTone(a.number('attendance'), 85, 70)),
          meter('Weekly active users', a['weeklyActive'] == null ? null : a.number('weeklyActive'), meterTone(a.number('weeklyActive'), 70, 50)),
          if (a['feeCollection'] == null && a['attendance'] == null && a['weeklyActive'] == null)
            Text('No activity to score yet.', style: HqText.small),
          Text(a.strOrNull('lastActive') == null ? 'No activity yet' : 'Last activity: ${ago(a['lastActive'])}', style: HqText.sub),
        ]),
      ),
      HqCard(
        margin: const EdgeInsets.only(bottom: 12),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Text('Plan and billing', style: HqText.h3),
          const SizedBox(height: 12),
          HqList([
            HqRow(
              title: a.strOrNull('planName') == null ? 'No plan' : '${a.str('planName')} plan',
              sub: status == 'trial' ? 'Demo ends ${fd(a['demoEndsOn'])}' : 'Renews ${fd(detail['renewsOn'])}',
              trailing: Text(status == 'trial' || price == null ? 'Free demo' : '${inr(price)} / mo', style: HqText.row),
            ),
            HqRow(
              title: 'Students vs limit',
              sub: lim == null ? 'Unlimited on this plan' : '$stu of $lim',
              trailing: lim == null ? null : SizedBox(width: 110, child: HqBar((stu / lim * 100).clamp(0, 100).toDouble(), tone: stu / lim >= .9 ? Tone.gold : Tone.primary)),
            ),
            for (final i in invoices)
              HqRow(
                title: 'Invoice · ${monthLong(i.str('period'))}',
                sub: inr(i.number('total')),
                trailing: _invoiceTag(i.str('status')),
              ),
          ]),
        ]),
      ),
      HqCard(
        margin: const EdgeInsets.only(bottom: 12),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Text('Contact', style: HqText.h3),
          const SizedBox(height: 12),
          HqList([
            KeyValueRow('Academy email', c.str('aemail', '–')),
            KeyValueRow('Academy phone', c.str('aphone', '–')),
            KeyValueRow('Address', _address(c)),
            KeyValueRow('Owner', '${c.str('owner', '–')}${c.str('ophone').isEmpty ? ' · phone not added' : ' · ${c.str('ophone')}'}'),
            KeyValueRow('Owner email', c.str('oemail', '–')),
          ]),
        ]),
      ),
      HqCard(
        margin: const EdgeInsets.only(bottom: 12),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Text('Bank accounts', style: HqText.h3),
          const SizedBox(height: 4),
          Text('Only the academy admin can change these, from their app. You can map the payment gateway.', style: HqText.sub),
          const SizedBox(height: 10),
          if (banks.isEmpty)
            const EmptyNote('No bank account on file yet.', padding: 14)
          else
            HqList([
              for (final b in banks)
                Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                  Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Expanded(
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text('${b.str('bank')} •••• •••• ${b.str('last4')}', style: HqText.row),
                        Text('${b.str('holder')} · ${b.str('type')} · ${b.str('ifsc')}', style: HqText.small),
                      ]),
                    ),
                    if (b.flag('primary')) const Tag('Primary', tone: Tone.primary),
                  ]),
                  const SizedBox(height: 8),
                  Row(children: [
                    b.strOrNull('gateway') == null
                        ? const Tag('Gateway not mapped', tone: Tone.gold)
                        : Tag(b.str('gateway'), tone: Tone.green, icon: 'check'),
                    if (b.strOrNull('merchantId') != null) ...[const SizedBox(width: 8), Text(b.str('merchantId'), style: HqText.small)],
                    const Spacer(),
                    if (canWrite || canPlan)
                      HqButton(b.strOrNull('gateway') == null ? 'Map gateway' : 'Change gateway', small: true, onPressed: () async {
                        final done = await showHqModal<bool>(context, builder: (_) => _GatewayModal(academyId: a.str('id'), bank: b));
                        if (done == true) {
                          onChanged();
                          if (context.mounted) showToast(context, 'Gateway mapped');
                        }
                      }),
                  ]),
                ]),
            ]),
        ]),
      ),
      if (canWrite || canPlan || log.isNotEmpty)
        HqCard(
          margin: const EdgeInsets.only(bottom: 12),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Text('Manage this academy', style: HqText.h3),
            const SizedBox(height: 10),
            HqList([
              if (canWrite)
                HqRow(
                  leading: const IconTile('edit', tone: Tone.primary),
                  title: 'Edit details',
                  sub: 'Contact, address and owner, same as onboarding',
                  trailing: ic('chev', 14, Hq.muted),
                  onTap: () async {
                    final saved = await showHqFullPage<bool>(context, builder: (_) => EditAcademyPage(detail: detail));
                    if (saved == true) {
                      onChanged();
                      if (context.mounted) showToast(context, 'Academy details saved');
                    }
                  },
                ),
              if (canPlan)
                HqRow(
                  leading: const IconTile('layers', tone: Tone.violet),
                  title: 'Change plan',
                  sub: a.strOrNull('planName') == null ? 'Choose a plan' : 'Now on ${a.str('planName')}',
                  trailing: ic('chev', 14, Hq.muted),
                  onTap: () async {
                    final done = await showHqModal<bool>(context, builder: (_) => _ChangePlanModal(academy: a));
                    if (done == true) {
                      onChanged();
                      ref.invalidate(plansProvider);
                      if (context.mounted) showToast(context, 'Plan changed');
                    }
                  },
                ),
            ]),
            if (log.isNotEmpty) ...[
              const SizedBox(height: 12),
              Text('Recent changes', style: HqText.sub),
              const SizedBox(height: 6),
              HqList([
                for (final l in log)
                  HqRow(title: l.str('text'), sub: '${l.str('who')} · ${ago(l['at'])}', wrap: true, titleStyle: HqText.row.copyWith(fontSize: 12.5)),
              ]),
            ],
          ]),
        ),
      Wrap(spacing: 8, runSpacing: 8, children: [
        HqButton('View students', icon: 'cap', kind: BtnKind.primary, onPressed: () {
          Navigator.of(context).pop();
          hqGo(context, '/users?tab=students&academy=${a.str('id')}');
        }),
        if (canWrite && status != 'churned')
          HqButton(status == 'suspended' ? 'Reactivate' : 'Suspend', kind: status == 'suspended' ? BtnKind.normal : BtnKind.danger, onPressed: () async {
            final suspend = status != 'suspended';
            final ok = await confirmHq(context,
                title: suspend ? 'Suspend ${a.str('name')}?' : 'Reactivate ${a.str('name')}?',
                body: suspend ? 'Everyone linked to this academy loses access until you reactivate it. Their data is kept.' : 'Access comes back for everyone linked to this academy.',
                confirmLabel: suspend ? 'Suspend' : 'Reactivate',
                danger: suspend);
            if (!ok || !context.mounted) return;
            try {
              await ref.read(dioClientProvider).postMap('/admin/hq/academies/${a.str('id')}/${suspend ? 'suspend' : 'reactivate'}');
              onChanged();
              if (context.mounted) showToast(context, suspend ? '${a.str('name')} suspended' : '${a.str('name')} reactivated');
            } on ApiException catch (e) {
              if (context.mounted) showToast(context, e.message);
            }
          }),
      ]),
    ]);
  }

  static String _address(Map<String, dynamic> c) {
    final parts = ['a1', 'a2', 'landmark', 'city', 'district', 'state', 'pin'].map((k) => c.str(k).trim()).where((s) => s.isNotEmpty).toList();
    final seen = <String>[];
    for (final p in parts) {
      if (!seen.contains(p)) seen.add(p);
    }
    return seen.isEmpty ? '–' : seen.join(', ');
  }

  static Widget _invoiceTag(String s) => switch (s) {
        'paid' => const Tag('Paid', tone: Tone.green),
        'overdue' => const Tag('Overdue', tone: Tone.red),
        'waived' => const Tag('Waived', tone: Tone.mute),
        _ => const Tag('Due', tone: Tone.blue),
      };
}

// ---------------------------------------------------------------------------------------------

final _peopleProvider = FutureProvider.autoDispose.family<List<Map<String, dynamic>>, (String, String)>(
  (ref, k) => ref.watch(dioClientProvider).getList('/admin/hq/academies/${k.$1}/people', query: {'kind': k.$2}),
);

/// Students, trainers, courses or batches of one academy, inside the same drawer.
class _People extends ConsumerStatefulWidget {
  const _People({required this.academy, required this.kind, required this.onKind, required this.onBack});

  final Map<String, dynamic> academy;
  final String kind;
  final ValueChanged<String> onKind;
  final VoidCallback onBack;

  @override
  ConsumerState<_People> createState() => _PeopleState();
}

class _PeopleState extends ConsumerState<_People> {
  String _q = '';
  int _limit = 15;

  static const _titles = {'students': 'Students', 'trainers': 'Trainers', 'courses': 'Courses', 'batches': 'Batches'};

  @override
  Widget build(BuildContext context) {
    final a = widget.academy;
    final k = widget.kind;
    final data = ref.watch(_peopleProvider((a.str('id'), k)));
    final total = switch (k) {
      'students' => a.integer('students'),
      'trainers' => a.integer('trainers'),
      'courses' => a.integer('courses'),
      _ => a.integer('batches'),
    };

    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Align(alignment: Alignment.centerLeft, child: HqButton(a.str('name'), icon: 'left', small: true, onPressed: widget.onBack)),
      const SizedBox(height: 12),
      Text.rich(TextSpan(children: [
        TextSpan(text: _titles[k], style: HqText.h2.copyWith(fontSize: 19)),
        TextSpan(text: ' · $total', style: HqText.h2.copyWith(fontSize: 19, color: Hq.muted)),
      ])),
      Text('${a.str('name')} · ${a.str('city')}', style: HqText.muted),
      const SizedBox(height: 14),
      ChipRow(scroll: true, [
        for (final e in _titles.entries)
          HqChip(e.value, selected: k == e.key, onTap: () {
            widget.onKind(e.key);
            setState(() {
              _q = '';
              _limit = 15;
            });
          }),
      ]),
      const SizedBox(height: 14),
      SearchBox(hint: 'Search ${_titles[k]!.toLowerCase()}', onChanged: (v) => setState(() {
            _q = v.toLowerCase();
            _limit = 15;
          })),
      const SizedBox(height: 12),
      data.when(
        loading: () => const HqLoading(),
        error: (e, _) => HqError(e is ApiException ? e.message : 'Could not load this list.'),
        data: (rows) {
          bool has(Map<String, dynamic> r) => _q.isEmpty || r.values.join(' ').toLowerCase().contains(_q);
          final list = rows.where(has).toList();
          return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            MiniStats(_summary(k, rows)),
            if (list.isEmpty)
              const EmptyNote('Nothing matches')
            else
              for (final r in list.take(_limit)) Padding(padding: const EdgeInsets.only(bottom: 10), child: _row(k, r)),
            if (list.length > _limit) HqButton('Show more (${list.length - _limit} left)', expand: true, onPressed: () => setState(() => _limit += 15)),
          ]);
        },
      ),
    ]);
  }

  List<(String, String, Color?)> _summary(String k, List<Map<String, dynamic>> rows) {
    switch (k) {
      case 'students':
        final due = rows.where((r) => r.number('feeDue') > 0).length;
        final att = rows.where((r) => r['attendance'] != null).toList();
        final avg = att.isEmpty ? null : att.fold<double>(0, (s, r) => s + r.number('attendance')) / att.length;
        return [('${rows.length - due}', 'Fees clear', Hq.green), ('$due', 'Fees due', due > 0 ? Hq.gold : null), (avg == null ? '–' : pct(avg), 'Attendance', null)];
      case 'trainers':
        final none = rows.where((r) => r.integer('batches') == 0).length;
        return [('${rows.length}', 'Trainers', null), ('${rows.length - none}', 'With batches', Hq.green), ('$none', 'No batch yet', none > 0 ? Hq.gold : null)];
      case 'courses':
        return [('${rows.length}', 'Courses', null), ('${rows.fold<int>(0, (s, r) => s + r.integer('batches'))}', 'Batches', null), (num0(rows.fold<int>(0, (s, r) => s + r.integer('enrolled'))), 'Enrolled', null)];
      default:
        final running = rows.where((r) => r.str('status') == 'ACTIVE').length;
        return [('${rows.length}', 'Batches', null), ('$running', 'Active', Hq.green), ('${rows.length - running}', 'Inactive', null)];
    }
  }

  Widget _row(String k, Map<String, dynamic> r) {
    switch (k) {
      case 'students':
        final due = r.number('feeDue');
        return HqCard(
          radius: 16,
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          child: Row(children: [
            Avatar(initials(r.str('name')), tone: due > 0 ? Tone.gold : Tone.green),
            const SizedBox(width: 11),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(r.str('name'), style: HqText.row.copyWith(fontSize: 13.5)),
                Text(r.str('courses').isEmpty ? 'Not in a batch yet' : r.str('courses'), maxLines: 1, overflow: TextOverflow.ellipsis, style: HqText.small),
                Text(r['attendance'] == null ? 'No attendance yet' : 'Attendance ${pct(r.number('attendance'))}', style: HqText.sub),
              ]),
            ),
            due > 0 ? Tag('Due ${inr(due)}', tone: Tone.gold) : const Tag('Paid', tone: Tone.green),
          ]),
        );
      case 'trainers':
        final b = r.integer('batches');
        return HqCard(
          radius: 16,
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          child: Row(children: [
            Avatar(initials(r.str('name')), tone: Tone.gold),
            const SizedBox(width: 11),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(r.str('name'), style: HqText.row.copyWith(fontSize: 13.5)),
                Text('${r.str('spec').isEmpty ? 'No course assigned' : r.str('spec')}${r['years'] == null ? '' : ' · ${r.integer('years')} yrs experience'}', maxLines: 1, overflow: TextOverflow.ellipsis, style: HqText.small),
              ]),
            ),
            Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
              Tag(b == 0 ? 'No batch yet' : '$b batch${b == 1 ? '' : 'es'}', tone: b == 0 ? Tone.mute : Tone.blue),
              if (r.integer('students') > 0) Padding(padding: const EdgeInsets.only(top: 3), child: Text('${r.integer('students')} students', style: HqText.sub)),
            ]),
          ]),
        );
      case 'courses':
        return HqCard(
          radius: 16,
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          child: Row(children: [
            const IconTile('book', tone: Tone.green, size: 36),
            const SizedBox(width: 11),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(r.str('name'), style: HqText.row.copyWith(fontSize: 13.5)),
                Text('${r.integer('batches')} batch${r.integer('batches') == 1 ? '' : 'es'} · ${r.integer('enrolled')} enrolled', style: HqText.small),
              ]),
            ),
            if (r['fee'] != null) Text('${inr(r.number('fee'))}/mo', style: HqText.row),
          ]),
        );
      default:
        final active = r.str('status') == 'ACTIVE';
        return HqCard(
          radius: 16,
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          child: Row(children: [
            IconTile('layers', tone: active ? Tone.green : Tone.mute, size: 36),
            const SizedBox(width: 11),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('${r.str('course')} · ${r.str('name')}', maxLines: 1, overflow: TextOverflow.ellipsis, style: HqText.row.copyWith(fontSize: 13.5)),
                Text(r.str('trainers').isEmpty ? 'No trainer assigned' : r.str('trainers'), style: HqText.small.copyWith(color: r.str('trainers').isEmpty ? Hq.red : Hq.muted)),
                Text('${r.str('days').isEmpty ? 'No schedule' : r.str('days')} · ${r.integer('enrolled')} enrolled', style: HqText.sub),
              ]),
            ),
            Tag(active ? 'Active' : 'Inactive', tone: active ? Tone.green : Tone.mute),
          ]),
        );
    }
  }
}

// ---------------------------------------------------------------------------------------------

/// "Edit academy": the same three sections as onboarding, saved to the server.
class EditAcademyPage extends ConsumerStatefulWidget {
  const EditAcademyPage({super.key, required this.detail});
  final Map<String, dynamic> detail;

  @override
  ConsumerState<EditAcademyPage> createState() => _EditAcademyPageState();
}

class _EditAcademyPageState extends ConsumerState<EditAcademyPage> {
  late final AcademyFormData _data = AcademyFormData(from: {...widget.detail.obj('academy'), ...widget.detail.obj('contact')});
  final Set<String> _open = {'details'};
  bool _busy = false;

  @override
  void dispose() {
    _data.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final issues = _data.issues();
    if (issues.isNotEmpty) {
      setState(() => _open.add(issues.first.$1));
      showToast(context, issues.first.$2);
      return;
    }
    setState(() => _busy = true);
    try {
      await ref.read(dioClientProvider).putMap('/admin/hq/academies/${widget.detail.obj('academy').str('id')}', body: _data.toJson());
      if (mounted) Navigator.of(context).pop(true);
    } on ApiException catch (e) {
      if (mounted) {
        setState(() => _busy = false);
        showToast(context, e.message);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final a = widget.detail.obj('academy');
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 640),
        child: ListenableBuilder(
          listenable: _data,
          builder: (context, _) => SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(16, 20, 16, 40),
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              FormTopBar(title: 'Edit academy', subtitle: a.str('name'), onBack: () => Navigator.of(context).pop()),
              AcademyFormSections(
                data: _data,
                open: _open,
                onToggle: (k) => setState(() => _open.contains(k) ? _open.remove(k) : _open.add(k)),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(2, 4, 2, 12),
                child: Text('Bank account and plan are changed from their own rows in the profile.', style: HqText.sub),
              ),
              HqButton('Save changes', icon: 'check', kind: BtnKind.primary, expand: true, busy: _busy, onPressed: _save),
            ]),
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------------------------

class _ChangePlanModal extends ConsumerStatefulWidget {
  const _ChangePlanModal({required this.academy});
  final Map<String, dynamic> academy;

  @override
  ConsumerState<_ChangePlanModal> createState() => _ChangePlanModalState();
}

class _ChangePlanModalState extends ConsumerState<_ChangePlanModal> {
  String? _plan;
  String _reason = 'Academy asked for it';
  String? _error;
  bool _busy = false;

  Future<void> _save() async {
    if (_plan == null || _plan == widget.academy.str('plan')) return setState(() => _error = 'Pick a different plan.');
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await ref.read(dioClientProvider).putMap('/admin/hq/academies/${widget.academy.str('id')}/plan', body: {'planCode': _plan, 'reason': _reason});
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
    final plans = ref.watch(plansProvider).valueOrNull ?? const <Map<String, dynamic>>[];
    final a = widget.academy;
    _plan ??= a.strOrNull('plan');
    final sel = plans.where((p) => p.str('code') == _plan).firstOrNull;
    final cur = plans.where((p) => p.str('code') == a.str('plan')).firstOrNull;
    final diff = sel == null || cur == null ? 0 : sel.number('price') - cur.number('price');
    final lim = sel?.integerOrNull('maxStudents');
    final over = lim != null && a.integer('students') > lim;

    return ModalFrame(
      title: 'Change plan',
      sub: '${a.str('name')} · now ${a.strOrNull('planName') ?? 'no plan'}',
      error: _error,
      actions: [
        HqButton('Cancel', onPressed: () => Navigator.of(context).pop()),
        HqButton('Change plan', kind: BtnKind.primary, busy: _busy, onPressed: _save),
      ],
      children: [
        HqSelect<String>(
          label: 'New plan',
          value: _plan,
          options: [for (final p in plans) SelectOption(p.str('code'), '${p.str('name')} · ${inr(p.number('price'))} / mo')],
          onChanged: (v) => setState(() => _plan = v),
        ),
        HqCard(
          radius: 14,
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          margin: const EdgeInsets.only(bottom: 12),
          child: Text(
            _plan == a.str('plan')
                ? 'This is the current plan.'
                : '${diff > 0 ? 'Upgrade' : 'Downgrade'}: ${diff > 0 ? '+' : '−'}${inr(diff.abs())} / month, from the next renewal.${over ? '\n${a.integer('students')} students is over the $lim limit of ${sel!.str('name')}. Ask the academy to reduce first.' : ''}',
            style: HqText.muted.copyWith(fontSize: 12.5, color: over ? Hq.gold : Hq.muted),
          ),
        ),
        HqSelect<String>(
          label: 'Reason',
          value: _reason,
          searchable: false,
          options: [for (final r in const ['Academy asked for it', 'Growth in students', 'Cost saving', 'Plan ended or trial finished', 'Other']) SelectOption(r, r)],
          onChanged: (v) => setState(() => _reason = v),
        ),
      ],
    );
  }
}

class _GatewayModal extends ConsumerStatefulWidget {
  const _GatewayModal({required this.academyId, required this.bank});
  final String academyId;
  final Map<String, dynamic> bank;

  @override
  ConsumerState<_GatewayModal> createState() => _GatewayModalState();
}

class _GatewayModalState extends ConsumerState<_GatewayModal> {
  late String _provider = widget.bank.strOrNull('gateway') ?? 'Razorpay';
  late final _merchant = TextEditingController(text: widget.bank.str('merchantId'));
  String? _error;
  bool _busy = false;

  @override
  void dispose() {
    _merchant.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final m = _merchant.text.trim();
    if (!RegExp(r'^[A-Za-z0-9_\-]{6,30}$').hasMatch(m)) {
      return setState(() => _error = 'Enter the merchant ID: 6 to 30 letters, numbers, - or _.');
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await ref.read(dioClientProvider).putMap('/admin/hq/academies/${widget.academyId}/banks/${widget.bank.str('id')}/gateway', body: {'provider': _provider, 'merchantId': m});
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
    final b = widget.bank;
    return ModalFrame(
      title: 'Map payment gateway',
      sub: '${b.str('bank')} •••• ${b.str('last4')} · ${b.str('ifsc')}',
      error: _error,
      actions: [
        HqButton('Cancel', onPressed: () => Navigator.of(context).pop()),
        HqButton('Save mapping', kind: BtnKind.primary, busy: _busy, onPressed: _save),
      ],
      children: [
        HqSelect<String>(
          label: 'Payment gateway',
          value: _provider,
          searchable: false,
          options: [for (final g in const ['Razorpay', 'Cashfree', 'PayU']) SelectOption(g, g)],
          onChanged: (v) => setState(() => _provider = v),
        ),
        HqField(label: 'Merchant ID from the gateway', controller: _merchant, hint: 'e.g. rzp_live_8KxPq2', formatters: [FilteringTextInputFormatter.allow(RegExp(r'[A-Za-z0-9_\-]'))]),
        Text('Fees paid to this academy settle into this account through the gateway you map here.', style: HqText.sub),
        const SizedBox(height: 12),
      ],
    );
  }
}
