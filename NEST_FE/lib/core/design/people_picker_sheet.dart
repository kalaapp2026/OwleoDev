import 'package:flutter/material.dart';
import 'package:nest_fe/app/theme/app_tokens.dart';
import 'package:nest_fe/app/theme/app_typography.dart';
import 'package:nest_fe/core/design/avatar.dart';
import 'package:nest_fe/core/design/buttons.dart';
import 'package:nest_fe/core/design/pressable.dart';

/// One selectable person. [subtitle] carries whatever disambiguates them in this context - the
/// courses a trainer teaches, a student's batch - since two people can share a first name and an
/// avatar colour.
@immutable
class PickablePerson {
  const PickablePerson({
    required this.id,
    required this.name,
    this.subtitle,
    this.imageUrl,
  });

  final String id;
  final String name;
  final String? subtitle;
  final String? imageUrl;
}

/// A searchable multi-select sheet for choosing people.
///
/// Returns the chosen ids, or null if dismissed - so a caller can tell "picked nobody" (an empty
/// set) apart from "changed their mind" (null) and avoid wiping an existing selection.
///
/// Selection is held internally and only handed back on Done. Committing per tap would make an
/// accidental deselection on a 40-student roster silently destructive.
Future<Set<String>?> showPeoplePickerSheet({
  required BuildContext context,
  required String title,
  required List<PickablePerson> people,
  required Set<String> initiallySelected,
  Color? accentColor,
  String searchHint = 'Search',
  String emptyLabel = 'No one to show here yet.',
}) {
  return showModalBottomSheet<Set<String>>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    barrierColor: const Color(0xB8040710),
    builder: (sheetContext) => _PeoplePickerSheet(
      title: title,
      people: people,
      initiallySelected: initiallySelected,
      accentColor: accentColor ?? sheetContext.palette.primary,
      searchHint: searchHint,
      emptyLabel: emptyLabel,
    ),
  );
}

class _PeoplePickerSheet extends StatefulWidget {
  const _PeoplePickerSheet({
    required this.title,
    required this.people,
    required this.initiallySelected,
    required this.accentColor,
    required this.searchHint,
    required this.emptyLabel,
  });

  final String title;
  final List<PickablePerson> people;
  final Set<String> initiallySelected;
  final Color accentColor;
  final String searchHint;
  final String emptyLabel;

  @override
  State<_PeoplePickerSheet> createState() => _PeoplePickerSheetState();
}

class _PeoplePickerSheetState extends State<_PeoplePickerSheet> {
  late final Set<String> _selected = {...widget.initiallySelected};
  final _searchController = TextEditingController();
  String _query = '';

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  List<PickablePerson> get _filtered {
    final q = _query.trim().toLowerCase();
    if (q.isEmpty) return widget.people;
    return widget.people
        .where((p) =>
            p.name.toLowerCase().contains(q) ||
            (p.subtitle?.toLowerCase().contains(q) ?? false))
        .toList();
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final filtered = _filtered;

    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: Container(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.sizeOf(context).height * 0.86,
        ),
        decoration: BoxDecoration(
          color: palette.surface,
          borderRadius: AppRadii.sheetTop,
          border: Border.all(color: palette.border),
        ),
        clipBehavior: Clip.antiAlias,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 36,
              height: 4,
              margin: const EdgeInsets.only(top: AppSpacing.md, bottom: AppSpacing.xxs),
              decoration: BoxDecoration(
                color: palette.border,
                borderRadius: AppRadii.all(2),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(
                  AppSpacing.xxl, AppSpacing.sm, AppSpacing.xxl, AppSpacing.lg),
              child: Column(
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        widget.title,
                        style: TextStyle(
                          fontSize: AppType.xxl,
                          fontWeight: AppType.bold,
                          color: palette.text,
                        ),
                      ),
                      Text(
                        '${_selected.length} selected',
                        style: TextStyle(
                          fontSize: AppType.smd,
                          fontWeight: AppType.bold,
                          color: widget.accentColor,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: AppSpacing.lg),
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: AppSpacing.lg, vertical: AppSpacing.md),
                    decoration: BoxDecoration(
                      color: palette.surfaceRaised,
                      borderRadius: AppRadii.all(AppRadii.lg),
                      border: Border.all(color: palette.border),
                    ),
                    child: Row(
                      children: [
                        Icon(Icons.search, size: 14, color: palette.textFaint),
                        const SizedBox(width: AppSpacing.sm),
                        Expanded(
                          child: TextField(
                            controller: _searchController,
                            onChanged: (v) => setState(() => _query = v),
                            style: TextStyle(
                              fontSize: AppType.lg,
                              fontWeight: AppType.regular,
                              color: palette.text,
                            ),
                            decoration: InputDecoration(
                              isDense: true,
                              border: InputBorder.none,
                              contentPadding: EdgeInsets.zero,
                              hintText: widget.searchHint,
                              hintStyle:
                                  TextStyle(fontSize: AppType.lg, color: palette.textFaint),
                            ),
                          ),
                        ),
                        if (_query.isNotEmpty)
                          Pressable(
                            onTap: () {
                              _searchController.clear();
                              setState(() => _query = '');
                            },
                            child: Icon(Icons.close_rounded,
                                size: 13, color: palette.textFaint),
                          ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            Flexible(
              child: filtered.isEmpty
                  ? Padding(
                      padding: const EdgeInsets.all(AppSpacing.x4l),
                      child: Text(
                        widget.people.isEmpty ? widget.emptyLabel : 'No matches',
                        textAlign: TextAlign.center,
                        style: TextStyle(fontSize: AppType.base, color: palette.textFaint),
                      ),
                    )
                  : ListView.builder(
                      shrinkWrap: true,
                      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm),
                      itemCount: filtered.length,
                      itemBuilder: (context, i) {
                        final person = filtered[i];
                        final selected = _selected.contains(person.id);
                        return Pressable(
                          onTap: () => setState(() {
                            if (!_selected.remove(person.id)) _selected.add(person.id);
                          }),
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: AppSpacing.lg, vertical: AppSpacing.md),
                            decoration: BoxDecoration(
                              color: selected
                                  ? widget.accentColor.withValues(alpha: 0.08)
                                  : Colors.transparent,
                              borderRadius: AppRadii.all(AppRadii.lg),
                            ),
                            child: Row(
                              children: [
                                PersonAvatar(
                                  name: person.name,
                                  seed: person.id,
                                  size: 32,
                                ),
                                const SizedBox(width: AppSpacing.lg),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Text(
                                        person.name,
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: TextStyle(
                                          fontSize: AppType.xxl,
                                          fontWeight:
                                              selected ? AppType.semi : AppType.regular,
                                          color:
                                              selected ? palette.text : palette.textMuted,
                                        ),
                                      ),
                                      if (person.subtitle != null)
                                        Padding(
                                          padding: const EdgeInsets.only(top: 1),
                                          child: Text(
                                            person.subtitle!,
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                            style: TextStyle(
                                              fontSize: AppType.xs,
                                              color: palette.textFaint,
                                            ),
                                          ),
                                        ),
                                    ],
                                  ),
                                ),
                                const SizedBox(width: AppSpacing.sm),
                                Container(
                                  width: 20,
                                  height: 20,
                                  alignment: Alignment.center,
                                  decoration: BoxDecoration(
                                    shape: BoxShape.circle,
                                    color: selected
                                        ? widget.accentColor
                                        : Colors.transparent,
                                    border: Border.all(
                                      color: selected
                                          ? widget.accentColor
                                          : palette.border,
                                      width: 1.5,
                                    ),
                                  ),
                                  child: selected
                                      ? Icon(Icons.check,
                                          size: 13,
                                          weight: 900,
                                          color: palette.onPrimary)
                                      : null,
                                ),
                              ],
                            ),
                          ),
                        );
                      },
                    ),
            ),
            Container(
              padding: EdgeInsets.fromLTRB(AppSpacing.xxl, AppSpacing.lg, AppSpacing.xxl,
                  AppSpacing.xxl + MediaQuery.paddingOf(context).bottom),
              decoration: BoxDecoration(
                border: Border(top: BorderSide(color: palette.borderSoft)),
              ),
              child: AppPrimaryButton(
                label: 'Done',
                icon: Icons.check,
                onPressed: () => Navigator.of(context).pop(_selected),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
