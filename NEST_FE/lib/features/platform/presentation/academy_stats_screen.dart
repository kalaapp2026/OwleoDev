import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:nest_fe/core/widgets/async_value_view.dart';
import 'package:nest_fe/features/platform/data/platform_api.dart';
import 'package:nest_fe/features/platform/presentation/academy_detail_screen.dart';
import 'package:nest_fe/features/platform/presentation/console_layout.dart';
import 'package:nest_fe/features/platform/presentation/super_admin_dashboard_screen.dart';

final academyStatsProvider =
    FutureProvider.autoDispose((ref) => ref.watch(platformApiProvider).academies());

enum _SortBy { name, students, trainers, courses, batches, fees, activity }

/// Tenant table for the Super Admin console. This is the one screen in the app built desktop-first:
/// it's a dense comparison view (which academies are big, which are dormant, which are suspended),
/// and that reads far better as a real table than as a column of cards. Narrow windows still get a
/// card list rather than a table squeezed sideways.
class AcademyStatsScreen extends ConsumerStatefulWidget {
  const AcademyStatsScreen({super.key, this.embedded = false});

  final bool embedded;

  @override
  ConsumerState<AcademyStatsScreen> createState() => _AcademyStatsScreenState();
}

class _AcademyStatsScreenState extends ConsumerState<AcademyStatsScreen> {
  final _searchController = TextEditingController();
  String _query = '';
  _SortBy _sortBy = _SortBy.students;
  bool _ascending = false;

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  List<AcademySummary> _visible(List<AcademySummary> all) {
    final query = _query.trim().toLowerCase();
    final filtered = query.isEmpty
        ? [...all]
        : all
            .where((a) =>
                a.name.toLowerCase().contains(query) || (a.city ?? '').toLowerCase().contains(query))
            .toList();

    int compare(AcademySummary a, AcademySummary b) {
      switch (_sortBy) {
        case _SortBy.name:
          return a.name.toLowerCase().compareTo(b.name.toLowerCase());
        case _SortBy.students:
          return a.students.compareTo(b.students);
        case _SortBy.trainers:
          return a.trainers.compareTo(b.trainers);
        case _SortBy.courses:
          return a.courses.compareTo(b.courses);
        case _SortBy.batches:
          return a.batches.compareTo(b.batches);
        case _SortBy.fees:
          return a.feesCollected.compareTo(b.feesCollected);
        case _SortBy.activity:
          // Never-active academies sort as oldest rather than being dropped - "nobody has ever
          // opened this" is the single most interesting row in this column.
          final aTime = a.lastActivityAt?.millisecondsSinceEpoch ?? 0;
          final bTime = b.lastActivityAt?.millisecondsSinceEpoch ?? 0;
          return aTime.compareTo(bTime);
      }
    }

    filtered.sort((a, b) => _ascending ? compare(a, b) : compare(b, a));
    return filtered;
  }

  void _onSort(_SortBy column) {
    setState(() {
      if (_sortBy == column) {
        _ascending = !_ascending;
      } else {
        _sortBy = column;
        // Numeric columns are most useful biggest-first; names read better A-Z.
        _ascending = column == _SortBy.name;
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final async = ref.watch(academyStatsProvider);

    return Scaffold(
      appBar: widget.embedded ? null : AppBar(title: const Text('Academies')),
      body: AsyncValueView<List<AcademySummary>>(
        value: async,
        onRetry: () => ref.invalidate(academyStatsProvider),
        data: (context, all) {
          final rows = _visible(all);
          return RefreshIndicator(
            onRefresh: () async {
              ref.invalidate(academyStatsProvider);
              await ref.read(academyStatsProvider.future);
            },
            child: ConsolePage(
              children: [
                _Toolbar(
                  controller: _searchController,
                  total: all.length,
                  showing: rows.length,
                  onChanged: (v) => setState(() => _query = v),
                ),
                const SizedBox(height: 16),
                if (rows.isEmpty)
                  const Padding(
                    padding: EdgeInsets.only(top: 40),
                    child: EmptyState(icon: Icons.search_off, message: 'No academies match that search.'),
                  )
                else if (ConsoleBreakpoints.isCompact(context))
                  ...rows.map((a) => _AcademyCard(academy: a, onTap: () => _open(a)))
                else
                  _AcademyTable(
                    rows: rows,
                    sortBy: _sortBy,
                    ascending: _ascending,
                    onSort: _onSort,
                    onOpen: _open,
                  ),
              ],
            ),
          );
        },
      ),
    );
  }

  void _open(AcademySummary academy) {
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => AcademyDetailScreen(academyId: academy.id, initial: academy)),
    );
  }
}

class _Toolbar extends StatelessWidget {
  const _Toolbar({
    required this.controller,
    required this.total,
    required this.showing,
    required this.onChanged,
  });

  final TextEditingController controller;
  final int total;
  final int showing;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    final label = showing == total ? '$total academies' : '$showing of $total academies';
    return Row(
      children: [
        Expanded(
          child: Text(label, style: Theme.of(context).textTheme.titleMedium),
        ),
        SizedBox(
          width: ConsoleBreakpoints.isCompact(context) ? 180 : 280,
          child: TextField(
            controller: controller,
            onChanged: onChanged,
            decoration: InputDecoration(
              isDense: true,
              hintText: 'Search name or city',
              prefixIcon: const Icon(Icons.search, size: 20),
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
            ),
          ),
        ),
      ],
    );
  }
}

class _AcademyTable extends StatelessWidget {
  const _AcademyTable({
    required this.rows,
    required this.sortBy,
    required this.ascending,
    required this.onSort,
    required this.onOpen,
  });

  final List<AcademySummary> rows;
  final _SortBy sortBy;
  final bool ascending;
  final void Function(_SortBy) onSort;
  final void Function(AcademySummary) onOpen;

  @override
  Widget build(BuildContext context) {
    // Even on desktop the table can outgrow a narrow window, so it scrolls inside its own box -
    // the page itself must never scroll sideways.
    return Card(
      margin: EdgeInsets.zero,
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: ConstrainedBox(
          constraints: BoxConstraints(minWidth: MediaQuery.sizeOf(context).width - 96),
          child: DataTable(
            sortColumnIndex: _columnIndex(sortBy),
            sortAscending: ascending,
            headingRowHeight: 44,
            dataRowMinHeight: 48,
            dataRowMaxHeight: 56,
            columns: [
              DataColumn(label: const Text('Academy'), onSort: (_, _) => onSort(_SortBy.name)),
              const DataColumn(label: Text('Status')),
              const DataColumn(label: Text('Plan')),
              DataColumn(label: const Text('Students'), numeric: true, onSort: (_, _) => onSort(_SortBy.students)),
              DataColumn(label: const Text('Trainers'), numeric: true, onSort: (_, _) => onSort(_SortBy.trainers)),
              DataColumn(label: const Text('Courses'), numeric: true, onSort: (_, _) => onSort(_SortBy.courses)),
              DataColumn(label: const Text('Batches'), numeric: true, onSort: (_, _) => onSort(_SortBy.batches)),
              DataColumn(label: const Text('Fees collected'), numeric: true, onSort: (_, _) => onSort(_SortBy.fees)),
              DataColumn(label: const Text('Last active'), onSort: (_, _) => onSort(_SortBy.activity)),
            ],
            rows: rows
                .map((a) => DataRow(
                      onSelectChanged: (_) => onOpen(a),
                      cells: [
                        DataCell(Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Text(a.name, style: const TextStyle(fontWeight: FontWeight.w600)),
                            if (a.city != null)
                              Text(a.city!, style: Theme.of(context).textTheme.bodySmall),
                          ],
                        )),
                        DataCell(ConsoleStatusChip(status: a.status)),
                        DataCell(Text(a.plan ?? '-')),
                        DataCell(Text('${a.students}')),
                        DataCell(Text('${a.trainers}')),
                        DataCell(Text('${a.courses}')),
                        DataCell(Text('${a.batches}')),
                        DataCell(Text(formatCurrency(a.feesCollected))),
                        DataCell(Text(
                          formatRelative(a.lastActivityAt),
                          style: a.lastActivityAt == null
                              ? TextStyle(color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.45))
                              : null,
                        )),
                      ],
                    ))
                .toList(),
          ),
        ),
      ),
    );
  }

  int _columnIndex(_SortBy sortBy) => switch (sortBy) {
        _SortBy.name => 0,
        _SortBy.students => 3,
        _SortBy.trainers => 4,
        _SortBy.courses => 5,
        _SortBy.batches => 6,
        _SortBy.fees => 7,
        _SortBy.activity => 8,
      };
}

/// Narrow-window fallback - the same data, stacked, since a 9-column table on a phone is unusable.
class _AcademyCard extends StatelessWidget {
  const _AcademyCard({required this.academy, required this.onTap});

  final AcademySummary academy;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(academy.name,
                        style: Theme.of(context).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700)),
                  ),
                  ConsoleStatusChip(status: academy.status),
                ],
              ),
              if (academy.city != null)
                Text(academy.city!, style: Theme.of(context).textTheme.bodySmall),
              const SizedBox(height: 10),
              Wrap(
                spacing: 14,
                runSpacing: 6,
                children: [
                  _MiniStat('Students', '${academy.students}'),
                  _MiniStat('Trainers', '${academy.trainers}'),
                  _MiniStat('Courses', '${academy.courses}'),
                  _MiniStat('Batches', '${academy.batches}'),
                  _MiniStat('Fees', formatCurrency(academy.feesCollected)),
                ],
              ),
              const SizedBox(height: 8),
              Text('Last active ${formatRelative(academy.lastActivityAt)}',
                  style: Theme.of(context).textTheme.bodySmall),
            ],
          ),
        ),
      ),
    );
  }
}

class _MiniStat extends StatelessWidget {
  const _MiniStat(this.label, this.value);
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(value, style: const TextStyle(fontWeight: FontWeight.w700)),
        Text(label, style: Theme.of(context).textTheme.bodySmall),
      ],
    );
  }
}

String formatCurrency(double amount) {
  if (amount == 0) return '-';
  final rounded = amount.round();
  final digits = rounded.toString();
  // Indian grouping (1,23,456) - last 3 digits, then pairs.
  if (digits.length <= 3) return '₹$digits';
  final last3 = digits.substring(digits.length - 3);
  var rest = digits.substring(0, digits.length - 3);
  final parts = <String>[];
  while (rest.length > 2) {
    parts.insert(0, rest.substring(rest.length - 2));
    rest = rest.substring(0, rest.length - 2);
  }
  if (rest.isNotEmpty) parts.insert(0, rest);
  return '₹${parts.join(',')},$last3';
}

String formatRelative(DateTime? time) {
  if (time == null) return 'never';
  final diff = DateTime.now().difference(time.toLocal());
  if (diff.inMinutes < 1) return 'just now';
  if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
  if (diff.inHours < 24) return '${diff.inHours}h ago';
  if (diff.inDays < 30) return '${diff.inDays}d ago';
  return '${(diff.inDays / 30).floor()}mo ago';
}
