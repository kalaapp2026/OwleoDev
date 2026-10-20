import 'package:flutter/material.dart';

import '../../app/theme.dart';
import 'primitives.dart';
import 'icons.dart';

/// The prototype's CSS grid classes. They break on the VIEWPORT width (media queries), not the
/// width of the container, and so does this.
enum GridKind {
  /// Four equal columns, two below 1180px.
  g4,

  /// Three equal columns, one below 1180px.
  g3,

  /// Two equal columns, one below 900px.
  g2,

  /// A wide column (1.7fr) and a narrow one (1fr); stacks below 1180px.
  g21,

  /// A narrow column (1fr) and a wide one (1.5fr); stacks below 1180px.
  g12,
}

class HqGrid extends StatelessWidget {
  const HqGrid(this.kind, this.children, {super.key, this.gap = 14, this.bottom = 14});

  final GridKind kind;
  final List<Widget> children;
  final double gap;

  /// Margin under the whole grid (`.grid{margin-bottom:14px}`).
  final double bottom;

  @override
  Widget build(BuildContext context) {
    final w = MediaQuery.sizeOf(context).width;
    final (cols, flex) = switch (kind) {
      GridKind.g4 => (w >= 1180 ? 4 : 2, <int>[1, 1, 1, 1]),
      GridKind.g3 => (w >= 1180 ? 3 : 1, <int>[1, 1, 1]),
      GridKind.g2 => (w >= 900 ? 2 : 1, <int>[1, 1]),
      GridKind.g21 => (w >= 1180 ? 2 : 1, <int>[17, 10]),
      GridKind.g12 => (w >= 1180 ? 2 : 1, <int>[10, 15]),
    };

    final rows = <Widget>[];
    for (var i = 0; i < children.length; i += cols) {
      final slice = children.sublist(i, i + cols > children.length ? children.length : i + cols);
      rows.add(
        IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (var k = 0; k < cols; k++) ...[
                if (k > 0) SizedBox(width: gap),
                Expanded(flex: flex[k % flex.length], child: k < slice.length ? slice[k] : const SizedBox.shrink()),
              ],
            ],
          ),
        ),
      );
    }
    return Padding(
      padding: EdgeInsets.only(bottom: bottom),
      child: Column(
        children: [
          for (var i = 0; i < rows.length; i++) ...[if (i > 0) SizedBox(height: gap), rows[i]],
        ],
      ),
    );
  }
}

/// Wraps a screen's content: centred, max 1240 wide, side padding that grows with the window.
class PageBody extends StatelessWidget {
  const PageBody({super.key, required this.children});
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final w = MediaQuery.sizeOf(context).width;
    final side = (w * .026).clamp(16.0, 34.0);
    return Align(
      alignment: Alignment.topCenter,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 1240),
        child: Padding(
          padding: EdgeInsets.fromLTRB(side, 0, side, 0),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: children),
        ),
      ),
    );
  }
}

/// One KPI card (`.kpi`): tinted icon, label, big value, a footnote and an optional delta/sparkline.
class Kpi extends StatelessWidget {
  const Kpi({
    super.key,
    required this.icon,
    required this.label,
    required this.value,
    this.tone = Tone.primary,
    this.foot,
    this.delta,
    this.valueColor,
    this.spark,
    this.onTap,
  });

  final String icon;
  final String label;
  final String value;
  final Tone tone;
  final String? foot;
  final Widget? delta;
  final Color? valueColor;
  final Widget? spark;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return HqCard(
      onTap: onTap,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              IconTile(icon, tone: tone),
              const SizedBox(width: 10),
              Expanded(child: Text(label, maxLines: 1, overflow: TextOverflow.ellipsis, style: HqText.kpiLabel)),
            ],
          ),
          const SizedBox(height: 10),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(value, maxLines: 1, style: HqText.kpiValue.copyWith(color: valueColor ?? Hq.text)),
          ),
          if (foot != null || delta != null) ...[
            const SizedBox(height: 10),
            Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Expanded(child: Text(foot ?? '', style: HqText.sub)),
                if (delta != null) ...[const SizedBox(width: 8), delta!],
              ],
            ),
          ],
          if (spark != null) ...[const SizedBox(height: 10), spark!],
        ],
      ),
    );
  }
}

/// `.mini`: a row of small stat boxes (value over caption), used at the top of drawers.
class MiniStats extends StatelessWidget {
  const MiniStats(this.items, {super.key, this.onTap});

  /// (value, caption, optional value colour)
  final List<(String, String, Color?)> items;
  final void Function(int index)? onTap;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 16),
      child: Row(
        children: [
          for (var i = 0; i < items.length; i++) ...[
            if (i > 0) const SizedBox(width: 8),
            Expanded(
              child: MouseRegion(
                cursor: onTap != null ? SystemMouseCursors.click : MouseCursor.defer,
                child: GestureDetector(
                  onTap: onTap == null ? null : () => onTap!(i),
                  child: Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: Hq.raised,
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: Hq.border),
                    ),
                    child: Stack(
                      children: [
                        SizedBox(
                          width: double.infinity,
                          child: Column(
                            children: [
                              FittedBox(
                                fit: BoxFit.scaleDown,
                                child: Text(items[i].$1, style: HqText.h2.copyWith(fontSize: 17, color: items[i].$3 ?? Hq.text)),
                              ),
                              Text(items[i].$2, style: HqText.small.copyWith(fontSize: 10, fontWeight: FontWeight.w600)),
                            ],
                          ),
                        ),
                        if (onTap != null) Positioned(right: -2, top: -2, child: ic('chev', 12, Hq.faint)),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// A two-line "label / value" row used all over the drawers (`<small>label</small><b>value</b>`).
class KeyValueRow extends StatelessWidget {
  const KeyValueRow(this.label, this.value, {super.key, this.trailing, this.valueColor});
  final String label;
  final String value;
  final Widget? trailing;
  final Color? valueColor;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label, style: HqText.small),
              Text(value, style: HqText.row.copyWith(color: valueColor ?? Hq.text)),
            ],
          ),
        ),
        if (trailing != null) ...[const SizedBox(width: 10), trailing!],
      ],
    );
  }
}
