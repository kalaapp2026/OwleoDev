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
    this.badgeOf,
    this.alertBadges = false,
  });

  final List<T> options;
  final String Function(T) labelOf;
  final T selected;
  final ValueChanged<T> onTap;

  /// A small count pill after the label ("Regular 2"). Return null or 0 to show none - except
  /// when [showZeroBadges]-style callers want a 0, which they get by returning 0 with [alertBadges] off.
  final int? Function(T)? badgeOf;

  /// Red pills for "things needing attention" (fees due); otherwise neutral counts.
  final bool alertBadges;

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
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Flexible(
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
                    if (badgeOf?.call(o) case final count? when count > 0 || !alertBadges) ...[
                      const SizedBox(width: 5),
                      Container(
                        constraints: const BoxConstraints(minWidth: 16),
                        height: 16,
                        padding: const EdgeInsets.symmetric(horizontal: 4),
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          color: o == selected
                              ? Colors.white.withValues(alpha: 0.28)
                              : (alertBadges ? palette.notPaidSoft : palette.surface),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text(
                          '$count',
                          style: TextStyle(
                            fontSize: 9,
                            fontWeight: FontWeight.w800,
                            color: o == selected
                                ? Colors.white
                                : (alertBadges ? palette.notPaid : palette.textMuted),
                          ),
                        ),
                      ),
                    ],
                  ],
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
