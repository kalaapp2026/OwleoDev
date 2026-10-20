import 'package:flutter/material.dart';

import '../../app/theme.dart';
import 'icons.dart';
import 'primitives.dart';

/// `.osec`: a form section that folds away, with an icon, a one-line summary and a status badge
/// ("Done" / "Incomplete") so a long form can be scanned without opening every part.
class CollapsibleSection extends StatelessWidget {
  const CollapsibleSection({
    super.key,
    required this.icon,
    required this.title,
    required this.summary,
    required this.open,
    required this.onToggle,
    required this.child,
    this.badge,
    this.badgeTone = Tone.green,
  });

  final String icon;
  final String title;
  final String summary;
  final bool open;
  final VoidCallback onToggle;
  final Widget child;
  final String? badge;
  final Tone badgeTone;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: Hq.raised,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: Hq.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          MouseRegion(
            cursor: SystemMouseCursors.click,
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: onToggle,
              child: Padding(
                padding: const EdgeInsets.all(14),
                child: Row(
                  children: [
                    IconTile(icon, tone: Tone.primary, size: 38, iconSize: 19),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(title, style: HqText.row.copyWith(fontSize: 14)),
                          Text(summary, maxLines: 1, overflow: TextOverflow.ellipsis, style: HqText.small),
                        ],
                      ),
                    ),
                    if (badge != null) ...[Tag(badge!, tone: badgeTone), const SizedBox(width: 8)],
                    AnimatedRotation(turns: open ? .5 : 0, duration: const Duration(milliseconds: 160), child: ic('chevd', 18, Hq.muted)),
                  ],
                ),
              ),
            ),
          ),
          if (open)
            Container(
              padding: const EdgeInsets.fromLTRB(14, 14, 14, 2),
              decoration: const BoxDecoration(border: Border(top: BorderSide(color: Hq.soft))),
              child: child,
            ),
        ],
      ),
    );
  }
}

/// The header of a full-screen form: back arrow, title, subtitle (`.obtop`).
class FormTopBar extends StatelessWidget {
  const FormTopBar({super.key, required this.title, required this.subtitle, required this.onBack});
  final String title, subtitle;
  final VoidCallback onBack;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 18),
      child: Row(
        children: [
          MouseRegion(
            cursor: SystemMouseCursors.click,
            child: GestureDetector(
              onTap: onBack,
              child: Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(color: Hq.raised, borderRadius: BorderRadius.circular(13), border: Border.all(color: Hq.border)),
                child: Center(child: ic('back', 20, Hq.text)),
              ),
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: HqText.h2),
                Text(subtitle, maxLines: 1, overflow: TextOverflow.ellipsis, style: HqText.muted),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Two fields side by side, stacking under 480px (`.frow`).
class FieldRow extends StatelessWidget {
  const FieldRow(this.children, {super.key});
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    if (MediaQuery.sizeOf(context).width < 480) {
      return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: children);
    }
    return Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
      for (var i = 0; i < children.length; i++) ...[if (i > 0) const SizedBox(width: 12), Expanded(child: children[i])],
    ]);
  }
}
