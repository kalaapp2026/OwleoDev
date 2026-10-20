import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../app/theme.dart';
import '../format.dart';
import 'controls.dart';

enum SeriesType { bar, area, line }

class ChartSeries {
  const ChartSeries(this.name, this.color, this.type, this.values, {this.dash = false, this.hideInTip = false});

  final String name;
  final Color color;
  final SeriesType type;
  final List<double> values;
  final bool dash;

  /// Leave out of the hover tooltip.
  final bool hideInTip;
}

/// The prototype's hand-drawn SVG charts, drawn with a [CustomPainter]. One shared scale per
/// chart, nice round axis steps, bars/areas/lines in any mix, optional stacking, a hover
/// tooltip, a clickable legend that focuses one series, and 3M / 6M / All range chips once there
/// are enough points.
class HqChart extends StatefulWidget {
  const HqChart({
    super.key,
    required this.labels,
    required this.series,
    this.tipLabels,
    this.height = 230,
    this.stack = false,
    this.axisFmt,
    this.tipFmt,
    this.leftPad = 46,
    this.noRange = false,
    this.showLegend,
    this.onLegend,
  });

  final List<String> labels;
  final List<String>? tipLabels;
  final List<ChartSeries> series;
  final double height;
  final bool stack;

  /// Formats the y-axis ticks. Defaults to plain grouped numbers.
  final String Function(double)? axisFmt;

  /// Formats values in the tooltip. Defaults to [axisFmt].
  final String Function(double)? tipFmt;
  final double leftPad;
  final bool noRange;

  /// Force the legend on or off. By default it shows when there is more than one series.
  final bool? showLegend;
  final ValueChanged<String>? onLegend;

  @override
  State<HqChart> createState() => _HqChartState();
}

class _HqChartState extends State<HqChart> {
  final Set<String> _off = {};
  int _range = 0; // 0 = all
  int? _hover;

  List<T> _slice<T>(List<T> a) => _range > 0 && a.length > _range ? a.sublist(a.length - _range) : a;

  void _legend(String name) {
    final all = widget.series.map((s) => s.name).toList();
    final visible = all.where((n) => !_off.contains(n)).toList();
    setState(() {
      if (visible.length == all.length) {
        _off
          ..clear()
          ..addAll(all.where((n) => n != name));
      } else if (!_off.contains(name)) {
        if (visible.length == 1) {
          _off.clear();
        } else {
          _off.add(name);
        }
      } else {
        _off.remove(name);
      }
    });
    widget.onLegend?.call(name);
  }

  @override
  Widget build(BuildContext context) {
    final fmt = widget.axisFmt ?? (v) => num0(v);
    final tfmt = widget.tipFmt ?? fmt;
    final labels = _slice(widget.labels);
    final tips = widget.tipLabels == null ? null : _slice(widget.tipLabels!);
    final visible = widget.series.where((s) => !_off.contains(s.name)).map((s) => (s: s, v: _slice(s.values))).toList();
    final showRange = widget.labels.length >= 9 && !widget.noRange;
    final showLegend = widget.showLegend ?? widget.series.length > 1;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (showRange)
          Align(
            alignment: Alignment.centerRight,
            child: Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: SegControl<int>(
                dense: true,
                items: const [(3, '3M'), (6, '6M'), (0, 'All')],
                value: _range,
                onChanged: (v) => setState(() {
                  _range = v;
                  _hover = null;
                }),
              ),
            ),
          ),
        // The height is fixed up front (from the window width, not the chart's own width) so the
        // grid's equal-height rows can measure this card; a LayoutBuilder alone cannot be measured.
        SizedBox(
          height: math.min(widget.height, MediaQuery.sizeOf(context).width < 480 ? 200.0 : 999.0),
          child: LayoutBuilder(
            builder: (ctx, c) {
              final w = c.maxWidth.isFinite ? c.maxWidth : 320.0;
              return _ChartBody(
                width: w,
                height: c.maxHeight,
                labels: labels,
                tipLabels: tips,
                series: visible,
                stack: widget.stack,
                axisFmt: fmt,
                tipFmt: tfmt,
                leftPad: widget.leftPad,
                hover: _hover,
                onHover: (i) => setState(() => _hover = i),
              );
            },
          ),
        ),
        if (showLegend)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Wrap(
              spacing: 14,
              runSpacing: 4,
              children: [
                for (final s in widget.series.where((s) => !s.hideInTip))
                  MouseRegion(
                    cursor: SystemMouseCursors.click,
                    child: GestureDetector(
                      onTap: () => _legend(s.name),
                      child: Opacity(
                        opacity: _off.contains(s.name) ? .38 : 1,
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Container(width: 9, height: 9, decoration: BoxDecoration(color: s.color, borderRadius: BorderRadius.circular(3))),
                            const SizedBox(width: 6),
                            Text(s.name,
                                style: HqText.small.copyWith(
                                  decoration: _off.contains(s.name) ? TextDecoration.lineThrough : null,
                                )),
                          ],
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
      ],
    );
  }
}

class _ChartBody extends StatelessWidget {
  const _ChartBody({
    required this.width,
    required this.height,
    required this.labels,
    required this.tipLabels,
    required this.series,
    required this.stack,
    required this.axisFmt,
    required this.tipFmt,
    required this.leftPad,
    required this.hover,
    required this.onHover,
  });

  final double width, height;
  final List<String> labels;
  final List<String>? tipLabels;
  final List<({ChartSeries s, List<double> v})> series;
  final bool stack;
  final String Function(double) axisFmt, tipFmt;
  final double leftPad;
  final int? hover;
  final ValueChanged<int?> onHover;

  static const _pr = 10.0;

  @override
  Widget build(BuildContext context) {
    final n = labels.length;
    final iw = width - leftPad - _pr;
    final bw = n == 0 ? 1.0 : iw / n;

    int? indexAt(Offset p) {
      if (n == 0) return null;
      return ((p.dx - leftPad) / bw).floor().clamp(0, n - 1);
    }

    final hi = hover;
    return MouseRegion(
      onHover: (e) => onHover(indexAt(e.localPosition)),
      onExit: (_) => onHover(null),
      child: GestureDetector(
        onTapDown: (d) => onHover(indexAt(d.localPosition)),
        onPanUpdate: (d) => onHover(indexAt(d.localPosition)),
        onPanEnd: (_) => onHover(null),
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            CustomPaint(
              size: Size(width, height),
              painter: _ChartPainter(
                labels: labels,
                series: series,
                stack: stack,
                axisFmt: axisFmt,
                leftPad: leftPad,
                hover: hi,
              ),
            ),
            if (hi != null && n > 0) _tooltip(hi, iw, bw),
          ],
        ),
      ),
    );
  }

  Widget _tooltip(int i, double iw, double bw) {
    final cx = leftPad + (i + .5) * bw;
    const tw = 170.0;
    final left = (cx > width / 2 ? cx - tw - 12 : cx + 12).clamp(0.0, math.max(0.0, width - tw)).toDouble();
    return Positioned(
      left: left,
      top: 6,
      width: tw,
      child: IgnorePointer(
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 9),
          decoration: BoxDecoration(
            color: Hq.high,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: Hq.border),
            boxShadow: const [BoxShadow(color: Color(0x80000000), blurRadius: 28, offset: Offset(0, 12))],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(tipLabels?[i] ?? labels[i], style: HqText.small.copyWith(fontWeight: FontWeight.w700)),
              const SizedBox(height: 5),
              for (final e in series.where((e) => !e.s.hideInTip))
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 1.5),
                  child: Row(
                    children: [
                      Container(width: 8, height: 8, decoration: BoxDecoration(color: e.s.color, borderRadius: BorderRadius.circular(3))),
                      const SizedBox(width: 7),
                      Expanded(child: Text(e.s.name, style: HqText.body.copyWith(fontSize: 12))),
                      Text(i < e.v.length ? tipFmt(e.v[i]) : '', style: HqText.body.copyWith(fontSize: 12, fontWeight: FontWeight.w800)),
                    ],
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ChartPainter extends CustomPainter {
  _ChartPainter({
    required this.labels,
    required this.series,
    required this.stack,
    required this.axisFmt,
    required this.leftPad,
    required this.hover,
  });

  final List<String> labels;
  final List<({ChartSeries s, List<double> v})> series;
  final bool stack;
  final String Function(double) axisFmt;
  final double leftPad;
  final int? hover;

  static const _pr = 10.0, _pt = 10.0, _pb = 26.0;

  @override
  void paint(Canvas canvas, Size size) {
    final n = labels.length;
    if (n == 0) return;
    final w = size.width, h = size.height;
    final iw = w - leftPad - _pr, ih = h - _pt - _pb;

    // Axis range: one shared scale, rounded to a "nice" step.
    var hi = 0.0, lo = 0.0;
    if (stack) {
      for (var i = 0; i < n; i++) {
        var p = 0.0, q = 0.0;
        for (final e in series) {
          final v = i < e.v.length ? e.v[i] : 0.0;
          v >= 0 ? p += v : q += v;
        }
        hi = math.max(hi, p);
        lo = math.min(lo, q);
      }
    } else {
      for (final e in series) {
        for (final v in e.v) {
          hi = math.max(hi, v);
          lo = math.min(lo, v);
        }
      }
    }
    final rawStep = math.max(hi - lo, 1) / 4;
    final pw = math.pow(10, (math.log(rawStep) / math.ln10).floor()).toDouble();
    final nn = rawStep / pw;
    final step = (nn <= 1 ? 1 : nn <= 2 ? 2 : nn <= 2.5 ? 2.5 : nn <= 5 ? 5 : 10) * pw;
    final top = (hi * 1.02 / step).ceil() * step;
    final bot = (lo * 1.02 / step).floor() * step;
    final range = (top - bot) == 0 ? step : (top - bot);

    double y(double v) => _pt + ih - ((v - bot) / range) * ih;
    double x(int i) => leftPad + (i + .5) * iw / n;
    final bw = iw / n;

    // Grid + y labels.
    final grid = Paint()..color = Hq.soft..strokeWidth = 1;
    for (var v = bot; v <= top + step / 1000; v += step) {
      final yy = y(v);
      canvas.drawLine(Offset(leftPad, yy), Offset(w - _pr, yy), grid);
      _text(canvas, axisFmt(v), Offset(leftPad - 8, yy), size: 10.5, color: Hq.faint, align: _A.right, vCenter: true);
    }
    if (bot < 0) {
      canvas.drawLine(Offset(leftPad, y(0)), Offset(w - _pr, y(0)), Paint()..color = const Color(0xFF3A4766)..strokeWidth = 1);
    }

    // x labels: every other one when the slots get narrow; the newest is always shown and bold.
    final every = bw < 34 ? 2 : 1;
    for (var i = 0; i < n; i++) {
      if ((n - 1 - i) % every == 0) {
        final last = i == n - 1;
        _text(canvas, labels[i], Offset(x(i), h - 7), size: 10.5, color: last ? Hq.text : Hq.faint, weight: last ? FontWeight.w700 : FontWeight.w400, align: _A.center, vBottom: true);
      }
    }

    final barS = series.where((e) => e.s.type == SeriesType.bar).toList();
    final cum = List<double>.filled(n, 0), cumN = List<double>.filled(n, 0);
    final gap = math.max(2.0, bw * .14);
    final gw = bw - gap * 2;
    final bn = stack ? 1 : math.max(1, barS.length);
    final one = math.min(26.0, (gw - (bn - 1) * 2) / bn);

    for (var si = 0; si < series.length; si++) {
      final e = series[si];
      final color = e.s.color;
      switch (e.s.type) {
        case SeriesType.bar:
          for (var i = 0; i < e.v.length && i < n; i++) {
            final v = e.v[i];
            double x0, y0, y1, bwid;
            if (stack) {
              final b = v >= 0 ? cum : cumN;
              final base = b[i];
              b[i] += v;
              bwid = math.min(gw, 30.0);
              x0 = x(i) - bwid / 2;
              y0 = y(base);
              y1 = y(base + v);
            } else {
              final k = barS.indexOf(e);
              final tot = bn * one + (bn - 1) * 2;
              x0 = x(i) - tot / 2 + k * (one + 2);
              y0 = y(0);
              y1 = y(v);
              bwid = one;
            }
            final hh = (y0 - y1).abs();
            final r = RRect.fromRectAndRadius(
              Rect.fromLTWH(x0, math.min(y0, y1), bwid, math.max(hh, v != 0 ? 1.0 : 0.0)),
              Radius.circular(math.min(4.0, bwid / 2)),
            );
            canvas.drawRRect(r, Paint()..color = color);
          }
        case SeriesType.area:
          final up = <Offset>[], dn = <Offset>[];
          for (var i = 0; i < e.v.length && i < n; i++) {
            final base = stack ? cum[i] : 0.0;
            up.add(Offset(x(i), y(base + e.v[i])));
            dn.add(Offset(x(i), y(base)));
            if (stack) cum[i] += e.v[i];
          }
          if (up.isEmpty) break;
          final fill = Path()..moveTo(up.first.dx, up.first.dy);
          for (final p in up.skip(1)) {
            fill.lineTo(p.dx, p.dy);
          }
          for (final p in dn.reversed) {
            fill.lineTo(p.dx, p.dy);
          }
          fill.close();
          final top0 = up.map((p) => p.dy).reduce(math.min);
          canvas.drawPath(
            fill,
            Paint()
              ..shader = LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [color.withValues(alpha: stack ? .55 : .34), color.withValues(alpha: stack ? .30 : .02)],
              ).createShader(Rect.fromLTWH(0, top0, w, math.max(1, _pt + ih - top0))),
          );
          // The outline sits on the top edge of this layer.
          final edge = stack
              ? [for (var i = 0; i < up.length; i++) Offset(up[i].dx, y(cum[i]))]
              : up;
          _stroke(canvas, edge, color, 2);
          if (!stack) _endDot(canvas, edge.last, color);
        case SeriesType.line:
          final pts = [for (var i = 0; i < e.v.length && i < n; i++) Offset(x(i), y(e.v[i]))];
          if (pts.isEmpty) break;
          _stroke(canvas, pts, color, 2.25, dash: e.s.dash);
          _endDot(canvas, pts.last, color);
      }
    }

    if (hover != null && hover! < n) {
      final hx = x(hover!);
      _dashedV(canvas, hx, _pt, _pt + ih);
    }
  }

  void _stroke(Canvas canvas, List<Offset> pts, Color color, double width, {bool dash = false}) {
    final path = Path()..moveTo(pts.first.dx, pts.first.dy);
    for (final p in pts.skip(1)) {
      path.lineTo(p.dx, p.dy);
    }
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = width
      ..strokeJoin = StrokeJoin.round
      ..strokeCap = StrokeCap.round;
    if (!dash) {
      canvas.drawPath(path, paint);
      return;
    }
    for (final m in path.computeMetrics()) {
      var d = 0.0;
      while (d < m.length) {
        canvas.drawPath(m.extractPath(d, math.min(d + 5, m.length)), paint);
        d += 9;
      }
    }
  }

  void _endDot(Canvas canvas, Offset p, Color color) {
    canvas.drawCircle(p, 4.5 + 1.25, Paint()..color = Hq.raised);
    canvas.drawCircle(p, 4.5, Paint()..color = color);
  }

  void _dashedV(Canvas canvas, double x, double y0, double y1) {
    final paint = Paint()..color = Hq.muted..strokeWidth = 1;
    for (var y = y0; y < y1; y += 6) {
      canvas.drawLine(Offset(x, y), Offset(x, math.min(y + 3, y1)), paint);
    }
  }

  void _text(Canvas canvas, String s, Offset at,
      {double size = 11, Color color = Hq.faint, FontWeight weight = FontWeight.w400, _A align = _A.left, bool vCenter = false, bool vBottom = false}) {
    final tp = TextPainter(
      text: TextSpan(text: s, style: TextStyle(fontSize: size, color: color, fontWeight: weight)),
      textDirection: TextDirection.ltr,
    )..layout();
    var dx = at.dx;
    if (align == _A.right) dx -= tp.width;
    if (align == _A.center) dx -= tp.width / 2;
    var dy = at.dy;
    if (vCenter) dy -= tp.height / 2;
    if (vBottom) dy -= tp.height * .8;
    tp.paint(canvas, Offset(dx, dy));
  }

  @override
  bool shouldRepaint(_ChartPainter old) => true;
}

enum _A { left, right, center }

/// `.spark`: a tiny filled trend line with a dot on the latest value.
class Spark extends StatelessWidget {
  const Spark(this.values, this.color, {super.key, this.height = 44});

  final List<double> values;
  final Color color;
  final double height;

  @override
  Widget build(BuildContext context) {
    if (values.length < 2) return SizedBox(height: height);
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: SizedBox(
        height: height,
        width: double.infinity,
        child: CustomPaint(painter: _SparkPainter(values, color)),
      ),
    );
  }
}

class _SparkPainter extends CustomPainter {
  _SparkPainter(this.v, this.color);
  final List<double> v;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final lo = v.reduce(math.min), hi = v.reduce(math.max);
    final r = (hi - lo) == 0 ? 1.0 : hi - lo;
    final n = v.length;
    final pts = [for (var i = 0; i < n; i++) Offset(i / (n - 1) * size.width, 4 + (1 - (v[i] - lo) / r) * (size.height - 10))];
    final line = Path()..moveTo(pts.first.dx, pts.first.dy);
    for (final p in pts.skip(1)) {
      line.lineTo(p.dx, p.dy);
    }
    final area = Path.from(line)..lineTo(size.width, size.height)..lineTo(0, size.height)..close();
    canvas.drawPath(
      area,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [color.withValues(alpha: .3), color.withValues(alpha: 0)],
        ).createShader(Offset.zero & size),
    );
    canvas.drawPath(line, Paint()..color = color..style = PaintingStyle.stroke..strokeWidth = 2..strokeJoin = StrokeJoin.round);
    canvas.drawCircle(pts.last, 7, Paint()..color = Hq.raised);
    canvas.drawCircle(pts.last, 4, Paint()..color = color);
  }

  @override
  bool shouldRepaint(_SparkPainter old) => old.v != v || old.color != color;
}

class DonutSegment {
  const DonutSegment(this.value, this.color);
  final double value;
  final Color color;
}

/// `.donut`: ring chart with a widget in the middle.
class Donut extends StatelessWidget {
  const Donut(this.segments, {super.key, this.size = 120, this.stroke = 14, this.center});

  final List<DonutSegment> segments;
  final double size;
  final double stroke;
  final Widget? center;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size,
      height: size,
      child: Stack(
        alignment: Alignment.center,
        children: [
          CustomPaint(size: Size(size, size), painter: _DonutPainter(segments, stroke)),
          ?center,
        ],
      ),
    );
  }
}

class _DonutPainter extends CustomPainter {
  _DonutPainter(this.segs, this.stroke);
  final List<DonutSegment> segs;
  final double stroke;

  @override
  void paint(Canvas canvas, Size size) {
    final r = (size.width - stroke) / 2;
    final rect = Rect.fromCircle(center: size.center(Offset.zero), radius: r);
    canvas.drawCircle(rect.center, r, Paint()..color = Hq.high..style = PaintingStyle.stroke..strokeWidth = stroke);
    final total = segs.fold<double>(0, (a, s) => a + s.value);
    if (total <= 0) return;
    final circ = 2 * math.pi * r;
    final gapAngle = segs.length > 1 ? 2.5 / circ * 2 * math.pi : 0.0;
    var start = -math.pi / 2;
    for (final s in segs) {
      final sweep = s.value / total * 2 * math.pi;
      if (s.color != Colors.transparent && sweep > gapAngle) {
        canvas.drawArc(rect, start, sweep - gapAngle, false,
            Paint()..color = s.color..style = PaintingStyle.stroke..strokeWidth = stroke);
      }
      start += sweep;
    }
  }

  @override
  bool shouldRepaint(_DonutPainter old) => old.segs != segs;
}

/// The small health ring used for an academy or student score (green / gold / red by value).
class HealthRing extends StatelessWidget {
  const HealthRing(this.score, {super.key, this.size = 40});
  final int score;
  final double size;

  static Tone toneOf(num h) => h >= 80 ? Tone.green : (h >= 62 ? Tone.gold : Tone.red);

  @override
  Widget build(BuildContext context) {
    final t = toneOf(score);
    final big = size > 44;
    return Donut(
      [DonutSegment(score.toDouble(), t.color), DonutSegment(100.0 - score, Colors.transparent)],
      size: size,
      stroke: big ? 7 : 4,
      center: Text('$score', style: TextStyle(fontSize: big ? 15 : 11, fontWeight: FontWeight.w800, color: Hq.text)),
    );
  }
}
