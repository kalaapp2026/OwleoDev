import 'package:flutter/material.dart';

/// Layout rules for the Super Admin console, which is a WEB/desktop tool rather than a phone
/// screen - it's operated on a wide monitor, scanned rather than thumbed through, and shows dense
/// tabular data. The rest of the app stays mobile-first; only this console flips that priority.
///
/// It still degrades to a single column on a narrow window rather than breaking, so opening the
/// console on a phone shows something usable instead of a horizontally-scrolling mess.
class ConsoleBreakpoints {
  ConsoleBreakpoints._();

  /// Below this, fall back to the stacked phone-style layout.
  static const double compact = 700;

  /// Above this there's room for the full desktop treatment (widest stat rows, side-by-side panels).
  static const double wide = 1200;

  static bool isCompact(BuildContext context) => MediaQuery.sizeOf(context).width < compact;

  static bool isWide(BuildContext context) => MediaQuery.sizeOf(context).width >= wide;

  /// Stat tiles per row. A desktop console wastes its width with 2-up tiles; a phone can't fit 6.
  static int statColumns(BuildContext context) {
    final width = MediaQuery.sizeOf(context).width;
    if (width >= wide) return 6;
    if (width >= 950) return 4;
    if (width >= compact) return 3;
    return 2;
  }
}

/// Centres console content and caps its width. Without a cap, tables and charts stretch edge to
/// edge on an ultrawide monitor and become genuinely hard to read across.
class ConsolePage extends StatelessWidget {
  const ConsolePage({super.key, required this.children, this.maxWidth = 1400});

  final List<Widget> children;
  final double maxWidth;

  @override
  Widget build(BuildContext context) {
    final horizontal = ConsoleBreakpoints.isCompact(context) ? 16.0 : 32.0;
    return Align(
      alignment: Alignment.topCenter,
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: maxWidth),
        child: ListView(
          padding: EdgeInsets.fromLTRB(horizontal, 20, horizontal, 40),
          children: children,
        ),
      ),
    );
  }
}

class ConsoleSectionTitle extends StatelessWidget {
  const ConsoleSectionTitle(this.text, {super.key, this.trailing});

  final String text;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12, top: 4),
      child: Row(
        children: [
          Expanded(
            child: Text(
              text.toUpperCase(),
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w700,
                letterSpacing: 0.8,
                color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.55),
              ),
            ),
          ),
          ?trailing,
        ],
      ),
    );
  }
}

/// A single headline number. Sized for scanning a row of them at a glance.
class ConsoleStat {
  const ConsoleStat(this.label, this.value, this.icon, {this.footnote, this.tone});

  final String label;
  final String value;
  final IconData icon;
  final String? footnote;

  /// Optional semantic colour - used sparingly, only where a number means "needs attention"
  /// (suspended tenants, pending approvals) rather than for decoration.
  final Color? tone;
}

class ConsoleStatGrid extends StatelessWidget {
  const ConsoleStatGrid({super.key, required this.stats});

  final List<ConsoleStat> stats;

  @override
  Widget build(BuildContext context) {
    final columns = ConsoleBreakpoints.statColumns(context);
    return GridView.count(
      crossAxisCount: columns,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      mainAxisSpacing: 12,
      crossAxisSpacing: 12,
      childAspectRatio: ConsoleBreakpoints.isCompact(context) ? 1.7 : 1.75,
      children: stats.map((s) => _ConsoleStatCard(stat: s)).toList(),
    );
  }
}

class _ConsoleStatCard extends StatelessWidget {
  const _ConsoleStatCard({required this.stat});

  final ConsoleStat stat;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final accent = stat.tone ?? colorScheme.primary;
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(stat.icon, color: accent, size: 20),
            const Spacer(),
            FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerLeft,
              child: Text(
                stat.value,
                style: Theme.of(context)
                    .textTheme
                    .headlineSmall
                    ?.copyWith(fontWeight: FontWeight.w700, color: accent),
              ),
            ),
            const SizedBox(height: 2),
            Text(
              stat.label,
              style: Theme.of(context).textTheme.bodySmall,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            if (stat.footnote != null)
              Text(
                stat.footnote!,
                style: TextStyle(fontSize: 10, color: colorScheme.onSurface.withValues(alpha: 0.45)),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
          ],
        ),
      ),
    );
  }
}

/// Status pill - encodes state in shape and colour as well as text, so a suspended tenant is
/// visible when scanning a long table rather than needing to be read.
class ConsoleStatusChip extends StatelessWidget {
  const ConsoleStatusChip({super.key, required this.status});

  final String status;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final suspended = status == 'SUSPENDED';
    final color = suspended ? colorScheme.error : Colors.green.shade600;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        status.toLowerCase(),
        style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: color),
      ),
    );
  }
}
