import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

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
import '../shell/shell_data.dart';
import '../users/users_screen.dart' show FieldRow2;

final transfersProvider = FutureProvider.autoDispose<Map<String, dynamic>>(
  (ref) => ref.watch(dioClientProvider).getMap('/admin/hq/transfers'),
);

void refreshTransfers(WidgetRef ref) {
  ref.invalidate(transfersProvider);
  ref.invalidate(approvalsProvider);
  ref.invalidate(badgesProvider);
}

const _stepTone = {'review': (Tone.blue, 'Needs your review'), 'otp': (Tone.gold, 'Waiting for OTPs'), 'done': (Tone.green, 'Transferred'), 'rejected': (Tone.red, 'Rejected')};

/// Academy transfer: an academy changes hands only after both owners confirm with their own code.
class TransfersScreen extends ConsumerStatefulWidget {
  const TransfersScreen({super.key});

  @override
  ConsumerState<TransfersScreen> createState() => _TransfersScreenState();
}

class _TransfersScreenState extends ConsumerState<TransfersScreen> {
  String _f = 'open';
  String? _history;
  bool _opened = false;

  /// Arriving from Approvals with a request id in the address opens that request's transfer.
  Future<void> _openFromRequest() async {
    if (_opened) return;
    final req = GoRouterState.of(context).uri.queryParameters['request'];
    if (req == null) return;
    _opened = true;
    try {
      await ref.read(dioClientProvider).postMap('/admin/hq/transfers/from-request/$req');
      refreshTransfers(ref);
    } on ApiException catch (e) {
      if (mounted) showToast(context, e.message);
    }
  }

  @override
  Widget build(BuildContext context) {
    WidgetsBinding.instance.addPostFrameCallback((_) => _openFromRequest());
    final canWrite = ref.watch(sessionProvider).user?.canWrite ?? false;
    return asyncBody(ref.watch(transfersProvider), onRetry: () => ref.invalidate(transfersProvider), data: (d) {
      final all = d.maps('items');
      bool match(Map<String, dynamic> t) => switch (_f) {
            'open' => t.str('step') == 'review' || t.str('step') == 'otp',
            'done' => t.str('step') == 'done',
            'rej' => t.str('step') == 'rejected',
            _ => true,
          };
      final list = all.where(match).toList();
      return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        HqGrid(GridKind.g4, [
          Kpi(icon: 'swap', tone: Tone.gold, label: 'Open transfers', value: '${d.integer('open')}', foot: 'not finished yet'),
          Kpi(icon: 'clock', tone: Tone.blue, label: 'Needs review', value: '${d.integer('review')}', foot: 'start verification'),
          Kpi(icon: 'lock', tone: Tone.violet, label: 'Waiting for OTPs', value: '${d.integer('otp')}', foot: 'owners still to confirm'),
          Kpi(icon: 'check', tone: Tone.green, label: 'Transferred', value: '${d.integer('done')}', foot: 'completed'),
        ]),
        Padding(
          padding: const EdgeInsets.only(top: 4, bottom: 12),
          child: Row(children: [
            Expanded(
              child: ChipRow([
                for (final (k, l, n) in [('open', 'Open', d.integer('open')), ('done', 'Transferred', d.integer('done')), ('rej', 'Rejected', d.integer('rejected')), ('all', 'All', all.length)])
                  HqChip(l, selected: _f == k, count: n, onTap: () => setState(() => _f = k)),
              ], scroll: true),
            ),
            if (canWrite)
              HqButton('New', icon: 'plus', small: true, kind: BtnKind.primary, onPressed: () async {
                final done = await showHqModal<bool>(context, builder: (_) => _NewTransfer(academies: d.maps('academies')));
                if (done == true) {
                  refreshTransfers(ref);
                  if (context.mounted) showToast(context, 'Transfer opened');
                }
              }),
          ]),
        ),
        if (list.isEmpty) const EmptyNote('No transfers here'),
        LayoutBuilder(builder: (context, c) {
          final cols = c.maxWidth >= 900 ? 2 : 1;
          return Wrap(spacing: 10, runSpacing: 10, children: [
            for (final t in list)
              SizedBox(
                width: (c.maxWidth - (cols - 1) * 10) / cols,
                child: _TransferCard(t: t, canWrite: canWrite, showHistory: _history == t.str('id'), onHistory: () => setState(() => _history = _history == t.str('id') ? null : t.str('id'))),
              ),
          ]);
        }),
        Padding(padding: const EdgeInsets.fromLTRB(2, 14, 2, 0), child: Text('An academy changes hands only after the current owner and the new owner both confirm with their own OTP. Requests come from the academy app and reach you through Approvals.', style: HqText.sub)),
      ]);
    });
  }
}

class _TransferCard extends ConsumerWidget {
  const _TransferCard({required this.t, required this.canWrite, required this.showHistory, required this.onHistory});
  final Map<String, dynamic> t;
  final bool canWrite, showHistory;
  final VoidCallback onHistory;

  Future<void> _reject(BuildContext context, WidgetRef ref) async {
    final done = await showHqModal<bool>(context, builder: (_) => _RejectModal(transfer: t));
    if (done == true) {
      refreshTransfers(ref);
      if (context.mounted) showToast(context, t.str('step') == 'otp' ? 'Transfer cancelled' : 'Transfer rejected');
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final step = t.str('step');
    final (tone, label) = _stepTone[step]!;
    final history = t.maps('history');
    const names = ['Review', 'Current owner OTP', 'New owner OTP', 'Transferred'];
    final stepIdx = switch (step) { 'review' => 0, 'otp' => 1, 'done' => 3, _ => -1 };

    Tone stage(int i) => step == 'done' || i < stepIdx || (i == 1 && t.flag('verifiedFrom') && stepIdx == 1) || (i == 2 && t.flag('verifiedTo'))
        ? Tone.green
        : (i == stepIdx || (stepIdx == 1 && i == 2) ? Tone.primary : Tone.mute);

    return HqCard(
      radius: 14,
      padding: const EdgeInsets.all(12),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(t.str('academy'), style: HqText.row),
              Text('${t.str('ref')}${t.strOrNull('request') == null ? '' : ' · from ${t.str('request')}'}', style: HqText.small),
            ]),
          ),
          Tag(label, tone: tone),
        ]),
        const SizedBox(height: 8),
        HqList([
          KeyValueRow('Current owner', t.str('currentOwner')),
          KeyValueRow('New owner', '${t.str('newOwner')} · ${t.str('newEmail')}'),
          KeyValueRow('Reason', t.str('reason')),
          if (t.strOrNull('notes') != null) KeyValueRow('Notes', t.str('notes')),
        ]),
        if (step != 'rejected') ...[
          const SizedBox(height: 10),
          Wrap(crossAxisAlignment: WrapCrossAlignment.center, spacing: 4, runSpacing: 4, children: [
            for (var i = 0; i < names.length; i++) ...[Tag(names[i], tone: stage(i)), if (i < names.length - 1) ic('chev', 11, Hq.faint)],
          ]),
        ],
        if (step == 'review') ...[
          const SizedBox(height: 10),
          Text('Start verification to send a one-time code to the current owner and to the new owner. The academy moves only after both confirm.', style: HqText.muted.copyWith(fontSize: 12)),
          if (canWrite)
            Padding(
              padding: const EdgeInsets.only(top: 10),
              child: Wrap(spacing: 6, runSpacing: 6, children: [
                HqButton('Start verification', small: true, kind: BtnKind.primary, onPressed: () async {
                  final done = await showHqModal<bool>(context, builder: (_) => _StartModal(transfer: t));
                  if (done == true) {
                    refreshTransfers(ref);
                    if (context.mounted) showToast(context, 'A code was sent to both owners');
                  }
                }),
                HqButton('Reject', small: true, color: Hq.red, onPressed: () => _reject(context, ref)),
              ]),
            ),
        ],
        if (step == 'otp') ...[
          const SizedBox(height: 10),
          _Party(transfer: t, who: 'from', title: 'Current owner confirms the handover', name: t.str('currentOwner'), canWrite: canWrite),
          _Party(transfer: t, who: 'to', title: 'New owner accepts', name: t.str('newOwner'), canWrite: canWrite),
          if (canWrite) Align(alignment: Alignment.centerLeft, child: HqButton('Cancel this transfer', small: true, color: Hq.red, onPressed: () => _reject(context, ref))),
        ],
        if (step == 'done')
          Padding(padding: const EdgeInsets.only(top: 10), child: Row(children: [ic('check', 13, Hq.green), const SizedBox(width: 6), Expanded(child: Text('Transferred ${t['doneAt'] == null ? '' : ago(t['doneAt'])}. Both owners confirmed with an OTP.', style: HqText.muted.copyWith(fontSize: 12.5)))])),
        if (step == 'rejected')
          Padding(padding: const EdgeInsets.only(top: 10), child: Row(children: [ic('x', 13, Hq.red), const SizedBox(width: 6), Expanded(child: Text(t.strOrNull('why') ?? 'Rejected', style: HqText.muted.copyWith(fontSize: 12.5)))])),
        const SizedBox(height: 6),
        Align(alignment: Alignment.centerLeft, child: HqButton('History (${history.length})', icon: 'clock', small: true, kind: BtnKind.ghost, onPressed: onHistory)),
        if (showHistory) HqList([for (final h in history) HqRow(title: h.str('x'), wrap: true, sub: '${h.str('who')} · ${ago(h['at'])}', titleStyle: HqText.row.copyWith(fontSize: 12.5))]),
      ]),
    );
  }
}

class _Party extends ConsumerStatefulWidget {
  const _Party({required this.transfer, required this.who, required this.title, required this.name, required this.canWrite});
  final Map<String, dynamic> transfer;
  final String who, title, name;
  final bool canWrite;

  @override
  ConsumerState<_Party> createState() => _PartyState();
}

class _PartyState extends ConsumerState<_Party> {
  final _code = TextEditingController();
  String? _error;
  bool _busy = false;

  @override
  void dispose() {
    _code.dispose();
    super.dispose();
  }

  Future<void> _verify() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final r = await ref.read(dioClientProvider).postMap('/admin/hq/transfers/${widget.transfer.str('id')}/verify/${widget.who}', body: {'code': _code.text.trim()});
      refreshTransfers(ref);
      ref.invalidate(transfersProvider);
      if (!mounted) return;
      if (r.flag('done')) {
        if (r.strOrNull('username') != null) {
          await showHqModal<void>(context, width: 440, builder: (_) => _NewOwnerLogin(name: widget.transfer.str('newOwner'), username: r.str('username'), password: r.str('password')));
        } else {
          showToast(context, 'Both confirmed. The academy has been transferred.');
        }
      } else {
        showToast(context, 'Verified');
      }
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _resend() async {
    try {
      await ref.read(dioClientProvider).postMap('/admin/hq/transfers/${widget.transfer.str('id')}/resend/${widget.who}');
      refreshTransfers(ref);
      if (mounted) showToast(context, 'A new code was sent');
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = widget.transfer;
    final ok = t.flag(widget.who == 'from' ? 'verifiedFrom' : 'verifiedTo');
    final dest = t.str(widget.who == 'from' ? 'fromDest' : 'toDest');
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(color: Hq.raised, borderRadius: BorderRadius.circular(12), border: Border.all(color: Hq.border)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(widget.title, style: HqText.row.copyWith(fontSize: 13)),
              Text('${widget.name} · code sent to $dest', style: HqText.small),
            ]),
          ),
          Tag(ok ? 'Verified' : 'Pending', tone: ok ? Tone.green : Tone.gold),
        ]),
        if (!ok && widget.canWrite) ...[
          const SizedBox(height: 8),
          Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Expanded(child: HqField(label: '6-digit code', controller: _code, bottom: 0, keyboard: TextInputType.number, formatters: [FilteringTextInputFormatter.digitsOnly, LengthLimitingTextInputFormatter(6)], onSubmitted: (_) => _verify())),
            const SizedBox(width: 8),
            Padding(padding: const EdgeInsets.only(top: 22), child: HqButton('Verify', small: true, kind: BtnKind.primary, busy: _busy, onPressed: _verify)),
            const SizedBox(width: 6),
            Padding(padding: const EdgeInsets.only(top: 22), child: HqButton('Resend', small: true, onPressed: _resend)),
          ]),
          if (_error != null) Padding(padding: const EdgeInsets.only(top: 6), child: Text(_error!, style: HqText.small.copyWith(color: Hq.red))),
        ],
      ]),
    );
  }
}

class _NewOwnerLogin extends StatelessWidget {
  const _NewOwnerLogin({required this.name, required this.username, required this.password});
  final String name, username, password;

  @override
  Widget build(BuildContext context) {
    Widget row(String l, String v) => Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: Row(children: [
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text(l, style: HqText.small), Text(v, style: HqText.row.copyWith(fontSize: 15, letterSpacing: .5))])),
            HqButton('Copy', small: true, onPressed: () {
              Clipboard.setData(ClipboardData(text: v));
              showToast(context, 'Copied');
            }),
          ]),
        );
    return ModalFrame(
      title: 'Transferred',
      sub: '$name is the new owner. They had no account, so one was created.',
      actions: [HqButton('Done', kind: BtnKind.primary, onPressed: () => Navigator.of(context).pop())],
      children: [
        row('Username', username),
        row('Temporary password', password),
        Text('Shown once. They are asked to change it at first sign in.', style: HqText.sub),
        const SizedBox(height: 14),
      ],
    );
  }
}

class _StartModal extends ConsumerStatefulWidget {
  const _StartModal({required this.transfer});
  final Map<String, dynamic> transfer;

  @override
  ConsumerState<_StartModal> createState() => _StartModalState();
}

class _StartModalState extends ConsumerState<_StartModal> {
  late final _name = TextEditingController(text: widget.transfer.str('newOwner'));
  final _phone = TextEditingController();
  String? _error;
  bool _busy = false;

  @override
  void dispose() {
    _name.dispose();
    _phone.dispose();
    super.dispose();
  }

  Future<void> _go() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await ref.read(dioClientProvider).postMap('/admin/hq/transfers/${widget.transfer.str('id')}/start', body: {'name': _name.text.trim(), 'phone': _phone.text.trim()});
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
        title: 'Start verification',
        sub: '${widget.transfer.str('academy')} · a code goes to each owner',
        error: _error,
        actions: [HqButton('Cancel', onPressed: () => Navigator.of(context).pop()), HqButton('Send codes', kind: BtnKind.primary, busy: _busy, onPressed: _go)],
        children: [
          Text('Current owner: ${widget.transfer.str('fromDest')}\nNew owner: ${widget.transfer.str('toDest')}', style: HqText.muted.copyWith(fontSize: 12.5)),
          const SizedBox(height: 12),
          HqField(label: "New owner's name", controller: _name),
          HqField(label: "New owner's mobile", controller: _phone, hint: '10-digit mobile, for their account', keyboard: TextInputType.phone, formatters: [FilteringTextInputFormatter.digitsOnly, LengthLimitingTextInputFormatter(10)]),
        ],
      );
}

class _RejectModal extends ConsumerStatefulWidget {
  const _RejectModal({required this.transfer});
  final Map<String, dynamic> transfer;

  @override
  ConsumerState<_RejectModal> createState() => _RejectModalState();
}

class _RejectModalState extends ConsumerState<_RejectModal> {
  final _c = TextEditingController();
  String? _error;
  bool _busy = false;

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  Future<void> _go() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await ref.read(dioClientProvider).postMap('/admin/hq/transfers/${widget.transfer.str('id')}/reject', body: {'reason': _c.text.trim()});
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
    final otp = widget.transfer.str('step') == 'otp';
    return ModalFrame(
      title: '${otp ? 'Cancel' : 'Reject'} transfer',
      sub: widget.transfer.str('academy'),
      error: _error,
      actions: [HqButton('Back', onPressed: () => Navigator.of(context).pop()), HqButton(otp ? 'Cancel transfer' : 'Reject', kind: BtnKind.danger, busy: _busy, onPressed: _go)],
      children: [HqField(label: 'Reason', controller: _c, hint: 'Why is this not going ahead?')],
    );
  }
}

const _reasons = ['Stepping down', 'Selling the academy', 'Retiring', 'Moving away', 'Family succession', 'Other'];

class _NewTransfer extends ConsumerStatefulWidget {
  const _NewTransfer({required this.academies});
  final List<Map<String, dynamic>> academies;

  @override
  ConsumerState<_NewTransfer> createState() => _NewTransferState();
}

class _NewTransferState extends ConsumerState<_NewTransfer> {
  String? _academy;
  String _reason = _reasons.first;
  final _name = TextEditingController(), _email = TextEditingController(), _notes = TextEditingController();
  String? _error;
  bool _busy = false;

  @override
  void dispose() {
    _name.dispose();
    _email.dispose();
    _notes.dispose();
    super.dispose();
  }

  Future<void> _go() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await ref.read(dioClientProvider).postMap('/admin/hq/transfers', body: {'academyId': _academy ?? '', 'name': _name.text.trim(), 'email': _email.text.trim(), 'reason': _reason, 'notes': _notes.text.trim()});
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
        title: 'New transfer',
        sub: 'For a handover that came in outside the app',
        error: _error,
        actions: [HqButton('Cancel', onPressed: () => Navigator.of(context).pop()), HqButton('Open transfer', kind: BtnKind.primary, busy: _busy, onPressed: _go)],
        children: [
          HqSelect<String>(label: 'Academy', value: _academy, hint: 'Choose an academy', options: [for (final a in widget.academies) SelectOption(a.str('id'), a.str('name'))], onChanged: (v) => setState(() => _academy = v)),
          FieldRow2([HqField(label: "New owner's name", controller: _name), HqField(label: "New owner's email", controller: _email, keyboard: TextInputType.emailAddress)]),
          HqSelect<String>(label: 'Reason', value: _reason, searchable: false, options: [for (final r in _reasons) SelectOption(r, r)], onChanged: (v) => setState(() => _reason = v)),
          HqField(label: 'Notes', controller: _notes, hint: 'Optional'),
        ],
      );
}
