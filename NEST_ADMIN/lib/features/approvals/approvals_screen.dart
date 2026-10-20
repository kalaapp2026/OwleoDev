import 'package:flutter/material.dart';
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
import '../academies/academies_screen.dart';
import '../plans/plans_screen.dart';
import '../shell/nav.dart';
import '../shell/shell_data.dart';

final approvalsProvider = FutureProvider.autoDispose<Map<String, dynamic>>(
  (ref) => ref.watch(dioClientProvider).getMap('/admin/hq/approvals'),
);

void refreshApprovals(WidgetRef ref) {
  ref.invalidate(approvalsProvider);
  ref.invalidate(badgesProvider);
  ref.invalidate(academiesProvider);
  ref.invalidate(alertsProvider);
}

Tone _statusTone(String s) => switch (s) {
      'pending' => Tone.blue,
      'delayed' => Tone.gold,
      'escalated' => Tone.red,
      'approved' => Tone.green,
      'rejected' => Tone.red,
      _ => Tone.violet,
    };

/// Approvals: what is waiting for a decision, and the standard flow each kind of request follows.
class ApprovalsScreen extends ConsumerStatefulWidget {
  const ApprovalsScreen({super.key});

  @override
  ConsumerState<ApprovalsScreen> createState() => _ApprovalsScreenState();
}

class _ApprovalsScreenState extends ConsumerState<ApprovalsScreen> {
  String _tab = 'queue';
  String _filter = 'open';
  String? _history;

  @override
  Widget build(BuildContext context) {
    final data = ref.watch(approvalsProvider);
    return asyncBody(data, onRetry: () => ref.invalidate(approvalsProvider), data: (d) {
      return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: SegControl<String>(
            expand: true,
            items: const [('queue', 'Requests'), ('wf', 'Workflows')],
            value: _tab,
            onChanged: (v) => setState(() => _tab = v),
          ),
        ),
        if (_tab == 'wf') _workflows(d) else _queue(d),
      ]);
    });
  }

  // ------------------------------------------------------------------------------ requests

  Widget _queue(Map<String, dynamic> d) {
    final all = d.maps('requests');
    final c = d.obj('counts');
    final user = ref.watch(sessionProvider).user;
    final canPlan = user != null && (user.isSuper || user.role.code == 'FINANCE');
    final open = all.where((r) => !['approved', 'rejected', 'returned'].contains(r.str('status'))).toList();
    final decided = all.length - open.length;
    final list = all.where((r) {
      final s = r.str('status');
      return switch (_filter) {
        'open' => open.contains(r),
        'decided' => !open.contains(r),
        'all' => true,
        _ => s == _filter,
      };
    }).toList();

    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      if (canPlan)
        Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: HqButton("Change an academy's plan", icon: 'layers', expand: true, onPressed: () async {
            final done = await showHqModal<bool>(context, builder: (_) => const _DirectPlanModal());
            if (done == true) {
              refreshApprovals(ref);
              if (mounted) showToast(context, 'Plan changed');
            }
          }),
        ),
      HqGrid(GridKind.g4, [
        Kpi(icon: 'clock', tone: Tone.blue, label: 'Pending', value: '${c.integer('pending')}', foot: 'within the time limit'),
        Kpi(icon: 'warn', tone: Tone.gold, label: 'Delayed', value: '${c.integer('delayed')}', valueColor: Hq.gold, foot: 'past the time limit'),
        Kpi(icon: 'flag', tone: Tone.red, label: 'Escalated', value: '${c.integer('escalated')}', valueColor: Hq.red, foot: 'sent to a senior approver'),
        Kpi(icon: 'check', tone: Tone.green, label: 'Decided', value: '$decided', foot: 'approved, returned or rejected'),
      ]),
      Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: ChipRow([
          for (final (k, l, n) in [('open', 'Open', open.length), ('delayed', 'Delayed', c.integer('delayed')), ('escalated', 'Escalated', c.integer('escalated')), ('decided', 'Decided', decided), ('all', 'All', all.length)])
            HqChip(l, selected: _filter == k, count: n, onTap: () => setState(() => _filter = k)),
        ]),
      ),
      if (list.isEmpty) const EmptyNote('Nothing here'),
      for (final r in list) Padding(padding: const EdgeInsets.only(bottom: 10), child: _requestCard(r)),
    ]);
  }

  Widget _requestCard(Map<String, dynamic> r) {
    final status = r.str('status');
    final decided = ['approved', 'rejected', 'returned'].contains(status);
    final stages = r.strings('stages');
    final stage = r.integer('stage');
    final canAct = r.flag('canAct');
    final type = r.str('type');
    final history = r.maps('history');
    final details = (r['details'] as List? ?? const []).map((e) => (e as List).map((x) => x.toString()).toList()).toList();

    Widget actions() {
      if (decided) return const SizedBox.shrink();
      if (!canAct) {
        return Row(children: [
          ic('lock', 12, Hq.muted),
          const SizedBox(width: 6),
          Expanded(child: Text('Waiting on ${r.str('stageRole')}${r.str('stageRole') == 'Academy owner' ? '. HQ cannot act at this stage.' : '. Your role cannot act here.'}', style: HqText.muted.copyWith(fontSize: 12))),
        ]);
      }
      if (type == 'OWNERSHIP_TRANSFER') {
        return Wrap(spacing: 6, runSpacing: 6, children: [
          HqButton('Open in Academy transfer', icon: 'swap', small: true, kind: BtnKind.primary, onPressed: () => hqGo(context, '/transfers?request=${r.str('id')}')),
          HqButton('Reject', small: true, color: Hq.red, onPressed: () => _decide(r, 'reject')),
        ]);
      }
      if (type == 'PLAN_CHANGE') return _PlanChoice(request: r, onDone: () => refreshApprovals(ref));
      return Wrap(spacing: 6, runSpacing: 6, children: [
        HqButton('Approve', small: true, kind: BtnKind.primary, onPressed: () => _decide(r, 'approve')),
        HqButton('Return', small: true, onPressed: () => _decide(r, 'return')),
        HqButton('Reject', small: true, color: Hq.red, onPressed: () => _decide(r, 'reject')),
      ]);
    }

    return HqCard(
      radius: 14,
      padding: const EdgeInsets.all(12),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(r.str('typeLabel'), style: HqText.row.copyWith(fontSize: 13.5)),
              Text('${r.str('number')}${r.strOrNull('academy') == null ? '' : ' · ${r.str('academy')}'}', style: HqText.small),
            ]),
          ),
          Tag(status, tone: _statusTone(status)),
        ]),
        const SizedBox(height: 9),
        Text(r.str('summary'), style: HqText.body.copyWith(fontSize: 13)),
        if (details.isNotEmpty) ...[
          const SizedBox(height: 8),
          if (r.flag('fromAcademyApp')) Text('Requested in the academy app', style: HqText.sub.copyWith(fontSize: 11)),
          const SizedBox(height: 2),
          HqList([for (final p in details) KeyValueRow(p[0], p[1])]),
        ],
        const SizedBox(height: 9),
        Wrap(crossAxisAlignment: WrapCrossAlignment.center, spacing: 4, runSpacing: 4, children: [
          for (var i = 0; i < stages.length; i++) ...[
            Tag('${i < stage || status == 'approved' ? '✓ ' : ''}${stages[i]}', tone: status == 'approved' || i < stage ? Tone.green : (i == stage && !decided ? Tone.primary : Tone.mute)),
            if (i < stages.length - 1) ic('chev', 11, Hq.faint),
          ],
        ]),
        const SizedBox(height: 8),
        Text('By ${r.str('requestedBy')} · ${decided ? 'decided' : '${r.integer('ageDays')} day${r.integer('ageDays') == 1 ? '' : 's'} waiting'}', style: HqText.small.copyWith(fontSize: 11.5)),
        if (!decided) ...[const SizedBox(height: 10), actions()],
        const SizedBox(height: 6),
        Align(
          alignment: Alignment.centerLeft,
          child: HqButton('History (${history.length})', icon: 'clock', small: true, kind: BtnKind.ghost, onPressed: () => setState(() => _history = _history == r.str('id') ? null : r.str('id'))),
        ),
        if (_history == r.str('id'))
          HqList([for (final h in history) HqRow(title: h.str('text'), sub: '${h.str('who')} · ${ago(h['at'])}', wrap: true, titleStyle: HqText.row.copyWith(fontSize: 12.5))]),
      ]),
    );
  }

  Future<void> _decide(Map<String, dynamic> r, String action) async {
    final done = await showHqModal<bool>(context, builder: (_) => _DecisionModal(request: r, action: action));
    if (done == true) {
      refreshApprovals(ref);
      if (mounted) showToast(context, switch (action) { 'approve' => 'Approved', 'return' => 'Returned to the requester with your comment', _ => 'Rejected. The requester has been told why.' });
    }
  }

  // ---------------------------------------------------------------------------- workflows

  Widget _workflows(Map<String, dynamic> d) {
    final isSuper = d.flag('isSuper');
    final list = d.maps('workflows');
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(2, 0, 2, 12),
        child: Text('One standard flow per request type, applied to every academy. ${isSuper ? 'Tap − or + to change a time limit.' : 'Only a Super admin can change these.'}', style: HqText.muted.copyWith(fontSize: 12.5)),
      ),
      for (final w in list)
        Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: HqCard(
            radius: 14,
            padding: const EdgeInsets.all(12),
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Row(children: [
                Expanded(child: Text(w.str('label'), style: HqText.row.copyWith(fontSize: 14))),
                Tag(w.flag('locked') ? 'Fixed for all academies' : 'Academies may adjust', tone: w.flag('locked') ? Tone.violet : Tone.mute, icon: w.flag('locked') ? 'lock' : 'edit'),
              ]),
              const SizedBox(height: 10),
              Wrap(crossAxisAlignment: WrapCrossAlignment.center, spacing: 4, runSpacing: 4, children: [
                for (final (i, s) in ['Request', ...w.strings('stages'), 'Decision'].indexed) ...[
                  Tag(s, tone: i == 0 || i == w.strings('stages').length + 1 ? Tone.mute : Tone.primary),
                  if (i < w.strings('stages').length + 1) ic('chev', 11, Hq.faint),
                ],
              ]),
              const SizedBox(height: 8),
              HqList([
                KeyValueRow('Time limit per stage', '${w.integer('slaDays')} days',
                    trailing: isSuper
                        ? Row(mainAxisSize: MainAxisSize.min, children: [
                            _stepBtn('−', () => _sla(w, -1)),
                            const SizedBox(width: 6),
                            _stepBtn('+', () => _sla(w, 1)),
                          ])
                        : null),
                KeyValueRow('Escalates to', w.str('escalateTo')),
                Text('Rejected: back to the requester with comments. Returned: ask them to change it and ask again. The requester and approver are told at every step.', style: HqText.small.copyWith(fontSize: 12)),
              ]),
              if (isSuper)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: HqButton(w.flag('locked') ? 'Allow academies to adjust' : 'Fix for all academies', small: true, onPressed: () => _saveWorkflow(w.str('type'), {'locked': !w.flag('locked')})),
                  ),
                ),
            ]),
          ),
        ),
    ]);
  }

  Widget _stepBtn(String t, VoidCallback f) => SizedBox(width: 34, child: HqButton(t, small: true, expand: true, onPressed: f));

  void _sla(Map<String, dynamic> w, int delta) {
    final next = (w.integer('slaDays') + delta).clamp(1, 10);
    if (next == w.integer('slaDays')) return;
    _saveWorkflow(w.str('type'), {'slaDays': next});
  }

  Future<void> _saveWorkflow(String type, Map<String, dynamic> body) async {
    try {
      await ref.read(dioClientProvider).putMap('/admin/hq/approvals/workflows/$type', body: body);
      ref.invalidate(approvalsProvider);
    } on ApiException catch (e) {
      if (mounted) showToast(context, e.message);
    }
  }
}

/// Plan chips + Approve/Reject for a plan change: HQ can apply a different plan from the one asked for.
class _PlanChoice extends ConsumerStatefulWidget {
  const _PlanChoice({required this.request, required this.onDone});
  final Map<String, dynamic> request;
  final VoidCallback onDone;

  @override
  ConsumerState<_PlanChoice> createState() => _PlanChoiceState();
}

class _PlanChoiceState extends ConsumerState<_PlanChoice> {
  String? _sel;

  @override
  Widget build(BuildContext context) {
    final r = widget.request;
    final plans = ref.watch(plansProvider).valueOrNull ?? const <Map<String, dynamic>>[];
    final academy = (ref.watch(academiesProvider).valueOrNull ?? const <Map<String, dynamic>>[]).where((a) => a.str('id') == r.str('academyId')).firstOrNull;
    final requested = r.obj('payload').strOrNull('requested');
    final sel = _sel ?? r.obj('payload').strOrNull('plan');
    final students = academy?.integer('students') ?? 0;
    final curPlan = academy?.strOrNull('plan');
    final chosen = plans.where((p) => p.str('code') == sel).firstOrNull;

    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Text('Choose the plan to apply. It starts from the next renewal.', style: HqText.muted.copyWith(fontSize: 12)),
      const SizedBox(height: 8),
      Wrap(spacing: 8, runSpacing: 8, children: [
        for (final p in plans)
          Builder(builder: (_) {
            final lim = p.integerOrNull('maxStudents');
            final over = lim != null && students > lim;
            final current = p.str('code') == curPlan;
            return Opacity(
              opacity: over || current ? .45 : 1,
              child: IgnorePointer(
                ignoring: over || current,
                child: HqChip('${p.str('name')} · ${inr(p.number('price'))}${current ? ' (current)' : over ? ' (over limit)' : ''}', selected: sel == p.str('code'), onTap: () => setState(() => _sel = p.str('code'))),
              ),
            );
          }),
      ]),
      if (sel != null && requested != null && sel != requested)
        Padding(padding: const EdgeInsets.only(top: 6), child: Text('Different from the plan the academy asked for.', style: HqText.small.copyWith(color: Hq.gold, fontSize: 12))),
      const SizedBox(height: 10),
      Wrap(spacing: 6, runSpacing: 6, children: [
        HqButton('Approve ${chosen?.str('name') ?? ''} plan'.trim(), small: true, kind: BtnKind.primary, onPressed: chosen == null ? null : () async {
          try {
            final dio = ref.read(dioClientProvider);
            await dio.putMap('/admin/hq/approvals/${r.str('id')}/plan', body: {'planCode': sel});
            await dio.postMap('/admin/hq/approvals/${r.str('id')}/decide', body: {'action': 'approve', 'comment': ''});
            widget.onDone();
            if (context.mounted) showToast(context, 'Plan changed to ${chosen.str('name')}');
          } on ApiException catch (e) {
            if (context.mounted) showToast(context, e.message);
          }
        }),
        HqButton('Reject', small: true, color: Hq.red, onPressed: () async {
          final done = await showHqModal<bool>(context, builder: (_) => _DecisionModal(request: r, action: 'reject'));
          if (done == true) {
            widget.onDone();
            if (context.mounted) showToast(context, 'Rejected. The requester has been told why.');
          }
        }),
      ]),
    ]);
  }
}

class _DecisionModal extends ConsumerStatefulWidget {
  const _DecisionModal({required this.request, required this.action});
  final Map<String, dynamic> request;
  final String action;

  @override
  ConsumerState<_DecisionModal> createState() => _DecisionModalState();
}

class _DecisionModalState extends ConsumerState<_DecisionModal> {
  final _c = TextEditingController();
  String? _error;
  bool _busy = false;

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  Future<void> _go() async {
    final a = widget.action;
    if (a != 'approve' && _c.text.trim().length < 3) return setState(() => _error = 'A comment is required.');
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await ref.read(dioClientProvider).postMap('/admin/hq/approvals/${widget.request.str('id')}/decide', body: {'action': a, 'comment': _c.text.trim()});
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
    final a = widget.action;
    final r = widget.request;
    return ModalFrame(
      title: switch (a) { 'approve' => 'Approve request', 'return' => 'Return request', _ => 'Reject request' },
      sub: '${r.str('typeLabel')} · ${r.strOrNull('academy') ?? r.str('requestedBy')}',
      error: _error,
      actions: [
        HqButton('Cancel', onPressed: () => Navigator.of(context).pop()),
        HqButton(switch (a) { 'approve' => 'Approve', 'return' => 'Return to requester', _ => 'Reject' }, kind: a == 'reject' ? BtnKind.danger : BtnKind.primary, busy: _busy, onPressed: _go),
      ],
      children: [
        Text(r.str('summary'), style: HqText.body.copyWith(fontSize: 13)),
        const SizedBox(height: 12),
        HqField(
          label: 'Comment${a == 'approve' ? ' (optional)' : ''}',
          controller: _c,
          hint: a == 'approve' ? 'Add a note for the record' : 'Say what needs to change',
        ),
      ],
    );
  }
}

class _DirectPlanModal extends ConsumerStatefulWidget {
  const _DirectPlanModal();

  @override
  ConsumerState<_DirectPlanModal> createState() => _DirectPlanModalState();
}

class _DirectPlanModalState extends ConsumerState<_DirectPlanModal> {
  String? _academy;
  String? _plan;
  String _reason = 'Academy asked for it';
  String? _error;
  bool _busy = false;

  Future<void> _go() async {
    if (_academy == null || _plan == null) return setState(() => _error = 'Choose an academy and a plan.');
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await ref.read(dioClientProvider).postMap('/admin/hq/approvals/direct-plan', body: {'academyId': _academy, 'planCode': _plan, 'reason': _reason});
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
    final academies = (ref.watch(academiesProvider).valueOrNull ?? const <Map<String, dynamic>>[]).where((a) => a.str('status') != 'churned').toList();
    final plans = ref.watch(plansProvider).valueOrNull ?? const <Map<String, dynamic>>[];
    return ModalFrame(
      title: "Change an academy's plan",
      sub: 'Starts from the next renewal',
      error: _error,
      actions: [
        HqButton('Cancel', onPressed: () => Navigator.of(context).pop()),
        HqButton('Change plan', kind: BtnKind.primary, busy: _busy, onPressed: _go),
      ],
      children: [
        HqSelect<String>(
          label: 'Academy',
          value: _academy,
          hint: 'Choose an academy',
          options: [for (final a in academies) SelectOption(a.str('id'), '${a.str('name')} · ${a.strOrNull('planName') ?? 'no plan'}')],
          onChanged: (v) => setState(() => _academy = v),
        ),
        HqSelect<String>(
          label: 'New plan',
          value: _plan,
          hint: 'Choose a plan',
          options: [for (final p in plans) SelectOption(p.str('code'), '${p.str('name')} · ${inr(p.number('price'))} / mo')],
          onChanged: (v) => setState(() => _plan = v),
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
