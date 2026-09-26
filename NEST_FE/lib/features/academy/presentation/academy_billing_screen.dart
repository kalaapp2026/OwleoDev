import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:nest_fe/core/format/money.dart';
import 'package:nest_fe/core/widgets/async_value_view.dart';
import 'package:nest_fe/features/academy/data/academy_billing_api.dart';

/// Read-only: current plan and real invoice history. There is no self-service plan change here -
/// that stays a Super Admin action via the platform billing console, since there's no payment
/// gateway wired up for an academy to switch its own plan.
class AcademyBillingScreen extends ConsumerWidget {
  const AcademyBillingScreen({super.key, required this.academyId});

  final String academyId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colorScheme = Theme.of(context).colorScheme;
    final academyAsync = ref.watch(academyDetailProvider(academyId));
    final invoicesAsync = ref.watch(academyInvoicesProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Billing & Subscription')),
      body: RefreshIndicator(
        onRefresh: () async {
          ref.invalidate(academyDetailProvider(academyId));
          ref.invalidate(academyInvoicesProvider);
          await Future.wait([
            ref.read(academyDetailProvider(academyId).future),
            ref.read(academyInvoicesProvider.future),
          ]);
        },
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            AsyncValueView<Academy>(
              value: academyAsync,
              onRetry: () => ref.invalidate(academyDetailProvider(academyId)),
              data: (context, academy) => Card(
                child: ListTile(
                  leading: Icon(Icons.workspace_premium_outlined, color: colorScheme.primary),
                  title: Text(academy.plan ?? 'No plan set'),
                  subtitle: Text('Current plan · ${academy.name}'),
                ),
              ),
            ),
            const SizedBox(height: 20),
            Padding(
              padding: const EdgeInsets.only(left: 4, bottom: 8),
              child: Text('Invoice history',
                  style: TextStyle(fontWeight: FontWeight.w700, color: colorScheme.onSurface.withValues(alpha: 0.7))),
            ),
            AsyncValueView<List<AcademyInvoice>>(
              value: invoicesAsync,
              onRetry: () => ref.invalidate(academyInvoicesProvider),
              data: (context, invoices) {
                if (invoices.isEmpty) {
                  return const EmptyState(icon: Icons.receipt_long_outlined, message: 'No invoices raised yet.');
                }
                return Column(
                  children: invoices.map((inv) => _InvoiceRow(invoice: inv)).toList(),
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}

class _InvoiceRow extends StatelessWidget {
  const _InvoiceRow({required this.invoice});
  final AcademyInvoice invoice;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final paid = invoice.status == 'PAID';
    final statusColor = invoice.overdue ? colorScheme.error : (paid ? Colors.green : colorScheme.onSurface.withValues(alpha: 0.6));

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        leading: Icon(Icons.receipt_outlined, color: colorScheme.onSurface.withValues(alpha: 0.6)),
        title: Text(invoice.period),
        subtitle: Text('Due ${formatFeeDate(DateTime.parse(invoice.dueOn))}'),
        trailing: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Text(money(invoice.amount), style: const TextStyle(fontWeight: FontWeight.w700)),
            const SizedBox(height: 2),
            Text(
              invoice.overdue ? '${invoice.status} · overdue' : invoice.status,
              style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: statusColor),
            ),
          ],
        ),
      ),
    );
  }
}
