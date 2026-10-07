import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:nest_fe/app/theme/app_tokens.dart';
import 'package:nest_fe/core/design/charts.dart';
import 'package:nest_fe/core/auth/session_controller.dart';
import 'package:nest_fe/core/design/gold_tabs.dart';
import 'package:nest_fe/core/design/status_badge.dart';
import 'package:nest_fe/core/format/money.dart';
import 'package:nest_fe/core/providers/core_providers.dart';
import 'package:nest_fe/core/widgets/async_value_view.dart';
import 'package:nest_fe/features/fees/data/fee_roster.dart';
import 'package:nest_fe/features/fees/data/student_other_fees.dart';
import 'package:nest_fe/features/fees/data/student_statement.dart';
import 'package:nest_fe/features/fees/presentation/fee_format.dart' show statusLabel;
import 'package:nest_fe/features/fees/presentation/fees_screen.dart' show feesApiProvider;
import 'package:nest_fe/features/fees/presentation/student_pay_sheet.dart';
import 'package:share_plus/share_plus.dart';
import 'dart:typed_data';

final _myRegularProvider = FutureProvider.autoDispose<StudentStatement>((ref) {
  ref.watch(activeMembershipIdProvider);
  return ref.watch(feesApiProvider).myStatement();
});

final _myOtherProvider = FutureProvider.autoDispose<StudentOtherFees>((ref) {
  ref.watch(activeMembershipIdProvider);
  return ref.watch(feesApiProvider).myOtherFees();
});

final _payEnabledProvider = FutureProvider.autoDispose<bool>((ref) async {
  try {
    return await ref.watch(feesApiProvider).paymentsEnabled();
  } catch (_) {
    return false;
  }
});

enum _Tab { regular, other, statement }

/// The student's own Fees tab: Regular / Other / Statement, read-only.
///
/// Reads `/me/fees/*`, which can only ever return the caller's own rows. Paying online is not
/// here yet - the backend has no payment gateway, so a "Pay now" button would only pretend.
class StudentFeesScreen extends ConsumerStatefulWidget {
  const StudentFeesScreen({super.key});

  @override
  ConsumerState<StudentFeesScreen> createState() => _State();
}

class _State extends ConsumerState<StudentFeesScreen> {
  _Tab _tab = _Tab.regular;

  void _refresh() {
    ref.invalidate(_myRegularProvider);
    ref.invalidate(_myOtherProvider);
  }

  Future<void> _download() async {
    try {
      final bytes = await ref.read(feesApiProvider).downloadMyStatement();
      await Share.shareXFiles([
        XFile.fromData(Uint8List.fromList(bytes), name: 'fee_statement.csv', mimeType: 'text/csv'),
      ], text: 'My fee statement');
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(e.toString().replaceFirst('Exception: ', ''))));
      }
    }
  }

  Future<void> _payRegular(StatementRow r) async {
    final paid = await showPaySheet(
      context: context,
      title: r.context,
      subtitle: r.label,
      amount: r.balance,
      onPay: (m) => ref.read(feesApiProvider).payMyFee(
          category: FeeCategory.regular, courseId: r.courseId, period: r.label, method: m),
    );
    if (paid) _refresh();
  }

  Future<void> _payOther(OtherFeeRow f) async {
    final paid = await showPaySheet(
      context: context,
      title: f.name,
      subtitle: f.custom ? 'One-time' : 'Academy fee',
      amount: f.outstanding,
      onPay: (m) => ref.read(feesApiProvider).payMyFee(
          category: FeeCategory.other, feeTypeId: f.feeTypeId, studentFeeId: f.studentFeeId, method: m),
    );
    if (paid) _refresh();
  }

  @override
  Widget build(BuildContext context) {
    final regular = ref.watch(_myRegularProvider);
    final other = ref.watch(_myOtherProvider);
    final payEnabled = ref.watch(_payEnabledProvider).valueOrNull ?? false;

    int dueCount(Iterable<PaymentStatus> s) => s.where((x) => !x.isSettled).length;
    final regularDue = regular.maybeWhen(
        data: (s) => dueCount(s.rows.where((r) => r.category == FeeCategory.regular).map((r) => r.status)), orElse: () => 0);
    final otherDue = other.maybeWhen(data: (s) => dueCount(s.fees.map((f) => f.status)), orElse: () => 0);

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 14, 20, 0),
          child: AcademyPill(name: ref.watch(sessionControllerProvider).user?.activeMembership?.academyName ?? ''),
        ),
        Expanded(
          child: RefreshIndicator(
            onRefresh: () async {
              ref.invalidate(_myRegularProvider);
              ref.invalidate(_myOtherProvider);
            },
            child: ListView(
              padding: const EdgeInsets.fromLTRB(20, 14, 20, 24),
              children: [
                GoldTabs<_Tab>(
                  options: _Tab.values,
                  labelOf: (t) => switch (t) {
                    _Tab.regular => regularDue > 0 ? 'Regular · $regularDue' : 'Regular',
                    _Tab.other => otherDue > 0 ? 'Other · $otherDue' : 'Other',
                    _Tab.statement => 'Statement',
                  },
                  selected: _tab,
                  onTap: (t) => setState(() => _tab = t),
                ),
                const SizedBox(height: 16),
                switch (_tab) {
                  _Tab.regular => AsyncValueView<StudentStatement>(
                      value: regular,
                      onRetry: () => ref.invalidate(_myRegularProvider),
                      data: (context, s) {
                        final rows = s.rows.where((r) => r.category == FeeCategory.regular).toList();
                        final billed = rows.fold<num>(0, (a, r) => a + r.fee);
                        final paid = rows.fold<num>(0, (a, r) => a + r.paid);
                        return _list(
                          billed: billed,
                          paid: paid,
                          title: 'Course fees',
                          cards: [
                            for (final r in rows)
                              _FeeCard(
                                icon: Icons.music_note_outlined,
                                title: r.context,
                                subtitle: r.label,
                                amount: r.fee,
                                paid: r.paid,
                                status: r.status,
                                paidOn: r.paidOn,
                                onPay: payEnabled && !r.status.isSettled && r.courseId != null ? () => _payRegular(r) : null,
                                onReceipt: r.status.isSettled ? () => _receipt(r.context, r.label, r.paid, r.mode, r.paidOn) : null,
                              ),
                          ],
                        );
                      },
                    ),
                  _Tab.other => AsyncValueView<StudentOtherFees>(
                      value: other,
                      onRetry: () => ref.invalidate(_myOtherProvider),
                      data: (context, s) => _list(
                        billed: s.totalAmount,
                        paid: s.totalPaid,
                        title: 'Other fees',
                        cards: [
                          for (final f in s.fees)
                            _FeeCard(
                              icon: Icons.inventory_2_outlined,
                              title: f.name,
                              subtitle: f.custom ? 'One-time' : 'Academy fee',
                              amount: f.amount,
                              paid: f.paid,
                              status: f.status,
                              dueDate: f.dueDate,
                              paidOn: f.lastPaidOn,
                              onPay: payEnabled && !f.status.isSettled ? () => _payOther(f) : null,
                              onReceipt: f.status.isSettled ? () => _receipt(f.name, '', f.paid, f.lastPaymentMode, f.lastPaidOn) : null,
                            ),
                        ],
                      ),
                    ),
                  _Tab.statement => AsyncValueView<StudentStatement>(
                      value: regular,
                      onRetry: () => ref.invalidate(_myRegularProvider),
                      data: (context, s) => _Statement(
                        regular: s,
                        other: other.valueOrNull,
                        onDownload: _download,
                      ),
                    ),
                },
              ],
            ),
          ),
        ),
      ],
    );
  }

  void _receipt(String title, String detail, num amount, String? mode, DateTime? date) {
    shareReceipt(
      title: title,
      detail: detail,
      amount: amount,
      reference: '',
      mode: mode == null ? 'Academy' : (mode == 'GATEWAY' ? 'Online payment' : 'Academy ($mode)'),
      date: date ?? DateTime.now(),
    );
  }

  Widget _list({required num billed, required num paid, required String title, required List<Widget> cards}) {
    final palette = context.palette;
    final due = (billed - paid).clamp(0, double.infinity);
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: palette.surfaceRaised,
          borderRadius: AppRadii.all(AppRadii.xxl),
          border: Border.all(color: palette.border),
        ),
        child: Row(children: [
          DonutChart(
              percent: billed > 0 ? paid / billed * 100 : 100,
              size: 64,
              strokeWidth: 7,
              color: due > 0 ? palette.primary : palette.paidManual),
          const SizedBox(width: 14),
          Expanded(
            child: Column(children: [
              _kv('Total due', money(due), due > 0 ? palette.notPaid : palette.paidManual, big: true),
              const SizedBox(height: 6),
              _kv('Paid so far', money(paid), palette.text),
              const SizedBox(height: 4),
              Align(
                alignment: Alignment.centerLeft,
                child: Text(due > 0 ? 'Payments are recorded by your academy' : 'All caught up — no pending fees',
                    style: TextStyle(fontSize: 9.5, color: palette.textFaint)),
              ),
            ]),
          ),
        ]),
      ),
      const SizedBox(height: 18),
      Text(title, style: TextStyle(fontWeight: FontWeight.w800, fontSize: 13.5, color: palette.text)),
      const SizedBox(height: 10),
      if (cards.isEmpty)
        Container(
          padding: const EdgeInsets.symmetric(vertical: 22),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: palette.surfaceRaised,
            borderRadius: AppRadii.all(AppRadii.xl),
            border: Border.all(color: palette.border),
          ),
          child: Text('Nothing here yet', style: TextStyle(fontSize: 12, color: palette.textFaint)),
        )
      else
        for (final c in cards) Padding(padding: const EdgeInsets.only(bottom: 10), child: c),
    ]);
  }

  Widget _kv(String k, String v, Color color, {bool big = false}) => Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(k, style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.w600, color: context.palette.textMuted)),
          Text(v, style: TextStyle(fontSize: big ? 15 : 12.5, fontWeight: FontWeight.w800, color: color)),
        ],
      );
}

class _FeeCard extends StatelessWidget {
  const _FeeCard({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.amount,
    required this.paid,
    required this.status,
    this.dueDate,
    this.paidOn,
    this.onPay,
    this.onReceipt,
  });

  final VoidCallback? onPay;
  final VoidCallback? onReceipt;
  final IconData icon;
  final String title;
  final String subtitle;
  final num amount;
  final num paid;
  final PaymentStatus status;
  final DateTime? dueDate;
  final DateTime? paidOn;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final balance = amount - paid;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: palette.surfaceRaised,
        borderRadius: AppRadii.all(AppRadii.xxl),
        border: Border.all(color: palette.border),
      ),
      child: Column(children: [
        Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(color: palette.goldSoft, borderRadius: AppRadii.all(AppRadii.lg)),
            child: Icon(icon, size: 17, color: palette.gold),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13, color: palette.text)),
              const SizedBox(height: 2),
              Text(subtitle, style: TextStyle(fontSize: 10.5, color: palette.textFaint)),
            ]),
          ),
          StatusBadge(label: statusLabel(status), color: status.color(palette), softColor: status.softColor(palette)),
        ]),
        const SizedBox(height: 10),
        Container(
          padding: const EdgeInsets.only(top: 10),
          decoration: BoxDecoration(border: Border(top: BorderSide(color: palette.borderSoft))),
          child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
            Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(money(amount), style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: palette.text)),
              if (status == PaymentStatus.partial)
                Text('${money(balance)} balance remaining',
                    style: TextStyle(fontSize: 9.5, fontWeight: FontWeight.w600, color: palette.partial)),
              if (!status.isSettled && dueDate != null)
                Text('Due ${formatFeeDate(dueDate!)}', style: TextStyle(fontSize: 9.5, color: palette.textFaint)),
              if (status.isSettled && paidOn != null)
                Text('Paid on ${formatFeeDate(paidOn!)}', style: TextStyle(fontSize: 9.5, color: palette.textFaint)),
            ]),
            if (onPay != null)
              FilledButton.icon(
                onPressed: onPay,
                icon: const Icon(Icons.credit_card, size: 14),
                label: const Text('Pay now'),
              )
            else if (onReceipt != null)
              OutlinedButton.icon(
                onPressed: onReceipt,
                icon: const Icon(Icons.receipt_long_outlined, size: 14),
                label: const Text('Receipt'),
              ),
          ]),
        ),
      ]),
    );
  }
}

/// Every payment, newest first, over a date range of at most six months (as in the reference).
class _Statement extends StatefulWidget {
  const _Statement({required this.regular, required this.other, required this.onDownload});
  final VoidCallback onDownload;
  final StudentStatement regular;
  final StudentOtherFees? other;

  @override
  State<_Statement> createState() => _StatementState();
}

class _StatementState extends State<_Statement> {
  late DateTime _to = DateTime(DateTime.now().year, DateTime.now().month, DateTime.now().day);
  late DateTime _from = DateTime(_to.year, _to.month - 6, _to.day);

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final items = <({String label, String sub, num amount, DateTime date, String mode})>[
      for (final r in widget.regular.rows)
        if (r.paid > 0 && r.paidOn != null)
          (label: r.context, sub: '${r.label} · Regular', amount: r.paid, date: r.paidOn!, mode: r.mode ?? 'Cash'),
      for (final f in widget.other?.fees ?? const <OtherFeeRow>[])
        if (f.paid > 0 && f.lastPaidOn != null)
          (label: f.name, sub: 'Other', amount: f.paid, date: f.lastPaidOn!, mode: f.lastPaymentMode ?? 'Cash'),
    ]..sort((a, b) => b.date.compareTo(a.date));
    final inRange = items.where((i) => !i.date.isBefore(_from) && !i.date.isAfter(_to)).toList();
    final total = inRange.fold<num>(0, (a, i) => a + i.amount);

    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(children: [
        _rangeButton('From', _from, (d) => setState(() {
              _from = d;
              if (_from.isAfter(_to)) _to = _from;
              final limit = DateTime(_to.year, _to.month - 6, _to.day);
              if (_from.isBefore(limit)) _to = DateTime(_from.year, _from.month + 6, _from.day);
            })),
        const SizedBox(width: 8),
        _rangeButton('To', _to, (d) => setState(() {
              _to = d;
              if (_to.isBefore(_from)) _from = _to;
              final limit = DateTime(_to.year, _to.month - 6, _to.day);
              if (_from.isBefore(limit)) _from = limit;
            })),
      ]),
      const SizedBox(height: 6),
      Text('Statements can cover up to a 6-month range', style: TextStyle(fontSize: 9.5, color: palette.textFaint)),
      const SizedBox(height: 12),
      Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: palette.surfaceRaised,
          borderRadius: AppRadii.all(AppRadii.xl),
          border: Border.all(color: palette.border),
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('${inRange.length} transaction${inRange.length == 1 ? '' : 's'}',
              style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.w600, color: palette.textMuted)),
          const SizedBox(height: 2),
          Text(money(total), style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: palette.text)),
          const SizedBox(height: 8),
          OutlinedButton.icon(
            onPressed: widget.onDownload,
            icon: const Icon(Icons.download, size: 15),
            label: const Text('Download statement'),
          ),
        ]),
      ),
      const SizedBox(height: 12),
      if (inRange.isEmpty)
        Container(
          padding: const EdgeInsets.symmetric(vertical: 22),
          alignment: Alignment.center,
          child: Text('No transactions in this range', style: TextStyle(fontSize: 12, color: palette.textFaint)),
        ),
      for (final i in inRange)
        Container(
          margin: const EdgeInsets.only(bottom: 8),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(
            color: palette.surfaceRaised,
            borderRadius: AppRadii.all(AppRadii.xl),
            border: Border.all(color: palette.border),
          ),
          child: Row(children: [
            Container(
              width: 32,
              height: 32,
              decoration: BoxDecoration(color: palette.paidManualSoft, borderRadius: AppRadii.all(AppRadii.md)),
              child: Icon(Icons.check_circle_outline, size: 15, color: palette.paidManual),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(i.label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontWeight: FontWeight.w700, fontSize: 12, color: palette.text)),
                const SizedBox(height: 2),
                Text('${i.sub} · ${i.mode} · ${formatFeeDate(i.date)}',
                    style: TextStyle(fontSize: 10, color: palette.textFaint)),
              ]),
            ),
            Text(money(i.amount), style: TextStyle(fontWeight: FontWeight.w800, fontSize: 12.5, color: palette.text)),
          ]),
        ),
    ]);
  }

  Widget _rangeButton(String label, DateTime v, ValueChanged<DateTime> onPick) {
    final palette = context.palette;
    return Expanded(
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(label, style: TextStyle(fontSize: 10, fontWeight: FontWeight.w600, color: palette.textMuted)),
        const SizedBox(height: 4),
        InkWell(
          borderRadius: AppRadii.all(AppRadii.md),
          onTap: () async {
            final picked = await showDatePicker(
              context: context,
              initialDate: v,
              firstDate: DateTime(2022),
              lastDate: DateTime.now(),
            );
            if (picked != null) onPick(DateTime(picked.year, picked.month, picked.day));
          },
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
            decoration: BoxDecoration(
              color: palette.surfaceRaised,
              borderRadius: AppRadii.all(AppRadii.md),
              border: Border.all(color: palette.border),
            ),
            child: Row(children: [
              Icon(Icons.calendar_today_outlined, size: 13, color: palette.textFaint),
              const SizedBox(width: 6),
              Text(formatFeeDate(v), style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: palette.text)),
            ]),
          ),
        ),
      ]),
    );
  }
}
