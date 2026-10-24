import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:nest_fe/app/theme/app_tokens.dart';
import 'package:nest_fe/app/theme/app_typography.dart';
import 'package:nest_fe/core/design/pressable.dart';
import 'package:nest_fe/core/design/status_badge.dart';
import 'package:nest_fe/features/fees/data/fee_roster.dart';
import 'package:nest_fe/features/fees/data/student_statement.dart';
import 'package:nest_fe/features/fees/data/transaction_ledger.dart';
import 'package:nest_fe/features/fees/presentation/fee_format.dart';
import 'package:nest_fe/features/fees/data/fees_api.dart' show feesApiProvider;

/// "Fee slips & history" with the link through to the full statement.
class FeeHistoryHeader extends StatelessWidget {
  const FeeHistoryHeader({super.key, required this.onStatement});

  final VoidCallback onStatement;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text('Fee slips & history',
            style: TextStyle(
                fontSize: AppType.md, fontWeight: AppType.bold, color: palette.text)),
        Pressable(
          onTap: onStatement,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.download_outlined, size: 13, color: palette.primary),
              const SizedBox(width: AppSpacing.xxs),
              Text('Statement',
                  style: TextStyle(
                      fontSize: AppType.smd, fontWeight: AppType.bold, color: palette.primary)),
            ],
          ),
        ),
      ],
    );
  }
}

/// One line of the slips list: what it was for, paid of billed, and where it stands.
class FeeSlipTile extends StatelessWidget {
  const FeeSlipTile({
    super.key,
    required this.label,
    required this.fee,
    required this.paid,
    required this.status,
    this.paidOn,
  });

  final String label;
  final num fee;
  final num paid;
  final PaymentStatus status;
  final DateTime? paidOn;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md, vertical: 11),
      decoration: BoxDecoration(
        color: palette.surfaceRaised,
        borderRadius: AppRadii.all(AppRadii.lg),
        border: Border.all(color: palette.borderSoft),
      ),
      child: Row(
        children: [
          Icon(Icons.receipt_long_outlined, size: 15, color: palette.textFaint),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                        fontSize: AppType.smd, fontWeight: AppType.semi, color: palette.text)),
                const SizedBox(height: 2),
                Text(
                  '${money(paid)} of ${money(fee)}'
                  '${paidOn == null ? '' : ' (${formatFeeDate(paidOn!)})'}',
                  style: TextStyle(fontSize: AppType.xs, color: palette.textFaint),
                ),
              ],
            ),
          ),
          const SizedBox(width: AppSpacing.xs),
          StatusBadge(
            label: statusLabel(status),
            color: status.color(palette),
            softColor: status.softColor(palette),
            dense: true,
          ),
        ],
      ),
    );
  }
}

typedef RecentKey = ({String membershipId, String studentName, FeeCategory category});

/// A student's payments over the last year, newest first. The ledger endpoint is academy-wide, so
/// it is narrowed by the student's name server-side and then to the exact person here - two
/// students can share a surname, never an id.
final recentTransactionsProvider =
    FutureProvider.autoDispose.family<List<LedgerEntry>, RecentKey>((ref, key) async {
  final now = DateTime.now();
  final ledger = await ref.watch(feesApiProvider).transactions(
        from: DateTime(now.year - 1, now.month, now.day),
        to: now,
        category: key.category,
        query: key.studentName,
      );
  return ledger.entries.where((e) => e.membershipId == key.membershipId).toList();
});

/// "Recent transactions": each payment - and each reversal - with how and when it arrived.
class RecentTransactions extends ConsumerWidget {
  const RecentTransactions({super.key, required this.keyOf});

  final RecentKey keyOf;

  static String _mode(String? mode) => switch ((mode ?? '').toUpperCase()) {
        'CASH' => 'Cash',
        'UPI' => 'UPI',
        'GATEWAY' => 'Gateway',
        _ => '',
      };

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final palette = context.palette;
    final entries = ref.watch(recentTransactionsProvider(keyOf)).valueOrNull ?? const <LedgerEntry>[];
    if (entries.isEmpty) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SizedBox(height: AppSpacing.xl),
        Text('Recent transactions',
            style: TextStyle(
                fontSize: AppType.md, fontWeight: AppType.bold, color: palette.text)),
        const SizedBox(height: AppSpacing.xs),
        for (final e in entries.take(8))
          Container(
            padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 2),
            decoration: BoxDecoration(
              border: Border(bottom: BorderSide(color: palette.borderSoft)),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        e.reversal ? 'Reverted · ${e.context}' : e.context,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                            fontSize: AppType.md,
                            fontWeight: AppType.semi,
                            color: palette.text),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        [
                          if (e.occurredOn != null) formatFeeDate(e.occurredOn!),
                          if (_mode(e.mode).isNotEmpty) _mode(e.mode),
                        ].join(' · '),
                        style: TextStyle(fontSize: AppType.xs, color: palette.textFaint),
                      ),
                    ],
                  ),
                ),
                Text(
                  e.amount < 0 ? '-${money(e.amount.abs())}' : '+${money(e.amount)}',
                  style: TextStyle(
                    fontSize: AppType.lg,
                    fontWeight: AppType.bold,
                    color: e.amount < 0 ? palette.notPaid : palette.paidManual,
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }
}
