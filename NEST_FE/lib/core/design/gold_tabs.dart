import 'package:flutter/material.dart';
import 'package:nest_fe/app/theme/app_tokens.dart';

/// The student screens' tab pill: a raised track with the selected tab filled gold - the
/// reference's treatment for Overview/Calendar/History, Regular/Other/Statement and the like.
/// (AppSegmentedControl is the teal, outlined one the staff screens use.)
class GoldTabs<T> extends StatelessWidget {
  const GoldTabs({
    super.key,
    required this.options,
    required this.labelOf,
    required this.selected,
    required this.onTap,
  });

  final List<T> options;
  final String Function(T) labelOf;
  final T selected;
  final ValueChanged<T> onTap;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: palette.surfaceHigh,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: palette.border),
      ),
      child: Row(children: [
        for (final o in options)
          Expanded(
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () => onTap(o),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 180),
                padding: const EdgeInsets.symmetric(vertical: 9),
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: o == selected ? palette.gold : Colors.transparent,
                  borderRadius: BorderRadius.circular(11),
                ),
                child: Text(
                  labelOf(o),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: o == selected ? Colors.white : palette.textMuted,
                  ),
                ),
              ),
            ),
          ),
      ]),
    );
  }
}

/// The gold academy pill under a student screen's header.
class AcademyPill extends StatelessWidget {
  const AcademyPill({super.key, required this.name});
  final String name;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return Align(
      alignment: Alignment.centerLeft,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: palette.goldSoft,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: palette.gold.withValues(alpha: 0.4)),
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(Icons.apartment_outlined, size: 12, color: palette.gold),
          const SizedBox(width: 6),
          Flexible(
            child: Text(name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: palette.gold)),
          ),
        ]),
      ),
    );
  }
}
