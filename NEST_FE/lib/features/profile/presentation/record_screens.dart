import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:nest_fe/app/theme/app_tokens.dart';
import 'package:nest_fe/app/theme/app_typography.dart';
import 'package:nest_fe/core/design/attached_select.dart';
import 'package:nest_fe/core/design/app_date_picker.dart';
import 'package:nest_fe/core/design/buttons.dart';
import 'package:nest_fe/core/design/confirm_dialog.dart';
import 'package:nest_fe/core/error/api_exception.dart';
import 'package:nest_fe/core/widgets/app_notice.dart';
import 'package:nest_fe/core/widgets/async_value_view.dart';
import 'package:nest_fe/features/profile/data/self_profile.dart';
import 'package:nest_fe/features/profile/data/self_profile_api.dart';
import 'package:nest_fe/features/profile/presentation/profile_widgets.dart';

/// An academy as the forms need it - just enough to label and key a dropdown.
typedef AcademyChoice = ({String id, String name});

// ---------------------------------------------------------------------------
// Cards
// ---------------------------------------------------------------------------

String? _academyShort(List<AcademyChoice> academies, String? id) {
  for (final a in academies) {
    if (a.id == id) {
      final parts = a.name.trim().split(RegExp(r'\s+')).where((p) => p.isNotEmpty).toList();
      return parts.take(2).map((p) => p[0]).join().toUpperCase();
    }
  }
  return null;
}

class _RecordCard extends StatelessWidget {
  const _RecordCard({
    required this.icon,
    required this.color,
    required this.title,
    required this.body,
    required this.badge,
    required this.trailing,
    required this.date,
    required this.academyShort,
    required this.onTap,
  });
  final IconData icon;
  final Color color;
  final String title;
  final String body;
  final String badge;
  final String? trailing;
  final DateTime date;
  final String? academyShort;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return ProfileCard(
      onTap: onTap,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          IconTile(icon: icon, color: color),
          const SizedBox(width: AppSpacing.lg),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(title,
                          style: TextStyle(fontSize: AppType.md, fontWeight: AppType.heavy, color: palette.text, height: 1.3)),
                    ),
                    if (onTap != null) Icon(Icons.edit_outlined, size: 12, color: palette.textFaint),
                  ],
                ),
                if (body.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 3),
                    child: Text(body, style: TextStyle(fontSize: AppType.sm, color: palette.textMuted, height: 1.45)),
                  ),
                const SizedBox(height: AppSpacing.md),
                Wrap(
                  spacing: 6,
                  runSpacing: 4,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2.5),
                      decoration: BoxDecoration(
                        color: color.withValues(alpha: 0.1),
                        borderRadius: AppRadii.all(AppRadii.sm),
                        border: Border.all(color: color.withValues(alpha: 0.27)),
                      ),
                      child: Text(badge, style: TextStyle(fontSize: 10, fontWeight: AppType.bold, color: color)),
                    ),
                    if (trailing != null)
                      Text(trailing!, style: TextStyle(fontSize: AppType.tiny, fontWeight: AppType.bold, color: palette.text)),
                    Text(longDate(date), style: TextStyle(fontSize: AppType.tiny, color: palette.textFaint)),
                    if (academyShort != null)
                      Text('· $academyShort', style: TextStyle(fontSize: AppType.tiny, color: palette.textFaint)),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class AchievementCard extends StatelessWidget {
  const AchievementCard({super.key, required this.achievement, required this.academies, this.onTap});
  final Achievement achievement;
  final List<AcademyChoice> academies;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final type = AchievementType.of(achievement.type);
    final color = type.color(context.palette);
    return _RecordCard(
      icon: type.icon,
      color: color,
      title: achievement.title,
      body: achievement.description,
      badge: type.label,
      trailing: null,
      date: achievement.date,
      academyShort: _academyShort(academies, achievement.academyId),
      onTap: onTap,
    );
  }
}

class PerformanceLogCard extends StatelessWidget {
  const PerformanceLogCard({super.key, required this.log, required this.academies, this.onTap});
  final PerformanceLog log;
  final List<AcademyChoice> academies;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final category = PerformanceCategory.of(log.category);
    final color = category.color(context.palette);
    return _RecordCard(
      icon: category.icon,
      color: color,
      title: log.title,
      body: log.notes,
      badge: category.label,
      trailing: log.result,
      date: log.date,
      academyShort: _academyShort(academies, log.academyId),
      onTap: onTap,
    );
  }
}

// ---------------------------------------------------------------------------
// Full lists
// ---------------------------------------------------------------------------

class AchievementsScreen extends ConsumerWidget {
  const AchievementsScreen({super.key, required this.academies, required this.defaultAcademyId});
  final List<AcademyChoice> academies;
  final String? defaultAcademyId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final palette = context.palette;
    Future<void> open([Achievement? existing]) async {
      await Navigator.of(context).push(MaterialPageRoute(
        builder: (_) => AchievementFormScreen(existing: existing, academies: academies, defaultAcademyId: defaultAcademyId),
      ));
    }

    return Scaffold(
      backgroundColor: palette.bg,
      appBar: AppBar(
        title: const Text('Achievements'),
        actions: [TextButton.icon(onPressed: open, icon: const Icon(Icons.add, size: 16), label: const Text('Add'))],
      ),
      body: AsyncValueView(
        value: ref.watch(achievementsProvider),
        onRetry: () => ref.invalidate(achievementsProvider),
        data: (context, list) => list.isEmpty
            ? const Padding(padding: EdgeInsets.all(AppSpacing.page), child: ProfileEmptyNote('No achievements added yet.'))
            : ListView.separated(
                padding: const EdgeInsets.all(AppSpacing.xxl),
                itemCount: list.length,
                separatorBuilder: (_, _) => const SizedBox(height: AppSpacing.lg),
                itemBuilder: (_, i) => AchievementCard(achievement: list[i], academies: academies, onTap: () => open(list[i])),
              ),
      ),
    );
  }
}

class PerformanceLogScreen extends ConsumerWidget {
  const PerformanceLogScreen({super.key, required this.academies, required this.defaultAcademyId});
  final List<AcademyChoice> academies;
  final String? defaultAcademyId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final palette = context.palette;
    Future<void> open([PerformanceLog? existing]) async {
      await Navigator.of(context).push(MaterialPageRoute(
        builder: (_) => PerformanceLogFormScreen(existing: existing, academies: academies, defaultAcademyId: defaultAcademyId),
      ));
    }

    return Scaffold(
      backgroundColor: palette.bg,
      appBar: AppBar(
        title: const Text('Performance Log'),
        actions: [TextButton.icon(onPressed: open, icon: const Icon(Icons.add, size: 16), label: const Text('Add'))],
      ),
      body: AsyncValueView(
        value: ref.watch(performanceLogsProvider),
        onRetry: () => ref.invalidate(performanceLogsProvider),
        data: (context, list) => list.isEmpty
            ? const Padding(padding: EdgeInsets.all(AppSpacing.page), child: ProfileEmptyNote('No performance logs added yet.'))
            : ListView.separated(
                padding: const EdgeInsets.all(AppSpacing.xxl),
                itemCount: list.length,
                separatorBuilder: (_, _) => const SizedBox(height: AppSpacing.lg),
                itemBuilder: (_, i) => PerformanceLogCard(log: list[i], academies: academies, onTap: () => open(list[i])),
              ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Forms
// ---------------------------------------------------------------------------

/// Academy dropdown shared by both forms. Hidden for a person with fewer than two academies -
/// there is nothing to choose.
class _AcademyField extends StatelessWidget {
  const _AcademyField({required this.academies, required this.value, required this.onChanged});
  final List<AcademyChoice> academies;
  final String? value;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    if (academies.length < 2) return const SizedBox.shrink();
    AcademyChoice? current;
    for (final a in academies) {
      if (a.id == value) current = a;
    }
    return Padding(
      padding: const EdgeInsets.only(top: AppSpacing.xxl),
      child: AttachedSelect<AcademyChoice>(
        label: 'Academy',
        options: academies,
        value: current,
        labelOf: (a) => a.name,
        onSelected: (a) => onChanged(a.id),
      ),
    );
  }
}

class AchievementFormScreen extends ConsumerStatefulWidget {
  const AchievementFormScreen({super.key, this.existing, required this.academies, required this.defaultAcademyId});
  final Achievement? existing;
  final List<AcademyChoice> academies;
  final String? defaultAcademyId;

  @override
  ConsumerState<AchievementFormScreen> createState() => _AchievementFormScreenState();
}

class _AchievementFormScreenState extends ConsumerState<AchievementFormScreen> {
  late final _title = TextEditingController(text: widget.existing?.title);
  late final _description = TextEditingController(text: widget.existing?.description);
  late String _type = widget.existing?.type ?? 'AWARD';
  late DateTime _date = widget.existing?.date ?? DateTime.now();
  late String? _academyId = widget.existing?.academyId ?? widget.defaultAcademyId;
  bool _saving = false;

  bool get _editing => widget.existing != null;
  bool get _canSave => _title.text.trim().isNotEmpty;

  @override
  void dispose() {
    _title.dispose();
    _description.dispose();
    super.dispose();
  }

  Future<void> _pickDate() async {
    final picked = await showAppDatePicker(
        context: context, title: 'Date', value: _date, maxDate: DateTime.now().add(const Duration(days: 1)));
    if (picked != null) setState(() => _date = picked);
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    try {
      await ref.read(selfProfileApiProvider).saveAchievement(widget.existing?.id, {
        'title': _title.text.trim(),
        'description': _description.text.trim(),
        'type': _type,
        'date': wireDate(_date),
        'academyId': _academyId,
      });
      ref.invalidate(achievementsProvider);
      if (mounted) {
        AppNotice.success(context, _editing ? 'Achievement updated.' : 'Achievement added.');
        Navigator.of(context).pop();
      }
    } on ApiException catch (e) {
      if (mounted) AppNotice.error(context, e.message);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _delete() async {
    final ok = await showAppConfirmDialog(
        context: context,
        title: 'Delete achievement?',
        message: 'This cannot be undone.',
        confirmLabel: 'Delete',
        cancelLabel: 'Cancel');
    if (!ok) return;
    try {
      await ref.read(selfProfileApiProvider).deleteAchievement(widget.existing!.id);
      ref.invalidate(achievementsProvider);
      if (mounted) {
        AppNotice.success(context, 'Achievement deleted.');
        Navigator.of(context).pop();
      }
    } on ApiException catch (e) {
      if (mounted) AppNotice.error(context, e.message);
    }
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return Scaffold(
      backgroundColor: palette.bg,
      appBar: AppBar(
        title: Text(_editing ? 'Edit Achievement' : 'Add Achievement'),
        actions: [if (_editing) DeleteAction(onPressed: _delete)],
      ),
      body: ListView(
        padding: const EdgeInsets.all(AppSpacing.page),
        children: [
          LabeledTextField(
              label: 'Title', controller: _title, hint: 'e.g. Annual Day — Best Performer', onChanged: (_) => setState(() {})),
          const SizedBox(height: AppSpacing.xxl),
          LabeledTextField(label: 'Description', controller: _description, hint: 'What was this for?', maxLines: 3),
          const SizedBox(height: AppSpacing.xxl),
          const FormLabel('Type'),
          ChipChoices<AchievementType>(
            options: AchievementType.all,
            selected: AchievementType.of(_type),
            labelOf: (t) => t.label,
            iconOf: (t) => t.icon,
            colorOf: (t) => t.color(palette),
            onSelected: (t) => setState(() => _type = t.wire),
          ),
          const SizedBox(height: AppSpacing.xxl),
          PickerField(label: 'Date', text: longDate(_date), icon: Icons.calendar_today_outlined, onTap: _pickDate),
          _AcademyField(academies: widget.academies, value: _academyId, onChanged: (id) => setState(() => _academyId = id)),
          const SizedBox(height: AppSpacing.x5l),
          AppPrimaryButton(
            label: _editing ? 'Save changes' : 'Add achievement',
            icon: Icons.check,
            busy: _saving,
            onPressed: _canSave ? _save : null,
          ),
        ],
      ),
    );
  }
}

class PerformanceLogFormScreen extends ConsumerStatefulWidget {
  const PerformanceLogFormScreen({super.key, this.existing, required this.academies, required this.defaultAcademyId});
  final PerformanceLog? existing;
  final List<AcademyChoice> academies;
  final String? defaultAcademyId;

  @override
  ConsumerState<PerformanceLogFormScreen> createState() => _PerformanceLogFormScreenState();
}

class _PerformanceLogFormScreenState extends ConsumerState<PerformanceLogFormScreen> {
  late final _title = TextEditingController(text: widget.existing?.title);
  late final _result = TextEditingController(text: widget.existing?.result);
  late final _notes = TextEditingController(text: widget.existing?.notes);
  late String _category = widget.existing?.category ?? 'EXAM';
  late DateTime _date = widget.existing?.date ?? DateTime.now();
  late String? _academyId = widget.existing?.academyId ?? widget.defaultAcademyId;
  bool _saving = false;

  bool get _editing => widget.existing != null;
  bool get _canSave => _title.text.trim().isNotEmpty && _result.text.trim().isNotEmpty;

  @override
  void dispose() {
    _title.dispose();
    _result.dispose();
    _notes.dispose();
    super.dispose();
  }

  Future<void> _pickDate() async {
    final picked = await showAppDatePicker(
        context: context, title: 'Date', value: _date, maxDate: DateTime.now().add(const Duration(days: 1)));
    if (picked != null) setState(() => _date = picked);
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    try {
      await ref.read(selfProfileApiProvider).saveLog(widget.existing?.id, {
        'title': _title.text.trim(),
        'category': _category,
        'result': _result.text.trim(),
        'date': wireDate(_date),
        'academyId': _academyId,
        'notes': _notes.text.trim(),
      });
      ref.invalidate(performanceLogsProvider);
      if (mounted) {
        AppNotice.success(context, _editing ? 'Performance log updated.' : 'Performance log added.');
        Navigator.of(context).pop();
      }
    } on ApiException catch (e) {
      if (mounted) AppNotice.error(context, e.message);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _delete() async {
    final ok = await showAppConfirmDialog(
        context: context,
        title: 'Delete performance log?',
        message: 'This cannot be undone.',
        confirmLabel: 'Delete',
        cancelLabel: 'Cancel');
    if (!ok) return;
    try {
      await ref.read(selfProfileApiProvider).deleteLog(widget.existing!.id);
      ref.invalidate(performanceLogsProvider);
      if (mounted) {
        AppNotice.success(context, 'Performance log deleted.');
        Navigator.of(context).pop();
      }
    } on ApiException catch (e) {
      if (mounted) AppNotice.error(context, e.message);
    }
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return Scaffold(
      backgroundColor: palette.bg,
      appBar: AppBar(
        title: Text(_editing ? 'Edit Performance Log' : 'Add Performance Log'),
        actions: [if (_editing) DeleteAction(onPressed: _delete)],
      ),
      body: ListView(
        padding: const EdgeInsets.all(AppSpacing.page),
        children: [
          LabeledTextField(
              label: 'Title', controller: _title, hint: 'e.g. Term 2 Practical Exam', onChanged: (_) => setState(() {})),
          const SizedBox(height: AppSpacing.xxl),
          const FormLabel('Category'),
          ChipChoices<PerformanceCategory>(
            options: PerformanceCategory.all,
            selected: PerformanceCategory.of(_category),
            labelOf: (c) => c.label,
            iconOf: (c) => c.icon,
            colorOf: (c) => c.color(palette),
            onSelected: (c) => setState(() => _category = c.wire),
          ),
          const SizedBox(height: AppSpacing.xxl),
          LabeledTextField(
              label: 'Result / score',
              controller: _result,
              hint: 'e.g. 92/100, Excellent, Level 2 Cleared',
              onChanged: (_) => setState(() {})),
          const SizedBox(height: AppSpacing.xxl),
          PickerField(label: 'Date', text: longDate(_date), icon: Icons.calendar_today_outlined, onTap: _pickDate),
          _AcademyField(academies: widget.academies, value: _academyId, onChanged: (id) => setState(() => _academyId = id)),
          const SizedBox(height: AppSpacing.xxl),
          LabeledTextField(label: 'Notes (optional)', controller: _notes, hint: 'Any additional context', maxLines: 3),
          const SizedBox(height: AppSpacing.x5l),
          AppPrimaryButton(
            label: _editing ? 'Save changes' : 'Add performance log',
            icon: Icons.check,
            busy: _saving,
            onPressed: _canSave ? _save : null,
          ),
        ],
      ),
    );
  }
}
