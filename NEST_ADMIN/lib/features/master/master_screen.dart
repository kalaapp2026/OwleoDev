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
import '../../core/ui/primitives.dart';
import '../../core/ui/overlays.dart';

final masterProvider = FutureProvider.autoDispose<Map<String, dynamic>>(
  (ref) => ref.watch(dioClientProvider).getMap('/admin/hq/master'),
);

const _tabs = [('batches', 'Batch types'), ('roles', 'Roles'), ('cats', 'Categories'), ('fields', 'Required fields')];
const _singular = {'batches': 'batch type', 'roles': 'role', 'cats': 'category'};

/// Master data: the lists every academy chooses from, and the profile fields every academy must collect.
class MasterScreen extends ConsumerStatefulWidget {
  const MasterScreen({super.key});

  @override
  ConsumerState<MasterScreen> createState() => _MasterScreenState();
}

class _MasterScreenState extends ConsumerState<MasterScreen> {
  String _tab = 'cats';
  final _new = TextEditingController();
  bool _busy = false;

  @override
  void dispose() {
    _new.dispose();
    super.dispose();
  }

  Future<void> _run(Future<void> Function() f, String ok) async {
    try {
      await f();
      ref.invalidate(masterProvider);
      if (mounted && ok.isNotEmpty) showToast(context, ok);
    } on ApiException catch (e) {
      if (mounted) showToast(context, e.message);
    }
  }

  Future<void> _add() async {
    final n = _new.text.trim();
    if (n.length < 2) return showToast(context, 'Enter a name.');
    setState(() => _busy = true);
    await _run(() => ref.read(dioClientProvider).postMap('/admin/hq/master/$_tab', body: {'name': n}), 'Added $n');
    if (mounted) {
      setState(() => _busy = false);
      _new.clear();
    }
  }

  @override
  Widget build(BuildContext context) {
    final sup = ref.watch(sessionProvider).user?.isSuper ?? false;
    return asyncBody(ref.watch(masterProvider), onRetry: () => ref.invalidate(masterProvider), data: (d) {
      final history = d.maps('history');
      return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: ChipRow([for (final (k, l) in _tabs) HqChip(l, selected: _tab == k, onTap: () => setState(() => _tab = k))], scroll: true),
        ),
        if (!sup)
          HqCard(
            margin: const EdgeInsets.only(bottom: 12),
            padding: const EdgeInsets.all(12),
            child: Row(children: [
              ic('lock', 13, Hq.muted),
              const SizedBox(width: 8),
              Expanded(child: Text('Global changes can only be made by a Super admin. You can view the current setup.', style: HqText.muted.copyWith(fontSize: 12.5))),
            ]),
          ),
        if (_tab == 'fields') _fields(d, sup) else _list(d, sup),
        HqCard(
          margin: const EdgeInsets.only(top: 12),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            const CardHeader('Configuration history', sub: 'Every global change is recorded', bottom: 6),
            if (history.isEmpty) const EmptyNote('No changes yet', padding: 14),
            HqList([for (final h in history) HqRow(title: h.str('text'), wrap: true, sub: '${h.str('who')} · ${ago(h['at'])}')]),
          ]),
        ),
      ]);
    });
  }

  Widget _fields(Map<String, dynamic> d, bool sup) {
    final fields = d.maps('fields');
    return HqCard(
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        const CardHeader('Required fields', sub: 'Applies to every academy. Profiles that miss a required field are flagged in Users.', bottom: 6),
        HqList([
          for (final f in fields)
            HqRow(
              title: f.str('label'),
              sub: '${num0(f.integer('missing'))} profiles are missing this',
              trailing: HqSwitch(
                value: f.flag('on'),
                onChanged: sup ? (v) => _run(() => ref.read(dioClientProvider).putMap('/admin/hq/master/fields/${f.str('key')}', body: {'required': v}), '') : (_) {},
              ),
            ),
        ]),
      ]),
    );
  }

  Widget _list(Map<String, dynamic> d, bool sup) {
    final list = d.maps(_tab);
    final active = list.where((x) => x.flag('active')).length;
    final title = _tabs.firstWhere((t) => t.$1 == _tab).$2;
    return HqCard(
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        CardHeader(title, sub: '$active active, ${list.length - active} inactive. Applied across all academies.', bottom: 12),
        if (sup)
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Expanded(child: HqField(label: 'New ${_singular[_tab]}', controller: _new, hint: 'Add a new ${_singular[_tab]}', bottom: 0, onSubmitted: (_) => _add())),
              const SizedBox(width: 8),
              Padding(padding: const EdgeInsets.only(top: 22), child: HqButton('Add', icon: 'plus', kind: BtnKind.primary, busy: _busy, onPressed: _add)),
            ]),
          ),
        HqList([
        for (final x in list)
          HqRow(
            title: x.str('name'),
            titleStyle: x.flag('active') ? null : HqText.row.copyWith(color: Hq.faint, decoration: TextDecoration.lineThrough),
            sub: !x.flag('active')
                ? 'Inactive. Existing records keep it.'
                : x['academies'] == null
                    ? 'Available to every academy'
                    : '${x.integer('academies')} academies · ${num0(x.integer('users'))} active users',
            trailing: sup
                ? HqButton(x.flag('active') ? 'Deactivate' : 'Reactivate', small: true, onPressed: () => _run(() => ref.read(dioClientProvider).putMap('/admin/hq/master/items/${x.str('id')}', body: {'active': !x.flag('active')}), '${x.str('name')} ${x.flag('active') ? 'deactivated' : 'reactivated'}'))
                : Tag(x.flag('active') ? 'Active' : 'Inactive', tone: x.flag('active') ? Tone.green : Tone.mute),
          ),
        ]),
      ]),
    );
  }
}
