import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/theme.dart';
import '../../core/auth/session.dart';
import '../../core/ui/controls.dart';
import '../../core/ui/primitives.dart';
import 'modules.dart';
import 'nav.dart';
import 'screens.dart';
import 'workspace.dart';

/// Checks the signed-in role may open a module before showing it. The server refuses the data
/// regardless; this is so a Support admin sees a clear "restricted" page instead of a screen full
/// of failed requests.
class ModuleGate extends ConsumerWidget {
  const ModuleGate(this.id, {super.key});
  final String id;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user = ref.watch(sessionProvider).user;
    if (user == null) return const SizedBox.shrink();
    if (!user.can(id)) return _Restricted(module: hqModules[id]?.title ?? 'This module', roleLabel: user.role.label);
    final finance = ref.watch(workspaceProvider);
    if (!workspaceAllows(id, finance: finance)) return _WrongWorkspace(module: hqModules[id]?.title ?? 'This module', finance: finance);
    return screenFor(id);
  }
}

/// Finance and business operations are never open together; this explains it and offers the switch.
class _WrongWorkspace extends ConsumerWidget {
  const _WrongWorkspace({required this.module, required this.finance});
  final String module;
  final bool finance;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final canFinance = ref.watch(sessionProvider).user?.can('finance') ?? false;
    return HqCard(
      padding: const EdgeInsets.symmetric(vertical: 34, horizontal: 18),
      child: Column(children: [
        IconTile(finance ? 'bld' : 'wallet', tone: Tone.gold, size: 48, iconSize: 22),
        const SizedBox(height: 12),
        Text(finance ? 'Business operations are hidden' : 'Finance is a separate workspace', style: HqText.title),
        const SizedBox(height: 6),
        ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 380),
          child: Text(finance ? '$module is part of business operations. Go back to operations to open it.' : '$module is part of Finance. Open Finance with the code sent to your email; business operations are hidden while it is open.', textAlign: TextAlign.center, style: HqText.muted),
        ),
        const SizedBox(height: 16),
        if (finance) HqButton('Back to operations', icon: 'bld', onPressed: () => backToOperations(context, ref))
        else if (canFinance) HqButton('Open Finance', icon: 'wallet', kind: BtnKind.primary, onPressed: () => showOpenFinance(context, ref)),
      ]),
    );
  }
}

class _Restricted extends StatelessWidget {
  const _Restricted({required this.module, required this.roleLabel});
  final String module, roleLabel;

  @override
  Widget build(BuildContext context) {
    return HqCard(
      padding: const EdgeInsets.symmetric(vertical: 34, horizontal: 18),
      child: Column(
        children: [
          const IconTile('lock', tone: Tone.red, size: 48, iconSize: 22),
          const SizedBox(height: 12),
          Text('This module is restricted', style: HqText.title),
          const SizedBox(height: 6),
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 360),
            child: Text(
              '$module is not available to the $roleLabel role. Ask a Super admin for access.',
              textAlign: TextAlign.center,
              style: HqText.muted,
            ),
          ),
          const SizedBox(height: 16),
          HqButton('Back to dashboard', icon: 'home', onPressed: () => hqGo(context, '/overview')),
        ],
      ),
    );
  }
}
