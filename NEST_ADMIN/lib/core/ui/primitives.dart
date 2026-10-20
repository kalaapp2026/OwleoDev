import 'package:flutter/material.dart';

import '../../app/theme.dart';
import 'icons.dart';

/// `.card`: raised surface, 1px border, 18px radius.
class HqCard extends StatelessWidget {
  const HqCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(18),
    this.color,
    this.borderColor,
    this.radius = Hq.radiusCard,
    this.onTap,
    this.margin,
  });

  final Widget child;
  final EdgeInsetsGeometry padding;
  final Color? color;
  final Color? borderColor;
  final double radius;
  final VoidCallback? onTap;
  final EdgeInsetsGeometry? margin;

  @override
  Widget build(BuildContext context) {
    Widget card = Container(
      margin: margin,
      padding: padding,
      decoration: BoxDecoration(
        color: color ?? Hq.raised,
        borderRadius: BorderRadius.circular(radius),
        border: Border.all(color: borderColor ?? Hq.border),
      ),
      child: child,
    );
    if (onTap != null) {
      card = MouseRegion(cursor: SystemMouseCursors.click, child: GestureDetector(onTap: onTap, child: card));
    }
    return card;
  }
}

/// `.ch`: a card's title row - heading, optional sub-line, optional trailing control.
class CardHeader extends StatelessWidget {
  const CardHeader(this.title, {super.key, this.sub, this.trailing, this.bottom = 14});

  final String title;
  final String? sub;
  final Widget? trailing;
  final double bottom;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(bottom: bottom),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: HqText.h3),
                if (sub != null) Padding(padding: const EdgeInsets.only(top: 1), child: Text(sub!, style: HqText.sub)),
              ],
            ),
          ),
          if (trailing != null) ...[const SizedBox(width: 12), trailing!],
        ],
      ),
    );
  }
}

/// `.tile`: the 32px rounded square that holds an icon, tinted by tone.
class IconTile extends StatelessWidget {
  const IconTile(this.icon, {super.key, this.tone = Tone.primary, this.size = 32, this.iconSize = 17});

  final String icon;
  final Tone tone;
  final double size;
  final double iconSize;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(color: tone.soft, borderRadius: BorderRadius.circular(size * .31)),
      child: Center(child: ic(icon, iconSize, tone.color)),
    );
  }
}

/// `.tag`: small uppercase status label.
class Tag extends StatelessWidget {
  const Tag(this.text, {super.key, this.tone = Tone.mute, this.icon, this.lowercase = false});

  final String text;
  final Tone tone;
  final String? icon;
  final bool lowercase;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(color: tone.soft, borderRadius: BorderRadius.circular(8)),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[ic(icon!, 11, tone.color), const SizedBox(width: 5)],
          Flexible(
            child: Text(
              lowercase ? text : text.toUpperCase(),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: HqText.tag(tone.color),
            ),
          ),
        ],
      ),
    );
  }
}

/// `.delta`: a green/red up-or-down pill. [good] says whether "up" is the good direction (expenses
/// going up is red).
class Delta extends StatelessWidget {
  const Delta(this.value, {super.key, this.suffix = '%', this.good = true});

  final double value;
  final String suffix;
  final bool good;

  @override
  Widget build(BuildContext context) {
    final up = value >= 0;
    final tone = (up == good) ? Tone.green : Tone.red;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(color: tone.soft, borderRadius: BorderRadius.circular(9)),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          ic(up ? 'up' : 'down', 12, tone.color),
          const SizedBox(width: 3),
          Text('${value.abs().toStringAsFixed(1)}$suffix',
              style: HqText.tag(tone.color).copyWith(fontSize: 11.5, letterSpacing: 0)),
        ],
      ),
    );
  }
}

/// `.av`: round (or rounded-square) initials badge in a tone.
class Avatar extends StatelessWidget {
  const Avatar(this.label, {super.key, this.tone = Tone.primary, this.size = 36, this.square = false, this.icon});

  final String label;
  final Tone tone;
  final double size;
  final bool square;
  final String? icon;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: Hq.tint(tone.color),
        border: Border.all(color: Hq.tint(tone.color, .38)),
        borderRadius: BorderRadius.circular(square ? 11 : size),
      ),
      child: Center(
        child: icon != null
            ? ic(icon!, size * .44, tone.color)
            : Text(label, style: TextStyle(fontSize: size * .35, fontWeight: FontWeight.w800, color: tone.color)),
      ),
    );
  }
}

/// `.bar`: thin progress bar. [value] is 0-100.
class HqBar extends StatelessWidget {
  const HqBar(this.value, {super.key, this.tone = Tone.primary, this.height = 6});

  final double value;
  final Tone tone;
  final double height;

  @override
  Widget build(BuildContext context) {
    final f = (value / 100).clamp(0.0, 1.0);
    return ClipRRect(
      borderRadius: BorderRadius.circular(height / 2),
      child: Container(
        height: height,
        color: Hq.high,
        alignment: Alignment.centerLeft,
        child: FractionallySizedBox(widthFactor: f, child: Container(color: tone.color)),
      ),
    );
  }
}

/// `.meter`: label + value over a bar.
class Meter extends StatelessWidget {
  const Meter(this.label, this.valueText, this.value, {super.key, this.tone = Tone.primary});

  final String label;
  final String valueText;
  final double value;
  final Tone tone;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Flexible(child: Text(label, style: HqText.bodyStrong.copyWith(fontSize: 12.5))),
              Text(valueText, style: HqText.bodyStrong.copyWith(fontSize: 12.5, color: tone.color)),
            ],
          ),
          const SizedBox(height: 6),
          HqBar(value, tone: tone),
        ],
      ),
    );
  }
}

/// `.list` + `.row`: rows separated by a hairline, first row flush with the top.
class HqList extends StatelessWidget {
  const HqList(this.rows, {super.key});
  final List<Widget> rows;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (var i = 0; i < rows.length; i++)
          Container(
            padding: EdgeInsets.only(top: i == 0 ? 0 : 10, bottom: 10),
            decoration: BoxDecoration(border: i == 0 ? null : const Border(top: BorderSide(color: Hq.soft))),
            child: rows[i],
          ),
      ],
    );
  }
}

/// The common row: optional leading, a title + sub-line, optional trailing. Tapping is optional.
class HqRow extends StatelessWidget {
  const HqRow({
    super.key,
    this.leading,
    required this.title,
    this.sub,
    this.trailing,
    this.onTap,
    this.wrap = false,
    this.titleStyle,
  });

  final Widget? leading;
  final String title;
  final String? sub;
  final Widget? trailing;
  final VoidCallback? onTap;

  /// Let the title and sub-line wrap onto several lines instead of ellipsising.
  final bool wrap;
  final TextStyle? titleStyle;

  @override
  Widget build(BuildContext context) {
    final row = Row(
      children: [
        if (leading != null) ...[leading!, const SizedBox(width: 11)],
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title,
                  maxLines: wrap ? null : 1,
                  overflow: wrap ? null : TextOverflow.ellipsis,
                  style: titleStyle ?? HqText.row),
              if (sub != null)
                Text(sub!, maxLines: wrap ? null : 1, overflow: wrap ? null : TextOverflow.ellipsis, style: HqText.small),
            ],
          ),
        ),
        if (trailing != null) ...[const SizedBox(width: 11), trailing!],
      ],
    );
    if (onTap == null) return row;
    return MouseRegion(cursor: SystemMouseCursors.click, child: GestureDetector(behavior: HitTestBehavior.opaque, onTap: onTap, child: row));
  }
}

/// `.empty`: the quiet "nothing here" line.
class EmptyNote extends StatelessWidget {
  const EmptyNote(this.text, {super.key, this.padding = 22});
  final String text;
  final double padding;

  @override
  Widget build(BuildContext context) => Padding(
        padding: EdgeInsets.all(padding),
        child: Center(child: Text(text, textAlign: TextAlign.center, style: HqText.muted.copyWith(color: Hq.faint))),
      );
}

/// `.note`: the small footnote under a page.
class PageNote extends StatelessWidget {
  const PageNote(this.text, {super.key});
  final String text;

  @override
  Widget build(BuildContext context) =>
      Padding(padding: const EdgeInsets.fromLTRB(2, 6, 2, 0), child: Text(text, style: HqText.sub));
}

/// The uppercase micro-heading used to group tiles and settings.
class SectionLabel extends StatelessWidget {
  const SectionLabel(this.text, {super.key, this.top = 0});
  final String text;
  final double top;

  @override
  Widget build(BuildContext context) => Padding(
        padding: EdgeInsets.fromLTRB(2, top, 2, 10),
        child: Text(text.toUpperCase(), style: HqText.section),
      );
}

/// Centred spinner for a screen that is still loading.
class HqLoading extends StatelessWidget {
  const HqLoading({super.key});

  @override
  Widget build(BuildContext context) => const Padding(
        padding: EdgeInsets.symmetric(vertical: 60),
        child: Center(
          child: SizedBox(width: 26, height: 26, child: CircularProgressIndicator(strokeWidth: 2.5, color: Hq.primary)),
        ),
      );
}

/// A failed load, with a retry.
class HqError extends StatelessWidget {
  const HqError(this.message, {super.key, this.onRetry});
  final String message;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    return HqCard(
      child: Column(
        children: [
          IconTile('warn', tone: Tone.red, size: 44, iconSize: 22),
          const SizedBox(height: 12),
          Text(message, textAlign: TextAlign.center, style: HqText.muted),
          if (onRetry != null) ...[
            const SizedBox(height: 12),
            OutlinedButton(onPressed: onRetry, child: const Text('Try again')),
          ],
        ],
      ),
    );
  }
}

/// Stand-in for a module whose screen has not been built yet.
class ComingSoon extends StatelessWidget {
  const ComingSoon(this.title, {super.key});
  final String title;

  @override
  Widget build(BuildContext context) {
    return HqCard(
      padding: const EdgeInsets.symmetric(vertical: 40, horizontal: 18),
      child: Column(
        children: [
          const IconTile('clock', tone: Tone.gold, size: 48, iconSize: 22),
          const SizedBox(height: 12),
          Text(title, style: HqText.title),
          const SizedBox(height: 6),
          Text('This module is being built.', style: HqText.muted),
        ],
      ),
    );
  }
}
