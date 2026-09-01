import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:nest_fe/app/theme/app_tokens.dart';
import 'package:nest_fe/app/theme/app_typography.dart';
import 'package:nest_fe/core/design/buttons.dart';
import 'package:nest_fe/core/design/confirm_dialog.dart';
import 'package:nest_fe/core/design/pressable.dart';
import 'package:nest_fe/core/design/status_badge.dart';
import 'package:nest_fe/core/design/toast.dart';
import 'package:nest_fe/features/fees/data/student_other_fees.dart';
import 'package:nest_fe/features/fees/presentation/add_student_fee_screen.dart';
import 'package:nest_fe/features/fees/presentation/fee_format.dart';
import 'package:nest_fe/features/fees/presentation/fees_screen.dart' show feesApiProvider;

final studentOtherFeesProvider =
    FutureProvider.autoDispose.family<StudentOtherFees, String>((ref, membershipId) {
  return ref.watch(feesApiProvider).studentOtherFees(membershipId);
});

/// The Other side of a student's fee profile: their costume, exam and one-off charges.
///
/// Shows even when the student has nothing - that is the case a newly joined student is in, and
/// blocking the tab would leave nowhere to add their first one-off fee from.
class StudentOtherFeesTab extends ConsumerStatefulWidget {
  const StudentOtherFeesTab({
    super.key,
    required this.membershipId,
    required this.studentName,
  });

  final String membershipId;
  final String studentName;

  @override
  ConsumerState<StudentOtherFeesTab> createState() => _StudentOtherFeesTabState();
}

class _StudentOtherFeesTabState extends ConsumerState<StudentOtherFeesTab> {
  bool _busy = false;

  void _refresh() => ref.invalidate(studentOtherFeesProvider(widget.membershipId));

  void _showError(Object error) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(error.toString().replaceFirst('Exception: ', ''))),
    );
  }

  Future<void> _markPaid(OtherFeeRow row) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await ref.read(feesApiProvider).recordOtherPayment(
            membershipId: widget.membershipId,
            feeTypeId: row.feeTypeId,
            studentFeeId: row.studentFeeId,
            amountPaid: row.outstanding,
            mode: 'CASH',
          );
      _refresh();
      if (mounted) showAppToast(context, '${row.name} marked as paid');
    } catch (e) {
      _showError(e);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _undo(OtherFeeRow row) async {
    final confirmed = await showAppConfirmDialog(
      context: context,
      title: 'Change status to unpaid?',
      message: '${row.name} will be reversed. The original entry stays on the statement with a '
          'matching reversal beside it.',
      confirmLabel: 'Yes, undo',
    );
    if (!confirmed || _busy) return;

    setState(() => _busy = true);
    try {
      await ref.read(feesApiProvider).reverseEntry(transactionId: row.lastPaymentId!);
      _refresh();
      if (mounted) showAppToast(context, '${row.name} reverted to unpaid');
    } catch (e) {
      _showError(e);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _addFee() async {
    final created = await Navigator.of(context).push<bool>(MaterialPageRoute(
      builder: (_) => AddStudentFeeScreen(
        membershipId: widget.membershipId,
        studentName: widget.studentName,
      ),
    ));
    if (created == true) {
      _refresh();
      if (mounted) showAppToast(context, 'Fee added for ${widget.studentName}');
    }
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final async = ref.watch(studentOtherFeesProvider(widget.membershipId));

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
      data: (other) => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (other.fees.isEmpty)
            _EmptyState(studentName: widget.studentName, onAdd: _addFee)
          else ...[
            Row(
              children: [
                StatBox(label: 'Total fees', value: money(other.totalAmount)),
                const SizedBox(width: AppSpacing.sm),
                StatBox(
                  label: 'Paid',
                  value: money(other.totalPaid),
                  accent: palette.paidManual,
                ),
                const SizedBox(width: AppSpacing.sm),
                StatBox(
                  label: 'Balance',
                  value: money(other.outstanding),
                  accent: other.outstanding > 0 ? palette.notPaid : palette.textFaint,
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.lg),
            for (final row in other.fees)
              Padding(
                padding: const EdgeInsets.only(bottom: AppSpacing.sm),
                child: _FeeRowTile(
                  row: row,
                  busy: _busy,
                  onMarkPaid: () => _markPaid(row),
                  onUndo: () => _undo(row),
                ),
              ),
            const SizedBox(height: AppSpacing.sm),
            AppPrimaryButton(
              label: 'Add a fee for ${widget.studentName}',
              icon: Icons.add,
              onPressed: _busy ? null : _addFee,
            ),
          ],
        ],
      ),
    );
  }
}

class _FeeRowTile extends StatelessWidget {
  const _FeeRowTile({
    required this.row,
    required this.busy,
    required this.onMarkPaid,
    required this.onUndo,
  });

  final OtherFeeRow row;
  final bool busy;
  final VoidCallback onMarkPaid;
  final VoidCallback onUndo;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;

    return Container(
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: palette.surfaceRaised,
        borderRadius: AppRadii.all(AppRadii.xl),
        border: Border.all(color: palette.borderSoft),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  children: [
                    Flexible(
                      child: Text(
                        row.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: AppType.md,
                          fontWeight: AppType.semi,
                          color: palette.text,
                        ),
                      ),
                    ),
                    if (row.custom) ...[
                      const SizedBox(width: AppSpacing.xs),
                      // Labelled, because a charge that applies to this student alone behaves
                      // differently from one the whole batch owes.
                      StatusBadge(
                        label: 'INDIVIDUAL',
                        color: palette.gold,
                        softColor: palette.goldSoft,
                        dense: true,
                      ),
                    ],
                  ],
                ),
                const SizedBox(height: 2),
                Text(
                  row.isSettled
                      ? '${money(row.amount)}'
                          '${row.lastPaidOn == null ? '' : ' · paid (${formatFeeDate(row.lastPaidOn!)})'}'
                      : '${money(row.outstanding)} of ${money(row.amount)}'
                          '${row.dueDate == null ? '' : ' · due ${formatFeeDate(row.dueDate!)}'}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: AppType.smd, color: palette.textMuted),
                ),
              ],
            ),
          ),
          const SizedBox(width: AppSpacing.sm),
          if (!row.isSettled)
            _Action(
              label: 'Mark Paid',
              color: palette.primary,
              soft: palette.primarySoft,
              onTap: busy ? null : onMarkPaid,
            )
          else if (row.canUndo)
            _Action(
              label: 'Undo',
              color: palette.notPaid,
              soft: palette.notPaidSoft,
              onTap: busy ? null : onUndo,
            )
          else
            StatusBadge(
              label: statusLabel(row.status),
              color: row.status.color(palette),
              softColor: row.status.softColor(palette),
              dense: true,
            ),
        ],
      ),
    );
  }
}

class _Action extends StatelessWidget {
  const _Action({
    required this.label,
    required this.color,
    required this.soft,
    required this.onTap,
  });

  final String label;
  final Color color;
  final Color soft;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Pressable(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md, vertical: 7),
        decoration: BoxDecoration(
          color: soft,
          borderRadius: AppRadii.all(AppRadii.md),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: AppType.smd,
            fontWeight: AppType.bold,
            color: color,
          ),
        ),
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({required this.studentName, required this.onAdd});

  final String studentName;
  final VoidCallback onAdd;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return Container(
      padding: const EdgeInsets.all(AppSpacing.x4l),
      decoration: BoxDecoration(
        color: palette.surfaceRaised,
        borderRadius: AppRadii.all(AppRadii.x3l),
        border: Border.all(color: palette.border),
      ),
      child: Column(
        children: [
          Icon(Icons.receipt_long_outlined, size: 28, color: palette.textFaint),
          const SizedBox(height: AppSpacing.md),
          Text(
            'No Other Fees yet for $studentName',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: AppType.lg,
              fontWeight: AppType.bold,
              color: palette.text,
            ),
          ),
          const SizedBox(height: AppSpacing.xs),
          Text(
            "This student isn't linked to any Other Fees record - maybe they just joined. Add one "
            'below, like a uniform or book fee, just for them.',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: AppType.smd, color: palette.textMuted, height: 1.5),
          ),
          const SizedBox(height: AppSpacing.lg),
          AppPrimaryButton(
            label: 'Add fee for $studentName',
            icon: Icons.add,
            onPressed: onAdd,
          ),
        ],
      ),
    );
  }
}
