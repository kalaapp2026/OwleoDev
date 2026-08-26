import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:nest_fe/app/theme/app_tokens.dart';
import 'package:nest_fe/app/theme/app_typography.dart';
import 'package:nest_fe/core/design/attached_select.dart';
import 'package:nest_fe/core/design/buttons.dart';
import 'package:nest_fe/core/design/charts.dart';
import 'package:nest_fe/core/design/confirm_dialog.dart';
import 'package:nest_fe/core/design/flip_toggle.dart';
import 'package:nest_fe/core/design/pressable.dart';
import 'package:nest_fe/core/design/status_badge.dart';
import 'package:nest_fe/features/curriculum/data/curriculum_api.dart';
import 'package:nest_fe/features/enrolment/data/batch.dart';
import 'package:nest_fe/features/enrolment/presentation/batches_screen.dart';
import 'package:nest_fe/features/fees/data/fee_roster.dart';
import 'package:nest_fe/features/fees/presentation/fees_screen.dart'
    show FeesScreen, feesApiProvider;

/// Which selector currently owns the open dropdown panel.
///
/// The two selectors sit side by side, and an open panel is wider than its trigger. Without a
/// single owner they overlap and neither is readable, so open state lives here rather than inside
/// each [AttachedSelect].
enum _OpenPanel { none, course, batch }

/// The roster request: the three things that identify a batch's fees for a month.
///
/// A record, so Riverpod's family caches on value equality - re-selecting the same course and
/// batch reuses the fetch instead of re-issuing it.
typedef _RosterKey = ({String courseId, String batchId, String period});

final _rosterProvider =
    FutureProvider.autoDispose.family<FeeRoster, _RosterKey>((ref, key) {
  return ref.watch(feesApiProvider).roster(
        courseId: key.courseId,
        batchId: key.batchId,
        period: key.period,
      );
});

/// Regular Fees: month -> course -> batch, then the batch's students with their fee position.
///
/// The list appears as soon as course and batch are both chosen - there is no "view" button,
/// because there is nothing left to confirm once the cascade is complete.
class RegularFeesScreen extends ConsumerStatefulWidget {
  const RegularFeesScreen({super.key});

  @override
  ConsumerState<RegularFeesScreen> createState() => _RegularFeesScreenState();
}

class _RegularFeesScreenState extends ConsumerState<RegularFeesScreen> {
  DateTime _month = DateTime(DateTime.now().year, DateTime.now().month);
  String? _courseId;
  String? _batchId;
  _OpenPanel _open = _OpenPanel.none;

  String _query = '';
  final Set<PaymentStatus> _statusFilter = {};
  bool _busy = false;

  String get _period =>
      '${_month.year}-${_month.month.toString().padLeft(2, '0')}';

  _RosterKey? get _rosterKey => (_courseId != null && _batchId != null)
      ? (courseId: _courseId!, batchId: _batchId!, period: _period)
      : null;

  void _setMonth(int delta) {
    setState(() => _month = DateTime(_month.year, _month.month + delta));
  }

  void _selectCourse(String courseId) {
    setState(() {
      _courseId = courseId;
      // The chosen batch belonged to the previous course, so it cannot survive the change.
      // Leaving it would silently request a roster for a batch/course pair that does not exist.
      _batchId = null;
    });
  }

  Future<void> _markPaid(FeeRosterEntry entry) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await ref.read(feesApiProvider).recordEntry(
            membershipId: entry.membershipId,
            courseId: _courseId!,
            period: _period,
            amountPaid: entry.balance,
            mode: 'CASH',
          );
      _refresh();
    } catch (e) {
      _showError(e);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _undo(FeeRosterEntry entry) async {
    // Marking paid needs no confirmation - it is what the admin came to do, and it is undoable.
    // Undoing does, because it is the destructive direction.
    final confirmed = await showAppConfirmDialog(
      context: context,
      title: 'Undo this payment?',
      message: '${entry.studentName}\'s payment will be reversed. The original entry stays on '
          'the statement with a matching reversal beside it.',
      confirmLabel: 'Undo',
    );
    if (!confirmed || _busy) return;

    setState(() => _busy = true);
    try {
      await ref.read(feesApiProvider).reverseEntry(transactionId: entry.lastPaymentId!);
      _refresh();
    } catch (e) {
      _showError(e);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _refresh() {
    final key = _rosterKey;
    if (key != null) ref.invalidate(_rosterProvider(key));
  }

  void _showError(Object error) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(error.toString().replaceFirst('Exception: ', ''))),
    );
  }

  List<FeeRosterEntry> _visible(FeeRoster roster) {
    final q = _query.trim().toLowerCase();
    return roster.entries.where((e) {
      if (q.isNotEmpty && !e.studentName.toLowerCase().contains(q)) return false;
      if (_statusFilter.isNotEmpty && !_statusFilter.contains(e.status)) return false;
      return true;
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final coursesAsync = ref.watch(activeCoursesProvider);
    final key = _rosterKey;

    // No own Scaffold or AppBar - this renders inside AppShell's IndexedStack as the Fees tab,
    // which already supplies both (the title comes from the shell's own tab titles).
    return ColoredBox(
      color: palette.bg,
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(
                AppSpacing.xl, AppSpacing.md, AppSpacing.xl, AppSpacing.md),
            child: Column(
              children: [
                // The report download, fee slips and per-student history still live on the old
                // screen - they are phase 5 of this port. Keeping a door to them means the
                // redesign doesn't take working features away in the meantime.
                Align(
                  alignment: Alignment.centerRight,
                  child: Pressable(
                    onTap: () => Navigator.of(context).push(MaterialPageRoute(
                      builder: (_) => const _LegacyFeesPage(),
                    )),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: AppSpacing.xxs),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.description_outlined, size: 13, color: palette.textMuted),
                          const SizedBox(width: AppSpacing.xxs),
                          Text('Reports & history',
                              style: TextStyle(fontSize: AppType.xs, color: palette.textMuted)),
                        ],
                      ),
                    ),
                  ),
                ),
                _MonthStepper(
                  month: _month,
                  onPrevious: () => _setMonth(-1),
                  // Never past the current month: fees for a month that has not started yet are
                  // not a thing an admin can collect.
                  onNext: _month.isBefore(DateTime(DateTime.now().year, DateTime.now().month))
                      ? () => _setMonth(1)
                      : null,
                ),
                const SizedBox(height: AppSpacing.lg),
                coursesAsync.when(
                  loading: () => const _SelectorPlaceholder(),
                  error: (e, _) => _InlineError(message: 'Courses failed to load', error: e),
                  data: (courses) => Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: AttachedSelect<dynamic>(
                          label: 'Course',
                          options: courses,
                          labelOf: (c) => c.name as String,
                          value: courses.where((c) => c.id == _courseId).firstOrNull,
                          searchable: courses.length > 6,
                          panelSpan: PanelSpan.left,
                          isOpen: _open == _OpenPanel.course,
                          onOpenChanged: (o) =>
                              setState(() => _open = o ? _OpenPanel.course : _OpenPanel.none),
                          onSelected: (c) => _selectCourse(c.id as String),
                        ),
                      ),
                      const SizedBox(width: AppSpacing.md),
                      Expanded(child: _BatchSelect(
                        courseId: _courseId,
                        batchId: _batchId,
                        isOpen: _open == _OpenPanel.batch,
                        onOpenChanged: (o) =>
                            setState(() => _open = o ? _OpenPanel.batch : _OpenPanel.none),
                        onSelected: (b) => setState(() => _batchId = b.id),
                      )),
                    ],
                  ),
                ),
              ],
            ),
          ),
          if (key == null)
            Expanded(
              child: _EmptyState(
                icon: Icons.filter_list_rounded,
                title: _courseId == null ? 'Choose a course' : 'Choose a batch',
                message: 'The student list appears as soon as both are selected.',
              ),
            )
          else
            Expanded(
              child: ref.watch(_rosterProvider(key)).when(
                    loading: () => const Center(child: CircularProgressIndicator()),
                    error: (e, _) => _InlineError(message: 'Could not load the roster', error: e),
                    data: (roster) => _RosterBody(
                      roster: roster,
                      visible: _visible(roster),
                      query: _query,
                      statusFilter: _statusFilter,
                      busy: _busy,
                      onQueryChanged: (v) => setState(() => _query = v),
                      onToggleStatus: (s) => setState(() {
                        _statusFilter.contains(s) ? _statusFilter.remove(s) : _statusFilter.add(s);
                      }),
                      onMarkPaid: _markPaid,
                      onUndo: _undo,
                    ),
                  ),
            ),
        ],
      ),
    );
  }
}

/// The batch half of the cascade. Disabled until a course is chosen, because a batch only means
/// something inside one.
class _BatchSelect extends ConsumerWidget {
  const _BatchSelect({
    required this.courseId,
    required this.batchId,
    required this.isOpen,
    required this.onOpenChanged,
    required this.onSelected,
  });

  final String? courseId;
  final String? batchId;
  final bool isOpen;
  final ValueChanged<bool> onOpenChanged;
  final ValueChanged<Batch> onSelected;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (courseId == null) {
      return AttachedSelect<Batch>(
        label: 'Batch',
        options: const [],
        labelOf: (b) => b.name,
        enabled: false,
        placeholder: 'Course first',
        onSelected: (_) {},
      );
    }

    final batchesAsync = ref.watch(batchesForCourseProvider(courseId!));
    return batchesAsync.when(
      loading: () => AttachedSelect<Batch>(
        label: 'Batch',
        options: const [],
        labelOf: (b) => b.name,
        enabled: false,
        placeholder: 'Loading...',
        onSelected: (_) {},
      ),
      error: (_, _) => AttachedSelect<Batch>(
        label: 'Batch',
        options: const [],
        labelOf: (b) => b.name,
        enabled: false,
        placeholder: 'Unavailable',
        onSelected: (_) {},
      ),
      data: (batches) {
        final active = batches.where((b) => b.status == 'ACTIVE').toList();
        return AttachedSelect<Batch>(
          label: 'Batch',
          options: active,
          labelOf: (b) => b.name,
          value: active.where((b) => b.id == batchId).firstOrNull,
          // One batch is not a choice - showing a padlock says "decided for you" rather than
          // making the admin open a menu to pick the only entry.
          locked: active.length == 1 && batchId != null,
          searchable: active.length > 6,
          panelSpan: PanelSpan.right,
          isOpen: isOpen,
          onOpenChanged: onOpenChanged,
          emptyLabel: 'No active batches',
          onSelected: onSelected,
        );
      },
    );
  }
}

class _RosterBody extends StatelessWidget {
  const _RosterBody({
    required this.roster,
    required this.visible,
    required this.query,
    required this.statusFilter,
    required this.busy,
    required this.onQueryChanged,
    required this.onToggleStatus,
    required this.onMarkPaid,
    required this.onUndo,
  });

  final FeeRoster roster;
  final List<FeeRosterEntry> visible;
  final String query;
  final Set<PaymentStatus> statusFilter;
  final bool busy;
  final ValueChanged<String> onQueryChanged;
  final ValueChanged<PaymentStatus> onToggleStatus;
  final ValueChanged<FeeRosterEntry> onMarkPaid;
  final ValueChanged<FeeRosterEntry> onUndo;

  static const _filters = [
    (PaymentStatus.notPaid, 'Not paid'),
    (PaymentStatus.partial, 'Partial'),
    (PaymentStatus.due, 'Due'),
    (PaymentStatus.paidManual, 'Paid'),
  ];

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xl),
          child: Column(
            children: [
              // Progress reads the roster totals, not the filtered list - filtering to "not paid"
              // must not make it look like nobody has paid.
              AppProgressBar(
                paid: roster.paidCount,
                total: roster.studentCount,
                trailingLabel: '${roster.paidCount}/${roster.studentCount} paid',
              ),
              const SizedBox(height: AppSpacing.sm),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text('Collected ${_money(roster.collected)}',
                      style: TextStyle(fontSize: AppType.smd, color: palette.textMuted)),
                  Text('Expected ${_money(roster.expected)}',
                      style: TextStyle(fontSize: AppType.smd, color: palette.textMuted)),
                ],
              ),
              const SizedBox(height: AppSpacing.lg),
              TextField(
                onChanged: onQueryChanged,
                style: TextStyle(fontSize: AppType.md, color: palette.text),
                decoration: InputDecoration(
                  isDense: true,
                  hintText: 'Search students',
                  hintStyle: TextStyle(fontSize: AppType.md, color: palette.textFaint),
                  prefixIcon: Icon(Icons.search_rounded, size: 16, color: palette.textMuted),
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
                ),
              ),
              const SizedBox(height: AppSpacing.md),
              SizedBox(
                height: 32,
                child: ListView.separated(
                  scrollDirection: Axis.horizontal,
                  itemCount: _filters.length,
                  separatorBuilder: (_, _) => const SizedBox(width: AppSpacing.xs),
                  itemBuilder: (context, i) {
                    final (status, label) = _filters[i];
                    return AppFilterChip(
                      label: label,
                      selected: statusFilter.contains(status),
                      accent: status.color(palette),
                      onTap: () => onToggleStatus(status),
                    );
                  },
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: AppSpacing.md),
        Expanded(
          child: visible.isEmpty
              ? _EmptyState(
                  icon: Icons.search_off_rounded,
                  title: roster.entries.isEmpty ? 'No students in this batch' : 'Nothing matches',
                  message: roster.entries.isEmpty
                      ? 'Add students to the batch to collect fees for them.'
                      : 'Try a different name or clear the filters.',
                )
              : ListView.separated(
                  padding: const EdgeInsets.fromLTRB(
                      AppSpacing.xl, 0, AppSpacing.xl, AppSpacing.x3l),
                  itemCount: visible.length,
                  separatorBuilder: (_, _) => const SizedBox(height: AppSpacing.sm),
                  itemBuilder: (context, i) => _StudentRow(
                    entry: visible[i],
                    busy: busy,
                    onMarkPaid: () => onMarkPaid(visible[i]),
                    onUndo: () => onUndo(visible[i]),
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
    required this.onMarkPaid,
    required this.onUndo,
  });

  final FeeRosterEntry entry;
  final bool busy;
  final VoidCallback onMarkPaid;
  final VoidCallback onUndo;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final settled = entry.status.isSettled;

    return Container(
      padding: const EdgeInsets.all(AppSpacing.lg),
      decoration: BoxDecoration(
        color: palette.surfaceRaised,
        borderRadius: AppRadii.all(AppRadii.xl),
        border: Border.all(color: palette.border),
      ),
      child: Row(
        children: [
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
                Row(
                  children: [
                    StatusBadge(
                      label: _statusLabel(entry.status),
                      color: entry.status.color(palette),
                      dense: true,
                    ),
                    const SizedBox(width: AppSpacing.xs),
                    Flexible(
                      child: Text(
                        settled
                            ? _money(entry.totalPaid)
                            : '${_money(entry.totalPaid)} of ${_money(entry.agreedFee)}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(fontSize: AppType.xs, color: palette.textMuted),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(width: AppSpacing.sm),
          // The toggle only reverses a payment it can actually reverse. A settled row with nothing
          // undoable (an older payment already reversed, or a closed period) shows the badge alone
          // rather than an action the server would refuse.
          if (settled && !entry.canUndo)
            const SizedBox.shrink()
          else
            FlipToggle(
              isOn: settled,
              onLabel: 'Undo',
              offLabel: 'Mark Paid',
              onColor: palette.notPaid,
              offColor: palette.primary,
              onTap: busy ? null : (settled ? onUndo : onMarkPaid),
            ),
        ],
      ),
    );
  }
}

class _MonthStepper extends StatelessWidget {
  const _MonthStepper({required this.month, required this.onPrevious, required this.onNext});

  final DateTime month;
  final VoidCallback? onPrevious;
  final VoidCallback? onNext;

  static const _names = [
    'January', 'February', 'March', 'April', 'May', 'June',
    'July', 'August', 'September', 'October', 'November', 'December'
  ];

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return Row(
      children: [
        AppIconButton(
            icon: Icons.chevron_left_rounded, onTap: onPrevious, tooltip: 'Previous month'),
        Expanded(
          child: Center(
            child: Text(
              '${_names[month.month - 1]} ${month.year}',
              style: TextStyle(
                fontSize: AppType.xxl,
                fontWeight: AppType.bold,
                color: palette.text,
              ),
            ),
          ),
        ),
        AppIconButton(
            icon: Icons.chevron_right_rounded, onTap: onNext, tooltip: 'Next month'),
      ],
    );
  }
}

class _SelectorPlaceholder extends StatelessWidget {
  const _SelectorPlaceholder();

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return Container(
      height: 62,
      decoration: BoxDecoration(
        color: palette.surfaceRaised,
        borderRadius: AppRadii.all(AppRadii.lg),
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({required this.icon, required this.title, required this.message});

  final IconData icon;
  final String title;
  final String message;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.x4l),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 34, color: palette.textFaint),
            const SizedBox(height: AppSpacing.md),
            Text(title,
                style: TextStyle(
                    fontSize: AppType.xxl, fontWeight: AppType.bold, color: palette.text)),
            const SizedBox(height: AppSpacing.xs),
            Text(
              message,
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: AppType.md, color: palette.textMuted, height: 1.4),
            ),
          ],
        ),
      ),
    );
  }
}

class _InlineError extends StatelessWidget {
  const _InlineError({required this.message, required this.error});

  final String message;
  final Object error;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.x4l),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.error_outline_rounded, size: 30, color: palette.notPaid),
            const SizedBox(height: AppSpacing.sm),
            Text(message,
                style: TextStyle(
                    fontSize: AppType.lg, fontWeight: AppType.bold, color: palette.text)),
            const SizedBox(height: AppSpacing.xs),
            Text(
              error.toString().replaceFirst('Exception: ', ''),
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: AppType.xs, color: palette.textMuted),
            ),
          ],
        ),
      ),
    );
  }
}

String _statusLabel(PaymentStatus status) => switch (status) {
      PaymentStatus.notPaid => 'NOT PAID',
      PaymentStatus.due => 'DUE',
      PaymentStatus.partial => 'PARTIAL',
      PaymentStatus.paidManual => 'PAID',
      PaymentStatus.paidGateway => 'GATEWAY',
      PaymentStatus.closed => 'CLOSED',
    };

/// Indian digit grouping - last three, then twos: 1,23,456. Every amount in this app is read that
/// way, and a plain thousands separator looks wrong to the people using it.
String _money(num value) {
  final whole = value.round().abs().toString();
  final String grouped;
  if (whole.length <= 3) {
    grouped = whole;
  } else {
    final last3 = whole.substring(whole.length - 3);
    var rest = whole.substring(0, whole.length - 3);
    final parts = <String>[];
    while (rest.length > 2) {
      parts.insert(0, rest.substring(rest.length - 2));
      rest = rest.substring(0, rest.length - 2);
    }
    if (rest.isNotEmpty) parts.insert(0, rest);
    grouped = '${parts.join(',')},$last3';
  }
  return '${value < 0 ? '-' : ''}₹$grouped';
}

/// The pre-redesign fees screen, still carrying the report download, fee slips and per-student
/// history that phases 4-5 will absorb. It renders as a tab body with no chrome of its own, so it
/// needs a Scaffold when pushed as a page.
class _LegacyFeesPage extends StatelessWidget {
  const _LegacyFeesPage();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Reports & history')),
      body: const FeesScreen(),
    );
  }
}
