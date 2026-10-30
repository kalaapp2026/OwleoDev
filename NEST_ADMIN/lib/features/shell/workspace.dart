import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/theme.dart';
import '../../core/api/api_exception.dart';
import '../../core/auth/session.dart';
import '../../core/ui/controls.dart';
import '../../core/ui/overlays.dart';
import 'nav.dart';

/// Revenue, collections and invoicing live in their own workspace. Business operations and Finance are
/// never open together: opening one hides the other.
const Set<String> financeModules = {'finance', 'collections', 'invoicing', 'payments'};

/// Whether [module] may be shown in the current workspace. `welcome` is always allowed.
bool workspaceAllows(String module, {required bool finance}) {
  if (module == 'welcome') return true;
  return finance ? financeModules.contains(module) : !financeModules.contains(module);
}

/// `true` while the Finance workspace is open. The server holds the real state (it refuses finance data
/// without it), so a reload picks it back up; this mirrors it for the screens.
class WorkspaceController extends StateNotifier<bool> {
  WorkspaceController(this._ref, bool signedIn) : super(false) {
    if (signedIn) _load();
  }

  final Ref _ref;

  Future<void> _load() async {
    try {
      final r = await _ref.read(dioClientProvider).getMap('/admin/hq/workspace');
      if (mounted) {
        state = r['finance'] == true;
        NavHistory.home = state ? '/finance' : '/overview';
      }
    } catch (_) {
      // Stays in business operations; opening Finance is always an explicit step.
    }
  }

  /// Sends the code to the signed-in person's email. Returns the masked address.
  Future<String> sendCode() async {
    final r = await _ref.read(dioClientProvider).postMap('/admin/hq/workspace/finance/code');
    return (r['sentTo'] ?? '').toString();
  }

  Future<void> open(String code) async {
    await _ref.read(dioClientProvider).postMap('/admin/hq/workspace/finance/open', body: {'code': code});
    NavHistory.hq.clear();
    NavHistory.home = '/finance';
    state = true;
  }

  Future<void> close() async {
    try {
      await _ref.read(dioClientProvider).delete('/admin/hq/workspace/finance');
    } catch (_) {
      // Closing must always work on this side, even if the server is unreachable.
    }
    NavHistory.hq.clear();
    NavHistory.home = '/overview';
    state = false;
  }
}

final workspaceProvider = StateNotifierProvider<WorkspaceController, bool>((ref) {
  final signedIn = ref.watch(sessionProvider.select((s) => s.status == SessionStatus.signedIn));
  return WorkspaceController(ref, signedIn);
});

/// Asks for the emailed code, then opens Finance and lands on its home.
Future<void> showOpenFinance(BuildContext context, WidgetRef ref) async {
  final ok = await showHqModal<bool>(context, width: 440, builder: (_) => const _OpenFinance());
  if (ok == true && context.mounted) {
    context.go('/finance');
    showToast(context, 'Finance is open. Business operations are hidden.');
  }
}

Future<void> backToOperations(BuildContext context, WidgetRef ref) async {
  await ref.read(workspaceProvider.notifier).close();
  if (context.mounted) {
    context.go('/overview');
    showToast(context, 'Back in business operations. Finance is hidden.');
  }
}

class _OpenFinance extends ConsumerStatefulWidget {
  const _OpenFinance();

  @override
  ConsumerState<_OpenFinance> createState() => _OpenFinanceState();
}

class _OpenFinanceState extends ConsumerState<_OpenFinance> {
  final _code = TextEditingController();
  String? _sentTo, _error;
  bool _busy = false, _sending = false;

  @override
  void dispose() {
    _code.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    setState(() {
      _sending = true;
      _error = null;
    });
    try {
      final to = await ref.read(workspaceProvider.notifier).sendCode();
      if (mounted) setState(() => _sentTo = to);
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  Future<void> _open() async {
    if (!RegExp(r'^\d{6}$').hasMatch(_code.text.trim())) return setState(() => _error = 'Enter the 6-digit code.');
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await ref.read(workspaceProvider.notifier).open(_code.text.trim());
      if (mounted) Navigator.of(context).pop(true);
    } on ApiException catch (e) {
      setState(() {
        _busy = false;
        _error = e.message;
      });
    }
  }

  @override
  Widget build(BuildContext context) => ModalFrame(
        title: 'Open Finance',
        sub: 'Kept apart from business operations',
        error: _error,
        actions: [HqButton('Cancel', onPressed: () => Navigator.of(context).pop()), HqButton('Open Finance', kind: BtnKind.primary, busy: _busy, onPressed: _open)],
        children: [
          Text('Revenue and billing live in their own workspace. While it is open, business operations are hidden, and the other way round. Enter the 6-digit code sent to your registered email.', style: HqText.muted.copyWith(fontSize: 12.5, height: 1.5)),
          const SizedBox(height: 12),
          HqField(label: 'Code', controller: _code, hint: '6 digits', keyboard: TextInputType.number, maxLength: 6, onSubmitted: (_) => _open()),
          Row(children: [
            HqButton(_sentTo == null ? 'Send code' : 'Send again', small: true, busy: _sending, onPressed: _send),
            const SizedBox(width: 10),
            if (_sentTo != null) Expanded(child: Text('Code sent to $_sentTo', style: HqText.small)),
          ]),
          const SizedBox(height: 14),
        ],
      );
}
