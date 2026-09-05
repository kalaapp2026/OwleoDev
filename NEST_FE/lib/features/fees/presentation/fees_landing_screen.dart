import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:nest_fe/app/theme/app_tokens.dart';
import 'package:nest_fe/app/theme/app_typography.dart';
import 'package:nest_fe/core/design/attached_select.dart';
import 'package:nest_fe/core/design/calendar_modal.dart';
import 'package:nest_fe/core/design/pressable.dart';
import 'package:nest_fe/features/curriculum/data/curriculum_api.dart';
import 'package:nest_fe/features/enrolment/data/batch.dart';
import 'package:nest_fe/features/enrolment/data/enrolment_api.dart';
import 'package:nest_fe/features/fees/data/fee_summary.dart';
import 'package:nest_fe/features/fees/presentation/all_transactions_screen.dart';
import 'package:nest_fe/features/fees/presentation/fee_format.dart';
import 'package:nest_fe/features/fees/presentation/fees_screen.dart' show FeesScreen, feesApiProvider;
import 'package:nest_fe/features/fees/presentation/other_fees_screen.dart';
import 'package:nest_fe/features/fees/presentation/regular_fees_screen.dart';
import 'package:nest_fe/features/fees/presentation/student_profile_screen.dart';
import 'package:nest_fe/features/fees/presentation/widgets/revenue_card.dart';

typedef _SummaryKey = ({String period, String? courseId, String? batchId});

final _summaryProvider =
    FutureProvider.autoDispose.family<FeeSummary, _SummaryKey>((ref, key) {
  return ref.watch(feesApiProvider).summary(
        period: key.period,
        courseId: key.courseId,
        batchId: key.batchId,
      );
});

final _searchProvider =
    FutureProvider.autoDispose.family<List<StudentSearchResult>, String>((ref, query) {
  if (query.trim().isEmpty) return Future.value(const []);
  return ref.watch(feesApiProvider).searchStudents(query.trim());
});

enum _OpenFilter { none, course, batch }

/// Fees home: where both categories stand, and the way in to each.
class FeesLandingScreen extends ConsumerStatefulWidget {
  const FeesLandingScreen({super.key});

  @override
  ConsumerState<FeesLandingScreen> createState() => _FeesLandingScreenState();
}

class _FeesLandingScreenState extends ConsumerState<FeesLandingScreen> {
  DateTime _month = DateTime(DateTime.now().year, DateTime.now().month);
  String? _courseId;
  String? _courseName;
  String? _batchId;
  String? _batchName;
  _OpenFilter _open = _OpenFilter.none;

  /// Only one card opens at a time. They sit side by side, and two expanded cards make the pair
  /// tall enough to push everything below off the screen.
  String? _expandedCard;

  String _query = '';

  _SummaryKey get _key =>
      (period: periodOf(_month), courseId: _courseId, batchId: _batchId);

  void _stepMonth(int delta) =>
      setState(() => _month = DateTime(_month.year, _month.month + delta));

  Future<void> _pickMonth() async {
    final picked = await showAppCalendar(
      context: context,
      month: _month,
      latestMonth: DateTime(DateTime.now().year, DateTime.now().month),
    );
    if (picked != null) {
      setState(() => _month = DateTime(picked.year, picked.month));
    }
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final summaryAsync = ref.watch(_summaryProvider(_key));
    final coursesAsync = ref.watch(activeCoursesProvider);

    // No own Scaffold or AppBar - this renders inside AppShell's IndexedStack as the Fees tab.
    return ColoredBox(
      color: palette.bg,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(
            AppSpacing.xl, AppSpacing.md, AppSpacing.xl, AppSpacing.x5l),
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: coursesAsync.when(
                  loading: () => const _FilterPlaceholder(),
                  error: (_, _) => const _FilterPlaceholder(),
                  data: (courses) => AttachedSelect<dynamic>(
                    label: 'Course',
                    placeholder: 'All Courses',
                    options: courses,
                    labelOf: (c) => c.name as String,
                    value: courses.where((c) => c.id == _courseId).firstOrNull,
                    searchable: courses.length > 6,
                    // A half-width trigger opening a half-width panel truncates every course name.
                    panelSpan: PanelSpan.left,
                    isOpen: _open == _OpenFilter.course,
                    onOpenChanged: (o) =>
                        setState(() => _open = o ? _OpenFilter.course : _OpenFilter.none),
                    onSelected: (c) => setState(() {
                      _courseId = c.id as String;
                      _courseName = c.name as String;
                      // The batch filter belonged to the previous course.
                      _batchId = null;
                      _batchName = null;
                    }),
                  ),
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: _BatchFilter(
                  courseId: _courseId,
                  batchId: _batchId,
                  isOpen: _open == _OpenFilter.batch,
                  onOpenChanged: (o) =>
                      setState(() => _open = o ? _OpenFilter.batch : _OpenFilter.none),
                  onSelected: (b) => setState(() {
                    _batchId = b.id;
                    _batchName = b.name;
                  }),
                ),
              ),
            ],
          ),
          if (_courseId != null || _batchId != null) ...[
            const SizedBox(height: AppSpacing.sm),
            Row(
              children: [
                Expanded(
                  child: Text.rich(
                    TextSpan(
                      text: 'Showing: ',
                      style: TextStyle(fontSize: AppType.smd, color: palette.textFaint),
                      children: [
                        TextSpan(
                          text: '${_courseName ?? 'All courses'} · ${_batchName ?? 'All batches'}',
                          style: TextStyle(
                              fontWeight: AppType.bold, color: palette.text),
                        ),
                      ],
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                Pressable(
                  onTap: () => setState(() {
                    _courseId = null;
                    _courseName = null;
                    _batchId = null;
                    _batchName = null;
                  }),
                  child: Icon(Icons.close_rounded, size: 14, color: palette.textFaint),
                ),
              ],
            ),
          ],
          const SizedBox(height: AppSpacing.lg),
          summaryAsync.when(
            loading: () => const _CardsPlaceholder(),
            error: (e, _) => _InlineError(error: e),
            data: (summary) => IntrinsicHeight(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  RevenueCard(
                    label: 'Regular Fees',
                    icon: Icons.account_balance_wallet_outlined,
                    iconColor: palette.primary,
                    summary: summary.regular,
                    expanded: _expandedCard == 'regular',
                    onToggle: () => setState(() =>
                        _expandedCard = _expandedCard == 'regular' ? null : 'regular'),
                  ),
                  const SizedBox(width: AppSpacing.sm),
                  RevenueCard(
                    label: 'Other Fees',
                    icon: Icons.auto_awesome_outlined,
                    iconColor: palette.gateway,
                    summary: summary.other,
                    expanded: _expandedCard == 'other',
                    onToggle: () => setState(
                        () => _expandedCard = _expandedCard == 'other' ? null : 'other'),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: AppSpacing.xl),
          Row(
            children: [
              Expanded(
                child: _StudentSearch(
                  query: _query,
                  onChanged: (v) => setState(() => _query = v),
                  onOpen: (result) {
                    setState(() => _query = '');
                    Navigator.of(context).push(MaterialPageRoute(
                      builder: (_) => StudentProfileScreen(
                        membershipId: result.membershipId,
                        period: periodOf(_month),
                      ),
                    ));
                  },
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: _MonthControl(
                  label: shortMonthLabel(_month),
                  onPrevious: () => _stepMonth(-1),
                  onNext: _month.isBefore(DateTime(DateTime.now().year, DateTime.now().month))
                      ? () => _stepMonth(1)
                      : null,
                  onPick: _pickMonth,
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.xl),
          Text('Select fee category', style: AppType.sectionLabel(palette.textMuted)),
          const SizedBox(height: AppSpacing.sm),
          _CategoryCard(
            icon: Icons.account_balance_wallet_outlined,
            iconColor: palette.primary,
            iconBackground: palette.primarySoft,
            title: 'Regular Fees',
            subtitle: 'Monthly course & batch fees',
            onTap: () => Navigator.of(context).push(MaterialPageRoute(
              builder: (_) => const _RegularFeesPage(),
            )),
          ),
          const SizedBox(height: AppSpacing.md),
          _CategoryCard(
            icon: Icons.auto_awesome_outlined,
            iconColor: palette.gateway,
            iconBackground: palette.gatewaySoft,
            title: 'Other Fees',
            subtitle: 'Costume, annual day, audio & more',
            onTap: () => Navigator.of(context).push(MaterialPageRoute(
              builder: (_) => const OtherFeesScreen(),
            )),
          ),
          const SizedBox(height: AppSpacing.lg),
          _DashedButton(
            icon: Icons.receipt_long_outlined,
            label: 'View all transactions',
            onTap: () => Navigator.of(context).push(MaterialPageRoute(
              builder: (_) => const AllTransactionsScreen(),
            )),
          ),
          const SizedBox(height: AppSpacing.md),
          // The report download and fee slips still live on the old screen. Keeping a door to them
          // means the redesign doesn't take working features away before they are ported.
          Center(
            child: Pressable(
              onTap: () => Navigator.of(context).push(MaterialPageRoute(
                builder: (_) => const _LegacyFeesPage(),
              )),
              child: Padding(
                padding: const EdgeInsets.all(AppSpacing.xs),
                child: Text('Reports & fee slips',
                    style: TextStyle(fontSize: AppType.xs, color: palette.textMuted)),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Regular Fees pushed as its own page, with the chrome the tab version gets from the shell.
class _RegularFeesPage extends StatelessWidget {
  const _RegularFeesPage();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Regular Fees')),
      body: const RegularFeesScreen(),
    );
  }
}

class _LegacyFeesPage extends StatelessWidget {
  const _LegacyFeesPage();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Reports & fee slips')),
      body: const FeesScreen(),
    );
  }
}

class _BatchFilter extends ConsumerWidget {
  const _BatchFilter({
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
        locked: true,
        placeholder: 'All Batches',
        onSelected: (_) {},
      );
    }
    return ref.watch(batchesForCourseProvider(courseId!)).when(
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
              placeholder: 'All Batches',
              options: active,
              labelOf: (b) => b.name,
              value: active.where((b) => b.id == batchId).firstOrNull,
              // Grows leftward into the screen rather than off its right edge.
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

/// Search every student in the academy by name, from the landing.
class _StudentSearch extends ConsumerWidget {
  const _StudentSearch({
    required this.query,
    required this.onChanged,
    required this.onOpen,
  });

  final String query;
  final ValueChanged<String> onChanged;
  final ValueChanged<StudentSearchResult> onOpen;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final palette = context.palette;
    final results = query.trim().isEmpty
        ? const AsyncValue<List<StudentSearchResult>>.data([])
        : ref.watch(_searchProvider(query));

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        TextField(
          onChanged: onChanged,
          style: TextStyle(fontSize: AppType.smd, color: palette.text),
          decoration: InputDecoration(
            isDense: true,
            hintText: 'Search student',
            hintStyle: TextStyle(fontSize: AppType.smd, color: palette.textFaint),
            prefixIcon: Icon(Icons.search_rounded, size: 14, color: palette.textFaint),
            prefixIconConstraints: const BoxConstraints(minWidth: 30, minHeight: 30),
            filled: true,
            fillColor: palette.surfaceRaised,
            contentPadding:
                const EdgeInsets.symmetric(horizontal: AppSpacing.sm, vertical: 9),
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
        // Results sit inline rather than in an overlay: this is inside a scrolling list, and an
        // anchored panel would detach from the field as soon as the page moved.
        if (query.trim().isNotEmpty)
          results.when(
            loading: () => const SizedBox.shrink(),
            error: (_, _) => const SizedBox.shrink(),
            data: (list) => Container(
              margin: const EdgeInsets.only(top: AppSpacing.xs),
              constraints: const BoxConstraints(maxHeight: 200),
              decoration: BoxDecoration(
                color: palette.surface,
                borderRadius: AppRadii.all(AppRadii.lg),
                border: Border.all(color: palette.border),
              ),
              child: list.isEmpty
                  ? Padding(
                      padding: const EdgeInsets.all(AppSpacing.md),
                      child: Text('No students found',
                          textAlign: TextAlign.center,
                          style:
                              TextStyle(fontSize: AppType.xs, color: palette.textFaint)),
                    )
                  : ListView.builder(
                      shrinkWrap: true,
                      padding: EdgeInsets.zero,
                      itemCount: list.length,
                      itemBuilder: (context, i) => Pressable(
                        onTap: () => onOpen(list[i]),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                              horizontal: AppSpacing.md, vertical: AppSpacing.sm),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(list[i].studentName,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    fontSize: AppType.smd,
                                    fontWeight: AppType.semi,
                                    color: palette.text,
                                  )),
                              Text(list[i].context,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                      fontSize: AppType.tiny, color: palette.textFaint)),
                            ],
                          ),
                        ),
                      ),
                    ),
            ),
          ),
      ],
    );
  }
}

class _MonthControl extends StatelessWidget {
  const _MonthControl({
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
      padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 2),
      decoration: BoxDecoration(
        color: palette.surfaceRaised,
        borderRadius: AppRadii.all(AppRadii.lg),
        border: Border.all(color: palette.border),
      ),
      child: Row(
        children: [
          _Step(icon: Icons.chevron_left_rounded, onTap: onPrevious),
          Expanded(
            child: Pressable(
              onTap: onPick,
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 7),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.calendar_today_outlined, size: 12, color: palette.primary),
                    const SizedBox(width: 4),
                    Flexible(
                      child: Text(
                        label,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: AppType.smd,
                          fontWeight: AppType.bold,
                          color: palette.text,
                        ),
                      ),
                    ),
                  ],
                ),
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
        child: Icon(icon, size: 15,
            color: onTap == null ? palette.textFaint : palette.text),
      ),
    );
  }
}

class _CategoryCard extends StatelessWidget {
  const _CategoryCard({
    required this.icon,
    required this.iconColor,
    required this.iconBackground,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  final IconData icon;
  final Color iconColor;
  final Color iconBackground;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return Pressable(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(AppSpacing.lg),
        decoration: BoxDecoration(
          color: palette.surfaceRaised,
          borderRadius: AppRadii.all(AppRadii.x4l),
          border: Border.all(color: palette.border),
        ),
        child: Row(
          children: [
            Container(
              width: 44,
              height: 44,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: iconBackground,
                borderRadius: AppRadii.all(AppRadii.xl),
              ),
              child: Icon(icon, size: 22, color: iconColor),
            ),
            const SizedBox(width: AppSpacing.lg),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(title,
                      style: TextStyle(
                        fontSize: AppType.xxl,
                        fontWeight: AppType.bold,
                        color: palette.text,
                      )),
                  const SizedBox(height: 2),
                  Text(subtitle,
                      style: TextStyle(fontSize: AppType.smd, color: palette.textMuted)),
                ],
              ),
            ),
            Icon(Icons.chevron_right_rounded, size: 20, color: palette.textMuted),
          ],
        ),
      ),
    );
  }
}

class _DashedButton extends StatelessWidget {
  const _DashedButton({required this.icon, required this.label, required this.onTap});

  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return Pressable(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 13),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          borderRadius: AppRadii.all(AppRadii.xl),
          border: Border.all(color: palette.border),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 15, color: palette.revenue),
            const SizedBox(width: AppSpacing.sm),
            Text(label,
                style: TextStyle(
                  fontSize: AppType.md,
                  fontWeight: AppType.bold,
                  color: palette.textMuted,
                )),
            const SizedBox(width: AppSpacing.xs),
            Icon(Icons.chevron_right_rounded, size: 15, color: palette.textMuted),
          ],
        ),
      ),
    );
  }
}

class _FilterPlaceholder extends StatelessWidget {
  const _FilterPlaceholder();

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

class _CardsPlaceholder extends StatelessWidget {
  const _CardsPlaceholder();

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return Container(
      height: 190,
      decoration: BoxDecoration(
        color: palette.surfaceRaised,
        borderRadius: AppRadii.all(AppRadii.x3l),
      ),
    );
  }
}

class _InlineError extends StatelessWidget {
  const _InlineError({required this.error});

  final Object error;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return Container(
      padding: const EdgeInsets.all(AppSpacing.lg),
      decoration: BoxDecoration(
        color: palette.surfaceRaised,
        borderRadius: AppRadii.all(AppRadii.x3l),
        border: Border.all(color: palette.notPaid),
      ),
      child: Row(
        children: [
          Icon(Icons.error_outline_rounded, size: 18, color: palette.notPaid),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Text(
              error.toString().replaceFirst('Exception: ', ''),
              style: TextStyle(fontSize: AppType.smd, color: palette.textMuted),
            ),
          ),
        ],
      ),
    );
  }
}
