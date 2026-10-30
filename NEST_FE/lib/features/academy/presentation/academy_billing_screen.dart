import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:nest_fe/app/theme/app_tokens.dart';
import 'package:nest_fe/app/theme/app_typography.dart';
import 'package:nest_fe/core/design/confirm_dialog.dart';
import 'package:nest_fe/core/design/pressable.dart';
import 'package:nest_fe/core/design/status_badge.dart';
import 'package:nest_fe/core/error/api_exception.dart';
import 'package:nest_fe/core/format/money.dart';
import 'package:nest_fe/core/widgets/app_notice.dart';
import 'package:nest_fe/core/widgets/async_value_view.dart';
import 'package:nest_fe/features/academy/data/academy_billing_api.dart';
import 'package:nest_fe/features/academy/data/academy_settings_api.dart';
import 'package:nest_fe/features/academy/presentation/academy_settings_kit.dart';
import 'package:nest_fe/features/fees/data/razorpay_checkout.dart';

const _moduleLabels = {
  'events': 'Events',
  'services': 'Services marketplace',
  'study': 'Study material',
  'branding': 'Custom branding',
  'priority': 'Priority support',
  'manager': 'Dedicated account manager',
};

String _month(String ym) {
  const names = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
  if (ym.length < 7) return ym;
  return '${names[int.parse(ym.substring(5, 7)) - 1]} ${ym.substring(0, 4)}';
}

/// Billing and subscription: what the academy owes Owleo and a way to pay it, every plan Owleo offers with the academy's own
/// marked, the add-ons on sale with the ones the academy has taken marked, and the bill history with its GST and receipts.
///
/// A bill is paid in full through Razorpay. The server works out the amount and checks the gateway's signature before anything
/// is marked paid; without gateway credentials the Pay button explains how to pay Owleo directly instead.
class AcademyBillingScreen extends ConsumerStatefulWidget {
  const AcademyBillingScreen({super.key, required this.academyId});

  final String academyId;

  @override
  ConsumerState<AcademyBillingScreen> createState() => _AcademyBillingScreenState();
}

class _AcademyBillingScreenState extends ConsumerState<AcademyBillingScreen> {
  String? _payingBill;

  Future<void> _refresh() async {
    ref.invalidate(academyBillingProvider);
    ref.invalidate(myAcademyRequestsProvider);
  }

  Future<void> _requestPlan(BillingPlan plan) async {
    final confirmed = await showAppConfirmDialog(
      context: context,
      title: 'Request the ${plan.name} plan?',
      message: 'The Owleo team will review your request and switch the plan. It applies to future bills - '
          'bills already raised keep their amount.',
      confirmLabel: 'Send request',
      destructive: false,
    );
    if (!confirmed || !mounted) return;
    await _send(kind: AcademyRequestKind.planChange, targetPlan: plan.code, done: 'Plan change requested.');
  }

  Future<void> _requestAddon(BillingAddon addon) async {
    final confirmed = await showAppConfirmDialog(
      context: context,
      title: 'Ask for ${addon.name}?',
      message: 'This sends a message to the Owleo team, who will add it to your account. '
          '${addon.monthly ? 'It is charged every month from the next bill.' : 'It is charged once, on the next bill.'}',
      confirmLabel: 'Send request',
      destructive: false,
    );
    if (!confirmed || !mounted) return;
    await _send(
      kind: AcademyRequestKind.support,
      subject: 'Add-on request: ${addon.name}',
      details: 'Please add the "${addon.name}" add-on (${money(addon.price)}${addon.monthly ? ' per month' : ' one time'}) to our academy.',
      done: 'Request sent. The team will be in touch.',
    );
  }

  Future<void> _requestCancel() async {
    final confirmed = await showAppConfirmDialog(
      context: context,
      title: 'Cancel subscription?',
      message: 'This asks the Owleo team to end your subscription. Nothing changes until they confirm it with you.',
      confirmLabel: 'Send request',
    );
    if (!confirmed || !mounted) return;
    await _send(kind: AcademyRequestKind.cancelSubscription, done: 'Cancellation requested.');
  }

  Future<void> _send({required AcademyRequestKind kind, String? targetPlan, String? subject, String? details, required String done}) async {
    try {
      await ref.read(academySettingsApiProvider).submitRequest(kind: kind, targetPlan: targetPlan, subject: subject, details: details);
      ref.invalidate(myAcademyRequestsProvider);
      if (mounted) AppNotice.success(context, done);
    } on ApiException catch (e) {
      if (mounted) AppNotice.error(context, e.message);
    }
  }

  /// Pays one bill in full. The server opens the order and later verifies the signed result; the app never decides a payment
  /// succeeded on its own.
  Future<void> _pay(BillingOverview overview, BillingBill bill) async {
    if (!overview.paymentEnabled) {
      await showAppConfirmDialog(
        context: context,
        title: 'Online payment is not switched on yet',
        message: 'You can pay Owleo directly by bank transfer or UPI. Quote the bill number ${bill.number}, and the team will record '
            'the payment and it will show here.',
        confirmLabel: 'OK',
        destructive: false,
      );
      return;
    }
    final go = await showAppConfirmDialog(
      context: context,
      title: 'Pay ${money(bill.balance)}?',
      message: 'Bill ${bill.number} for ${_month(bill.period)}, including GST. You can pay by UPI, card or net banking.',
      confirmLabel: 'Pay ${money(bill.balance)}',
      destructive: false,
    );
    if (!go || !mounted) return;

    setState(() => _payingBill = bill.id);
    final api = ref.read(academyBillingApiProvider);
    try {
      final order = await api.createBillOrder(bill.id);
      final result = await openRazorpayCheckout(
        keyId: order.keyId,
        orderId: order.orderId,
        amountPaise: order.amountPaise,
        name: 'Owleo Nest',
        description: 'Bill ${bill.number}',
        allMethods: true,
      );
      // The money has moved by now. If the confirmation drops, retry rather than say it failed: the server's webhook settles it anyway.
      Object? lastError;
      var confirmed = false;
      for (var attempt = 0; attempt < 3 && !confirmed; attempt++) {
        try {
          await api.confirmBillPayment(orderId: result.orderId, paymentId: result.paymentId, signature: result.signature);
          confirmed = true;
        } catch (e) {
          lastError = e;
          await Future<void>.delayed(const Duration(seconds: 2));
        }
      }
      await _refresh();
      if (!mounted) return;
      if (confirmed) {
        AppNotice.success(context, 'Payment received. Thank you!');
      } else {
        AppNotice.error(context, "Your payment went through, but we couldn't confirm it yet. It will show as paid shortly - please don't pay again. ($lastError)");
      }
    } on CheckoutCancelled {
      if (mounted) AppNotice.success(context, 'Payment cancelled. Nothing was charged.');
    } on CheckoutFailed catch (e) {
      if (mounted) AppNotice.error(context, e.message);
    } on ApiException catch (e) {
      if (mounted) AppNotice.error(context, e.message);
    } finally {
      if (mounted) setState(() => _payingBill = null);
    }
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final async = ref.watch(academyBillingProvider);
    final pending = ref.watch(myAcademyRequestsProvider).valueOrNull?.where((r) => r.isPending).toList() ?? const [];
    final pendingPlan = pending.where((r) => r.kind == AcademyRequestKind.planChange).firstOrNull;
    final cancelPending = pending.any((r) => r.kind == AcademyRequestKind.cancelSubscription);

    return SettingsPage(
      title: 'Billing & Subscription',
      onRefresh: _refresh,
      children: [
        AsyncValueView<BillingOverview>(
          value: async,
          onRetry: () => ref.invalidate(academyBillingProvider),
          data: (context, o) {
            final current = o.current;
            final payable = o.bills.where((b) => b.payable).toList();
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (payable.isNotEmpty) ...[
                  _DueBanner(overview: o, bills: payable, paying: _payingBill, onPay: (b) => _pay(o, b)),
                  const SizedBox(height: AppSpacing.xl),
                ],
                if (current != null)
                  SettingsCard(
                    color: palette.goldSoft,
                    borderColor: palette.gold.withValues(alpha: 0.33),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text('YOUR PLAN', style: TextStyle(fontSize: AppType.xs, fontWeight: AppType.bold, letterSpacing: 0.4, color: palette.gold)),
                                  const SizedBox(height: 2),
                                  Text(current.name, style: TextStyle(fontSize: 18, fontWeight: AppType.heavy, color: palette.text)),
                                ],
                              ),
                            ),
                            Icon(Icons.workspace_premium_outlined, size: 22, color: palette.gold),
                          ],
                        ),
                        const SizedBox(height: AppSpacing.xl),
                        _UsageBar(label: 'Students', used: o.students, limit: current.maxStudents, color: palette.gold),
                        _UsageBar(label: 'Trainers', used: o.trainers, limit: current.maxTrainers, color: palette.gold),
                        Padding(
                          padding: const EdgeInsets.only(top: 4),
                          child: Text('${money(current.price)}/month, plus GST', style: TextStyle(fontSize: AppType.sm, color: palette.textMuted)),
                        ),
                      ],
                    ),
                  ),
                if (o.plans.isNotEmpty) ...[
                  const SettingsSectionLabel('Plans from Owleo'),
                  if (pendingPlan != null)
                    Padding(
                      padding: const EdgeInsets.only(bottom: AppSpacing.lg),
                      child: SettingsNote(text: 'You have asked to move to ${pendingPlan.targetPlan}. The team will confirm it.', icon: Icons.hourglass_bottom, color: palette.gold),
                    ),
                  for (final plan in o.plans) ...[
                    _PlanCard(
                      plan: plan,
                      isHigher: plan.price > (current?.price ?? 0),
                      requested: pendingPlan?.targetPlan == plan.code,
                      onRequest: pendingPlan != null ? null : () => _requestPlan(plan),
                    ),
                    const SizedBox(height: AppSpacing.lg),
                  ],
                ],
                if (o.addons.isNotEmpty) ...[
                  const SettingsSectionLabel('Add-ons'),
                  for (final addon in o.addons) ...[
                    _AddonCard(addon: addon, onRequest: () => _requestAddon(addon)),
                    const SizedBox(height: AppSpacing.lg),
                  ],
                ],
                const SettingsSectionLabel('Bills and payments'),
                if (o.bills.isEmpty)
                  const EmptyState(icon: Icons.receipt_long_outlined, message: 'No bills raised yet.')
                else
                  for (final bill in o.bills) ...[
                    _BillCard(bill: bill, paying: _payingBill == bill.id, onPay: bill.payable ? () => _pay(o, bill) : null),
                    const SizedBox(height: AppSpacing.lg),
                  ],
              ],
            );
          },
        ),
        const SizedBox(height: AppSpacing.x4l),
        Pressable(
          onTap: cancelPending ? null : _requestCancel,
          child: Container(
            padding: const EdgeInsets.symmetric(vertical: 13),
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: palette.notPaidSoft,
              borderRadius: AppRadii.all(AppRadii.xl),
              border: Border.all(color: palette.notPaid.withValues(alpha: 0.33)),
            ),
            child: Text(cancelPending ? 'Cancellation requested' : 'Cancel subscription', style: TextStyle(fontSize: AppType.xl, fontWeight: AppType.bold, color: palette.notPaid)),
          ),
        ),
      ],
    );
  }
}

/// What is owed, at the top where it cannot be missed, with a Pay button for each bill.
class _DueBanner extends StatelessWidget {
  const _DueBanner({required this.overview, required this.bills, required this.paying, required this.onPay});

  final BillingOverview overview;
  final List<BillingBill> bills;
  final String? paying;
  final void Function(BillingBill) onPay;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final overdue = overview.overdueCount > 0;
    final color = overdue ? palette.notPaid : palette.gold;
    final soft = overdue ? palette.notPaidSoft : palette.goldSoft;
    return SettingsCard(
      color: soft,
      borderColor: color.withValues(alpha: 0.4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Icon(overdue ? Icons.warning_amber_rounded : Icons.receipt_long_outlined, size: 18, color: color),
              const SizedBox(width: 8),
              Text(overdue ? 'OVERDUE' : 'PAYMENT DUE', style: TextStyle(fontSize: AppType.xs, fontWeight: AppType.bold, letterSpacing: 0.4, color: color)),
            ],
          ),
          const SizedBox(height: 4),
          Text(money(overview.outstanding), style: TextStyle(fontSize: 26, fontWeight: AppType.heavy, color: palette.text)),
          Text(
            bills.length == 1 ? 'Bill ${bills.first.number} · due ${formatFeeDate(DateTime.parse(bills.first.dueOn))}' : '${bills.length} bills are waiting for payment',
            style: TextStyle(fontSize: AppType.sm, color: palette.textMuted),
          ),
          const SizedBox(height: AppSpacing.lg),
          for (final b in bills)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: _PayButton(label: bills.length == 1 ? 'Pay ${money(b.balance)}' : '${_month(b.period)} · Pay ${money(b.balance)}', busy: paying == b.id, onTap: paying == null ? () => onPay(b) : null),
            ),
          if (!overview.paymentEnabled)
            Text('Online payment is not switched on yet. Pay Owleo by bank transfer or UPI and the team will record it here.', style: TextStyle(fontSize: AppType.xs, color: palette.textMuted)),
        ],
      ),
    );
  }
}

class _PayButton extends StatelessWidget {
  const _PayButton({required this.label, required this.busy, required this.onTap});

  final String label;
  final bool busy;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return Pressable(
      onTap: busy ? null : onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 12),
        alignment: Alignment.center,
        decoration: BoxDecoration(color: onTap == null && !busy ? palette.surfaceHigh : palette.primary, borderRadius: AppRadii.all(AppRadii.lg)),
        child: busy
            ? SizedBox(height: 18, width: 18, child: CircularProgressIndicator(strokeWidth: 2, color: palette.onPrimary))
            : Text(label, style: TextStyle(fontSize: AppType.md, fontWeight: AppType.bold, color: onTap == null ? palette.textFaint : palette.onPrimary)),
      ),
    );
  }
}

class _UsageBar extends StatelessWidget {
  const _UsageBar({required this.label, required this.used, required this.limit, required this.color});

  final String label;
  final int used;

  /// Null: the plan has no cap on this count.
  final int? limit;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final over = limit != null && used > limit!;
    final fraction = limit == null ? 1.0 : (limit == 0 ? 1.0 : (used / limit!).clamp(0.0, 1.0));
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Column(
        children: [
          Row(
            children: [
              Text(label, style: TextStyle(fontSize: AppType.sm, fontWeight: AppType.semi, color: palette.textMuted)),
              const Spacer(),
              Text(limit == null ? '$used · unlimited' : '$used / $limit', style: TextStyle(fontSize: AppType.sm, fontWeight: AppType.bold, color: over ? palette.notPaid : palette.text)),
            ],
          ),
          const SizedBox(height: 5),
          ClipRRect(
            borderRadius: BorderRadius.circular(3),
            child: LinearProgressIndicator(value: fraction, minHeight: 6, backgroundColor: palette.surfaceHigh, valueColor: AlwaysStoppedAnimation(over ? palette.notPaid : color)),
          ),
        ],
      ),
    );
  }
}

/// A plan Owleo offers. The academy's own is filled in gold with a tick and CURRENT; the rest stay quiet.
class _PlanCard extends StatelessWidget {
  const _PlanCard({required this.plan, required this.isHigher, required this.requested, required this.onRequest});

  final BillingPlan plan;
  final bool isHigher;
  final bool requested;
  final VoidCallback? onRequest;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final isCurrent = plan.current;
    final accent = isCurrent ? palette.gold : palette.primary;
    String cap(int? n, String what) => n == null ? 'Unlimited $what' : 'Up to $n $what';
    final features = [cap(plan.maxStudents, 'students'), cap(plan.maxTrainers, 'trainers'), for (final m in plan.modules) _moduleLabels[m] ?? m];

    return SettingsCard(
      color: isCurrent ? palette.goldSoft : palette.surfaceRaised,
      borderColor: isCurrent ? palette.gold : palette.border,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              if (isCurrent) ...[Icon(Icons.check_circle, size: 20, color: palette.gold), const SizedBox(width: 6)],
              Text(plan.name, style: TextStyle(fontSize: AppType.x4l, fontWeight: AppType.heavy, color: accent)),
              const Spacer(),
              if (plan.popular && !isCurrent) StatusBadge(label: 'POPULAR', color: palette.violet),
              if (isCurrent) StatusBadge(label: 'YOUR PLAN', color: palette.gold),
              if (requested) StatusBadge(label: 'REQUESTED', color: palette.primary),
            ],
          ),
          const SizedBox(height: AppSpacing.sm),
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(plan.price == 0 ? 'Free' : money(plan.price), style: TextStyle(fontSize: 22, fontWeight: AppType.heavy, color: palette.text)),
              if (plan.price > 0) ...[
                const SizedBox(width: 4),
                Padding(padding: const EdgeInsets.only(bottom: 3), child: Text('/month + GST', style: TextStyle(fontSize: AppType.smd, color: palette.textFaint))),
              ],
            ],
          ),
          const SizedBox(height: AppSpacing.lg),
          for (final line in features)
            Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Row(children: [
                Icon(Icons.check, size: 13, color: accent),
                const SizedBox(width: 6),
                Expanded(child: Text(line, style: TextStyle(fontSize: AppType.base, color: palette.textMuted))),
              ]),
            ),
          if (!isCurrent && !requested) ...[
            const SizedBox(height: AppSpacing.md),
            Pressable(
              onTap: onRequest,
              child: Container(
                padding: const EdgeInsets.symmetric(vertical: 10),
                alignment: Alignment.center,
                decoration: BoxDecoration(color: onRequest == null ? palette.surfaceHigh : palette.primary, borderRadius: AppRadii.all(AppRadii.lg)),
                child: Text('${isHigher ? 'Request upgrade' : 'Request switch'} to ${plan.name}',
                    style: TextStyle(fontSize: AppType.md, fontWeight: AppType.bold, color: onRequest == null ? palette.textFaint : palette.onPrimary)),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// An add-on. One the academy has is highlighted with ACTIVE and the month it started; the others show their price and can be asked for.
class _AddonCard extends StatelessWidget {
  const _AddonCard({required this.addon, required this.onRequest});

  final BillingAddon addon;
  final VoidCallback onRequest;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final on = addon.adopted;
    return SettingsCard(
      color: on ? palette.paidManualSoft : palette.surfaceRaised,
      borderColor: on ? palette.paidManual : palette.border,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              if (on) ...[Icon(Icons.check_circle, size: 18, color: palette.paidManual), const SizedBox(width: 6)],
              Expanded(child: Text(addon.name, style: TextStyle(fontSize: AppType.xl, fontWeight: AppType.heavy, color: on ? palette.paidManual : palette.text))),
              if (on) StatusBadge(label: 'ACTIVE', color: palette.paidManual),
            ],
          ),
          if (addon.description.isNotEmpty) ...[
            const SizedBox(height: 4),
            Text(addon.description, style: TextStyle(fontSize: AppType.base, color: palette.textMuted)),
          ],
          const SizedBox(height: AppSpacing.md),
          Text(
            '${money(addon.price)}${addon.monthly ? ' / month' : ' one time'} + GST${on && addon.fromPeriod != null ? ' · since ${_month(addon.fromPeriod!)}' : ''}',
            style: TextStyle(fontSize: AppType.sm, fontWeight: AppType.semi, color: on ? palette.paidManual : palette.textFaint),
          ),
          if (!on) ...[
            const SizedBox(height: AppSpacing.md),
            Pressable(
              onTap: onRequest,
              child: Container(
                padding: const EdgeInsets.symmetric(vertical: 9),
                alignment: Alignment.center,
                decoration: BoxDecoration(color: palette.surfaceHigh, borderRadius: AppRadii.all(AppRadii.lg), border: Border.all(color: palette.border)),
                child: Text('Ask Owleo to add this', style: TextStyle(fontSize: AppType.md, fontWeight: AppType.bold, color: palette.text)),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// One bill. Collapsed it shows the month, the total and the status; open it shows every line, the discount and GST, and
/// each payment that settled it. A bill with something owing carries its Pay button.
class _BillCard extends StatefulWidget {
  const _BillCard({required this.bill, required this.paying, required this.onPay});

  final BillingBill bill;
  final bool paying;
  final VoidCallback? onPay;

  @override
  State<_BillCard> createState() => _BillCardState();
}

class _BillCardState extends State<_BillCard> {
  bool _open = false;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final b = widget.bill;
    final paid = b.status == 'PAID' || (!b.payable && b.status != 'WAIVED');
    final label = b.status == 'WAIVED' ? 'WAIVED' : paid ? 'PAID' : b.overdue ? '${b.daysOverdue}D OVERDUE' : b.paid > 0 ? 'PART PAID' : 'DUE';
    final color = b.status == 'WAIVED' ? palette.textMuted : paid ? palette.paidManual : b.overdue ? palette.notPaid : palette.gold;
    Widget row(String l, String v, {bool bold = false, Color? c}) => Padding(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: Row(children: [
            Expanded(child: Text(l, style: TextStyle(fontSize: AppType.sm, color: palette.textMuted, fontWeight: bold ? AppType.bold : null))),
            Text(v, style: TextStyle(fontSize: AppType.md, fontWeight: bold ? AppType.heavy : AppType.semi, color: c ?? palette.text)),
          ]),
        );

    return SettingsCard(
      borderColor: b.overdue ? palette.notPaid.withValues(alpha: 0.5) : null,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Pressable(
            onTap: () => setState(() => _open = !_open),
            child: Row(
              children: [
                Container(width: 34, height: 34, decoration: BoxDecoration(color: palette.surfaceHigh, borderRadius: AppRadii.all(AppRadii.md)), child: Icon(Icons.receipt_outlined, size: 16, color: palette.textMuted)),
                const SizedBox(width: AppSpacing.lg),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(_month(b.period), style: TextStyle(fontSize: AppType.lg, fontWeight: AppType.semi, color: palette.text)),
                      Text('${b.number} · due ${formatFeeDate(DateTime.parse(b.dueOn))}', style: TextStyle(fontSize: AppType.xs, color: palette.textFaint)),
                    ],
                  ),
                ),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(money(b.total), style: TextStyle(fontSize: AppType.lg, fontWeight: AppType.bold, color: palette.text)),
                    const SizedBox(height: 3),
                    StatusBadge(label: label, color: color),
                  ],
                ),
                const SizedBox(width: 4),
                Icon(_open ? Icons.expand_less : Icons.expand_more, size: 20, color: palette.textFaint),
              ],
            ),
          ),
          if (_open) ...[
            const SizedBox(height: AppSpacing.lg),
            Divider(height: 1, color: palette.borderSoft),
            const SizedBox(height: AppSpacing.md),
            for (final l in b.lines) row(l.label, money(l.amount), c: l.amount < 0 ? palette.paidManual : null),
            if (b.discount > 0) row('Discount', '-${money(b.discount)}', c: palette.paidManual),
            row('GST (${b.gstRate.round()}%)', money(b.gst)),
            row('Total', money(b.total), bold: true),
            if (b.payments.isNotEmpty) ...[
              const SizedBox(height: AppSpacing.md),
              Text('PAYMENTS', style: TextStyle(fontSize: AppType.xs, fontWeight: AppType.bold, letterSpacing: 0.4, color: palette.textFaint)),
              const SizedBox(height: 4),
              for (final p in b.payments)
                row('${formatFeeDate(DateTime.parse(p.paidOn))} · ${p.mode}${p.online ? ' (online)' : ''}${p.reference.isEmpty ? '' : ' · ${p.reference}'}', money(p.amount), c: palette.paidManual),
            ],
            if (b.payable) row('Still to pay', money(b.balance), bold: true, c: b.overdue ? palette.notPaid : palette.text),
            if ((b.note ?? '').isNotEmpty) Padding(padding: const EdgeInsets.only(top: 6), child: Text(b.note!, style: TextStyle(fontSize: AppType.sm, color: palette.textMuted))),
          ],
          if (widget.onPay != null) ...[
            const SizedBox(height: AppSpacing.lg),
            _PayButton(label: 'Pay ${money(b.balance)}', busy: widget.paying, onTap: widget.onPay),
          ],
        ],
      ),
    );
  }
}
