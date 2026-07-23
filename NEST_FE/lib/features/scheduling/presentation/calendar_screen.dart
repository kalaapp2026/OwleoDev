import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:nest_fe/core/error/api_exception.dart';
import 'package:nest_fe/features/scheduling/data/calendar_api.dart';
import 'package:nest_fe/features/scheduling/data/calendar_class.dart';

const _weekdayLabels = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
const _monthNames = [
  'January', 'February', 'March', 'April', 'May', 'June',
  'July', 'August', 'September', 'October', 'November', 'December',
];

/// A distinguishable colour per academy, assigned deterministically (sorted by academy id) so
/// the same academy keeps the same colour across month navigation and app restarts, not just
/// within one render.
const _academyPalette = [
  Color(0xFF6750A4), // purple
  Color(0xFF2E7D32), // green
  Color(0xFFEF6C00), // orange
  Color(0xFF1565C0), // blue
  Color(0xFFAD1457), // pink
  Color(0xFF00838F), // teal
  Color(0xFF6D4C41), // brown
  Color(0xFF546E7A), // blue-grey
];

String _dateKey(DateTime d) => '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

bool _isSameDate(DateTime a, DateTime b) => a.year == b.year && a.month == b.month && a.day == b.day;

/// The merged multi-academy calendar (PRD 7.5): every class the caller can see across every
/// academy they belong to - their own batches as a Student, the batches they teach as a Trainer,
/// or every class in the academy as an Academy Admin - tap a date to see what's scheduled on it.
class CalendarScreen extends ConsumerStatefulWidget {
  const CalendarScreen({super.key});

  @override
  ConsumerState<CalendarScreen> createState() => _CalendarScreenState();
}

class _CalendarScreenState extends ConsumerState<CalendarScreen> {
  late DateTime _visibleMonth = DateTime(DateTime.now().year, DateTime.now().month, 1);
  DateTime _selectedDate = DateTime.now();
  List<CalendarClass>? _classes;
  bool _isLoading = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  /// The visible 6-row grid spans a bit of the previous/next month too, so those leading/trailing
  /// cells can still show their own class markers instead of just being blank filler.
  ({DateTime start, DateTime end}) _gridRange(DateTime month) {
    final firstOfMonth = DateTime(month.year, month.month, 1);
    final lastOfMonth = DateTime(month.year, month.month + 1, 0);
    final leadingDays = (firstOfMonth.weekday - DateTime.monday) % 7;
    final trailingDays = (DateTime.sunday - lastOfMonth.weekday) % 7;
    return (start: firstOfMonth.subtract(Duration(days: leadingDays)), end: lastOfMonth.add(Duration(days: trailingDays)));
  }

  Future<void> _load() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });
    final range = _gridRange(_visibleMonth);
    try {
      final classes = await ref.read(calendarApiProvider).classesInRange(from: _dateKey(range.start), to: _dateKey(range.end));
      if (mounted) setState(() => _classes = classes);
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _changeMonth(int delta) {
    setState(() => _visibleMonth = DateTime(_visibleMonth.year, _visibleMonth.month + delta, 1));
    _load();
  }

  void _goToToday() {
    final now = DateTime.now();
    setState(() {
      _selectedDate = now;
      _visibleMonth = DateTime(now.year, now.month, 1);
    });
    _load();
  }

  Map<String, Color> _academyColors() {
    final ids = (_classes ?? const <CalendarClass>[]).map((c) => c.academyId).toSet().toList()..sort();
    return {for (var i = 0; i < ids.length; i++) ids[i]: _academyPalette[i % _academyPalette.length]};
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final academyColors = _academyColors();
    final isMultiAcademy = academyColors.length > 1;

    final classesByDate = <String, List<CalendarClass>>{};
    for (final c in _classes ?? const <CalendarClass>[]) {
      (classesByDate[c.date] ??= []).add(c);
    }
    final selectedDayClasses = List<CalendarClass>.from(classesByDate[_dateKey(_selectedDate)] ?? const [])
      ..sort((a, b) => a.startTime.compareTo(b.startTime));

    return Scaffold(
      appBar: AppBar(
        title: const Text('Calendar'),
        actions: [TextButton(onPressed: _goToToday, child: const Text('Today'))],
      ),
      body: RefreshIndicator(
        onRefresh: _load,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                IconButton(onPressed: () => _changeMonth(-1), icon: const Icon(Icons.chevron_left)),
                Text(
                  '${_monthNames[_visibleMonth.month - 1]} ${_visibleMonth.year}',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
                ),
                IconButton(onPressed: () => _changeMonth(1), icon: const Icon(Icons.chevron_right)),
              ],
            ),
            if (_isLoading) const LinearProgressIndicator(minHeight: 2),
            if (_error != null)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: Text(_error!, style: TextStyle(color: colorScheme.error)),
              ),
            const SizedBox(height: 8),
            Row(
              children: _weekdayLabels
                  .map((label) => Expanded(
                        child: Center(
                          child: Text(label, style: Theme.of(context).textTheme.labelSmall?.copyWith(color: colorScheme.outline)),
                        ),
                      ))
                  .toList(),
            ),
            const SizedBox(height: 4),
            _MonthGrid(
              visibleMonth: _visibleMonth,
              gridRange: _gridRange(_visibleMonth),
              selectedDate: _selectedDate,
              classesByDate: classesByDate,
              academyColors: academyColors,
              onSelect: (date) => setState(() => _selectedDate = date),
            ),
            if (isMultiAcademy) ...[
              const SizedBox(height: 12),
              Wrap(
                spacing: 12,
                runSpacing: 6,
                children: academyColors.entries.map((entry) {
                  final name = (_classes ?? const <CalendarClass>[])
                      .firstWhere((c) => c.academyId == entry.key, orElse: () => _classes!.first)
                      .academyName;
                  return Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(width: 10, height: 10, decoration: BoxDecoration(color: entry.value, shape: BoxShape.circle)),
                      const SizedBox(width: 6),
                      Text(name ?? 'Academy', style: Theme.of(context).textTheme.bodySmall),
                    ],
                  );
                }).toList(),
              ),
            ],
            const Divider(height: 32),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(_formatSelectedDate(_selectedDate), style: Theme.of(context).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700)),
                if (selectedDayClasses.isNotEmpty)
                  Text(
                    '${selectedDayClasses.length} ${selectedDayClasses.length == 1 ? 'class' : 'classes'}',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(color: colorScheme.outline),
                  ),
              ],
            ),
            const SizedBox(height: 8),
            if (selectedDayClasses.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 24),
                child: Center(
                  child: Text('No classes scheduled on this date.', style: TextStyle(color: colorScheme.outline)),
                ),
              )
            else
              ...selectedDayClasses.map((c) => _ClassTile(
                    classInfo: c,
                    color: academyColors[c.academyId] ?? colorScheme.primary,
                    showAcademyName: isMultiAcademy,
                  )),
          ],
        ),
      ),
    );
  }

  String _formatSelectedDate(DateTime d) {
    final today = DateTime.now();
    final prefix = _isSameDate(d, today) ? 'Today · ' : '';
    const weekdayNames = ['Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday', 'Sunday'];
    return '$prefix${weekdayNames[d.weekday - 1]}, ${d.day} ${_monthNames[d.month - 1]}';
  }
}

class _MonthGrid extends StatelessWidget {
  const _MonthGrid({
    required this.visibleMonth,
    required this.gridRange,
    required this.selectedDate,
    required this.classesByDate,
    required this.academyColors,
    required this.onSelect,
  });

  final DateTime visibleMonth;
  final ({DateTime start, DateTime end}) gridRange;
  final DateTime selectedDate;
  final Map<String, List<CalendarClass>> classesByDate;
  final Map<String, Color> academyColors;
  final void Function(DateTime date) onSelect;

  @override
  Widget build(BuildContext context) {
    final days = <DateTime>[];
    for (var d = gridRange.start; !d.isAfter(gridRange.end); d = d.add(const Duration(days: 1))) {
      days.add(d);
    }
    final today = DateTime.now();

    return GridView.count(
      crossAxisCount: 7,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      childAspectRatio: 1,
      children: days.map((day) {
        final inCurrentMonth = day.month == visibleMonth.month;
        final isSelected = _isSameDate(day, selectedDate);
        final isToday = _isSameDate(day, today);
        final dayClasses = classesByDate[_dateKey(day)] ?? const <CalendarClass>[];
        final dotColors = dayClasses.map((c) => academyColors[c.academyId]).whereType<Color>().toSet().toList();

        final colorScheme = Theme.of(context).colorScheme;
        return Padding(
          padding: const EdgeInsets.all(2),
          child: InkWell(
            borderRadius: BorderRadius.circular(10),
            onTap: () => onSelect(day),
            child: Container(
              decoration: BoxDecoration(
                color: isSelected ? colorScheme.primary : null,
                borderRadius: BorderRadius.circular(10),
                border: isToday && !isSelected ? Border.all(color: colorScheme.primary, width: 1.4) : null,
              ),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    '${day.day}',
                    style: TextStyle(
                      color: isSelected
                          ? colorScheme.onPrimary
                          : inCurrentMonth
                              ? null
                              : colorScheme.outline.withValues(alpha: 0.6),
                      fontWeight: isToday || isSelected ? FontWeight.w700 : null,
                    ),
                  ),
                  const SizedBox(height: 2),
                  SizedBox(
                    height: 6,
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: dotColors
                          .take(3)
                          .map((c) => Container(
                                width: 5,
                                height: 5,
                                margin: const EdgeInsets.symmetric(horizontal: 1),
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  color: isSelected ? colorScheme.onPrimary : c,
                                ),
                              ))
                          .toList(),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      }).toList(),
    );
  }
}

class _ClassTile extends StatelessWidget {
  const _ClassTile({required this.classInfo, required this.color, required this.showAcademyName});

  final CalendarClass classInfo;
  final Color color;
  final bool showAcademyName;

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        leading: Container(
          width: 4,
          margin: const EdgeInsets.symmetric(vertical: 4),
          decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(2)),
        ),
        minLeadingWidth: 4,
        title: Text('${_fmtTime(classInfo.startTime)} – ${_fmtTime(classInfo.endTime)}  ·  ${classInfo.batchName}'),
        subtitle: Text([
          if (classInfo.courseName != null) classInfo.courseName!,
          classInfo.status,
          if (showAcademyName && classInfo.academyName != null) classInfo.academyName!,
        ].join(' · ')),
      ),
    );
  }

  String _fmtTime(String hhmmss) {
    final parts = hhmmss.split(':');
    if (parts.length < 2) return hhmmss;
    final hour = int.tryParse(parts[0]) ?? 0;
    final minute = parts[1];
    final period = hour >= 12 ? 'PM' : 'AM';
    final hour12 = hour % 12 == 0 ? 12 : hour % 12;
    return '$hour12:$minute $period';
  }
}
