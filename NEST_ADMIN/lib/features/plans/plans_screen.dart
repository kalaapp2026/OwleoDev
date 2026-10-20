import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/theme.dart';
import '../../core/api/api_exception.dart';
import '../../core/auth/session.dart';
import '../../core/format.dart';
import '../../core/json.dart';
import '../../core/ui/async.dart';
import '../../core/ui/controls.dart';
import '../../core/ui/icons.dart';
import '../../core/ui/layout.dart';
import '../../core/ui/overlays.dart';
import '../../core/ui/primitives.dart';
import '../../core/ui/sections.dart';
import '../shell/nav.dart';
import '../shell/shell_data.dart';

final plansProvider = FutureProvider.autoDispose<List<Map<String, dynamic>>>(
  (ref) => ref.watch(dioClientProvider).getList('/admin/hq/plans'),
);

const planModuleLabels = {
  'events': 'Events',
  'services': 'Services marketplace (academy admin login only)',
  'study': 'Study material',
  'branding': 'Custom branding',
  'priority': 'Priority support',
  'manager': 'Dedicated account manager',
};

const _planTones = ['blue', 'gold', 'violet', 'green', 'coral', 'magenta', 'primary'];

/// The bullet list on a plan card, built from its limits and extras.
List<String> planFeatures(Map<String, dynamic> p) {
  final s = p.integerOrNull('maxStudents'), t = p.integerOrNull('maxTrainers');
  return [
    s == null ? 'Unlimited students' : 'Up to $s students',
    t == null ? 'Unlimited trainers' : 'Up to $t trainers',
    'Fees, Attendance and Messages',
    'Email support',
    for (final m in p.strings('modules')) planModuleLabels[m] ?? m,
  ];
}

class PlansScreen extends ConsumerWidget {
  const PlansScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final plans = ref.watch(plansProvider);
    final alerts = ref.watch(alertsProvider).valueOrNull ?? const <HqAlert>[];
    final candidates = alerts.where((a) => a.kind == 'limit').toList();
    final user = ref.watch(sessionProvider).user;
    final canEdit = user != null && (user.isSuper || user.role.code == 'FINANCE');

    return asyncBody(plans, onRetry: () => ref.invalidate(plansProvider), data: (list) {
      return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: Row(children: [
            Expanded(child: Text('${list.length} plans. Changes apply from each academy\'s next renewal.', style: HqText.muted)),
            if (canEdit) HqButton('New plan', icon: 'plus', kind: BtnKind.primary, onPressed: () => _edit(context, ref, null, list)),
          ]),
        ),
        HqGrid(GridKind.g3, [
          for (final p in list) _PlanCard(plan: p, canEdit: canEdit, onEdit: () => _edit(context, ref, p, list), onDelete: () => _delete(context, ref, p, list)),
        ]),
        HqCard(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const CardHeader('Upgrade candidates', sub: 'Within 10% of their plan\'s student limit'),
            if (candidates.isEmpty)
              const EmptyNote('No academies close to their limit.')
            else
              HqList([
                for (final a in candidates)
                  HqRow(
                    leading: const IconTile('users', tone: Tone.gold),
                    title: a.text.split(' is at ').first,
                    sub: a.text.contains(' is at ') ? 'At ${a.text.split(' is at ').last}' : a.text,
                    trailing: ic('chev', 15, Hq.faint),
                    onTap: a.academyId == null ? null : () => hqGo(context, '/academies?open=${a.academyId}'),
                  ),
              ]),
          ]),
        ),
      ]);
    });
  }

  Future<void> _edit(BuildContext context, WidgetRef ref, Map<String, dynamic>? plan, List<Map<String, dynamic>> all) async {
    final done = await showHqModal<bool>(context, builder: (_) => _PlanForm(plan: plan));
    if (done == true) {
      ref.invalidate(plansProvider);
      ref.invalidate(alertsProvider);
      if (context.mounted) showToast(context, plan == null ? 'Plan added' : 'Plan saved');
    }
  }

  Future<void> _delete(BuildContext context, WidgetRef ref, Map<String, dynamic> plan, List<Map<String, dynamic>> all) async {
    final done = await showHqModal<bool>(context, builder: (_) => _DeletePlan(plan: plan, others: all.where((p) => p['code'] != plan['code']).toList()));
    if (done == true) {
      ref.invalidate(plansProvider);
      if (context.mounted) showToast(context, 'Plan deleted');
    }
  }
}

class _PlanCard extends StatelessWidget {
  const _PlanCard({required this.plan, required this.canEdit, required this.onEdit, required this.onDelete});
  final Map<String, dynamic> plan;
  final bool canEdit;
  final VoidCallback onEdit, onDelete;

  @override
  Widget build(BuildContext context) {
    final tone = Tone.byName(plan.strOrNull('tone'));
    return HqCard(
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(children: [
          Tag(plan.str('name'), tone: tone),
          const Spacer(),
          if (plan.flag('popular')) const Tag('Most popular', tone: Tone.green),
        ]),
        const SizedBox(height: 10),
        Text.rich(TextSpan(children: [
          TextSpan(text: inr(plan.number('price')), style: HqText.h1.copyWith(fontSize: 28, letterSpacing: -.8)),
          TextSpan(text: '  / month', style: HqText.muted),
        ])),
        const SizedBox(height: 10),
        for (final f in planFeatures(plan))
          Padding(
            padding: const EdgeInsets.only(bottom: 7),
            child: Row(children: [ic('check', 14, tone.color), const SizedBox(width: 8), Expanded(child: Text(f, style: HqText.muted))]),
          ),
        const SizedBox(height: 3),
        Container(
          padding: const EdgeInsets.only(top: 12),
          decoration: const BoxDecoration(border: Border(top: BorderSide(color: Hq.soft))),
          child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
            Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('${plan.integer('academies')}', style: HqText.h2.copyWith(fontSize: 18)),
              Text('academies', style: HqText.small),
            ]),
            Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
              Text(short(plan.number('monthly')), style: HqText.h2.copyWith(fontSize: 18)),
              Text('monthly revenue', style: HqText.small),
            ]),
          ]),
        ),
        if (canEdit) ...[
          const SizedBox(height: 12),
          Row(children: [
            Expanded(child: HqButton('Edit', icon: 'edit', onPressed: onEdit)),
            const SizedBox(width: 8),
            Expanded(child: HqButton('Delete', icon: 'trash', kind: BtnKind.danger, onPressed: onDelete)),
          ]),
        ],
      ]),
    );
  }
}

class _PlanForm extends ConsumerStatefulWidget {
  const _PlanForm({required this.plan});
  final Map<String, dynamic>? plan;

  @override
  ConsumerState<_PlanForm> createState() => _PlanFormState();
}

class _PlanFormState extends ConsumerState<_PlanForm> {
  late final _name = TextEditingController(text: widget.plan?.str('name') ?? '');
  late final _price = TextEditingController(text: widget.plan == null ? '' : widget.plan!.integer('price').toString());
  late final _students = TextEditingController(text: widget.plan?.integerOrNull('maxStudents')?.toString() ?? '');
  late final _trainers = TextEditingController(text: widget.plan?.integerOrNull('maxTrainers')?.toString() ?? '');
  late final Set<String> _mods = {...?widget.plan?.strings('modules')};
  late String _tone = widget.plan?.strOrNull('tone') ?? 'blue';
  late bool _popular = widget.plan?.flag('popular') ?? false;
  String? _error;
  bool _busy = false;

  @override
  void dispose() {
    _name.dispose();
    _price.dispose();
    _students.dispose();
    _trainers.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final name = _name.text.trim();
    final price = double.tryParse(_price.text.replaceAll(',', ''));
    if (name.length < 2) return setState(() => _error = 'Enter a plan name of at least 2 letters.');
    if (price == null || price <= 0) return setState(() => _error = 'Enter a monthly price above zero.');
    setState(() {
      _busy = true;
      _error = null;
    });
    final body = {
      'name': name,
      'price': price,
      'maxStudents': _students.text.trim(),
      'maxTrainers': _trainers.text.trim(),
      'modules': _mods.toList(),
      'tone': _tone,
      'popular': _popular,
    };
    try {
      final dio = ref.read(dioClientProvider);
      if (widget.plan == null) {
        await dio.postMap('/admin/hq/plans', body: body);
      } else {
        await dio.putMap('/admin/hq/plans/${widget.plan!.str('code')}', body: body);
      }
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
    final editing = widget.plan != null;
    return ModalFrame(
      title: editing ? 'Edit plan' : 'New plan',
      sub: editing ? '${widget.plan!.str('name')} · ${widget.plan!.integer('academies')} academies on it' : 'Set the price, limits and what is included',
      error: _error,
      actions: [
        HqButton('Cancel', onPressed: () => Navigator.of(context).pop()),
        HqButton(editing ? 'Save changes' : 'Add plan', kind: BtnKind.primary, busy: _busy, onPressed: _save),
      ],
      children: [
        HqField(label: 'Plan name', controller: _name, maxLength: 20),
        FieldRow([
          HqField(label: 'Price per month (₹)', controller: _price, keyboard: TextInputType.number, formatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]'))]),
          HqField(label: 'Student limit', controller: _students, hint: 'Unlimited', keyboard: TextInputType.number, formatters: [FilteringTextInputFormatter.digitsOnly]),
        ]),
        FieldRow([
          HqField(label: 'Trainer limit', controller: _trainers, hint: 'Unlimited', keyboard: TextInputType.number, formatters: [FilteringTextInputFormatter.digitsOnly]),
          const SizedBox.shrink(),
        ]),
        Padding(
          padding: const EdgeInsets.only(bottom: 13),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('Always included in every plan', style: HqText.label),
            const SizedBox(height: 6),
            Wrap(spacing: 6, runSpacing: 6, children: [
              for (final c in ['Fees', 'Attendance', 'Messages', 'Email support']) Tag(c, tone: Tone.mute, icon: 'lock'),
            ]),
          ]),
        ),
        Padding(
          padding: const EdgeInsets.only(bottom: 13),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('Extra features (choose any)', style: HqText.label),
            const SizedBox(height: 4),
            for (final e in planModuleLabels.entries)
              HqCheckRow(
                checked: _mods.contains(e.key),
                title: e.value,
                onChanged: (v) => setState(() => v ? _mods.add(e.key) : _mods.remove(e.key)),
              ),
          ]),
        ),
        Padding(
          padding: const EdgeInsets.only(bottom: 13),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('Colour', style: HqText.label),
            const SizedBox(height: 8),
            ChipRow([
              for (final t in _planTones)
                HqChip(
                  t == 'primary' ? 'teal' : t,
                  selected: _tone == t,
                  onTap: () => setState(() => _tone = t),
                  leading: Container(width: 9, height: 9, decoration: BoxDecoration(color: Tone.byName(t).color, shape: BoxShape.circle)),
                ),
            ]),
          ]),
        ),
        HqCheckRow(checked: _popular, title: 'Show as most popular', onChanged: (v) => setState(() => _popular = v)),
        const SizedBox(height: 8),
        Text('New price and limits apply from each academy\'s next renewal. Limits cannot go below what an academy already uses.', style: HqText.sub),
        const SizedBox(height: 14),
      ],
    );
  }
}

class _DeletePlan extends ConsumerStatefulWidget {
  const _DeletePlan({required this.plan, required this.others});
  final Map<String, dynamic> plan;
  final List<Map<String, dynamic>> others;

  @override
  ConsumerState<_DeletePlan> createState() => _DeletePlanState();
}

class _DeletePlanState extends ConsumerState<_DeletePlan> {
  late String? _to = widget.others.isEmpty ? null : widget.others.first.str('code');
  String? _error;
  bool _busy = false;

  Future<void> _go() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await ref.read(dioClientProvider).delete('/admin/hq/plans/${widget.plan.str('code')}${_to == null ? '' : '?moveTo=$_to'}');
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
    final n = widget.plan.integer('academies');
    if (widget.others.isEmpty) {
      return ModalFrame(
        title: 'Delete plan',
        sub: widget.plan.str('name'),
        actions: [HqButton('Close', onPressed: () => Navigator.of(context).pop())],
        children: [Text('This is the only plan. Add another plan first.', style: HqText.body), const SizedBox(height: 14)],
      );
    }
    return ModalFrame(
      title: 'Delete plan',
      sub: widget.plan.str('name'),
      error: _error,
      actions: [
        HqButton('Cancel', onPressed: () => Navigator.of(context).pop()),
        HqButton('Delete plan', kind: BtnKind.danger, busy: _busy, onPressed: _go),
      ],
      children: [
        Text(n > 0 ? '$n ${n == 1 ? 'academy is' : 'academies are'} on this plan. Choose where to move ${n == 1 ? 'it' : 'them'}.' : 'No academy is on this plan.', style: HqText.body),
        const SizedBox(height: 12),
        if (n > 0)
          HqSelect<String>(
            label: 'Move to',
            value: _to,
            options: [for (final p in widget.others) SelectOption(p.str('code'), '${p.str('name')} · ${inr(p.number('price'))}')],
            onChanged: (v) => setState(() => _to = v),
          ),
        Text('New academies can no longer pick it. Past invoices keep its name.', style: HqText.sub),
        const SizedBox(height: 14),
      ],
    );
  }
}
