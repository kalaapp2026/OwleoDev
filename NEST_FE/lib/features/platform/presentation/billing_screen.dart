import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:nest_fe/core/error/api_exception.dart';
import 'package:nest_fe/core/providers/core_providers.dart';
import 'package:nest_fe/core/widgets/app_notice.dart';
import 'package:nest_fe/core/widgets/async_value_view.dart';
import 'package:nest_fe/features/platform/data/billing_api.dart';
import 'package:nest_fe/features/platform/presentation/academy_stats_screen.dart' show formatCurrency;
import 'package:nest_fe/features/platform/presentation/console_layout.dart';

final billingApiProvider = Provider((ref) => BillingApi(ref.watch(dioClientProvider)));
final billingSummaryProvider = FutureProvider.autoDispose((ref) => ref.watch(billingApiProvider).summary());
final billingInvoicesProvider = FutureProvider.autoDispose((ref) => ref.watch(billingApiProvider).invoices());

/// Platform billing console: what academies owe NEST. The opposite direction of money from the
/// Fees screen, which is an academy billing its own students - hence the separate section rather
/// than reusing that UI.
class BillingScreen extends ConsumerWidget {
  const BillingScreen({super.key, this.embedded = false});

  final bool embedded;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final summaryAsync = ref.watch(billingSummaryProvider);

    return Scaffold(
      appBar: embedded ? null : AppBar(title: const Text('Billing')),
      body: AsyncValueView<BillingSummary>(
        value: summaryAsync,
        onRetry: () => ref.invalidate(billingSummaryProvider),
        data: (context, summary) => RefreshIndicator(
          onRefresh: () async {
            ref.invalidate(billingSummaryProvider);
            ref.invalidate(billingInvoicesProvider);
            await ref.read(billingSummaryProvider.future);
          },
          child: ConsolePage(
            children: [
              _Header(summary: summary),
              const SizedBox(height: 24),
              const ConsoleSectionTitle('Revenue'),
              ConsoleStatGrid(stats: _revenueStats(context, summary)),
              const SizedBox(height: 28),
              if (summary.byPlan.isNotEmpty) ...[
                const ConsoleSectionTitle('By plan'),
                _PlanBreakdownTable(rows: summary.byPlan),
                const SizedBox(height: 28),
              ],
              ConsoleSectionTitle('Invoices - ${summary.currentPeriod}'),
              const _InvoiceTable(),
            ],
          ),
        ),
      ),
    );
  }

  List<ConsoleStat> _revenueStats(BuildContext context, BillingSummary s) {
    final colorScheme = Theme.of(context).colorScheme;
    return [
      ConsoleStat('MRR', formatCurrency(s.mrr), Icons.trending_up, footnote: 'active plans'),
      ConsoleStat('ARR', formatCurrency(s.arr), Icons.calendar_today_outlined, footnote: 'MRR x 12'),
      ConsoleStat('Billed this month', formatCurrency(s.billedThisMonth), Icons.receipt_long_outlined),
      ConsoleStat('Collected', formatCurrency(s.collectedThisMonth), Icons.payments_outlined),
      ConsoleStat('Outstanding', formatCurrency(s.outstanding), Icons.hourglass_bottom,
          tone: s.outstanding > 0 ? colorScheme.error : null),
      ConsoleStat('Overdue invoices', '${s.overdueCount}', Icons.warning_amber_outlined,
          tone: s.overdueCount > 0 ? colorScheme.error : null,
          footnote: s.overdueCount > 0 ? 'need chasing' : null),
    ];
  }
}

class _Header extends ConsumerStatefulWidget {
  const _Header({required this.summary});
  final BillingSummary summary;

  @override
  ConsumerState<_Header> createState() => _HeaderState();
}

class _HeaderState extends ConsumerState<_Header> {
  bool _generating = false;

  Future<void> _generate() async {
    final ok = await AppNotice.confirm(
      context,
      title: 'Raise invoices for ${widget.summary.currentPeriod}?',
      message: 'Creates this month\'s invoice for every active paying academy. Academies already '
          'invoiced for this period are skipped, so running it twice is safe.',
      confirmLabel: 'Generate',
    );
    if (!ok) return;

    setState(() => _generating = true);
    try {
      final created = await ref.read(billingApiProvider).generate();
      if (mounted) {
        AppNotice.success(
          context,
          created == 0
              ? 'Nothing to raise - every active academy already has an invoice for this period.'
              : '$created invoice${created == 1 ? '' : 's'} raised.',
        );
        ref.invalidate(billingSummaryProvider);
        ref.invalidate(billingInvoicesProvider);
      }
    } on ApiException catch (e) {
      if (mounted) AppNotice.error(context, e.message);
    } finally {
      if (mounted) setState(() => _generating = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = widget.summary;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Platform billing', style: Theme.of(context).textTheme.headlineSmall),
              const SizedBox(height: 4),
              Text(
                '${s.payingAcademies} paying  ·  ${s.freeAcademies} on free  ·  period ${s.currentPeriod}',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],
          ),
        ),
        if (_generating)
          const Padding(
            padding: EdgeInsets.only(top: 8),
            child: SizedBox(height: 20, width: 20, child: CircularProgressIndicator(strokeWidth: 2)),
          )
        else
          FilledButton.icon(
            onPressed: _generate,
            icon: const Icon(Icons.receipt_long_outlined, size: 18),
            label: const Text('Generate invoices'),
          ),
      ],
    );
  }
}

class _PlanBreakdownTable extends StatelessWidget {
  const _PlanBreakdownTable({required this.rows});
  final List<PlanBreakdown> rows;

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        child: Column(
          children: rows
              .map((r) => Padding(
                    padding: const EdgeInsets.symmetric(vertical: 10),
                    child: Row(
                      children: [
                        Expanded(
                          flex: 3,
                          child: Text(r.displayName, style: const TextStyle(fontWeight: FontWeight.w600)),
                        ),
                        Expanded(
                          flex: 2,
                          child: Text('${r.academies} ${r.academies == 1 ? 'academy' : 'academies'}',
                              style: Theme.of(context).textTheme.bodySmall),
                        ),
                        Text(
                          '${formatCurrency(r.monthlyValue)}/mo',
                          style: const TextStyle(fontWeight: FontWeight.w700),
                        ),
                      ],
                    ),
                  ))
              .toList(),
        ),
      ),
    );
  }
}

class _InvoiceTable extends ConsumerWidget {
  const _InvoiceTable();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(billingInvoicesProvider);
    return AsyncValueView<List<Invoice>>(
      value: async,
      onRetry: () => ref.invalidate(billingInvoicesProvider),
      data: (context, invoices) {
        if (invoices.isEmpty) {
          return const Card(
            margin: EdgeInsets.zero,
            child: Padding(
              padding: EdgeInsets.symmetric(vertical: 32),
              child: EmptyState(
                icon: Icons.receipt_long_outlined,
                message: 'No invoices for this period yet - use Generate invoices above.',
              ),
            ),
          );
        }
        // Overdue first: this list exists to be worked through, and the rows that need action
        // should never be below the ones that don't.
        final sorted = [...invoices]..sort((a, b) {
            if (a.overdue != b.overdue) return a.overdue ? -1 : 1;
            if (a.isDue != b.isDue) return a.isDue ? -1 : 1;
            return b.amount.compareTo(a.amount);
          });

        if (ConsoleBreakpoints.isCompact(context)) {
          return Column(children: sorted.map((i) => _InvoiceCard(invoice: i)).toList());
        }
        return Card(
          margin: EdgeInsets.zero,
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: ConstrainedBox(
              constraints: BoxConstraints(minWidth: MediaQuery.sizeOf(context).width - 96),
              child: DataTable(
                headingRowHeight: 44,
                dataRowMinHeight: 48,
                dataRowMaxHeight: 60,
                columns: const [
                  DataColumn(label: Text('Academy')),
                  DataColumn(label: Text('Plan')),
                  DataColumn(label: Text('Amount'), numeric: true),
                  DataColumn(label: Text('Due')),
                  DataColumn(label: Text('Status')),
                  DataColumn(label: Text('Actions')),
                ],
                rows: sorted.map((i) => _row(context, ref, i)).toList(),
              ),
            ),
          ),
        );
      },
    );
  }

  DataRow _row(BuildContext context, WidgetRef ref, Invoice invoice) {
    return DataRow(cells: [
      DataCell(Text(invoice.academyName ?? invoice.academyId,
          style: const TextStyle(fontWeight: FontWeight.w600))),
      DataCell(Text(invoice.planCode)),
      DataCell(Text(formatCurrency(invoice.amount))),
      DataCell(Text(invoice.dueOn == null ? '-' : _shortDate(invoice.dueOn!))),
      DataCell(_InvoiceStatusChip(invoice: invoice)),
      DataCell(_InvoiceActions(invoice: invoice)),
    ]);
  }

  static String _shortDate(DateTime d) => '${d.day}/${d.month}';
}

class _InvoiceStatusChip extends StatelessWidget {
  const _InvoiceStatusChip({required this.invoice});
  final Invoice invoice;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final (label, color) = switch (invoice.status) {
      'PAID' => ('paid', Colors.green.shade600),
      'WAIVED' => ('waived', colorScheme.onSurface.withValues(alpha: 0.5)),
      _ => invoice.overdue
          ? ('${invoice.daysOverdue}d overdue', colorScheme.error)
          : ('due', colorScheme.tertiary),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(label, style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: color)),
    );
  }
}

class _InvoiceActions extends ConsumerWidget {
  const _InvoiceActions({required this.invoice});
  final Invoice invoice;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (!invoice.isDue) {
      return Text(
        invoice.isPaid ? (invoice.paymentMethod ?? 'paid') : 'closed',
        style: Theme.of(context).textTheme.bodySmall,
      );
    }
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        TextButton(
          onPressed: () => _recordPayment(context, ref, invoice),
          child: const Text('Record payment'),
        ),
        IconButton(
          icon: const Icon(Icons.block, size: 18),
          tooltip: 'Waive',
          onPressed: () => _waive(context, ref, invoice),
        ),
      ],
    );
  }
}

Future<void> _recordPayment(BuildContext context, WidgetRef ref, Invoice invoice) async {
  final result = await showDialog<_PaymentEntry>(
    context: context,
    builder: (_) => _RecordPaymentDialog(invoice: invoice),
  );
  if (result == null) return;

  try {
    await ref.read(billingApiProvider).markPaid(
          invoice.id,
          amount: result.amount,
          method: result.method,
          reference: result.reference,
          note: result.note,
        );
    if (context.mounted) {
      AppNotice.success(context, 'Payment recorded for ${invoice.academyName ?? 'academy'}.');
      ref.invalidate(billingSummaryProvider);
      ref.invalidate(billingInvoicesProvider);
    }
  } on ApiException catch (e) {
    if (context.mounted) AppNotice.error(context, e.message);
  }
}

Future<void> _waive(BuildContext context, WidgetRef ref, Invoice invoice) async {
  final ok = await AppNotice.confirm(
    context,
    title: 'Waive this invoice?',
    message: 'The charge is written off and recorded as waived - it stays in the history rather '
        'than disappearing, so the account still reconciles.',
    confirmLabel: 'Waive',
  );
  if (!ok) return;

  try {
    await ref.read(billingApiProvider).waive(invoice.id, 'Waived by operator');
    if (context.mounted) {
      AppNotice.success(context, 'Invoice waived.');
      ref.invalidate(billingSummaryProvider);
      ref.invalidate(billingInvoicesProvider);
    }
  } on ApiException catch (e) {
    if (context.mounted) AppNotice.error(context, e.message);
  }
}

class _PaymentEntry {
  const _PaymentEntry(this.amount, this.method, this.reference, this.note);
  final double amount;
  final String method;
  final String? reference;
  final String? note;
}

class _RecordPaymentDialog extends StatefulWidget {
  const _RecordPaymentDialog({required this.invoice});
  final Invoice invoice;

  @override
  State<_RecordPaymentDialog> createState() => _RecordPaymentDialogState();
}

class _RecordPaymentDialogState extends State<_RecordPaymentDialog> {
  late final TextEditingController _amount =
      TextEditingController(text: widget.invoice.amount.toStringAsFixed(2));
  final _reference = TextEditingController();
  final _note = TextEditingController();
  String _method = 'UPI';

  static const _methods = ['UPI', 'BANK_TRANSFER', 'CARD', 'CASH', 'CHEQUE'];

  @override
  void dispose() {
    _amount.dispose();
    _reference.dispose();
    _note.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text('Record payment - ${widget.invoice.academyName ?? ''}'),
      content: SizedBox(
        width: 380,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: _amount,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              decoration: const InputDecoration(labelText: 'Amount received', prefixText: '₹ '),
            ),
            const SizedBox(height: 14),
            // A picker, not free text - the method is a fixed set, and typing it invites
            // "upi"/"UPI "/"Upi" variants that make later reconciliation miserable.
            DropdownButtonFormField<String>(
              initialValue: _method,
              decoration: const InputDecoration(labelText: 'Method'),
              items: _methods
                  .map((m) => DropdownMenuItem(value: m, child: Text(m.replaceAll('_', ' '))))
                  .toList(),
              onChanged: (v) => setState(() => _method = v ?? 'UPI'),
            ),
            const SizedBox(height: 14),
            TextField(
              controller: _reference,
              decoration: const InputDecoration(labelText: 'Reference / txn id (optional)'),
            ),
            const SizedBox(height: 14),
            TextField(
              controller: _note,
              decoration: const InputDecoration(labelText: 'Note (optional)'),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Cancel')),
        FilledButton(
          onPressed: () {
            final amount = double.tryParse(_amount.text.trim());
            if (amount == null || amount <= 0) {
              AppNotice.error(context, 'Enter a valid amount.');
              return;
            }
            Navigator.of(context).pop(_PaymentEntry(
              amount,
              _method,
              _reference.text.trim().isEmpty ? null : _reference.text.trim(),
              _note.text.trim().isEmpty ? null : _note.text.trim(),
            ));
          },
          child: const Text('Record'),
        ),
      ],
    );
  }
}

/// Narrow-window fallback for the invoice table.
class _InvoiceCard extends ConsumerWidget {
  const _InvoiceCard({required this.invoice});
  final Invoice invoice;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(invoice.academyName ?? invoice.academyId,
                      style: const TextStyle(fontWeight: FontWeight.w700)),
                ),
                _InvoiceStatusChip(invoice: invoice),
              ],
            ),
            const SizedBox(height: 6),
            Text('${invoice.planCode}  ·  ${formatCurrency(invoice.amount)}',
                style: Theme.of(context).textTheme.bodySmall),
            if (invoice.isDue) ...[
              const SizedBox(height: 6),
              Align(alignment: Alignment.centerRight, child: _InvoiceActions(invoice: invoice)),
            ],
          ],
        ),
      ),
    );
  }
}
