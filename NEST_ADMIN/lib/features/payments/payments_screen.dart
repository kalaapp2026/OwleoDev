import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/theme.dart';
import '../../core/auth/session.dart';
import '../../core/download.dart';
import '../../core/format.dart';
import '../../core/json.dart';
import '../../core/ui/async.dart';
import '../../core/ui/controls.dart';
import '../../core/ui/layout.dart';
import '../../core/ui/overlays.dart';
import '../../core/ui/primitives.dart';
import '../academies/academy_drawer.dart' show GatewayModal;
import '../shell/nav.dart';

/// The filters on the transaction history, as one value so a provider can be keyed on it.
typedef TxFilter = ({String month, String type, String status, String source, String academy, String q});

const _noFilter = (month: '', type: 'all', status: 'all', source: 'all', academy: '', q: '');

final transactionsProvider = FutureProvider.autoDispose.family<Map<String, dynamic>, TxFilter>((ref, f) => ref.watch(dioClientProvider).getMap('/admin/hq/payments/transactions', query: {
      if (f.month.isNotEmpty) 'month': f.month,
      'type': f.type,
      'status': f.status,
      'source': f.source,
      if (f.academy.isNotEmpty) 'academy': f.academy,
      if (f.q.isNotEmpty) 'q': f.q,
    }));

final accountsProvider = FutureProvider.autoDispose<Map<String, dynamic>>((ref) => ref.watch(dioClientProvider).getMap('/admin/hq/payments/accounts'));

Tone _statusTone(String s) => switch (s) { 'paid' => Tone.green, 'failed' => Tone.red, _ => Tone.gold };
String _statusText(String s) => switch (s) { 'paid' => 'Paid', 'failed' => 'Failed', _ => 'Not completed' };

/// Payments: every payment that went through Owleo, and the account each academy is mapped to.
class PaymentsScreen extends ConsumerStatefulWidget {
  const PaymentsScreen({super.key});

  @override
  ConsumerState<PaymentsScreen> createState() => _PaymentsScreenState();
}

class _PaymentsScreenState extends ConsumerState<PaymentsScreen> {
  String _tab = 'tx';
  TxFilter _f = _noFilter;
  String _stateFilter = 'all', _accountQ = '';

  @override
  Widget build(BuildContext context) {
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: SegControl<String>(expand: true, items: const [('tx', 'Transactions'), ('ac', 'Account mapping')], value: _tab, onChanged: (v) => setState(() => _tab = v)),
      ),
      if (_tab == 'tx') _transactions() else _accounts(),
    ]);
  }

  // ---- transactions ----

  List<SelectOption<String>> _monthOptions() {
    final now = DateTime.now();
    return [
      const SelectOption('', 'All time'),
      for (var i = 0; i < 12; i++)
        () {
          final d = DateTime(now.year, now.month - i);
          final ym = '${d.year}-${d.month.toString().padLeft(2, '0')}';
          return SelectOption(ym, monthLong(ym));
        }(),
    ];
  }

  Widget _transactions() {
    final data = ref.watch(transactionsProvider(_f));
    final canExport = ref.watch(sessionProvider).user?.canExport ?? false;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      asyncBody(data, onRetry: () => ref.invalidate(transactionsProvider), data: (d) {
        final k = d.obj('kpis');
        final items = d.maps('items');
        final online = k.number('online'), manual = k.number('manual');
        final total = online + manual;
        return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          HqGrid(GridKind.g4, [
            Kpi(icon: 'rupee', tone: Tone.green, label: 'Subscriptions received', value: short(k.number('subscription')), foot: total == 0 ? 'nothing yet' : '${pct(online / total * 100)} paid online'),
            Kpi(icon: 'send', tone: Tone.blue, label: 'Paid online', value: short(online), foot: 'by academy admins'),
            Kpi(icon: 'edit', tone: Tone.violet, label: 'Recorded by hand', value: short(manual), foot: 'bank transfer, cash, cheque'),
            Kpi(icon: 'cap', tone: Tone.primary, label: 'Student fees collected', value: short(k.number('student')), foot: 'through Owleo, for academies'),
          ]),
          _filters(d, canExport, items),
          if (k.integer('started') + k.integer('failed') > 0)
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: Text('${k.integer('started')} not completed and ${k.integer('failed')} failed in this view. A payment that is not completed was started but not paid.', style: HqText.sub),
            ),
          if (items.isEmpty)
            const HqCard(child: EmptyNote('No payments match these filters.'))
          else
            HqCard(
              child: HqList([
                for (final x in items)
                  HqRow(
                    leading: IconTile(x.str('type') == 'student' ? 'cap' : 'wallet', tone: x.str('type') == 'student' ? Tone.primary : Tone.gold, size: 36),
                    title: x.str('academy'),
                    sub: [
                      x.str('ref'),
                      '${x.str('mode')}${x.str('source') == 'manual' ? ' · by hand' : ' · online'}',
                      if (x.str('reference').isNotEmpty) x.str('reference'),
                      'by ${x.str('by')}',
                      ago(x['at']),
                      if (x.str('note').isNotEmpty) x.str('note'),
                    ].join(' · '),
                    wrap: true,
                    trailing: Column(crossAxisAlignment: CrossAxisAlignment.end, mainAxisSize: MainAxisSize.min, children: [
                      Text(inr(x.number('amount')), style: HqText.row),
                      const SizedBox(height: 3),
                      Tag(_statusText(x.str('status')), tone: _statusTone(x.str('status'))),
                    ]),
                    onTap: x.str('type') == 'subscription' ? () => hqGo(context, '/collections?academy=${x.str('academyId')}') : null,
                  ),
              ]),
            ),
          const PageNote('Subscriptions are what academies pay Owleo. Student fees are what students pay their academy through Owleo\'s gateway: that money is collected for the academy and settles to the account it is mapped to. Online payments appear here the moment the gateway confirms them.'),
        ]);
      }),
    ]);
  }

  Widget _filters(Map<String, dynamic> d, bool canExport, List<Map<String, dynamic>> items) {
    final academies = d.maps('academies');
    return HqCard(
      margin: const EdgeInsets.only(bottom: 12),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        FieldRowAuto([
          HqSelect<String>(label: 'Month', value: _f.month, searchable: false, bottom: 8, options: _monthOptions(), onChanged: (v) => setState(() => _f = (month: v, type: _f.type, status: _f.status, source: _f.source, academy: _f.academy, q: _f.q))),
          HqSelect<String>(
            label: 'Academy',
            value: _f.academy,
            bottom: 8,
            options: [const SelectOption('', 'All academies'), for (final a in academies) SelectOption(a.str('id'), a.str('name'))],
            onChanged: (v) => setState(() => _f = (month: _f.month, type: _f.type, status: _f.status, source: _f.source, academy: v, q: _f.q)),
          ),
        ]),
        ChipRow(scroll: true, [
          for (final (k, n) in const [('all', 'All payments'), ('subscription', 'Subscriptions'), ('student', 'Student fees')])
            HqChip(n, selected: _f.type == k, onTap: () => setState(() => _f = (month: _f.month, type: k, status: _f.status, source: _f.source, academy: _f.academy, q: _f.q))),
        ]),
        const SizedBox(height: 8),
        ChipRow(scroll: true, [
          for (final (k, n) in const [('all', 'Any status'), ('paid', 'Paid'), ('started', 'Not completed'), ('failed', 'Failed')])
            HqChip(n, selected: _f.status == k, onTap: () => setState(() => _f = (month: _f.month, type: _f.type, status: k, source: _f.source, academy: _f.academy, q: _f.q))),
          for (final (k, n) in const [('online', 'Online'), ('manual', 'By hand')])
            HqChip(n, selected: _f.source == k, onTap: () => setState(() => _f = (month: _f.month, type: _f.type, status: _f.status, source: _f.source == k ? 'all' : k, academy: _f.academy, q: _f.q))),
        ]),
        const SizedBox(height: 10),
        Row(children: [
          Expanded(child: SearchBox(hint: 'Search reference, bill number, academy or person', height: 42, onChanged: (v) => setState(() => _f = (month: _f.month, type: _f.type, status: _f.status, source: _f.source, academy: _f.academy, q: v)))),
          if (canExport) ...[
            const SizedBox(width: 8),
            HqButton('Export', icon: 'dl', small: true, onPressed: items.isEmpty ? null : () => _export(items)),
          ],
        ]),
      ]),
    );
  }

  void _export(List<Map<String, dynamic>> items) {
    final rows = <List<Object?>>[
      ['date', 'time', 'type', 'academy', 'bill or fee', 'amount', 'mode', 'source', 'reference', 'status', 'by', 'note'],
      for (final x in items)
        () {
          final d = toDate(x['at']);
          return [d == null ? '' : fd(d), d == null ? '' : '${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}', x.str('type'), x.str('academy'), x.str('ref'), x.number('amount'), x.str('mode'), x.str('source'), x.str('reference'), x.str('status'), x.str('by'), x.str('note')];
        }(),
    ];
    downloadText('owleo-payments-${DateTime.now().toIso8601String().substring(0, 10)}.csv', csvText(rows));
    showToast(context, 'Payments exported');
  }

  // ---- account mapping ----

  Widget _accounts() {
    final user = ref.watch(sessionProvider).user;
    final canWrite = user != null && (user.isSuper || user.role.code == 'FINANCE' || user.role.code == 'OPS');
    return asyncBody(ref.watch(accountsProvider), onRetry: () => ref.invalidate(accountsProvider), data: (d) {
      final owleo = d.obj('owleo'), counts = d.obj('counts');
      final q = _accountQ.trim().toLowerCase();
      final list = d.maps('academies').where((a) => (_stateFilter == 'all' || a.str('state') == _stateFilter) && (q.isEmpty || a.str('academy').toLowerCase().contains(q) || a.str('merchantId').toLowerCase().contains(q))).toList();
      final connected = owleo.flag('connected');
      return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        HqCard(
          margin: const EdgeInsets.only(bottom: 12),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            CardHeader('Owleo receiving account', sub: 'Where subscription and student-fee payments arrive', trailing: Tag(connected ? 'Connected' : 'Not connected', tone: connected ? Tone.green : Tone.gold), bottom: 8),
            HqList([
              HqRow(leading: const IconTile('bank', tone: Tone.blue), title: owleo.str('gateway', 'Razorpay'), sub: connected ? 'Key ${owleo.str('keyHint')} · ${owleo.str('mode') == 'live' ? 'live: real money' : 'test mode: no real money moves'}' : 'No gateway credentials are set on the server, so academies cannot pay online yet.', wrap: true),
              HqRow(leading: IconTile('flow', tone: owleo.flag('webhook') ? Tone.green : Tone.gold), title: 'Payment confirmations (webhook)', sub: owleo.flag('webhook') ? 'Set. Payments are confirmed even if the browser closes.' : 'Not set. A payment is only confirmed while the academy\'s browser stays open.', wrap: true),
            ]),
          ]),
        ),
        HqGrid(GridKind.g4, [
          Kpi(icon: 'check', tone: Tone.green, label: 'Mapped', value: '${counts.integer('mapped')}', foot: 'bank and gateway'),
          Kpi(icon: 'bank', tone: Tone.gold, label: 'Bank only', value: '${counts.integer('bank')}', foot: 'gateway not mapped'),
          Kpi(icon: 'warn', tone: Tone.red, label: 'No account', value: '${counts.integer('none')}', foot: 'nothing on file'),
        ]),
        Padding(padding: const EdgeInsets.only(bottom: 10), child: SearchBox(hint: 'Search academy or merchant ID', height: 42, onChanged: (v) => setState(() => _accountQ = v))),
        Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: ChipRow([for (final (k, n) in const [('all', 'All'), ('mapped', 'Mapped'), ('bank', 'Bank only'), ('none', 'No account')]) HqChip(n, selected: _stateFilter == k, onTap: () => setState(() => _stateFilter = k))]),
        ),
        if (list.isEmpty)
          const HqCard(child: EmptyNote('No academies match.'))
        else
          LayoutBuilder(builder: (context, c) {
            final cols = c.maxWidth >= 760 ? 2 : 1;
            return Wrap(spacing: 12, runSpacing: 12, children: [for (final a in list) SizedBox(width: (c.maxWidth - (cols - 1) * 12) / cols, child: _accountCard(a, canWrite))]);
          }),
        const PageNote('Mapping an academy links its bank account to a gateway merchant account, so student fees collected through Owleo can settle to it. Subscription payments always arrive in Owleo\'s own account above.'),
      ]);
    });
  }

  Widget _accountCard(Map<String, dynamic> a, bool canWrite) {
    final state = a.str('state');
    final (label, tone) = switch (state) { 'mapped' => ('Mapped', Tone.green), 'bank' => ('Bank only', Tone.gold), _ => ('No account', Tone.red) };
    return HqCard(
      radius: 14,
      padding: const EdgeInsets.all(14),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(children: [
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text(a.str('academy'), style: HqText.row.copyWith(fontSize: 14)), if (a.flag('demo')) Text('On demo', style: HqText.small)])),
          Tag(label, tone: tone),
        ]),
        const SizedBox(height: 10),
        if (state == 'none')
          Text('No bank account on file. Add one on the academy\'s profile.', style: HqText.small)
        else ...[
          Text('${a.str('bank')} •••• ${a.str('last4')} · ${a.str('ifsc')}', style: HqText.body.copyWith(fontSize: 12.5)),
          Text(a.str('holder'), style: HqText.small),
          const SizedBox(height: 6),
          Text(state == 'mapped' ? '${a.str('gateway')} · ${a.str('merchantId')}' : 'Gateway not mapped', style: HqText.small.copyWith(color: state == 'mapped' ? Hq.green : Hq.gold)),
        ],
        const SizedBox(height: 10),
        MiniStats([(short(a.number('subscriptionPaid')), 'Paid Owleo', null), (short(a.number('studentCollected')), 'Student fees via Owleo', null), (a['lastPaid'] == null ? '–' : ago(a['lastPaid']), 'Last payment', null)]),
        Row(children: [
          if (canWrite && state != 'none')
            HqButton(state == 'mapped' ? 'Change mapping' : 'Map gateway', small: true, kind: state == 'mapped' ? BtnKind.normal : BtnKind.primary, onPressed: () async {
              final bank = {'id': a.str('bankId'), 'bank': a.str('bank'), 'last4': a.str('last4'), 'ifsc': a.str('ifsc'), 'gateway': a.strOrNull('gateway'), 'merchantId': a.str('merchantId')};
              final done = await showHqModal<bool>(context, builder: (_) => GatewayModal(academyId: a.str('academyId'), bank: bank));
              if (done == true) {
                ref.invalidate(accountsProvider);
                if (mounted) showToast(context, 'Gateway mapped');
              }
            }),
          const SizedBox(width: 8),
          HqButton('Payments', small: true, onPressed: () => setState(() {
                _tab = 'tx';
                _f = (month: '', type: 'all', status: 'all', source: 'all', academy: a.str('academyId'), q: '');
              })),
        ]),
      ]),
    );
  }
}

/// Two controls side by side, one under the other when narrow.
class FieldRowAuto extends StatelessWidget {
  const FieldRowAuto(this.children, {super.key});
  final List<Widget> children;

  @override
  Widget build(BuildContext context) => LayoutBuilder(builder: (context, c) {
        if (c.maxWidth < 460) return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: children);
        return Row(crossAxisAlignment: CrossAxisAlignment.start, children: [for (final (i, w) in children.indexed) ...[if (i > 0) const SizedBox(width: 10), Expanded(child: w)]]);
      });
}
