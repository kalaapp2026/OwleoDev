import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:nest_fe/app/theme/app_tokens.dart';
import 'package:nest_fe/app/theme/app_typography.dart';
import 'package:nest_fe/core/design/calendar_modal.dart';
import 'package:nest_fe/core/design/pressable.dart';
import 'package:nest_fe/features/fees/data/student_statement.dart';
import 'package:nest_fe/features/fees/data/transaction_ledger.dart';
import 'package:nest_fe/features/fees/presentation/fee_format.dart';
import 'package:nest_fe/features/fees/presentation/fees_screen.dart' show feesApiProvider;
import 'package:nest_fe/features/fees/presentation/student_profile_screen.dart';

typedef _LedgerKey = ({DateTime from, DateTime to, FeeCategory? category, String query});

final _ledgerProvider =
    FutureProvider.autoDispose.family<TransactionLedger, _LedgerKey>((ref, key) {
  return ref.watch(feesApiProvider).transactions(
        from: key.from,
        to: key.to,
        category: key.category,
        query: key.query,
      );
});

/// Every payment the academy has taken, across both fee categories.
///
/// Reversals appear here rather than being hidden. This is the screen an admin opens to answer
/// "what did we take last month" and to check someone else's entries - and since the totals are
/// net, quietly dropping the undone rows would make them impossible to reconcile.
class AllTransactionsScreen extends ConsumerStatefulWidget {
  const AllTransactionsScreen({super.key});

  @override
  ConsumerState<AllTransactionsScreen> createState() => _AllTransactionsScreenState();
}

class _AllTransactionsScreenState extends ConsumerState<AllTransactionsScreen> {
  DateTime _month = DateTime(DateTime.now().year, DateTime.now().month);

  /// Null means the whole month. The prototype's calendar narrows to one day; stepping the month
  /// clears it, because a day number means nothing carried into a different month.
  int? _day;

  FeeCategory? _category;
  String _query = '';

  DateTime get _from => _day == null
      ? DateTime(_month.year, _month.month, 1)
      : DateTime(_month.year, _month.month, _day!);

  DateTime get _to => _day == null
      // Day 0 of next month is the last day of this one - no leap-year special case.
      ? DateTime(_month.year, _month.month + 1, 0)
      : DateTime(_month.year, _month.month, _day!);

  _LedgerKey get _key =>
      (from: _from, to: _to, category: _category, query: _query);

  void _stepMonth(int delta) {
    setState(() {
      _month = DateTime(_month.year, _month.month + delta);
      _day = null;
    });
  }

  Future<void> _pickDate() async {
    final picked = await showAppCalendar(
      context: context,
      month: _month,
      selectedDay: _day,
      latestMonth: DateTime(DateTime.now().year, DateTime.now().month),
    );
    if (picked != null) {
      setState(() {
        _month = DateTime(picked.year, picked.month);
        _day = picked.day;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final async = ref.watch(_ledgerProvider(_key));

    return Scaffold(
      backgroundColor: palette.bg,
      appBar: AppBar(
        backgroundColor: palette.bg,
        title: const Text('All Transactions'),
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(
                AppSpacing.xl, AppSpacing.sm, AppSpacing.xl, 0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  'Regular + Other fees combined',
                  style: TextStyle(fontSize: AppType.smd, color: palette.textMuted),
                ),
                const SizedBox(height: AppSpacing.md),
                async.when(
                  loading: () => const _TotalsPlaceholder(),
                  error: (_, _) => const _TotalsPlaceholder(),
                  data: (ledger) => Row(
                    children: [
                      _Total(
                        label: 'Regular Fees',
                        value: money(ledger.regularTotal),
                        color: palette.primary,
                      ),
                      const SizedBox(width: AppSpacing.sm),
                      _Total(
                        label: 'Other Fees',
                        value: money(ledger.otherTotal),
                        color: palette.gateway,
                      ),
                      const SizedBox(width: AppSpacing.sm),
                      _Total(
                        label: 'Total',
                        value: money(ledger.total),
                        color: palette.revenue,
                        outlined: true,
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: AppSpacing.md),
                TextField(
                  onChanged: (v) => setState(() => _query = v),
                  style: TextStyle(fontSize: AppType.md, color: palette.text),
                  decoration: InputDecoration(
                    isDense: true,
                    hintText: 'Search student',
                    hintStyle: TextStyle(fontSize: AppType.md, color: palette.textFaint),
                    prefixIcon:
                        Icon(Icons.search_rounded, size: 16, color: palette.textFaint),
                    prefixIconConstraints:
                        const BoxConstraints(minWidth: 34, minHeight: 34),
                    filled: true,
                    fillColor: palette.surfaceRaised,
                    contentPadding: const EdgeInsets.symmetric(
                        horizontal: AppSpacing.md, vertical: AppSpacing.md),
                    border: OutlineInputBorder(
                      borderRadius: AppRadii.all(AppRadii.lg),
                      borderSide: BorderSide(color: palette.border),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: AppRadii.all(AppRadii.lg),
                      borderSide: BorderSide(color: palette.border),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: AppRadii.all(AppRadii.lg),
                      borderSide: BorderSide(color: palette.primary),
                    ),
                  ),
                ),
                const SizedBox(height: AppSpacing.sm),
                Row(
                  children: [
                    _Chip(
                      label: 'All',
                      selected: _category == null,
                      onTap: () => setState(() => _category = null),
                    ),
                    const SizedBox(width: AppSpacing.xs),
                    for (final c in FeeCategory.values) ...[
                      _Chip(
                        label: c.label,
                        selected: _category == c,
                        onTap: () => setState(() => _category = c),
                      ),
                      const SizedBox(width: AppSpacing.xs),
                    ],
                    const Spacer(),
                    _DateControl(
                      label: _day == null
                          ? shortMonthLabel(_month)
                          : formatFeeDate(DateTime(_month.year, _month.month, _day!)),
                      onPrevious: () => _stepMonth(-1),
                      onNext: _month.isBefore(
                              DateTime(DateTime.now().year, DateTime.now().month))
                          ? () => _stepMonth(1)
                          : null,
                      onPick: _pickDate,
                    ),
                  ],
                ),
                if (_day != null)
                  Padding(
                    padding: const EdgeInsets.only(top: AppSpacing.xs),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        Text('Narrowed to a single day',
                            style: TextStyle(
                                fontSize: AppType.smd, color: palette.textFaint)),
                        const SizedBox(width: AppSpacing.xs),
                        Pressable(
                          onTap: () => setState(() => _day = null),
                          child: Icon(Icons.close_rounded,
                              size: 13, color: palette.textFaint),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: AppSpacing.sm),
          Expanded(
            child: async.when(
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
              data: (ledger) => ledger.entries.isEmpty
                  ? Center(
                      child: Text('No transactions found.',
                          style:
                              TextStyle(fontSize: AppType.lg, color: palette.textFaint)),
                    )
                  : ListView.separated(
                      padding: const EdgeInsets.fromLTRB(
                          AppSpacing.xl, 0, AppSpacing.xl, AppSpacing.x3l),
                      itemCount: ledger.entries.length,
                      separatorBuilder: (_, _) =>
                          const SizedBox(height: AppSpacing.sm),
                      itemBuilder: (context, i) => _EntryTile(
                        entry: ledger.entries[i],
                        onTap: () => Navigator.of(context).push(MaterialPageRoute(
                          builder: (_) => StudentProfileScreen(
                            membershipId: ledger.entries[i].membershipId,
                            period: periodOf(_month),
                          ),
                        )),
                      ),
                    ),
            ),
          ),
        ],
      ),
    );
  }
}

class _EntryTile extends StatelessWidget {
  const _EntryTile({required this.entry, required this.onTap});

  final LedgerEntry entry;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final regular = entry.category == FeeCategory.regular;
    // A reversal is money going back out. Colouring it like a payment would make the list read as
    // more collected than the totals say.
    final amountColor = entry.reversal ? palette.notPaid : palette.paidManual;

    return Pressable(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(AppSpacing.md),
        decoration: BoxDecoration(
          color: palette.surfaceRaised,
          borderRadius: AppRadii.all(AppRadii.xl),
          border: Border.all(color: palette.borderSoft),
        ),
        child: Row(
          children: [
            Container(
              width: 38,
              height: 38,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: entry.reversal
                    ? palette.notPaidSoft
                    : regular
                        ? palette.primarySoft
                        : palette.gatewaySoft,
                borderRadius: AppRadii.all(AppRadii.lg),
              ),
              child: Icon(
                entry.reversal ? Icons.undo_rounded : Icons.receipt_long_outlined,
                size: 16,
                color: entry.reversal
                    ? palette.notPaid
                    : regular
                        ? palette.primary
                        : palette.gateway,
              ),
            ),
            const SizedBox(width: AppSpacing.md),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    entry.studentName,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: AppType.md,
                      fontWeight: AppType.semi,
                      color: palette.text,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    '${entry.reversal ? 'Reversed · ' : ''}'
                    '${entry.category.label} · ${entry.context}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: AppType.smd, color: palette.textFaint),
                  ),
                ],
              ),
            ),
            const SizedBox(width: AppSpacing.sm),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  '${entry.reversal ? '' : '+'}${money(entry.amount)}',
                  style: TextStyle(
                    fontSize: AppType.md,
                    fontWeight: AppType.bold,
                    color: amountColor,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  '${entry.mode ?? ''}'
                  '${entry.occurredOn == null ? '' : ' · ${formatFeeDate(entry.occurredOn!)}'}',
                  style: TextStyle(fontSize: AppType.tiny, color: palette.textFaint),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _Total extends StatelessWidget {
  const _Total({
    required this.label,
    required this.value,
    required this.color,
    this.outlined = false,
  });

  final String label;
  final String value;
  final Color color;
  final bool outlined;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.md, vertical: AppSpacing.md),
        decoration: BoxDecoration(
          color: palette.surfaceRaised,
          borderRadius: AppRadii.all(AppRadii.xl),
          border: Border.all(color: outlined ? color : palette.border),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: AppType.tiny, color: palette.textMuted)),
            const SizedBox(height: AppSpacing.xxs),
            FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerLeft,
              child: Text(
                value,
                maxLines: 1,
                style: TextStyle(
                  fontSize: AppType.x3l,
                  fontWeight: AppType.heavy,
                  color: color,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _TotalsPlaceholder extends StatelessWidget {
  const _TotalsPlaceholder();

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return Container(
      height: 58,
      decoration: BoxDecoration(
        color: palette.surfaceRaised,
        borderRadius: AppRadii.all(AppRadii.xl),
      ),
    );
  }
}

class _Chip extends StatelessWidget {
  const _Chip({required this.label, required this.selected, required this.onTap});

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return Pressable(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: selected ? palette.primarySoft : palette.surfaceRaised,
          borderRadius: AppRadii.all(AppRadii.pill),
          border: Border.all(color: selected ? palette.primary : palette.border),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: AppType.base,
            fontWeight: AppType.medium,
            color: selected ? palette.primary : palette.textMuted,
          ),
        ),
      ),
    );
  }
}

class _DateControl extends StatelessWidget {
  const _DateControl({
    required this.label,
    required this.onPrevious,
    required this.onNext,
    required this.onPick,
  });

  final String label;
  final VoidCallback? onPrevious;
  final VoidCallback? onNext;
  final VoidCallback onPick;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return Container(
      decoration: BoxDecoration(
        color: palette.surfaceRaised,
        borderRadius: AppRadii.all(AppRadii.lg),
        border: Border.all(color: palette.border),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _Step(icon: Icons.chevron_left_rounded, onTap: onPrevious),
          Pressable(
            onTap: onPick,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 7),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.calendar_today_outlined, size: 12, color: palette.revenue),
                  const SizedBox(width: 4),
                  Text(label,
                      style: TextStyle(
                          fontSize: AppType.smd,
                          fontWeight: AppType.bold,
                          color: palette.text)),
                ],
              ),
            ),
          ),
          _Step(icon: Icons.chevron_right_rounded, onTap: onNext),
        ],
      ),
    );
  }
}

class _Step extends StatelessWidget {
  const _Step({required this.icon, required this.onTap});

  final IconData icon;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return Pressable(
      onTap: onTap,
      child: SizedBox(
        width: 26,
        height: 30,
        child: Icon(icon,
            size: 15, color: onTap == null ? palette.textFaint : palette.text),
      ),
    );
  }
}
