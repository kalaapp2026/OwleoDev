import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/theme.dart';
import '../../core/ui/async.dart';
import '../../core/ui/icons.dart';
import '../../core/ui/layout.dart';
import '../../core/ui/primitives.dart';
import '../shell/nav.dart';
import '../shell/shell_data.dart';

/// Everything that needs a look today, grouped by what kind of problem it is.
class AlertsScreen extends ConsumerWidget {
  const AlertsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final alerts = ref.watch(alertsProvider);
    return asyncBody(alerts, onRetry: () => ref.invalidate(alertsProvider), data: (list) {
      final groups = <String, List<HqAlert>>{};
      for (final a in list) {
        groups.putIfAbsent(a.title, () => []).add(a);
      }
      return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        if (groups.isNotEmpty)
          HqGrid(GridKind.g4, [
            for (final e in groups.entries)
              Kpi(icon: e.value.first.icon, tone: Tone.byName(e.value.first.tone), label: e.key, value: '${e.value.length}', foot: 'open items'),
          ]),
        HqCard(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const CardHeader('All alerts', sub: 'Select one to open the academy'),
            if (list.isEmpty)
              const EmptyNote('Nothing needs a look right now. Alerts appear here when a bill is overdue, a demo is ending, an academy nears its plan limit or goes quiet.')
            else
              HqList([
                for (final a in list)
                  HqRow(
                    leading: IconTile(a.icon, tone: Tone.byName(a.tone)),
                    title: a.title,
                    sub: a.text,
                    wrap: true,
                    trailing: ic('chev', 15, Hq.faint),
                    onTap: a.academyId == null ? null : () => hqGo(context, '/academies?open=${a.academyId}'),
                  ),
              ]),
          ]),
        ),
      ]);
    });
  }
}
