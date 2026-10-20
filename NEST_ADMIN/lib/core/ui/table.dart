import 'package:flutter/material.dart';

import '../../app/theme.dart';

/// One column of an [HqTable]: a heading and how wide it is. A column with [flex] stretches to fill
/// spare room; one with a fixed [width] never does.
class HqCol {
  const HqCol(this.title, {this.width = 100, this.flex = 0, this.numeric = false});
  final String title;
  final double width;
  final int flex;

  /// Right-aligned, for figures that are compared down the column.
  final bool numeric;
}

/// `table`: header row, hairline-separated rows, hover highlight, horizontal scroll when the window
/// is narrower than the columns need (`min-width:1020px` in the prototype).
class HqTable extends StatelessWidget {
  const HqTable({super.key, required this.columns, required this.rows, this.onRowTap});

  final List<HqCol> columns;
  final List<List<Widget>> rows;
  final ValueChanged<int>? onRowTap;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, c) {
        // The table never gets narrower than its columns' own widths; a flex column's width is its minimum.
        final minWidth = columns.fold<double>(0, (s, k) => s + k.width);
        final totalFlex = columns.fold<int>(0, (s, k) => s + k.flex);
        final avail = c.maxWidth.isFinite ? c.maxWidth : minWidth;
        final width = avail < minWidth ? minWidth : avail;
        final extra = width - minWidth;

        double colWidth(HqCol k) => k.flex == 0 ? k.width : k.width + extra * k.flex / (totalFlex == 0 ? 1 : totalFlex);

        Widget cell(HqCol k, Widget w) => SizedBox(
              width: colWidth(k),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                child: Align(alignment: k.numeric ? Alignment.centerRight : Alignment.centerLeft, child: w),
              ),
            );

        final table = SizedBox(
          width: width,
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: Row(children: [
                  for (final k in columns)
                    cell(k, Text(k.title.toUpperCase(), maxLines: 2, textAlign: k.numeric ? TextAlign.right : TextAlign.left, style: HqText.th)),
                ]),
              ),
              for (var i = 0; i < rows.length; i++)
                _TableRow(
                  onTap: onRowTap == null ? null : () => onRowTap!(i),
                  child: Row(children: [for (var j = 0; j < columns.length; j++) cell(columns[j], rows[i][j])]),
                ),
            ],
          ),
        );
        if (avail >= minWidth) return table;
        return SingleChildScrollView(scrollDirection: Axis.horizontal, child: table);
      },
    );
  }
}

class _TableRow extends StatefulWidget {
  const _TableRow({required this.child, this.onTap});
  final Widget child;
  final VoidCallback? onTap;

  @override
  State<_TableRow> createState() => _TableRowState();
}

class _TableRowState extends State<_TableRow> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      cursor: widget.onTap == null ? MouseCursor.defer : SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: widget.onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 10),
          decoration: BoxDecoration(
            color: _hover ? const Color(0x8C1C2740) : Colors.transparent,
            border: const Border(top: BorderSide(color: Hq.soft)),
          ),
          child: widget.child,
        ),
      ),
    );
  }
}
