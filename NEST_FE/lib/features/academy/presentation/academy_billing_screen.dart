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

/// The academy's plan, how much of it is in use, the other plans on offer, and the real invoice
/// history.
///
/// There is no payment gateway, so an academy cannot switch plan or stop its subscription itself:
/// both are requests the Owleo team answers. Approving a plan change applies the new plan to
/// future invoices; invoices already raised keep the amount they were issued at.
class AcademyBillingScreen extends ConsumerWidget {
  const AcademyBillingScreen({super.key, required this.academyId});

  final String academyId;

  Future<void> _requestPlan(BuildContext context, WidgetRef ref, PlanSummary plan) async {
    final confirmed = await showAppConfirmDialog(
      context: context,
      title: 'Request the ${plan.displayName} plan?',
      message: 'The Owleo team will review your request and switch the plan. It applies to future invoices - '
          'invoices already raised keep their amount.',
      confirmLabel: 'Send request',
      destructive: false,
    );
    if (!confirmed || !context.mounted) return;
    await _send(context, ref, kind: AcademyRequestKind.planChange, targetPlan: plan.code, done: 'Plan change requested.');
  }

  Future<void> _requestCancel(BuildContext context, WidgetRef ref) async {
    final confirmed = await showAppConfirmDialog(
      context: context,
      title: 'Cancel subscription?',
      message: 'This asks the Owleo team to end your subscription. Nothing changes until they confirm it with you.',
      confirmLabel: 'Send request',
    );
    if (!confirmed || !context.mounted) return;
    await _send(context, ref, kind: AcademyRequestKind.cancelSubscription, done: 'Cancellation requested.');
  }

  Future<void> _send(BuildContext context, WidgetRef ref,
      {required AcademyRequestKind kind, String? targetPlan, required String done}) async {
    try {
      await ref.read(academySettingsApiProvider).submitRequest(kind: kind, targetPlan: targetPlan);
      ref.invalidate(myAcademyRequestsProvider);
      if (context.mounted) AppNotice.success(context, done);
    } on ApiException catch (e) {
      if (context.mounted) AppNotice.error(context, e.message);
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final palette = context.palette;
    final subscriptionAsync = ref.watch(subscriptionProvider);
    final invoicesAsync = ref.watch(academyInvoicesProvider);
    final pending = ref.watch(myAcademyRequestsProvider).valueOrNull?.where((r) => r.isPending).toList() ?? const [];
    final pendingPlan = pending.where((r) => r.kind == AcademyRequestKind.planChange).firstOrNull;
    final cancelPending = pending.any((r) => r.kind == AcademyRequestKind.cancelSubscription);

    return SettingsPage(
      title: 'Billing & Subscription',
      onRefresh: () async {
        ref.invalidate(subscriptionProvider);
        ref.invalidate(academyInvoicesProvider);
        ref.invalidate(myAcademyRequestsProvider);
      },
      children: [
        AsyncValueView<Subscription>(
          value: subscriptionAsync,
          onRetry: () => ref.invalidate(subscriptionProvider),
          data: (context, sub) => Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
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
                              Text('CURRENT PLAN',
                                  style: TextStyle(fontSize: AppType.xs, fontWeight: AppType.bold, letterSpacing: 0.4, color: palette.gold)),
                              const SizedBox(height: 2),
                              Text(sub.current.displayName,
                                  style: TextStyle(fontSize: 18, fontWeight: AppType.heavy, color: palette.text)),
                            ],
                          ),
                        ),
                        Icon(Icons.workspace_premium_outlined, size: 22, color: palette.gold),
                      ],
                    ),
                    const SizedBox(height: AppSpacing.xl),
                    _UsageBar(label: 'Students', used: sub.students, limit: sub.current.maxStudents, color: palette.gold),
                    _UsageBar(label: 'Trainers', used: sub.trainers, limit: sub.current.maxTrainers, color: palette.gold),
                    if (sub.current.monthlyPrice != null)
                      Padding(
                        padding: const EdgeInsets.only(top: 4),
                        child: Text('${money(sub.current.monthlyPrice!)}/month',
                            style: TextStyle(fontSize: AppType.sm, color: palette.textMuted)),
                      ),
                  ],
                ),
              ),
              if (sub.plans.isNotEmpty) ...[
                const SettingsSectionLabel('Available plans'),
                if (pendingPlan != null)
                  Padding(
                    padding: const EdgeInsets.only(bottom: AppSpacing.lg),
                    child: SettingsNote(
                      text: 'You have asked to move to ${pendingPlan.targetPlan}. The team will confirm it.',
                      icon: Icons.hourglass_bottom,
                      color: palette.gold,
                    ),
                  ),
                for (final plan in sub.plans) ...[
                  _PlanCard(
                    plan: plan,
                    isCurrent: plan.code == sub.current.code,
                    isHigher: (plan.monthlyPrice ?? 0) > (sub.current.monthlyPrice ?? 0),
                    requested: pendingPlan?.targetPlan == plan.code,
                    onRequest: pendingPlan != null ? null : () => _requestPlan(context, ref, plan),
                  ),
                  const SizedBox(height: AppSpacing.lg),
                ],
              ],
            ],
          ),
        ),
        const SettingsSectionLabel('Invoice history'),
        AsyncValueView<List<AcademyInvoice>>(
          value: invoicesAsync,
          onRetry: () => ref.invalidate(academyInvoicesProvider),
          data: (context, invoices) {
            if (invoices.isEmpty) {
              return const EmptyState(icon: Icons.receipt_long_outlined, message: 'No invoices raised yet.');
            }
            return SettingsCard(
              padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xl),
              child: Column(
                children: [
                  for (var i = 0; i < invoices.length; i++) _InvoiceRow(invoice: invoices[i], last: i == invoices.length - 1),
                ],
              ),
            );
          },
        ),
        const SizedBox(height: AppSpacing.x4l),
        Pressable(
          onTap: cancelPending ? null : () => _requestCancel(context, ref),
          child: Container(
            padding: const EdgeInsets.symmetric(vertical: 13),
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: palette.notPaidSoft,
              borderRadius: AppRadii.all(AppRadii.xl),
              border: Border.all(color: palette.notPaid.withValues(alpha: 0.33)),
            ),
            child: Text(cancelPending ? 'Cancellation requested' : 'Cancel subscription',
                style: TextStyle(fontSize: AppType.xl, fontWeight: AppType.bold, color: palette.notPaid)),
          ),
        ),
      ],
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
              Text(limit == null ? '$used · unlimited' : '$used / $limit',
                  style: TextStyle(fontSize: AppType.sm, fontWeight: AppType.bold, color: over ? palette.notPaid : palette.text)),
            ],
          ),
          const SizedBox(height: 5),
          ClipRRect(
            borderRadius: BorderRadius.circular(3),
            child: LinearProgressIndicator(
              value: fraction,
              minHeight: 6,
              backgroundColor: palette.surfaceHigh,
              valueColor: AlwaysStoppedAnimation(over ? palette.notPaid : color),
            ),
          ),
        ],
      ),
    );
  }
}

class _PlanCard extends StatelessWidget {
  const _PlanCard({required this.plan, required this.isCurrent, required this.isHigher, required this.requested, required this.onRequest});

  final PlanSummary plan;
  final bool isCurrent;
  final bool isHigher;
  final bool requested;
  final VoidCallback? onRequest;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final accent = isCurrent ? palette.gold : palette.primary;
    String cap(int? n, String what) => n == null ? 'Unlimited $what' : 'Up to $n $what';

    return SettingsCard(
      color: isCurrent ? palette.goldSoft : palette.surfaceRaised,
      borderColor: isCurrent ? palette.gold : palette.border,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(plan.displayName, style: TextStyle(fontSize: AppType.x4l, fontWeight: AppType.heavy, color: accent)),
              const Spacer(),
              if (isCurrent) StatusBadge(label: 'CURRENT', color: palette.gold),
              if (requested) StatusBadge(label: 'REQUESTED', color: palette.primary),
            ],
          ),
          const SizedBox(height: AppSpacing.sm),
          if (plan.monthlyPrice != null)
            Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(money(plan.monthlyPrice!), style: TextStyle(fontSize: 22, fontWeight: AppType.heavy, color: palette.text)),
                const SizedBox(width: 4),
                Padding(
                  padding: const EdgeInsets.only(bottom: 3),
                  child: Text('/month', style: TextStyle(fontSize: AppType.smd, color: palette.textFaint)),
                ),
              ],
            ),
          const SizedBox(height: AppSpacing.lg),
          for (final line in [cap(plan.maxStudents, 'students'), cap(plan.maxTrainers, 'trainers')])
            Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Row(children: [
                Icon(Icons.check, size: 13, color: accent),
                const SizedBox(width: 6),
                Text(line, style: TextStyle(fontSize: AppType.base, color: palette.textMuted)),
              ]),
            ),
          if (!isCurrent && !requested) ...[
            const SizedBox(height: AppSpacing.md),
            Pressable(
              onTap: onRequest,
              child: Container(
                padding: const EdgeInsets.symmetric(vertical: 10),
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: onRequest == null ? palette.surfaceHigh : palette.primary,
                  borderRadius: AppRadii.all(AppRadii.lg),
                ),
                child: Text('${isHigher ? 'Request upgrade' : 'Request switch'} to ${plan.displayName}',
                    style: TextStyle(
                        fontSize: AppType.md,
                        fontWeight: AppType.bold,
                        color: onRequest == null ? palette.textFaint : palette.onPrimary)),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _InvoiceRow extends StatelessWidget {
  const _InvoiceRow({required this.invoice, required this.last});

  final AcademyInvoice invoice;
  final bool last;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final paid = invoice.status == 'PAID';
    final statusColor = invoice.overdue ? palette.notPaid : (paid ? palette.paidManual : palette.textMuted);
    final statusSoft = invoice.overdue ? palette.notPaidSoft : (paid ? palette.paidManualSoft : palette.surfaceHigh);

    return Container(
      padding: const EdgeInsets.symmetric(vertical: 12),
      decoration: BoxDecoration(border: last ? null : Border(bottom: BorderSide(color: palette.borderSoft))),
      child: Row(
        children: [
          Container(
            width: 30,
            height: 30,
            decoration: BoxDecoration(color: palette.surfaceHigh, borderRadius: AppRadii.all(AppRadii.md)),
            child: Icon(Icons.receipt_outlined, size: 14, color: palette.textMuted),
          ),
          const SizedBox(width: AppSpacing.lg),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(invoice.period, style: TextStyle(fontSize: AppType.md, fontWeight: AppType.semi, color: palette.text)),
                Text('Due ${formatFeeDate(DateTime.parse(invoice.dueOn))}',
                    style: TextStyle(fontSize: AppType.xs, color: palette.textFaint)),
              ],
            ),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(money(invoice.amount), style: TextStyle(fontSize: AppType.md, fontWeight: AppType.bold, color: palette.text)),
              const SizedBox(height: 2),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 1.5),
                decoration: BoxDecoration(color: statusSoft, borderRadius: AppRadii.all(AppRadii.pill)),
                child: Text(invoice.overdue ? '${invoice.status} · OVERDUE' : invoice.status,
                    style: TextStyle(fontSize: 9.5, fontWeight: AppType.heavy, color: statusColor)),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
