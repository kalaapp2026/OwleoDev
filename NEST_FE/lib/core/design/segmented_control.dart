import 'package:flutter/material.dart';
import 'package:nest_fe/app/theme/app_tokens.dart';
import 'package:nest_fe/app/theme/app_typography.dart';
import 'package:nest_fe/core/design/pressable.dart';

/// A pill of side-by-side choices, the selected one filled.
///
/// Used wherever the options are few, fixed and worth showing all at once - billing type, active
/// vs inactive, accepted payment methods. A dropdown would hide exactly the comparison the person
/// is trying to make.
///
/// The outer hairline is a translucent white rather than a palette border on purpose: it has to
/// read against both the filled segment and the empty ones, and a solid border colour disappears
/// into whichever of the two it was tuned for.
class AppSegmentedControl<T> extends StatelessWidget {
  const AppSegmentedControl({
    super.key,
    required this.options,
    required this.labelOf,
    required this.isSelected,
    required this.onTap,
    this.activeColorOf,
    this.activeTextColorOf,
  });

  final List<T> options;
  final String Function(T) labelOf;

  /// Membership rather than equality, so the same widget serves both the single-select controls
  /// and the multi-select payment-method row.
  final bool Function(T) isSelected;

  final ValueChanged<T> onTap;

  /// Per-option fill. Defaults to the primary accent; Active/Inactive uses green vs a flat
  /// surface, payment methods use gold.
  final Color Function(BuildContext, T)? activeColorOf;
  final Color Function(BuildContext, T)? activeTextColorOf;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    // Container's own border/borderRadius clip (Clip.antiAlias) clips a child to the OUTER edge
    // of the box, not inset for the border's own width - so a segment's flat-cornered fill was
    // painting right up to (and, at the first/last segment's corners, past) the pill's rounded
    // silhouette, on top of the border stroke instead of staying inside it. Explicit padding
    // equal to the border width keeps every fill strictly inside the stroke, and clipping the end
    // segments to the same pill radius keeps their outer corners rounded regardless of how the
    // parent's own clip behaves.
    const borderWidth = 1.5;
    final pillRadius = AppRadii.all(AppRadii.pill);

    return Container(
      padding: const EdgeInsets.all(borderWidth),
      decoration: BoxDecoration(
        border: Border.all(color: const Color(0x66FFFFFF), width: borderWidth),
        borderRadius: pillRadius,
      ),
      clipBehavior: Clip.antiAlias,
      child: Row(
        children: [
          for (var i = 0; i < options.length; i++)
            Expanded(
              child: ClipRRect(
                borderRadius: BorderRadius.only(
                  topLeft: i == 0 ? pillRadius.topLeft : Radius.zero,
                  bottomLeft: i == 0 ? pillRadius.bottomLeft : Radius.zero,
                  topRight: i == options.length - 1 ? pillRadius.topRight : Radius.zero,
                  bottomRight: i == options.length - 1 ? pillRadius.bottomRight : Radius.zero,
                ),
                child: _Segment(
                  label: labelOf(options[i]),
                  selected: isSelected(options[i]),
                  activeColor: activeColorOf?.call(context, options[i]) ?? palette.primary,
                  activeTextColor:
                      activeTextColorOf?.call(context, options[i]) ?? palette.onPrimary,
                  // Divider on every segment but the last, so the pill's own rounded edge isn't
                  // cut by a stray vertical line.
                  showDivider: i < options.length - 1,
                  onTap: () => onTap(options[i]),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _Segment extends StatelessWidget {
  const _Segment({
    required this.label,
    required this.selected,
    required this.activeColor,
    required this.activeTextColor,
    required this.showDivider,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final Color activeColor;
  final Color activeTextColor;
  final bool showDivider;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;

    return Pressable(
      onTap: onTap,
      child: AnimatedContainer(
        duration: AppMotion.fade,
        padding: const EdgeInsets.symmetric(vertical: 13),
        decoration: BoxDecoration(
          color: selected ? activeColor : Colors.transparent,
          border: showDivider
              ? const Border(right: BorderSide(color: Color(0x4DFFFFFF)))
              : null,
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            // The tick is the multi-select's only "on" signal beyond the fill, and it keeps the
            // single-select consistent with it.
            if (selected) ...[
              Icon(Icons.check_rounded, size: 14, weight: 800, color: activeTextColor),
              const SizedBox(width: AppSpacing.xs),
            ],
            Flexible(
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: AppType.md,
                  fontWeight: AppType.bold,
                  color: selected ? activeTextColor : palette.text,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
