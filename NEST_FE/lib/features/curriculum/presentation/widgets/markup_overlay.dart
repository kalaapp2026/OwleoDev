import 'package:flutter/material.dart';

enum MarkupTool { pen, highlighter }

/// Draw over a document or image: a pen and a highlighter, undo and clear.
///
/// Marks live only for as long as the viewer is open - they are the student's scribbles while
/// reading, not an edit of the shared file (which other students also see). Strokes are stored
/// relative to the child's size, so they stay put if the layout changes.
class MarkupOverlay extends StatefulWidget {
  const MarkupOverlay({super.key, required this.child, required this.onToolChanged});

  final Widget child;

  /// So the host can switch off pan/zoom while a tool is active - otherwise every stroke would
  /// also drag the page.
  final ValueChanged<MarkupTool?> onToolChanged;

  @override
  State<MarkupOverlay> createState() => _MarkupOverlayState();
}

class _Stroke {
  _Stroke(this.tool, this.color, this.width);
  final MarkupTool tool;
  final Color color;
  final double width;
  final List<Offset> points = [];
}

class _MarkupOverlayState extends State<MarkupOverlay> {
  static const _penColors = [Color(0xFFE5545A), Color(0xFF2FE0C6), Colors.white];
  static const _highlightColors = [Color(0xFFF0B429), Color(0xFF2FE0C6), Color(0xFFFF8A5B)];

  final _strokes = <_Stroke>[];
  _Stroke? _current;
  MarkupTool? _tool;
  Color _color = _penColors.first;
  double _size = 1; // 0 thin, 1 medium, 2 thick

  void _setTool(MarkupTool? t) {
    setState(() {
      _tool = _tool == t ? null : t;
      if (_tool != null) {
        final palette = _tool == MarkupTool.pen ? _penColors : _highlightColors;
        if (!palette.contains(_color)) _color = palette.first;
      }
    });
    widget.onToolChanged(_tool);
  }

  double get _width {
    final i = _size.toInt();
    return _tool == MarkupTool.highlighter ? const [10.0, 16.0, 24.0][i] : const [1.5, 3.0, 5.0][i];
  }

  @override
  Widget build(BuildContext context) {
    return Stack(children: [
      Positioned.fill(
        child: LayoutBuilder(builder: (context, box) {
          final size = box.biggest;
          Offset norm(Offset p) => Offset(p.dx / size.width, p.dy / size.height);
          return Stack(children: [
            Positioned.fill(child: widget.child),
            Positioned.fill(
              child: IgnorePointer(
                ignoring: _tool == null,
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onPanStart: (d) {
                    _current = _Stroke(_tool!, _color, _width)..points.add(norm(d.localPosition));
                    setState(() {});
                  },
                  onPanUpdate: (d) => setState(() => _current?.points.add(norm(d.localPosition))),
                  onPanEnd: (_) {
                    if (_current != null && _current!.points.length > 1) _strokes.add(_current!);
                    setState(() => _current = null);
                  },
                  child: CustomPaint(
                    painter: _MarkupPainter([..._strokes, ?_current]),
                    size: Size.infinite,
                  ),
                ),
              ),
            ),
          ]);
        }),
      ),
      Positioned(
        left: 12,
        bottom: 12,
        right: 12,
        child: Center(child: _toolbar()),
      ),
    ]);
  }

  Widget _toolbar() {
    Widget tool(IconData icon, MarkupTool t, String tip) => IconButton(
          tooltip: tip,
          visualDensity: VisualDensity.compact,
          icon: Icon(icon, size: 20, color: _tool == t ? Colors.white : Colors.white70),
          style: IconButton.styleFrom(backgroundColor: _tool == t ? Colors.white24 : Colors.transparent),
          onPressed: () => _setTool(t),
        );
    final colors = _tool == MarkupTool.highlighter ? _highlightColors : _penColors;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(color: const Color(0xCC000000), borderRadius: BorderRadius.circular(30)),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        tool(Icons.edit_outlined, MarkupTool.pen, 'Pen'),
        tool(Icons.highlight_outlined, MarkupTool.highlighter, 'Highlighter'),
        if (_tool != null) ...[
          const SizedBox(width: 6),
          for (final c in colors)
            GestureDetector(
              onTap: () => setState(() => _color = c),
              child: Container(
                width: 18,
                height: 18,
                margin: const EdgeInsets.symmetric(horizontal: 3),
                decoration: BoxDecoration(
                  color: c,
                  shape: BoxShape.circle,
                  border: Border.all(color: _color == c ? Colors.white : Colors.white30, width: 2),
                ),
              ),
            ),
          const SizedBox(width: 6),
          for (var i = 0; i < 3; i++)
            GestureDetector(
              onTap: () => setState(() => _size = i.toDouble()),
              child: Container(
                width: 22,
                height: 22,
                alignment: Alignment.center,
                child: Container(
                  width: 5.0 + i * 3,
                  height: 5.0 + i * 3,
                  decoration: BoxDecoration(
                    color: _size == i ? Colors.white : Colors.white54,
                    shape: BoxShape.circle,
                  ),
                ),
              ),
            ),
        ],
        IconButton(
          tooltip: 'Undo',
          visualDensity: VisualDensity.compact,
          icon: const Icon(Icons.undo, size: 20, color: Colors.white70),
          onPressed: _strokes.isEmpty ? null : () => setState(_strokes.removeLast),
        ),
        IconButton(
          tooltip: 'Clear marks',
          visualDensity: VisualDensity.compact,
          icon: const Icon(Icons.delete_outline, size: 20, color: Colors.white70),
          onPressed: _strokes.isEmpty ? null : () => setState(_strokes.clear),
        ),
      ]),
    );
  }
}

class _MarkupPainter extends CustomPainter {
  _MarkupPainter(this.strokes);
  final List<_Stroke> strokes;

  @override
  void paint(Canvas canvas, Size size) {
    for (final s in strokes) {
      final paint = Paint()
        ..color = s.tool == MarkupTool.highlighter ? s.color.withValues(alpha: 0.38) : s.color
        ..strokeWidth = s.width
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round;
      final path = Path();
      for (var i = 0; i < s.points.length; i++) {
        final p = Offset(s.points[i].dx * size.width, s.points[i].dy * size.height);
        i == 0 ? path.moveTo(p.dx, p.dy) : path.lineTo(p.dx, p.dy);
      }
      canvas.drawPath(path, paint);
    }
  }

  @override
  bool shouldRepaint(covariant _MarkupPainter old) => true;
}
