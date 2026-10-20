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
import '../approvals/approvals_screen.dart';
import '../shell/nav.dart';
import '../users/users_screen.dart';

final exitsProvider = FutureProvider.autoDispose<Map<String, dynamic>>(
  (ref) => ref.watch(dioClientProvider).getMap('/admin/hq/exits'),
);

const _clearances = ['Outstanding dues cleared', 'Responsibilities handed over', 'Assets and data returned'];
const _stateLabel = {'approval': 'In approval', 'clearance': 'Clearances', 'ready': 'Ready to deactivate', 'done': 'Completed'};
const _stateTone = {'approval': Tone.blue, 'clearance': Tone.gold, 'ready': Tone.green, 'done': Tone.mute};

/// Exits: someone leaving, from approval through clearances to removed access.
class ExitsScreen extends ConsumerWidget {
  const ExitsScreen({super.key});

  void _refresh(WidgetRef ref) {
    ref.invalidate(exitsProvider);
    ref.invalidate(approvalsProvider);
    ref.invalidate(usersProvider);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final canWrite = ref.watch(sessionProvider).user?.canWrite ?? false;
    return asyncBody(ref.watch(exitsProvider), onRetry: () => ref.invalidate(exitsProvider), data: (d) {
      final items = d.maps('items');
      return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        HqGrid(GridKind.g4, [
          Kpi(icon: 'flow', tone: Tone.blue, label: 'In approval', value: '${d.integer('approval')}', foot: 'waiting on the workflow'),
          Kpi(icon: 'clock', tone: Tone.gold, label: 'Clearances', value: '${d.integer('clearance')}', foot: 'dues, handover, assets'),
          Kpi(icon: 'check', tone: Tone.green, label: 'Ready to deactivate', value: '${d.integer('ready')}', foot: 'all clearances done'),
          Kpi(icon: 'exit', tone: Tone.mute, label: 'Completed', value: '${d.integer('done')}', foot: 'access removed, record kept'),
        ]),
        Padding(
          padding: const EdgeInsets.only(top: 4, bottom: 12),
          child: Align(
            alignment: Alignment.centerRight,
            child: canWrite
                ? HqButton('New exit request', icon: 'plus', kind: BtnKind.primary, onPressed: () async {
                    final done = await showHqModal<bool>(context, builder: (_) => const _NewExit());
                    if (done == true) {
                      _refresh(ref);
                      if (context.mounted) showToast(context, 'Exit request sent for approval');
                    }
                  })
                : Row(mainAxisSize: MainAxisSize.min, children: [ic('lock', 12, Hq.muted), const SizedBox(width: 6), Text('Your role can view exits only', style: HqText.muted.copyWith(fontSize: 12))]),
          ),
        ),
        if (items.isEmpty) const EmptyNote('No exits yet'),
        LayoutBuilder(builder: (context, c) {
          final cols = c.maxWidth >= 900 ? 2 : 1;
          return Wrap(spacing: 10, runSpacing: 10, children: [
            for (final x in items) SizedBox(width: (c.maxWidth - (cols - 1) * 10) / cols, child: _ExitCard(exit: x, canWrite: canWrite, onChanged: () => _refresh(ref))),
          ]);
        }),
      ]);
    });
  }
}

class _ExitCard extends ConsumerWidget {
  const _ExitCard({required this.exit, required this.canWrite, required this.onChanged});
  final Map<String, dynamic> exit;
  final bool canWrite;
  final VoidCallback onChanged;

  Future<void> _tick(BuildContext context, WidgetRef ref, int i, bool v) async {
    try {
      await ref.read(dioClientProvider).postMap('/admin/hq/exits/${exit.str('id')}/clearance', body: {'index': i, 'done': v});
      onChanged();
    } on ApiException catch (e) {
      if (context.mounted) showToast(context, e.message);
    }
  }

  Future<void> _complete(BuildContext context, WidgetRef ref) async {
    final scope = exit.strOrNull('scope');
    final ok = await confirmHq(
      context,
      title: 'Remove access?',
      body: scope == null ? '${exit.str('name')} is signed out and loses access to every academy. The profile and its history are kept.' : '${exit.str('name')} loses access to $scope only. Other academies stay active.',
      confirmLabel: 'Deactivate',
      danger: true,
    );
    if (!ok) return;
    try {
      await ref.read(dioClientProvider).postMap('/admin/hq/exits/${exit.str('id')}/complete');
      onChanged();
      if (context.mounted) showToast(context, 'Access removed');
    } on ApiException catch (e) {
      if (context.mounted) showToast(context, e.message);
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = exit.str('state');
    final checks = (exit['checks'] as List? ?? const []).map((e) => e == true).toList();
    final scope = exit.strOrNull('scope');
    final locked = s == 'approval' || s == 'done' || !canWrite;
    return HqCard(
      radius: 14,
      padding: const EdgeInsets.all(12),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(children: [
          Avatar(initials(exit.str('name')), tone: roleTone(exit.str('role'))),
          const SizedBox(width: 10),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(exit.str('name'), maxLines: 1, overflow: TextOverflow.ellipsis, style: HqText.row),
              Text('${exit.str('userRef')} · ${exit.str('role')} · ${exit.str('academy')}', maxLines: 1, overflow: TextOverflow.ellipsis, style: HqText.small),
            ]),
          ),
          Tag(_stateLabel[s] ?? s, tone: _stateTone[s] ?? Tone.mute),
        ]),
        const SizedBox(height: 8),
        Text('${exit.str('reason')} · effective ${fd(exit['effective'])}', style: HqText.muted.copyWith(fontSize: 12.5)),
        if (scope != null)
          Padding(padding: const EdgeInsets.only(top: 8), child: Tag('Only $scope access is removed. Other academies stay active.', tone: Tone.violet)),
        const SizedBox(height: 8),
        HqList([
          HqRow(
            leading: Tag(s == 'approval' ? 'Waiting' : '✓ Done', tone: s == 'approval' ? Tone.blue : Tone.green),
            title: 'Approval',
            sub: s == 'approval' ? 'Routed through the Exit workflow${exit.strOrNull('approval') == null ? '' : ' (${exit.str('approval')})'}' : 'Approved through the Exit workflow',
            trailing: s == 'approval' ? HqButton('Open', small: true, onPressed: () => hqGo(context, '/approvals')) : null,
          ),
          for (var i = 0; i < _clearances.length; i++)
            HqCheckRow(checked: i < checks.length && checks[i], title: _clearances[i], onChanged: locked ? null : (v) => _tick(context, ref, i, v)),
        ]),
        if (s == 'ready' && canWrite)
          Padding(padding: const EdgeInsets.only(top: 10), child: Align(alignment: Alignment.centerLeft, child: HqButton('Deactivate ${scope == null ? 'access' : '$scope access'}', icon: 'exit', small: true, kind: BtnKind.primary, onPressed: () => _complete(context, ref)))),
        if (s == 'done') Padding(padding: const EdgeInsets.only(top: 8), child: Text('Access removed. The profile and its history are kept for records.', style: HqText.muted.copyWith(fontSize: 12))),
      ]),
    );
  }
}

const _reasons = ['Relocating to another city', 'Course completed', 'Fees and schedule conflict', 'Moving to a full-time role elsewhere', 'Left the academy', 'Other'];

class _NewExit extends ConsumerStatefulWidget {
  const _NewExit();

  @override
  ConsumerState<_NewExit> createState() => _NewExitState();
}

class _NewExitState extends ConsumerState<_NewExit> {
  String _q = '';
  List<Map<String, dynamic>> _results = const [];
  Map<String, dynamic>? _person;
  Map<String, dynamic>? _detail;
  String _scope = '*';
  String _reason = _reasons.first;
  DateTime _eff = DateTime.now().add(const Duration(days: 7));
  String? _error;
  bool _busy = false;
  int _seq = 0;

  Future<void> _search(String v) async {
    _q = v;
    final mine = ++_seq;
    if (v.trim().length < 2) return setState(() => _results = const []);
    final r = await ref.read(dioClientProvider).getMap('/admin/hq/users', query: {'q': v.trim(), 'limit': '8'});
    if (mounted && mine == _seq) setState(() => _results = r.maps('items'));
  }

  Future<void> _pick(Map<String, dynamic> p) async {
    setState(() {
      _person = p;
      _scope = '*';
    });
    final d = await ref.read(dioClientProvider).getMap('/admin/hq/users/${p.str('id')}');
    if (mounted) setState(() => _detail = d);
  }

  Future<void> _go() async {
    if (_person == null) return setState(() => _error = 'Choose the person.');
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await ref.read(dioClientProvider).postMap('/admin/hq/exits', body: {
        'userId': _person!.str('id'),
        'academyId': _scope == '*' ? '' : _scope,
        'reason': _reason,
        'effective': '${_eff.year}-${_eff.month.toString().padLeft(2, '0')}-${_eff.day.toString().padLeft(2, '0')}',
      });
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
    final academies = (_detail?.maps('academies') ?? const []).where((a) => a.str('status') == 'Active').toList();
    return ModalFrame(
      title: 'New exit request',
      sub: 'Goes through the Exit workflow before access is removed',
      error: _error,
      actions: [
        HqButton('Cancel', onPressed: () => Navigator.of(context).pop()),
        HqButton('Send for approval', kind: BtnKind.primary, busy: _busy, onPressed: _go),
      ],
      children: [
        if (_person == null) ...[
          SearchBox(hint: 'Search name, user ID or mobile', initial: _q, onChanged: _search),
          const SizedBox(height: 10),
          if (_results.isEmpty && _q.trim().length >= 2) const EmptyNote('No one matches', padding: 14),
          for (final p in _results)
            HqRow(
              leading: Avatar(initials(p.str('name')), tone: roleTone(p.str('role')), size: 32),
              title: p.str('name'),
              sub: '${p.str('ref')} · ${p.str('role')} · ${p.str('academy')}',
              onTap: () => _pick(p),
            ),
          const SizedBox(height: 8),
        ] else ...[
          HqRow(
            leading: Avatar(initials(_person!.str('name')), tone: roleTone(_person!.str('role')), size: 32),
            title: _person!.str('name'),
            sub: '${_person!.str('ref')} · ${_person!.str('role')} · ${_person!.str('academy')}',
            trailing: HqButton('Change', small: true, onPressed: () => setState(() {
                  _person = null;
                  _detail = null;
                })),
          ),
          const SizedBox(height: 12),
          HqSelect<String>(
            label: 'Access to remove',
            value: _scope,
            searchable: false,
            options: [const SelectOption('*', 'All academies'), for (final a in academies) SelectOption(a.str('academyId'), 'Only ${a.str('academy')}')],
            onChanged: (v) => setState(() => _scope = v),
          ),
          HqSelect<String>(label: 'Reason', value: _reason, searchable: false, options: [for (final r in _reasons) SelectOption(r, r)], onChanged: (v) => setState(() => _reason = v)),
          Text('EFFECTIVE FROM', style: HqText.th),
          const SizedBox(height: 6),
          HqButton(fd('${_eff.year}-${_eff.month.toString().padLeft(2, '0')}-${_eff.day.toString().padLeft(2, '0')}'), icon: 'cal', expand: true, onPressed: () async {
            final d = await pickHqDate(context, initial: _eff, first: DateTime.now().subtract(const Duration(days: 30)), last: DateTime.now().add(const Duration(days: 365)));
            if (d != null) setState(() => _eff = d);
          }),
          const SizedBox(height: 14),
        ],
      ],
    );
  }
}
