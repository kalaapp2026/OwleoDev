import 'package:flutter/material.dart';
import 'package:nest_fe/app/theme/app_tokens.dart';
import 'package:nest_fe/app/theme/app_typography.dart';
import 'package:nest_fe/core/design/avatar.dart';
import 'package:nest_fe/core/design/charts.dart';
import 'package:nest_fe/core/design/confirm_dialog.dart';
import 'package:nest_fe/core/design/flip_toggle.dart';
import 'package:nest_fe/core/design/pressable.dart';
import 'package:nest_fe/core/design/sheets.dart';
import 'package:nest_fe/core/design/status_badge.dart';
import 'package:nest_fe/features/fees/data/fee_roster.dart';
import 'package:nest_fe/features/fees/presentation/fee_format.dart';

/// How the roster is ordered.
///
/// Mirrors the prototype's five options. "Unpaid first" is the one that earns its place: it is how
/// an admin works a batch when collecting, since the paid rows are the ones they can skip.
enum RosterSort {
  none('Default order'),
  nameAsc('Name (A-Z)'),
  nameDesc('Name (Z-A)'),
  unpaidFirst('Payment status: Unpaid first'),
  paidFirst('Payment status: Paid first');

  const RosterSort(this.label);

  final String label;
}

/// Which status bucket the chips are filtering to. Distinct from [PaymentStatus] because "Paid"
/// here means either kind of paid, and "All" is not a status at all.
enum RosterFilter {
  all('All'),
  notPaid('Not Paid'),
  partial('Partial'),
  paid('Paid');

  const RosterFilter(this.label);

  final String label;

  bool matches(PaymentStatus status) => switch (this) {
        RosterFilter.all => true,
        // "Not Paid" includes overdue: due is not a separate thing an admin collects, it is the
        // same unpaid row with a deadline behind it.
        RosterFilter.notPaid => status == PaymentStatus.notPaid || status == PaymentStatus.due,
        RosterFilter.partial => status == PaymentStatus.partial,
        RosterFilter.paid => status.isSettled,
      };
}

/// The student list with its progress, search, sort, filters and mark-paid actions.
///
/// Shared by Regular Fees and Other Fees rather than duplicated: the two screens differ only in
/// how the list is chosen (course+batch vs fee type+batch), not in how it behaves once shown.
class StudentListBody extends StatefulWidget {
  const StudentListBody({
    super.key,
    required this.roster,
    required this.onMarkPaid,
    required this.onUndo,
    required this.onOpenProfile,
    this.onDownloadReport,
    this.busy = false,
    this.emptyText,
    this.onScrolled,
  });

  final FeeRoster roster;
  final ValueChanged<FeeRosterEntry> onMarkPaid;
  final ValueChanged<FeeRosterEntry> onUndo;
  final ValueChanged<FeeRosterEntry> onOpenProfile;
  final VoidCallback? onDownloadReport;
  final bool busy;
  final String? emptyText;

  /// Fires with true once the list is scrolled past the top, so the screen above can collapse its
  /// selector block and give the list more room.
  final ValueChanged<bool>? onScrolled;

  @override
  State<StudentListBody> createState() => _StudentListBodyState();
}

class _StudentListBodyState extends State<StudentListBody> {
  final _searchController = TextEditingController();
  String _query = '';
  RosterSort _sort = RosterSort.none;
  RosterFilter _filter = RosterFilter.all;
  DateTime? _receivedOn;
  bool _scrolled = false;

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  bool _handleScroll(ScrollNotification notification) {
    // 40px of travel, matching the prototype. Low enough that the collapse feels like a direct
    // response to scrolling, high enough that a stray touch doesn't trigger it.
    final scrolled = notification.metrics.pixels > 40;
    if (scrolled != _scrolled) {
      setState(() => _scrolled = scrolled);
      widget.onScrolled?.call(scrolled);
    }
    return false;
  }

  List<FeeRosterEntry> get _visible {
    final q = _query.trim().toLowerCase();
    final list = widget.roster.entries.where((e) {
      if (q.isNotEmpty && !e.studentName.toLowerCase().contains(q)) return false;
      if (!_filter.matches(e.status)) return false;
      if (_receivedOn != null && !_sameDay(e.lastPaidOn, _receivedOn!)) return false;
      return true;
    }).toList();

    switch (_sort) {
      case RosterSort.none:
        break;
      case RosterSort.nameAsc:
        list.sort((a, b) => a.studentName.toLowerCase().compareTo(b.studentName.toLowerCase()));
      case RosterSort.nameDesc:
        list.sort((a, b) => b.studentName.toLowerCase().compareTo(a.studentName.toLowerCase()));
      case RosterSort.unpaidFirst:
        list.sort((a, b) => _statusRank(a.status, true).compareTo(_statusRank(b.status, true)));
      case RosterSort.paidFirst:
        list.sort((a, b) => _statusRank(a.status, false).compareTo(_statusRank(b.status, false)));
    }
    return list;
  }

  static bool _sameDay(DateTime? a, DateTime b) =>
      a != null && a.year == b.year && a.month == b.month && a.day == b.day;

  /// Unpaid, then partial, then settled - or the reverse. Grouped rather than fully ordered, so
  /// rows keep their relative order inside a group instead of shuffling on every re-sort.
  static int _statusRank(PaymentStatus status, bool unpaidFirst) {
    final group = switch (status) {
      PaymentStatus.notPaid || PaymentStatus.due => 0,
      PaymentStatus.partial => 1,
      _ => 2,
    };
    return unpaidFirst ? group : 2 - group;
  }

  Future<void> _pickSort() async {
    final picked = await showAppOptionSheet<RosterSort>(
      context: context,
      title: 'Sort students',
      options: RosterSort.values,
      labelOf: (s) => s.label,
    );
    if (picked != null) setState(() => _sort = picked);
  }

  Future<void> _confirmUndo(FeeRosterEntry entry) async {
    final confirmed = await showAppConfirmDialog(
      context: context,
      title: 'Change status to unpaid?',
      message: '${entry.studentName} is currently marked as paid. The payment will be reversed - '
          'the original entry stays on the statement with a matching reversal beside it.',
      confirmLabel: 'Yes, undo',
    );
    if (confirmed) widget.onUndo(entry);
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final roster = widget.roster;
    final visible = _visible;

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(
              AppSpacing.xl, AppSpacing.lg, AppSpacing.xl, AppSpacing.sm),
          // Progress reads the roster totals, never the filtered list - filtering to "Not Paid"
          // must not make it look like nobody has paid.
          child: AppProgressBar(paid: roster.paidCount, total: roster.studentCount),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(AppSpacing.xl, AppSpacing.md, AppSpacing.xl, 0),
          child: Row(
            children: [
              Expanded(child: _SearchField(
                controller: _searchController,
                onChanged: (v) => setState(() => _query = v),
              )),
              const SizedBox(width: AppSpacing.sm),
              _SortButton(active: _sort != RosterSort.none, onTap: _pickSort),
            ],
          ),
        ),
        const SizedBox(height: AppSpacing.sm),
        SizedBox(
          height: 32,
          child: ListView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xl),
            children: [
              for (final f in RosterFilter.values) ...[
                _Chip(
                  label: f.label,
                  selected: _filter == f,
                  onTap: () => setState(() => _filter = f),
                ),
                const SizedBox(width: AppSpacing.xs),
              ],
              if (widget.onDownloadReport != null)
                _Chip(
                  label: 'Report',
                  icon: Icons.file_download_outlined,
                  selected: true,
                  // Revenue yellow, so it reads as an action rather than one more filter sitting
                  // in the same row.
                  accent: palette.revenue,
                  onTap: widget.onDownloadReport,
                ),
            ],
          ),
        ),
        if (_sort != RosterSort.none)
          _ActiveFilterLine(
            label: 'Sorted by: ',
            value: _sort.label,
            valueColor: palette.primary,
            onClear: () => setState(() => _sort = RosterSort.none),
          ),
        if (_receivedOn != null)
          _ActiveFilterLine(
            label: 'Fees received on: ',
            value: formatFeeDate(_receivedOn!),
            valueColor: palette.revenue,
            onClear: () => setState(() => _receivedOn = null),
          ),
        Expanded(
          child: visible.isEmpty
              ? _Empty(
                  isFiltered: roster.entries.isNotEmpty,
                  emptyText: widget.emptyText,
                )
              : NotificationListener<ScrollNotification>(
                  onNotification: _handleScroll,
                  child: ListView.separated(
                    padding: const EdgeInsets.fromLTRB(
                        AppSpacing.lg, AppSpacing.sm, AppSpacing.lg, 90),
                    itemCount: visible.length,
                    separatorBuilder: (_, _) => const SizedBox(height: AppSpacing.sm),
                    itemBuilder: (context, i) {
                      final entry = visible[i];
                      return _StudentRow(
                        entry: entry,
                        busy: widget.busy,
                        onTap: () => widget.onOpenProfile(entry),
                        onMarkPaid: () => widget.onMarkPaid(entry),
                        onUndo: () => _confirmUndo(entry),
                        onFilterByDate: entry.lastPaidOn == null
                            ? null
                            : () => setState(() => _receivedOn = entry.lastPaidOn),
                      );
                    },
                  ),
                ),
        ),
      ],
    );
  }
}

class _StudentRow extends StatelessWidget {
  const _StudentRow({
    required this.entry,
    required this.busy,
    required this.onTap,
    required this.onMarkPaid,
    required this.onUndo,
    this.onFilterByDate,
  });

  final FeeRosterEntry entry;
  final bool busy;
  final VoidCallback onTap;
  final VoidCallback onMarkPaid;
  final VoidCallback onUndo;
  final VoidCallback? onFilterByDate;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;

    return Pressable(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(AppSpacing.md),
        decoration: BoxDecoration(
          color: palette.surfaceRaised,
          borderRadius: AppRadii.all(AppRadii.x3l),
          border: Border.all(color: palette.borderSoft),
        ),
        child: Row(
          children: [
            InitialsAvatar(name: entry.studentName),
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
                      fontSize: AppType.lg,
                      fontWeight: AppType.semi,
                      color: palette.text,
                    ),
                  ),
                  const SizedBox(height: AppSpacing.xxs),
                  Text(
                    _detailLine(entry),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: AppType.smd, color: palette.textMuted),
                  ),
                ],
              ),
            ),
            const SizedBox(width: AppSpacing.sm),
            _action(context, palette),
          ],
        ),
      ),
    );
  }

  /// The prototype flips only between "not paid" and a hand-taken payment. A gateway or partial
  /// row shows its badge instead: reversing a gateway payment is not something an admin should do
  /// from a list row, and a partial is not a single payment to flip back.
  Widget _action(BuildContext context, AppPalette palette) {
    if (entry.status == PaymentStatus.notPaid || entry.status == PaymentStatus.due) {
      return FlipToggle(
        isOn: false,
        onLabel: 'Mark Not Paid',
        offLabel: 'Mark Paid',
        onColor: palette.paidManual,
        offColor: palette.notPaid,
        onTap: busy ? null : onMarkPaid,
      );
    }
    if (entry.status == PaymentStatus.paidManual && entry.canUndo) {
      return FlipToggle(
        isOn: true,
        onLabel: 'Mark Not Paid',
        offLabel: 'Mark Paid',
        onColor: palette.paidManual,
        offColor: palette.notPaid,
        onTap: busy ? null : onUndo,
      );
    }
    return StatusBadge(
      label: statusLabel(entry.status),
      color: entry.status.color(palette),
      softColor: entry.status.softColor(palette),
    );
  }

  String _detailLine(FeeRosterEntry e) {
    final paidOn = e.lastPaidOn;
    if (e.status == PaymentStatus.partial) {
      final date = paidOn == null ? '' : ' · ${formatFeeDate(paidOn)}';
      return '${money(e.totalPaid)}/${money(e.agreedFee)}$date';
    }
    if (e.status.isSettled) {
      return paidOn == null
          ? money(e.agreedFee)
          : '${money(e.agreedFee)} · paid (${formatFeeDate(paidOn)})';
    }
    return money(e.agreedFee);
  }
}

class _SearchField extends StatelessWidget {
  const _SearchField({required this.controller, required this.onChanged});

  final TextEditingController controller;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return TextField(
      controller: controller,
      onChanged: onChanged,
      style: TextStyle(fontSize: AppType.md, color: palette.text),
      decoration: InputDecoration(
        isDense: true,
        hintText: 'Search student',
        hintStyle: TextStyle(fontSize: AppType.md, color: palette.textFaint),
        prefixIcon: Icon(Icons.search_rounded, size: 16, color: palette.textFaint),
        prefixIconConstraints: const BoxConstraints(minWidth: 34, minHeight: 34),
        filled: true,
        fillColor: palette.surfaceRaised,
        contentPadding:
            const EdgeInsets.symmetric(horizontal: AppSpacing.md, vertical: AppSpacing.md),
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
    );
  }
}

class _SortButton extends StatelessWidget {
  const _SortButton({required this.active, required this.onTap});

  final bool active;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return Pressable(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md, vertical: 11),
        decoration: BoxDecoration(
          color: active ? palette.primarySoft : palette.surfaceRaised,
          borderRadius: AppRadii.all(AppRadii.lg),
          border: Border.all(color: active ? palette.primary : palette.border),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.swap_vert_rounded, size: 15, color: active ? palette.primary : palette.text),
            const SizedBox(width: AppSpacing.xxs),
            Text(
              'Sort',
              style: TextStyle(
                fontSize: AppType.md,
                fontWeight: AppType.bold,
                color: active ? palette.primary : palette.text,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Chip extends StatelessWidget {
  const _Chip({
    required this.label,
    required this.selected,
    this.onTap,
    this.icon,
    this.accent,
  });

  final String label;
  final bool selected;
  final VoidCallback? onTap;
  final IconData? icon;
  final Color? accent;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final tint = accent ?? palette.primary;
    return Pressable(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 7),
        decoration: BoxDecoration(
          color: selected ? tint.withValues(alpha: 0.14) : palette.surfaceRaised,
          borderRadius: AppRadii.all(AppRadii.pill),
          border: Border.all(color: selected ? tint : palette.border),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (icon != null) ...[
              Icon(icon, size: 12, color: selected ? tint : palette.textMuted),
              const SizedBox(width: AppSpacing.xxs),
            ],
            Text(
              label,
              style: TextStyle(
                fontSize: AppType.base,
                fontWeight: AppType.medium,
                color: selected ? tint : palette.textMuted,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ActiveFilterLine extends StatelessWidget {
  const _ActiveFilterLine({
    required this.label,
    required this.value,
    required this.valueColor,
    required this.onClear,
  });

  final String label;
  final String value;
  final Color valueColor;
  final VoidCallback onClear;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return Padding(
      padding: const EdgeInsets.fromLTRB(AppSpacing.xl, AppSpacing.xs, AppSpacing.xl, 0),
      child: Row(
        children: [
          Flexible(
            child: Text.rich(
              TextSpan(
                text: label,
                style: TextStyle(fontSize: AppType.smd, color: palette.textFaint),
                children: [
                  TextSpan(
                    text: value,
                    style: TextStyle(fontWeight: AppType.bold, color: valueColor),
                  ),
                ],
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          const SizedBox(width: AppSpacing.xs),
          Pressable(
            onTap: onClear,
            child: Icon(Icons.close_rounded, size: 13, color: palette.textFaint),
          ),
        ],
      ),
    );
  }
}

class _Empty extends StatelessWidget {
  const _Empty({required this.isFiltered, this.emptyText});

  final bool isFiltered;
  final String? emptyText;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.x4l),
        child: Text(
          isFiltered
              ? 'No students match these filters.'
              : emptyText ?? 'No students found.',
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: AppType.lg, color: palette.textFaint),
        ),
      ),
    );
  }
}
