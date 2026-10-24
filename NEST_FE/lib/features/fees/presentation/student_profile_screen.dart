import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:nest_fe/app/theme/app_tokens.dart';
import 'package:nest_fe/app/theme/app_typography.dart';
import 'package:nest_fe/core/design/pressable.dart';
import 'package:nest_fe/core/design/toast.dart';
import 'package:nest_fe/features/fees/data/fee_roster.dart';
import 'package:nest_fe/features/fees/data/student_fee_profile.dart';
import 'package:nest_fe/features/fees/data/student_statement.dart';
import 'package:nest_fe/features/fees/presentation/fee_format.dart';
import 'package:nest_fe/features/fees/presentation/fees_screen.dart' show feesApiProvider;
import 'package:nest_fe/features/fees/presentation/statement_screen.dart';
import 'package:nest_fe/features/fees/presentation/widgets/fee_history.dart';
import 'package:nest_fe/features/fees/presentation/widgets/fee_profile_body.dart';
import 'package:nest_fe/features/fees/presentation/widgets/student_other_fees_tab.dart';

typedef _ProfileKey = ({String membershipId, String period});

final _profileProvider =
    FutureProvider.autoDispose.family<StudentFeeProfile, _ProfileKey>((ref, key) {
  return ref.watch(feesApiProvider).feeProfile(
        membershipId: key.membershipId,
        period: key.period,
      );
});

/// The student's regular-fee periods, for the slips beneath the current one.
final _regularStatementProvider =
    FutureProvider.autoDispose.family<StudentStatement, String>((ref, membershipId) {
  return ref.watch(feesApiProvider).statement(
        membershipId: membershipId,
        category: FeeCategory.regular,
      );
});

/// A student's fee detail for one period: what they owe across their courses, and the recorder
/// for taking a payment against one or several of them. Its other half - the one-off and shared
/// Other fees - sits behind the same screen, one toggle away.
class StudentProfileScreen extends ConsumerStatefulWidget {
  const StudentProfileScreen({
    super.key,
    required this.membershipId,
    required this.period,
    this.initialShowOther = false,
  });

  final String membershipId;
  final String period;

  /// Opens on the Other side. Set when the student was reached from an Other fee, so the screen
  /// lands on the fee that was tapped rather than the regular one.
  final bool initialShowOther;

  @override
  ConsumerState<StudentProfileScreen> createState() => _StudentProfileScreenState();
}

class _StudentProfileScreenState extends ConsumerState<StudentProfileScreen> {
  /// Which half of the profile is showing. Regular and Other are the same student seen two ways,
  /// not two screens, so this switches the body rather than pushing a second page.
  late bool _showOther = widget.initialShowOther;

  _ProfileKey get _key => (membershipId: widget.membershipId, period: widget.period);

  void _refresh() {
    ref.invalidate(_profileProvider(_key));
    ref.invalidate(_regularStatementProvider(widget.membershipId));
    ref.invalidate(recentTransactionsProvider);
  }

  Future<void> _pay(List<FeeLine> targets, String mode, String? reference, num? partial) async {
    final api = ref.read(feesApiProvider);
    if (partial != null) {
      // A partial only ever applies to one course. Splitting an arbitrary amount across several
      // needs a rule nobody has decided, and guessing one would put money against the wrong
      // course silently.
      await api.recordEntry(
        membershipId: widget.membershipId,
        courseId: targets.first.id,
        period: widget.period,
        amountPaid: partial,
        mode: mode,
        gatewayRef: reference,
      );
    } else {
      for (final target in targets) {
        await api.recordEntry(
          membershipId: widget.membershipId,
          courseId: target.id,
          period: widget.period,
          amountPaid: target.outstanding,
          mode: mode,
          gatewayRef: reference,
        );
      }
    }
    _refresh();
    if (mounted) {
      showAppToast(
          context,
          partial != null
              ? 'Partial payment recorded'
              : targets.length == 1
                  ? 'Payment recorded'
                  : '${targets.length} courses marked as paid');
    }
  }

  Future<void> _edit(FeeLine line, num amount) async {
    await ref.read(feesApiProvider).updateAgreedFee(
          membershipId: widget.membershipId,
          courseId: line.id,
          agreedFee: amount,
        );
    _refresh();
    if (mounted) showAppToast(context, 'Agreed fee updated to ${money(amount)}');
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final async = ref.watch(_profileProvider(_key));

    return Scaffold(
      backgroundColor: palette.bg,
      appBar: AppBar(
        backgroundColor: palette.bg,
        title: Text(async.valueOrNull?.studentName ?? 'Student'),
      ),
      body: async.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(
          child: Padding(
            padding: const EdgeInsets.all(AppSpacing.x4l),
            child: Text(
              e.toString().replaceFirst('Exception: ', ''),
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: AppType.md, color: palette.textMuted),
            ),
          ),
        ),
        data: (profile) => _body(profile, palette),
      ),
    );
  }

  Widget _body(StudentFeeProfile profile, AppPalette palette) {
    String titleOf(CourseFeeRow c) =>
        c.batchName == null ? c.courseName : '${c.courseName} · ${c.batchName}';

    final lines = [
      for (final c in profile.courses)
        FeeLine(
          id: c.courseId,
          title: titleOf(c),
          context: titleOf(c),
          agreedFee: c.agreedFee,
          paid: c.totalPaid,
          balance: c.balance,
          status: c.status,
          paidOn: c.lastPaidOn,
        ),
    ];
    final overdue = profile.courses.any((c) => c.status == PaymentStatus.due);

    return ListView(
      padding: const EdgeInsets.fromLTRB(AppSpacing.xl, AppSpacing.md, AppSpacing.xl, AppSpacing.x5l),
      children: [
        Text(
          'Student fee profile · ${_periodLabel(profile.period)}',
          style: TextStyle(fontSize: AppType.smd, color: palette.textMuted),
        ),
        const SizedBox(height: AppSpacing.md),
        _CategoryToggle(
          showOther: _showOther,
          onChanged: (other) => setState(() => _showOther = other),
        ),
        const SizedBox(height: AppSpacing.lg),
        if (_showOther)
          StudentOtherFeesTab(
            membershipId: widget.membershipId,
            studentName: profile.studentName,
          )
        else ...[
          FeeProfileBody(
            lines: lines,
            noun: 'courses',
            selectPrompt: "Select which course you're collecting payment for:",
            selectHint: 'Select a course above to record a payment',
            settledText: 'Fully paid for this period',
            overdueText: overdue
                ? 'Overdue - the billing period for at least one course has closed'
                : null,
            onPay: _pay,
            onEdit: _edit,
          ),
          const SizedBox(height: AppSpacing.xxl),
          FeeHistoryHeader(onStatement: _openStatement),
          const SizedBox(height: AppSpacing.sm),
          for (final c in profile.courses)
            Padding(
              padding: const EdgeInsets.only(bottom: AppSpacing.xs),
              child: FeeSlipTile(
                label: titleOf(c),
                fee: c.agreedFee,
                paid: c.totalPaid,
                status: c.status,
                paidOn: c.lastPaidOn,
              ),
            ),
          _PastPeriods(membershipId: widget.membershipId, currentPeriod: profile.period),
          RecentTransactions(
            keyOf: (
              membershipId: widget.membershipId,
              studentName: profile.studentName,
              category: FeeCategory.regular,
            ),
          ),
        ],
      ],
    );
  }

  void _openStatement() => Navigator.of(context).push(MaterialPageRoute(
        builder: (_) => StatementScreen(membershipId: widget.membershipId),
      ));

  String _periodLabel(String period) => _periodName(period);
}

String _periodName(String period) {
  final parts = period.split('-');
  final month = int.tryParse(parts.length == 2 ? parts[1] : '');
  if (month == null || month < 1 || month > 12) return period;
  const names = [
    'January', 'February', 'March', 'April', 'May', 'June',
    'July', 'August', 'September', 'October', 'November', 'December'
  ];
  return '${names[month - 1]} ${parts[0]}';
}

/// The two billing periods before this one, as slips - what the student paid, or still owes, in the
/// months just gone.
class _PastPeriods extends ConsumerWidget {
  const _PastPeriods({required this.membershipId, required this.currentPeriod});

  final String membershipId;
  final String currentPeriod;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final statement = ref.watch(_regularStatementProvider(membershipId)).valueOrNull;
    if (statement == null) return const SizedBox.shrink();

    // Period labels sort chronologically as text ("2026-08" < "2026-09"), so "before this one" is a
    // string comparison, and the newest of those come first.
    final past = statement.rows.where((r) => r.label.compareTo(currentPeriod) < 0).toList()
      ..sort((a, b) => b.label.compareTo(a.label));
    final periods = <String>[];
    for (final r in past) {
      if (!periods.contains(r.label)) periods.add(r.label);
      if (periods.length == 2) break;
    }
    if (periods.isEmpty) return const SizedBox.shrink();

    return Column(
      children: [
        for (final p in periods)
          for (final r in past.where((r) => r.label == p))
            Padding(
              padding: const EdgeInsets.only(bottom: AppSpacing.xs),
              child: FeeSlipTile(
                label: r.context.isEmpty ? _periodName(p) : '${_periodName(p)} · ${r.context}',
                fee: r.fee,
                paid: r.paid,
                status: r.status,
                paidOn: r.paidOn,
              ),
            ),
      ],
    );
  }
}

/// Regular / Other. Both halves are the same student, so this switches the body in place.
class _CategoryToggle extends StatelessWidget {
  const _CategoryToggle({required this.showOther, required this.onChanged});

  final bool showOther;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: palette.surfaceRaised,
        borderRadius: AppRadii.all(AppRadii.lg),
        border: Border.all(color: palette.border),
      ),
      child: Row(
        children: [
          Expanded(
              child: _ToggleHalf(
                  label: 'Regular Fees', selected: !showOther, onTap: () => onChanged(false))),
          Expanded(
              child: _ToggleHalf(
                  label: 'Other Fees', selected: showOther, onTap: () => onChanged(true))),
        ],
      ),
    );
  }
}

class _ToggleHalf extends StatelessWidget {
  const _ToggleHalf({required this.label, required this.selected, required this.onTap});

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return Pressable(
      onTap: selected ? null : onTap,
      child: AnimatedContainer(
        duration: AppMotion.fade,
        padding: const EdgeInsets.symmetric(vertical: 9),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: selected ? palette.primary : Colors.transparent,
          borderRadius: AppRadii.all(AppRadii.md),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: AppType.md,
            fontWeight: AppType.bold,
            color: selected ? palette.onPrimary : palette.textMuted,
          ),
        ),
      ),
    );
  }
}
