import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/theme.dart';
import '../../core/api/api_exception.dart';
import '../../core/auth/session.dart';
import '../../core/download.dart';
import '../../core/format.dart';
import '../../core/json.dart';
import '../../core/ui/async.dart';
import '../../core/ui/controls.dart';
import '../../core/ui/overlays.dart';
import '../../core/ui/primitives.dart';
import '../users/users_screen.dart' show FieldRow2;

typedef ReportQuery = ({String? academy, int months});

final reportsProvider = FutureProvider.autoDispose.family<Map<String, dynamic>, ReportQuery>(
  (ref, q) => ref.watch(dioClientProvider).getMap('/admin/hq/reports', query: {'academy': ?q.academy, 'months': '${q.months}'}),
);

Tone _tone(String t) => switch (t) {
      'blue' => Tone.blue,
      'gold' => Tone.gold,
      'violet' => Tone.violet,
      'green' => Tone.green,
      'coral' => Tone.coral,
      'magenta' => Tone.magenta,
      _ => Tone.primary,
    };

/// Reports: CSV exports for authorised roles, and the audit trail of what HQ staff changed.
class ReportsScreen extends ConsumerStatefulWidget {
  const ReportsScreen({super.key});

  @override
  ConsumerState<ReportsScreen> createState() => _ReportsScreenState();
}

class _ReportsScreenState extends ConsumerState<ReportsScreen> {
  ReportQuery _q = (academy: null, months: 12);
  String? _busy;

  Future<void> _export(Map<String, dynamic> r) async {
    setState(() => _busy = r.str('key'));
    try {
      final d = await ref.read(dioClientProvider).getMap('/admin/hq/reports/${r.str('key')}', query: {'academy': ?_q.academy, 'months': '${_q.months}'});
      final rows = <List<Object?>>[
        d.strings('headers'),
        for (final row in d['rows'] as List) (row as List).cast<Object?>(),
      ];
      downloadText('owleo-${r.str('key')}-${DateTime.now().toIso8601String().substring(0, 10)}.csv', csvText(rows));
      ref.invalidate(reportsProvider);
      if (mounted) showToast(context, 'File ready: ${r.str('name')}');
    } on ApiException catch (e) {
      if (mounted) showToast(context, e.message);
    } finally {
      if (mounted) setState(() => _busy = null);
    }
  }

  @override
  Widget build(BuildContext context) {
    final canExport = ref.watch(sessionProvider).user?.canExport ?? false;
    return asyncBody(ref.watch(reportsProvider(_q)), onRetry: () => ref.invalidate(reportsProvider), data: (d) {
      final reports = d.maps('reports');
      final audit = d.maps('audit');
      final academies = d.maps('academies');
      return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        HqCard(
          padding: const EdgeInsets.all(12),
          margin: const EdgeInsets.only(bottom: 12),
          child: Row(children: [
            const Tag('Optional', tone: Tone.violet),
            const SizedBox(width: 10),
            Expanded(child: Text('Use this only if the dashboard summaries are not enough. Exports are limited to authorised roles.', style: HqText.muted.copyWith(fontSize: 12.5))),
          ]),
        ),
        FieldRow2([
          HqSelect<String>(
            label: 'Academy',
            value: _q.academy ?? '*',
            options: [const SelectOption('*', 'All academies'), for (final a in academies) SelectOption(a.str('id'), a.str('name'))],
            onChanged: (v) => setState(() => _q = (academy: v == '*' ? null : v, months: _q.months)),
          ),
          HqSelect<String>(
            label: 'Period',
            value: '${_q.months}',
            searchable: false,
            options: const [SelectOption('1', 'This month'), SelectOption('3', 'Last 3 months'), SelectOption('12', 'Last 12 months')],
            onChanged: (v) => setState(() => _q = (academy: _q.academy, months: int.parse(v))),
          ),
        ]),
        LayoutBuilder(builder: (context, c) {
          final cols = c.maxWidth >= 900 ? 2 : 1;
          return Wrap(spacing: 10, runSpacing: 10, children: [
            for (final r in reports)
              SizedBox(
                width: (c.maxWidth - (cols - 1) * 10) / cols,
                child: HqCard(
                  radius: 14,
                  padding: const EdgeInsets.all(12),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                    Row(children: [
                      IconTile(r.str('icon'), tone: _tone(r.str('tone')), size: 36, iconSize: 17),
                      const SizedBox(width: 11),
                      Expanded(
                        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          Text(r.str('name'), style: HqText.row),
                          Text(r.str('description'), style: HqText.small),
                        ]),
                      ),
                      Text.rich(TextSpan(children: [TextSpan(text: num0(r.integer('rows')), style: HqText.row.copyWith(fontSize: 15)), TextSpan(text: ' rows', style: HqText.sub.copyWith(fontSize: 10.5))])),
                    ]),
                    const SizedBox(height: 10),
                    Align(
                      alignment: Alignment.centerLeft,
                      child: HqButton(canExport ? 'Export CSV' : 'Export not allowed for your role', icon: canExport ? 'dl' : 'lock', small: true, busy: _busy == r.str('key'), onPressed: canExport ? () => _export(r) : null),
                    ),
                  ]),
                ),
              ),
          ]);
        }),
        HqCard(
          margin: const EdgeInsets.only(top: 12),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            const CardHeader('Audit trail', sub: 'Critical changes, approvals and account status updates', bottom: 6),
            if (audit.isEmpty) const EmptyNote('Nothing recorded yet', padding: 14),
            HqList([for (final l in audit) HqRow(title: l.str('text'), wrap: true, sub: '${l.str('who')} · ${ago(l['at'])}')]),
          ]),
        ),
      ]);
    });
  }
}
