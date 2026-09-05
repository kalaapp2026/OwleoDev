import 'package:flutter/material.dart';
import 'package:nest_fe/app/theme/app_tokens.dart';
import 'package:nest_fe/app/theme/app_typography.dart';
import 'package:nest_fe/core/design/pressable.dart';
import 'package:nest_fe/features/scheduling/data/schedule_entry.dart';

/// The reason picker shared by the reschedule, cancel and recurring-change flows.
///
/// Presets rather than a bare text field because these are the same six answers almost every
/// time, and typing a sentence on a phone is what makes people leave the reason blank. "Other"
/// reveals a free-text field so the uncommon case is still expressible.
class ReasonChips extends StatelessWidget {
  const ReasonChips({
    super.key,
    required this.selected,
    required this.customReason,
    required this.accent,
    required this.softAccent,
    required this.onSelected,
    required this.onCustomChanged,
  });

  final String selected;
  final String customReason;
  final Color accent;
  final Color softAccent;
  final ValueChanged<String> onSelected;
  final ValueChanged<String> onCustomChanged;

  /// What actually gets sent: the free text when "Other" is chosen and something was typed,
  /// otherwise the preset. Falls back to the literal "Other" rather than an empty reason.
  static String resolve(String selected, String customReason) {
    if (selected != 'Other') return selected;
    final trimmed = customReason.trim();
    return trimmed.isEmpty ? 'Other' : trimmed;
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Wrap(
          spacing: AppSpacing.xs,
          runSpacing: AppSpacing.xs,
          children: [
            for (final reason in scheduleChangeReasons)
              Pressable(
                onTap: () => onSelected(reason),
                child: AnimatedContainer(
                  duration: AppMotion.fade,
                  padding: const EdgeInsets.symmetric(
                      horizontal: AppSpacing.lg, vertical: 7),
                  decoration: BoxDecoration(
                    color: selected == reason ? softAccent : palette.surfaceRaised,
                    borderRadius: AppRadii.all(AppRadii.pill),
                    border: Border.all(
                        color: selected == reason ? accent : palette.border),
                  ),
                  child: Text(
                    reason,
                    style: TextStyle(
                      fontSize: AppType.smd,
                      fontWeight: AppType.bold,
                      color: selected == reason ? accent : palette.textMuted,
                    ),
                  ),
                ),
              ),
          ],
        ),
        if (selected == 'Other') ...[
          const SizedBox(height: AppSpacing.md),
          TextField(
            autofocus: true,
            onChanged: onCustomChanged,
            style: TextStyle(
                fontSize: AppType.xxl, fontWeight: AppType.medium, color: palette.text),
            decoration: InputDecoration(
              isDense: true,
              hintText: 'Add a short note',
              hintStyle: TextStyle(
                  fontSize: AppType.lg,
                  fontWeight: AppType.regular,
                  color: palette.textFaint),
              filled: true,
              fillColor: palette.surfaceRaised,
              contentPadding: const EdgeInsets.symmetric(
                  horizontal: AppSpacing.xl, vertical: AppSpacing.lg),
              border: OutlineInputBorder(
                borderRadius: AppRadii.all(AppRadii.xl),
                borderSide: BorderSide(color: palette.border),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: AppRadii.all(AppRadii.xl),
                borderSide: BorderSide(color: palette.border),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: AppRadii.all(AppRadii.xl),
                borderSide: BorderSide(color: accent),
              ),
            ),
          ),
        ],
      ],
    );
  }
}
