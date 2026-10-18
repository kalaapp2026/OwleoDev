import 'package:flutter/material.dart';
import 'package:nest_fe/app/theme/app_tokens.dart';
import 'package:nest_fe/app/theme/app_typography.dart';
import 'package:nest_fe/core/design/pressable.dart';

/// A row of equal-width outlined choices, the selected one tinted - the Events screens' treatment
/// for Upcoming/Past, Event type and Status.
///
/// An option can be shown but not yet available: pass [isEnabled] false and a [hintOf] such as
/// "Coming soon". It stays visible so people know it is planned, but cannot be tapped.
class AppChoiceChips<T> extends StatelessWidget {
  const AppChoiceChips({
    super.key,
    required this.options,
    required this.labelOf,
    required this.isSelected,
    required this.onTap,
    this.iconOf,
    this.isEnabled,
    this.hintOf,
  });

  final List<T> options;
  final String Function(T) labelOf;
  final bool Function(T) isSelected;
  final ValueChanged<T> onTap;
  final IconData? Function(T)? iconOf;
  final bool Function(T)? isEnabled;
  final String? Function(T)? hintOf;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (var i = 0; i < options.length; i++) ...[
            if (i > 0) const SizedBox(width: AppSpacing.md),
            Expanded(child: _chip(context, palette, options[i])),
          ],
        ],
      ),
    );
  }

  Widget _chip(BuildContext context, AppPalette palette, T option) {
    final selected = isSelected(option);
    final enabled = isEnabled?.call(option) ?? true;
    final hint = hintOf?.call(option);
    final icon = iconOf?.call(option);
    final fg = selected ? palette.primary : (enabled ? palette.textMuted : palette.textFaint);

    return Pressable(
      onTap: enabled ? () => onTap(option) : null,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md, vertical: 11),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: selected ? palette.primarySoft : palette.surfaceRaised,
          borderRadius: AppRadii.all(AppRadii.lg),
          border: Border.all(color: selected ? palette.primary : palette.border),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (icon != null) ...[Icon(icon, size: 14, color: fg), const SizedBox(width: 6)],
                Flexible(
                  child: Text(
                    labelOf(option),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: AppType.md, fontWeight: AppType.bold, color: fg),
                  ),
                ),
              ],
            ),
            if (hint != null)
              Padding(
                padding: const EdgeInsets.only(top: 2),
                child: Text(hint,
                    style: TextStyle(fontSize: AppType.tiny, fontWeight: AppType.semi, color: palette.gold)),
              ),
          ],
        ),
      ),
    );
  }
}
