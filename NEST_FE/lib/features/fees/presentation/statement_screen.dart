import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:share_plus/share_plus.dart';
import 'package:nest_fe/app/theme/app_tokens.dart';
import 'package:nest_fe/app/theme/app_typography.dart';
import 'package:nest_fe/core/design/buttons.dart';
import 'package:nest_fe/core/design/pressable.dart';
import 'package:nest_fe/core/design/status_badge.dart';
import 'package:nest_fe/core/design/toast.dart';
import 'package:nest_fe/features/fees/data/student_statement.dart';
import 'package:nest_fe/features/fees/presentation/fee_format.dart';
import 'package:nest_fe/features/fees/presentation/fees_screen.dart' show feesApiProvider;

typedef _StatementKey = ({String membershipId, FeeCategory? category});

final _statementProvider =
    FutureProvider.autoDispose.family<StudentStatement, _StatementKey>((ref, key) {
  return ref.watch(feesApiProvider).statement(
        membershipId: key.membershipId,
        category: key.category,
      );
});

/// One student's fee history, grouped by the day each was paid.
///
/// Rows are periods, not transactions: a month settled in three instalments is one line here. The
/// instalments are how the money arrived, which the ledger keeps; this is what was owed.
class StatementScreen extends ConsumerStatefulWidget {
  const StatementScreen({super.key, required this.membershipId});

  final String membershipId;

  @override
  ConsumerState<StatementScreen> createState() => _StatementScreenState();
}

class _StatementScreenState extends ConsumerState<StatementScreen> {
  FeeCategory? _category;
  bool _downloading = false;

  _StatementKey get _key => (membershipId: widget.membershipId, category: _category);

  Future<void> _download() async {
    if (_downloading) return;
    setState(() => _downloading = true);
    try {
      // Filtered exactly as the screen is. A download that silently widens to everything is worse
      // than none - it gets sent to a parent with periods they should not see.
      final bytes = await ref.read(feesApiProvider).downloadStatement(
            membershipId: widget.membershipId,
            category: _category,
          );
      final name = ref.read(_statementProvider(_key)).valueOrNull?.studentName ?? 'student';
      final safeName = name.replaceAll(RegExp(r'[^A-Za-z0-9]+'), '_');
      // Shared rather than written silently: on web this opens the browser's own save flow, and
      // on mobile it lets the admin send the statement straight to the parent - which is what the
      // document exists for.
      await Share.shareXFiles(
        [
          XFile.fromData(
            Uint8List.fromList(bytes),
            name: '${safeName}_fee_statement.csv',
            mimeType: 'text/csv',
          ),
        ],
        text: 'Fee statement for $name',
      );
      if (mounted) showAppToast(context, 'Statement ready to save or share');
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(e.toString().replaceFirst('Exception: ', ''))),
        );
      }
    } finally {
      if (mounted) setState(() => _downloading = false);
    }
  }

  /// Groups rows by the day they were paid, newest first, with anything unpaid in a trailing
  /// section - it has no date to place it and is what the reader is being asked to act on.
  List<({String label, List<StatementRow> rows})> _grouped(List<StatementRow> rows) {
    final byDay = <String, List<StatementRow>>{};
    for (final row in rows) {
      final key = row.paidOn == null
          ? '~unpaid'
          : '${row.paidOn!.year}-${row.paidOn!.month}-${row.paidOn!.day}';
      byDay.putIfAbsent(key, () => []).add(row);
    }
    final keys = byDay.keys.toList()
      ..sort((a, b) {
        if (a == '~unpaid') return 1;
        if (b == '~unpaid') return -1;
        return b.compareTo(a);
      });
    return [
      for (final key in keys)
        (label: formatDateSectionLabel(byDay[key]!.first.paidOn), rows: byDay[key]!)
    ];
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final async = ref.watch(_statementProvider(_key));

    return Scaffold(
      backgroundColor: palette.bg,
      appBar: AppBar(
        backgroundColor: palette.bg,
        title: const Text('Fee Statement'),
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
        data: (statement) => Column(
          children: [
            Expanded(child: _body(statement, palette)),
            Container(
              padding: const EdgeInsets.all(AppSpacing.lg),
              decoration: BoxDecoration(
                color: palette.bg,
                border: Border(top: BorderSide(color: palette.borderSoft)),
              ),
              child: SafeArea(
                top: false,
                child: AppPrimaryButton(
                  label: 'Download full statement',
                  icon: Icons.download_outlined,
                  busy: _downloading,
                  onPressed: statement.rows.isEmpty ? null : _download,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _body(StudentStatement statement, AppPalette palette) {
    final groups = _grouped(statement.rows);

    return ListView(
      padding: const EdgeInsets.fromLTRB(AppSpacing.xl, AppSpacing.md, AppSpacing.xl, AppSpacing.xl),
      children: [
        Text(
          '${statement.studentName} · Regular + Other combined',
          style: TextStyle(fontSize: AppType.smd, color: palette.textMuted),
        ),
        const SizedBox(height: AppSpacing.md),
        Container(
          padding: const EdgeInsets.all(AppSpacing.lg),
          decoration: BoxDecoration(
            color: palette.surfaceRaised,
            borderRadius: AppRadii.all(AppRadii.x3l),
            border: Border.all(color: palette.border),
          ),
          child: Column(
            children: [
              _SummaryLine(label: 'Total billed', value: money(statement.totalBilled)),
              const SizedBox(height: AppSpacing.sm),
              _SummaryLine(
                label: 'Total paid',
                value: money(statement.totalPaid),
                valueColor: palette.paidManual,
              ),
              const SizedBox(height: AppSpacing.sm),
              _SummaryLine(
                label: 'Outstanding balance',
                value: money(statement.outstanding),
                valueColor:
                    statement.outstanding > 0 ? palette.notPaid : palette.textFaint,
              ),
            ],
          ),
        ),
        const SizedBox(height: AppSpacing.md),
        Row(
          children: [
            _CategoryChip(
              label: 'All',
              selected: _category == null,
              onTap: () => setState(() => _category = null),
            ),
            const SizedBox(width: AppSpacing.xs),
            for (final c in FeeCategory.values) ...[
              _CategoryChip(
                label: c.label,
                selected: _category == c,
                onTap: () => setState(() => _category = c),
              ),
              const SizedBox(width: AppSpacing.xs),
            ],
          ],
        ),
        const SizedBox(height: AppSpacing.lg),
        Text('Transaction ledger', style: AppType.sectionLabel(palette.textMuted)),
        if (statement.rows.isEmpty)
          Padding(
            padding: const EdgeInsets.only(top: AppSpacing.x4l),
            child: Center(
              child: Text(
                _category == null
                    ? 'Nothing has been billed for this student yet.'
                    : 'No ${_category!.label.toLowerCase()} fees for this student.',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: AppType.lg, color: palette.textFaint),
              ),
            ),
          )
        else
          for (final group in groups) ...[
            Padding(
              padding: const EdgeInsets.fromLTRB(2, AppSpacing.md, 2, AppSpacing.xs),
              child: Text(
                group.label,
                style: TextStyle(
                  fontSize: AppType.smd,
                  fontWeight: AppType.bold,
                  // The unpaid section is muted rather than gold - it is not a day, and colouring
                  // it like one would imply money arrived then.
                  color: group.rows.first.paidOn == null ? palette.textFaint : palette.revenue,
                ),
              ),
            ),
            for (final row in group.rows) _StatementRowTile(row: row),
          ],
      ],
    );
  }
}

class _StatementRowTile extends StatelessWidget {
  const _StatementRowTile({required this.row});

  final StatementRow row;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final regular = row.category == FeeCategory.regular;

    return Container(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.md, horizontal: 2),
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
                Row(
                  children: [
                    Flexible(
                      child: Text(
                        _periodLabel(row.label),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: AppType.md,
                          fontWeight: AppType.semi,
                          color: palette.text,
                        ),
                      ),
                    ),
                    const SizedBox(width: AppSpacing.xs),
                    StatusBadge(
                      label: row.category.label.toUpperCase(),
                      color: regular ? palette.primary : palette.gateway,
                      softColor: regular ? palette.primarySoft : palette.gatewaySoft,
                      dense: true,
                    ),
                  ],
                ),
                const SizedBox(height: 3),
                Text(
                  '${row.context.isEmpty ? '' : '${row.context} · '}Fee ${money(row.fee)}',
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
                money(row.paid),
                style: TextStyle(
                  fontSize: AppType.md,
                  fontWeight: AppType.bold,
                  color: row.paid > 0 ? palette.paidManual : palette.textFaint,
                ),
              ),
              const SizedBox(height: 4),
              StatusBadge(
                label: statusLabel(row.status),
                color: row.status.color(palette),
                softColor: row.status.softColor(palette),
                dense: true,
              ),
            ],
          ),
        ],
      ),
    );
  }

  /// "2026-08" reads as a key, not a month. Anything that isn't a period key is a fee name and is
  /// shown as it is.
  String _periodLabel(String label) {
    final parts = label.split('-');
    if (parts.length != 2) return label;
    final year = int.tryParse(parts[0]);
    final month = int.tryParse(parts[1]);
    if (year == null || month == null || month < 1 || month > 12) return label;
    const names = [
      'January', 'February', 'March', 'April', 'May', 'June',
      'July', 'August', 'September', 'October', 'November', 'December'
    ];
    return '${names[month - 1]} $year';
  }
}

class _SummaryLine extends StatelessWidget {
  const _SummaryLine({required this.label, required this.value, this.valueColor});

  final String label;
  final String value;
  final Color? valueColor;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(label, style: TextStyle(fontSize: AppType.md, color: palette.textMuted)),
        Text(
          value,
          style: TextStyle(
            fontSize: AppType.md,
            fontWeight: AppType.bold,
            color: valueColor ?? palette.text,
          ),
        ),
      ],
    );
  }
}

class _CategoryChip extends StatelessWidget {
  const _CategoryChip({required this.label, required this.selected, required this.onTap});

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return Pressable(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 7),
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
