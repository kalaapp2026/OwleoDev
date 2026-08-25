import 'package:flutter/material.dart';
import 'package:nest_fe/app/theme/app_tokens.dart';
import 'package:nest_fe/app/theme/app_typography.dart';
import 'package:nest_fe/core/design/buttons.dart';

/// Shared chrome for the design's bottom sheets: grab handle, uppercase title, rounded top.
class _SheetShell extends StatelessWidget {
  const _SheetShell({required this.title, required this.child, this.trailing, this.maxHeightFactor = 0.7});

  final String title;
  final Widget child;
  final Widget? trailing;
  final double maxHeightFactor;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return Container(
      constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(context).height * maxHeightFactor),
      decoration: BoxDecoration(
        color: palette.surface,
        borderRadius: AppRadii.sheetTop,
        border: Border.all(color: palette.border),
      ),
      padding: const EdgeInsets.fromLTRB(AppSpacing.sm, AppSpacing.md, AppSpacing.sm, AppSpacing.x3l),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 36,
            height: 4,
            margin: const EdgeInsets.only(top: AppSpacing.xs, bottom: AppSpacing.xl),
            decoration: BoxDecoration(color: palette.border, borderRadius: AppRadii.all(2)),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(AppSpacing.lg, 0, AppSpacing.lg, AppSpacing.md),
            child: Row(
              children: [
                Expanded(child: Text(title.toUpperCase(), style: AppType.sectionLabel(palette.textMuted))),
                ?trailing,
              ],
            ),
          ),
          Flexible(child: child),
        ],
      ),
    );
  }
}

/// Single-choice bottom sheet. Returns the chosen value, or null if dismissed.
///
/// [optionBuilder] lets a caller render a richer row (icon + hint) without this needing to know
/// about the option type - the download sheet uses it for "PDF Document / opens print dialog".
Future<T?> showAppOptionSheet<T>({
  required BuildContext context,
  required String title,
  required List<T> options,
  required String Function(T) labelOf,
  Widget Function(BuildContext, T)? optionBuilder,
}) {
  return showModalBottomSheet<T>(
    context: context,
    backgroundColor: Colors.transparent,
    isScrollControlled: true,
    // The design's own curve, so a sheet feels like the dropdowns and dialogs rather than
    // Material's default.
    transitionAnimationController: null,
    builder: (sheetContext) {
      final palette = sheetContext.palette;
      return _SheetShell(
        title: title,
        child: ListView.separated(
          shrinkWrap: true,
          padding: EdgeInsets.zero,
          itemCount: options.length,
          separatorBuilder: (_, _) => const SizedBox.shrink(),
          itemBuilder: (context, i) {
            final option = options[i];
            return InkWell(
              onTap: () => Navigator.of(sheetContext).pop(option),
              borderRadius: AppRadii.all(AppRadii.lg),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xl, vertical: 13),
                child: optionBuilder?.call(context, option) ??
                    Text(
                      labelOf(option),
                      style: TextStyle(
                        fontSize: AppType.x3l,
                        fontWeight: AppType.regular,
                        color: palette.text,
                      ),
                    ),
              ),
            );
          },
        ),
      );
    },
  );
}

/// Multi-select bottom sheet with a live selected-count and a Done button that stays disabled
/// while nothing is chosen. Returns the final selection, or null if dismissed.
Future<List<T>?> showAppMultiSelectSheet<T>({
  required BuildContext context,
  required String title,
  required List<T> options,
  required String Function(T) labelOf,
  List<T> initialSelection = const [],
  String doneLabel = 'Done',
}) {
  return showModalBottomSheet<List<T>>(
    context: context,
    backgroundColor: Colors.transparent,
    isScrollControlled: true,
    builder: (sheetContext) {
      final selected = <T>[...initialSelection];
      return StatefulBuilder(
        builder: (context, setSheetState) {
          final palette = context.palette;
          return _SheetShell(
            title: title,
            maxHeightFactor: 0.78,
            trailing: Text(
              '${selected.length} selected',
              style: TextStyle(
                fontSize: AppType.smd,
                fontWeight: AppType.bold,
                color: palette.primary,
              ),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Flexible(
                  child: ListView.builder(
                    shrinkWrap: true,
                    padding: EdgeInsets.zero,
                    itemCount: options.length,
                    itemBuilder: (context, i) {
                      final option = options[i];
                      final isSelected = selected.contains(option);
                      return InkWell(
                        onTap: () => setSheetState(() {
                          isSelected ? selected.remove(option) : selected.add(option);
                        }),
                        borderRadius: AppRadii.all(AppRadii.lg),
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: AppSpacing.xl, vertical: 13),
                          decoration: BoxDecoration(
                            color: isSelected ? palette.primarySoft : Colors.transparent,
                            borderRadius: AppRadii.all(AppRadii.lg),
                          ),
                          child: Row(
                            children: [
                              Expanded(
                                child: Text(
                                  labelOf(option),
                                  style: TextStyle(
                                    fontSize: AppType.x3l,
                                    fontWeight: AppType.regular,
                                    color: palette.text,
                                  ),
                                ),
                              ),
                              _Checkbox(checked: isSelected),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
                ),
                const SizedBox(height: AppSpacing.lg),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm),
                  child: AppPrimaryButton(
                    label: doneLabel,
                    icon: Icons.check,
                    onPressed: selected.isEmpty
                        ? null
                        : () => Navigator.of(sheetContext).pop(List<T>.from(selected)),
                  ),
                ),
              ],
            ),
          );
        },
      );
    },
  );
}

class _Checkbox extends StatelessWidget {
  const _Checkbox({required this.checked, this.size = 20});

  final bool checked;
  final double size;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return AnimatedContainer(
      duration: AppMotion.fade,
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: checked ? palette.primary : Colors.transparent,
        borderRadius: AppRadii.all(size * 0.3),
        border: Border.all(color: checked ? palette.primary : palette.border, width: 1.5),
      ),
      child: checked
          ? Icon(Icons.check, size: size * 0.65, color: palette.onPrimary, weight: 800)
          : null,
    );
  }
}

/// Exposed because the breakdown rows on the student profile use the same checkbox at a smaller
/// size, and duplicating it there would let the two drift.
class AppCheckbox extends StatelessWidget {
  const AppCheckbox({super.key, required this.checked, this.size = 20});

  final bool checked;
  final double size;

  @override
  Widget build(BuildContext context) => _Checkbox(checked: checked, size: size);
}
