import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/theme.dart';
import '../../core/api/api_exception.dart';
import '../../core/auth/session.dart';
import '../../core/download.dart';
import '../../core/format.dart';
import '../../core/json.dart';
import '../../core/ui/controls.dart';
import '../../core/ui/overlays.dart';
import '../../core/ui/primitives.dart';
import '../shell/shell_data.dart';
import 'bill_widgets.dart';
import 'collections_data.dart';
import 'collections_dialogs.dart';

/// Re-reads everything Collections shows after a change.
void refreshCollections(WidgetRef ref) {
  ref.invalidate(collectionsOverviewProvider);
  ref.invalidate(billsProvider);
  ref.invalidate(offersProvider);
  ref.invalidate(addonsProvider);
  ref.invalidate(accountProvider);
  ref.invalidate(billDetailProvider);
  ref.invalidate(alertsProvider);
  ref.invalidate(badgesProvider);
}

Future<void> showAccountDrawer(BuildContext context, String academyId, {String? billId}) {
  return showHqDrawer(context, builder: (_) => _AccountDrawer(academyId: academyId, billId: billId));
}

class _AccountDrawer extends ConsumerStatefulWidget {
  const _AccountDrawer({required this.academyId, this.billId});
  final String academyId;
  final String? billId;

  @override
  ConsumerState<_AccountDrawer> createState() => _AccountDrawerState();
}

class _AccountDrawerState extends ConsumerState<_AccountDrawer> {
  late String? _bill = widget.billId;

  @override
  Widget build(BuildContext context) {
    final account = ref.watch(accountProvider(widget.academyId));
    return account.when(
      loading: () => const Center(child: CircularProgressIndicator(color: Hq.primary, strokeWidth: 2.5)),
      error: (e, _) => Padding(padding: const EdgeInsets.all(24), child: HqError(e is ApiException ? e.message : 'Could not load this account.')),
      data: (a) => DrawerShell(
        coverColors: const [Color(0xFF1E4D3C), Color(0xFF1E2A4D)],
        logo: const DrawerLogo('', color: Hq.green, icon: 'wallet'),
        child: _bill == null
            ? _Account(data: a, onOpenBill: (id) => setState(() => _bill = id))
            : _BillView(billId: _bill!, account: a, onBack: () => setState(() => _bill = null)),
      ),
    );
  }
}

class _Account extends ConsumerWidget {
  const _Account({required this.data, required this.onOpenBill});
  final Map<String, dynamic> data;
  final ValueChanged<String> onOpenBill;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final a = data.obj('academy');
    final bills = data.maps('bills');
    final open = bills.where((b) => b.number('balance') > 0 && b.str('status') != 'waived').toList()..sort((x, y) => x.str('period').compareTo(y.str('period')));
    final payments = data.maps('payments');
    final addons = data.maps('addons');
    final reminders = data.maps('reminders');
    final write = ref.watch(sessionProvider).user?.let((u) => u.isSuper || u.role.code == 'FINANCE') ?? false;
    final overdue = data.number('overdue');

    Future<void> remind() async {
      final done = await showHqModal<bool>(context, builder: (_) => RemindModal(academy: a, bills: open));
      if (done == true) {
        refreshCollections(ref);
        if (context.mounted) showToast(context, 'Reminder sent');
      }
    }

    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Wrap(spacing: 6, runSpacing: 6, children: [
        if (a.strOrNull('plan') != null) Tag(a.str('plan'), tone: Tone.blue),
        if (overdue > 0) const Tag('Overdue', tone: Tone.red),
      ]),
      const SizedBox(height: 8),
      Text(a.str('name'), style: HqText.h2.copyWith(fontSize: 19)),
      const SizedBox(height: 3),
      Text('${a.str('owner_name', 'No owner on file')} · ${a.strOrNull('owner_email') ?? a.str('email')}', style: HqText.muted),
      Padding(
        padding: const EdgeInsets.only(top: 14),
        child: Row(children: [
          for (final (v, l, red) in [
            (inr(data.number('toPay')), 'To pay', false),
            (inr(overdue), 'Overdue', overdue > 0),
            (inr(data.number('paid')), 'Paid so far', false),
          ])
            Expanded(
              child: Container(
                margin: EdgeInsets.only(right: l == 'Paid so far' ? 0 : 8),
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(color: Hq.surface, borderRadius: BorderRadius.circular(14), border: Border.all(color: Hq.border)),
                child: Column(children: [
                  FittedBox(fit: BoxFit.scaleDown, child: Text(v, style: HqText.h2.copyWith(fontSize: 15, color: red ? Hq.red : Hq.text))),
                  Text(l, style: HqText.small.copyWith(fontSize: 10.5)),
                ]),
              ),
            ),
        ]),
      ),
      if (write) ...[
        const SizedBox(height: 12),
        _ActionGrid([
          ('Send reminder', 'send', open.isEmpty ? null : remind),
          (
            'Record payment',
            'rupee',
            open.isEmpty
                ? null
                : () async {
                    final done = await showHqModal<bool>(context, builder: (_) => PaymentModal(bill: open.first, academyName: a.str('name')));
                    if (done == true) {
                      refreshCollections(ref);
                      if (context.mounted) showToast(context, 'Payment saved');
                    }
                  }
          ),
          ('Statement', 'dl', () => _statement(context, a, bills, payments)),
          (
            'Add an add-on',
            'plus',
            () async {
              final done = await showHqModal<bool>(context, builder: (_) => AssignAddonModal(academyId: a.str('id'), academyName: a.str('name')));
              if (done == true) {
                refreshCollections(ref);
                if (context.mounted) showToast(context, 'Add-on will appear on the next bill');
              }
            }
          ),
        ]),
      ],
      _Section('Bills', 'Tap a bill for the full breakdown', [
        if (bills.isEmpty) const EmptyNote('No bills yet', padding: 14),
        for (final b in bills)
          HqRow(
            title: monthLong(b.str('period')),
            sub: '${b.str('number')} · due ${fdShort(b['dueOn'])}',
            onTap: () => onOpenBill(b.str('id')),
            trailing: Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
              Text(inr(b.number('total')), style: HqText.row),
              const SizedBox(height: 4),
              BillStatusTags(b),
            ]),
          ),
      ]),
      _Section('Transactions', 'Every payment received from this academy', [
        if (payments.isEmpty) const EmptyNote('No payments yet', padding: 14),
        for (final p in payments)
          HqRow(
            title: '${inr(p.number('amount'))} · ${p.str('mode')}',
            sub: '${fd(p['paidOn'])}${p.strOrNull('reference') == null ? '' : ' · ${p.str('reference')}'} · for ${monthLong(p.str('period'))}',
            wrap: true,
            trailing: const Tag('Received', tone: Tone.green),
          ),
      ]),
      _Section('Add-ons', null, [
        if (addons.isEmpty) const EmptyNote('No add-ons', padding: 14),
        for (final d in addons)
          HqRow(
            title: d.str('name'),
            sub: '${inr(d.number('price'))} ${d.str('billing') == 'MONTH' ? '/ month' : 'one time'} · from ${monthLong(d.str('fromPeriod'))}',
            wrap: true,
            trailing: write
                ? HqButton('Remove', small: true, onPressed: () async {
                    try {
                      await ref.read(dioClientProvider).delete('/admin/hq/collections/academies/${a.str('id')}/addons/${d.str('id')}');
                      refreshCollections(ref);
                    } on ApiException catch (e) {
                      if (context.mounted) showToast(context, e.message);
                    }
                  })
                : null,
          ),
      ]),
      if (reminders.isNotEmpty)
        _Section('Reminders sent', null, [
          for (final r in reminders)
            HqRow(title: r.str('message'), sub: '${r.str('number')} · ${r.str('channels')} · ${ago(r['sentAt'])}', wrap: true, titleStyle: HqText.row.copyWith(fontSize: 12.5, fontWeight: FontWeight.w600)),
        ]),
    ]);
  }

  void _statement(BuildContext context, Map<String, dynamic> a, List<Map<String, dynamic>> bills, List<Map<String, dynamic>> payments) {
    final events = <({String d, String t, String r, String x, double dr, double cr})>[
      for (final b in bills) (d: b.str('issuedOn'), t: 'Bill', r: b.str('number'), x: '${monthLong(b.str('period'))} bill', dr: b.number('total'), cr: 0),
      for (final p in payments) (d: p.str('paidOn'), t: 'Payment', r: p.str('reference').isEmpty ? p.str('number') : p.str('reference'), x: '${p.str('mode')} for ${p.str('number')}', dr: 0, cr: p.number('amount')),
    ]..sort((x, y) => x.d.compareTo(y.d) != 0 ? x.d.compareTo(y.d) : (x.t == 'Bill' ? -1 : 1));
    var bal = 0.0;
    final rows = <List<Object?>>[
      ['Statement for ${a.str('name')}'],
      ['Generated', DateTime.now().toIso8601String().substring(0, 10)],
      ['Date', 'Type', 'Reference', 'Description', 'Billed', 'Received', 'Balance'],
      for (final e in events) ...[
        () {
          bal += e.dr - e.cr;
          return [e.d, e.t, e.r, e.x, e.dr == 0 ? '' : e.dr, e.cr == 0 ? '' : e.cr, bal];
        }(),
      ],
    ];
    downloadText('statement-${a.str('name').toLowerCase().replaceAll(RegExp(r'[^a-z0-9]+'), '-')}.csv', csvText(rows));
    showToast(context, 'Statement downloaded');
  }
}

extension _Let<T> on T {
  R let<R>(R Function(T) f) => f(this);
}

class _Section extends StatelessWidget {
  const _Section(this.title, this.sub, this.rows);
  final String title;
  final String? sub;
  final List<Widget> rows;

  @override
  Widget build(BuildContext context) {
    return HqCard(
      margin: const EdgeInsets.only(top: 12),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        CardHeader(title, sub: sub, bottom: 8),
        HqList(rows),
      ]),
    );
  }
}

class _ActionGrid extends StatelessWidget {
  const _ActionGrid(this.items);
  final List<(String, String, VoidCallback?)> items;

  @override
  Widget build(BuildContext context) {
    return GridView.count(
      crossAxisCount: 2,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      mainAxisSpacing: 8,
      crossAxisSpacing: 8,
      childAspectRatio: 4.4,
      children: [for (final (l, i, f) in items) HqButton(l, icon: i, expand: true, onPressed: f)],
    );
  }
}

// ---------------------------------------------------------------------------------------------

class _BillView extends ConsumerWidget {
  const _BillView({required this.billId, required this.account, required this.onBack});
  final String billId;
  final Map<String, dynamic> account;
  final VoidCallback onBack;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final detail = ref.watch(billDetailProvider(billId));
    final write = ref.watch(sessionProvider).user?.let((u) => u.isSuper || u.role.code == 'FINANCE') ?? false;
    return detail.when(
      loading: () => const HqLoading(),
      error: (e, _) => HqError(e is ApiException ? e.message : 'Could not load this bill.'),
      data: (b) {
        final a = account.obj('academy');
        final lines = b.maps('lines'), pays = b.maps('payments'), rems = b.maps('reminders');
        final balance = b.number('balance');
        final offer = b['offer'] is Map ? b.obj('offer') : null;
        final open = balance > 0 && b.str('status') != 'waived';
        Widget ln(String l, String v, {Color? c, bool bold = false}) => Padding(
              padding: const EdgeInsets.symmetric(vertical: 6),
              child: Row(children: [
                Expanded(child: Text(l, style: HqText.row.copyWith(fontWeight: bold ? FontWeight.w800 : FontWeight.w600, color: c ?? Hq.text))),
                Text(v, style: HqText.row.copyWith(color: c ?? Hq.text, fontWeight: bold ? FontWeight.w800 : FontWeight.w700)),
              ]),
            );

        return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Align(alignment: Alignment.centerLeft, child: HqButton('All bills', icon: 'left', small: true, onPressed: onBack)),
          const SizedBox(height: 10),
          BillStatusTags(b),
          const SizedBox(height: 8),
          Text('${monthLong(b.str('period'))} bill', style: HqText.h2.copyWith(fontSize: 19)),
          const SizedBox(height: 3),
          Text('${b.str('number')} · ${a.str('name')} · issued ${fdShort(b['issuedOn'])} · due ${fdShort(b['dueOn'])}', style: HqText.muted),
          HqCard(
            margin: const EdgeInsets.only(top: 12),
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Text('Breakdown', style: HqText.h3),
              const SizedBox(height: 6),
              for (final l in lines) ln(l.str('label'), (l.number('amount') < 0 ? '-' : '') + inr(l.number('amount').abs()), c: l.number('amount') < 0 ? Hq.green : null),
              if (b.number('discount') > 0) ln('Offer ${offer?.str('code') ?? ''} (${offer == null ? '' : offerText(offer)})', '-${inr(b.number('discount'))}', c: Hq.green),
              if (b.number('gstRate') > 0) ln('GST (${b.number('gstRate').round()}%)', inr(b.number('gst'))),
              const Divider(color: Hq.border, height: 12),
              ln('Total', inr(b.number('total')), bold: true),
              ln('Paid', inr(b.number('paid')), c: Hq.green),
              ln('To pay', inr(balance), bold: true, c: balance == 0 ? Hq.green : (b.str('status') == 'overdue' ? Hq.red : Hq.gold)),
            ]),
          ),
          HqCard(
            margin: const EdgeInsets.only(top: 12),
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Text('Payments', style: HqText.h3),
              const SizedBox(height: 8),
              if (pays.isEmpty)
                const EmptyNote('Nothing received yet', padding: 12)
              else
                HqList([for (final p in pays) HqRow(title: '${inr(p.number('amount'))} · ${p.str('mode')}', sub: '${fd(p['paidOn'])}${p.strOrNull('reference') == null ? '' : ' · ${p.str('reference')}'}', wrap: true)]),
            ]),
          ),
          if (rems.isNotEmpty)
            HqCard(
              margin: const EdgeInsets.only(top: 12),
              child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                Text('Reminders', style: HqText.h3),
                const SizedBox(height: 8),
                HqList([for (final r in rems.reversed) HqRow(title: r.str('message'), sub: '${r.str('channels')} · ${r.str('by')} · ${ago(r['sentAt'])}', wrap: true, titleStyle: HqText.row.copyWith(fontSize: 12.5, fontWeight: FontWeight.w600))]),
              ]),
            ),
          if (open && write) _OfferCard(bill: b, offer: offer, onChanged: () => refreshCollections(ref)),
          const SizedBox(height: 12),
          if (write)
            GridView.count(
              crossAxisCount: 2,
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              mainAxisSpacing: 8,
              crossAxisSpacing: 8,
              childAspectRatio: 4.4,
              children: [
                HqButton('Send reminder', icon: 'send', expand: true, onPressed: !open ? null : () async {
                  final done = await showHqModal<bool>(context, builder: (_) => RemindModal(academy: a, bills: [b]));
                  if (done == true) {
                    refreshCollections(ref);
                    if (context.mounted) showToast(context, 'Reminder sent');
                  }
                }),
                HqButton('Record payment', icon: 'rupee', expand: true, onPressed: !open ? null : () async {
                  final done = await showHqModal<bool>(context, builder: (_) => PaymentModal(bill: b, academyName: a.str('name')));
                  if (done == true) {
                    refreshCollections(ref);
                    if (context.mounted) showToast(context, 'Payment saved');
                  }
                }),
                HqButton('Add charge or credit', expand: true, onPressed: !open ? null : () async {
                  final done = await showHqModal<bool>(context, builder: (_) => AdjustModal(bill: b));
                  if (done == true) {
                    refreshCollections(ref);
                    if (context.mounted) showToast(context, 'Added to the bill');
                  }
                }),
                HqButton('Change due date', expand: true, onPressed: !open ? null : () async {
                  final done = await showHqModal<bool>(context, builder: (_) => DueDateModal(bill: b));
                  if (done == true) {
                    refreshCollections(ref);
                    if (context.mounted) showToast(context, 'Due date changed');
                  }
                }),
              ],
            ),
          const SizedBox(height: 8),
          HqButton('Download this bill (CSV)', icon: 'dl', expand: true, onPressed: () {
            final rows = <List<Object?>>[
              ['Bill', b.str('number')],
              ['Academy', a.str('name')],
              ['Month', monthLong(b.str('period'))],
              ['Issued', b.str('issuedOn')],
              ['Due', b.str('dueOn')],
              [],
              ['Item', 'Amount'],
              for (final l in lines) [l.str('label'), l.number('amount')],
              if (b.number('discount') > 0) ['Offer ${offer?.str('code') ?? ''}', -b.number('discount')],
              if (b.number('gstRate') > 0) ['GST (${b.number('gstRate').round()}%)', b.number('gst')],
              ['Total', b.number('total')],
              ['Paid', b.number('paid')],
              ['To pay', balance],
            ];
            downloadText('${b.str('number')}.csv', csvText(rows));
            showToast(context, 'Bill downloaded');
          }),
        ]);
      },
    );
  }
}

class _OfferCard extends ConsumerStatefulWidget {
  const _OfferCard({required this.bill, required this.offer, required this.onChanged});
  final Map<String, dynamic> bill;
  final Map<String, dynamic>? offer;
  final VoidCallback onChanged;

  @override
  ConsumerState<_OfferCard> createState() => _OfferCardState();
}

class _OfferCardState extends ConsumerState<_OfferCard> {
  String? _sel;
  bool _busy = false;

  Future<void> _apply(String? id) async {
    setState(() => _busy = true);
    try {
      await ref.read(dioClientProvider).putMap('/admin/hq/collections/bills/${widget.bill.str('id')}/offer', body: {'offerId': id});
      widget.onChanged();
      if (mounted) showToast(context, id == null ? 'Offer removed' : 'Offer applied');
    } on ApiException catch (e) {
      if (mounted) showToast(context, e.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final avail = widget.bill.maps('availableOffers');
    return HqCard(
      margin: const EdgeInsets.only(top: 12),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        CardHeader('Offer', sub: widget.offer != null ? 'Applied: ${widget.offer!.str('name')}' : 'Take something off this bill', bottom: 8),
        Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Expanded(
            child: HqSelect<String>(
              bottom: 0,
              compact: true,
              value: _sel ?? widget.offer?.strOrNull('id'),
              hint: 'Choose an offer',
              options: [for (final o in avail) SelectOption(o.str('id'), '${o.str('code')} · ${offerText(o)}')],
              onChanged: (v) => setState(() => _sel = v),
            ),
          ),
          const SizedBox(width: 8),
          HqButton('Apply', busy: _busy, onPressed: (_sel ?? widget.offer?.strOrNull('id')) == null ? null : () => _apply(_sel ?? widget.offer!.str('id'))),
        ]),
        if (widget.offer != null) Padding(padding: const EdgeInsets.only(top: 8), child: Align(alignment: Alignment.centerLeft, child: HqButton('Remove offer', small: true, kind: BtnKind.danger, onPressed: () => _apply(null)))),
      ]),
    );
  }
}
