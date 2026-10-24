import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:nest_fe/app/theme/app_tokens.dart';
import 'package:nest_fe/app/theme/app_typography.dart';
import 'package:nest_fe/core/design/toast.dart';
import 'package:nest_fe/features/fees/data/fee_roster.dart';
import 'package:nest_fe/features/fees/data/student_other_fees.dart';
import 'package:nest_fe/features/fees/data/student_statement.dart';
import 'package:nest_fe/features/fees/presentation/add_student_fee_screen.dart';
import 'package:nest_fe/features/fees/presentation/fee_format.dart';
import 'package:nest_fe/features/fees/data/fees_api.dart' show feesApiProvider;
import 'package:nest_fe/features/fees/presentation/statement_screen.dart';
import 'package:nest_fe/features/fees/presentation/widgets/fee_history.dart';
import 'package:nest_fe/features/fees/presentation/widgets/fee_profile_body.dart';

final studentOtherFeesProvider =
    FutureProvider.autoDispose.family<StudentOtherFees, String>((ref, membershipId) {
  return ref.watch(feesApiProvider).studentOtherFees(membershipId);
});

/// The Other side of a student's fee profile: their costume, exam and one-off charges.
///
/// The same screen as the Regular side - stats, an expandable breakdown to pick fees from, the
/// Cash/UPI recorder with full and partial payment - because collecting is the same job. It shows
/// even when the student has nothing: that is the case a newly joined student is in, and blocking
/// the tab would leave nowhere to add their first one-off fee from.
class StudentOtherFeesTab extends ConsumerWidget {
  const StudentOtherFeesTab({
    super.key,
    required this.membershipId,
    required this.studentName,
  });

  final String membershipId;
  final String studentName;

  void _refresh(WidgetRef ref) {
    ref.invalidate(studentOtherFeesProvider(membershipId));
    ref.invalidate(recentTransactionsProvider);
  }

  Future<void> _addFee(BuildContext context, WidgetRef ref) async {
    final created = await Navigator.of(context).push<bool>(MaterialPageRoute(
      builder: (_) => AddStudentFeeScreen(membershipId: membershipId, studentName: studentName),
    ));
    if (created == true) {
      _refresh(ref);
      if (context.mounted) showAppToast(context, 'Fee added for $studentName');
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final palette = context.palette;
    final async = ref.watch(studentOtherFeesProvider(membershipId));

    return async.when(
      loading: () => const Padding(
        padding: EdgeInsets.all(AppSpacing.x5l),
        child: Center(child: CircularProgressIndicator()),
      ),
      error: (e, _) => Padding(
        padding: const EdgeInsets.all(AppSpacing.x4l),
        child: Text(
          e.toString().replaceFirst('Exception: ', ''),
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: AppType.md, color: palette.textMuted),
        ),
      ),
      data: (other) {
        final rows = {for (final r in other.fees) (r.studentFeeId ?? r.feeTypeId)!: r};
        final lines = [
          for (final r in other.fees)
            FeeLine(
              id: (r.studentFeeId ?? r.feeTypeId)!,
              title: r.name,
              agreedFee: r.amount,
              paid: r.paid,
              balance: r.balance,
              status: r.status,
              paidOn: r.lastPaidOn,
              tag: r.custom ? 'INDIVIDUAL' : null,
            ),
        ];
        final overdue = other.fees.where((r) => r.status == PaymentStatus.due).firstOrNull;

        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            FeeProfileBody(
              lines: lines,
              noun: 'fee types',
              selectPrompt: "Select which fee you're collecting payment for:",
              selectHint: 'Select a fee above to record a payment',
              settledText: 'Fully paid',
              overdueText: overdue == null
                  ? null
                  : overdue.dueDate == null
                      ? 'Overdue'
                      : 'Overdue - payment was due ${formatFeeDate(overdue.dueDate!)}',
              addFeeLabel: other.fees.isEmpty ? 'Add fee for $studentName' : 'Add fee',
              onAddFee: () => _addFee(context, ref),
              onPay: (targets, mode, reference, partial) async {
                final api = ref.read(feesApiProvider);
                for (final t in targets) {
                  final row = rows[t.id]!;
                  await api.recordOtherPayment(
                    membershipId: membershipId,
                    feeTypeId: row.feeTypeId,
                    studentFeeId: row.studentFeeId,
                    amountPaid: partial ?? row.outstanding,
                    mode: mode,
                    gatewayRef: reference,
                  );
                }
                _refresh(ref);
                if (context.mounted) {
                  showAppToast(
                      context,
                      partial != null
                          ? 'Partial payment recorded'
                          : targets.length == 1
                              ? '${targets.first.title} marked as paid'
                              : '${targets.length} fees marked as paid');
                }
              },
              onEdit: (line, amount) async {
                final row = rows[line.id]!;
                await ref.read(feesApiProvider).updateOtherAmount(
                      membershipId: membershipId,
                      feeTypeId: row.feeTypeId,
                      studentFeeId: row.studentFeeId,
                      amount: amount,
                    );
                _refresh(ref);
                if (context.mounted) showAppToast(context, 'Fee updated to ${money(amount)}');
              },
            ),
            if (other.fees.isNotEmpty) ...[
              const SizedBox(height: AppSpacing.xxl),
              FeeHistoryHeader(
                onStatement: () => Navigator.of(context).push(MaterialPageRoute(
                  builder: (_) => StatementScreen(membershipId: membershipId),
                )),
              ),
              const SizedBox(height: AppSpacing.sm),
              for (final r in other.fees)
                Padding(
                  padding: const EdgeInsets.only(bottom: AppSpacing.xs),
                  child: FeeSlipTile(
                    label: r.name,
                    fee: r.amount,
                    paid: r.paid,
                    status: r.status,
                    paidOn: r.lastPaidOn,
                  ),
                ),
              RecentTransactions(
                keyOf: (
                  membershipId: membershipId,
                  studentName: studentName,
                  category: FeeCategory.other,
                ),
              ),
            ],
          ],
        );
      },
    );
  }
}
