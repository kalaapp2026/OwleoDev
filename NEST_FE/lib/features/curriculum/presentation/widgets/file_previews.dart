import 'package:flutter/material.dart';
import 'package:nest_fe/app/theme/app_tokens.dart';
import 'package:nest_fe/app/theme/app_typography.dart';
import 'package:nest_fe/core/design/pressable.dart';
import 'package:nest_fe/core/network/api_config.dart';
import 'package:nest_fe/features/curriculum/data/study_material.dart';
import 'package:pdfrx/pdfrx.dart';

enum MarkupTool { pen, highlighter }

class _Stroke {
  _Stroke(this.tool, this.color, this.width);
  final MarkupTool tool;
  final Color color;
  final double width;
  final List<Offset> points = []; // normalised 0..1 so marks survive a layout change
}

/// Pen and highlighter state for the document viewer.
///
/// Lives above the preview rather than inside it so a stroke survives toggling fullscreen, which
/// rebuilds the preview with a different layout. Marks last only as long as the viewer is open:
/// they are the reader's scribbles, not an edit of the shared file.
class MarkupController extends ChangeNotifier {
  MarkupTool? tool;
  int colorIndex = 0;
  int thickness = 1; // 0 thin, 1 medium, 2 thick
  bool toolbarVisible = true;

  /// Marks are kept per page, so turning back to a page finds your underlining still there.
  final Map<int, List<_Stroke>> _byPage = {};
  _Stroke? _current;
  bool _disposed = false;

  /// Zero-based page being read. Always 0 for a document that is not a PDF.
  int page = 0;

  /// The open PDF, once loaded. Null while loading, on failure, and for non-PDF documents - the
  /// preview falls back to a cover card in all three.
  PdfDocument? pdf;
  bool loadingPdf = false;
  String? pdfError;

  int get pageCount => pdf?.pages.length ?? 1;

  List<_Stroke> get _strokes => _byPage.putIfAbsent(page, () => []);

  bool get hasMarks => _byPage[page]?.isNotEmpty ?? false;

  Future<void> loadPdf(Uri uri) async {
    loadingPdf = true;
    notifyListeners();
    try {
      await pdfrxFlutterInitialize();
      final doc = await PdfDocument.openUri(uri);
      if (_disposed) {
        await doc.dispose();
        return;
      }
      pdf = doc;
    } catch (_) {
      pdfError = "Couldn't open this PDF in the app.";
    }
    loadingPdf = false;
    if (!_disposed) notifyListeners();
  }

  void setPage(int p) {
    final next = p.clamp(0, pageCount - 1);
    if (next == page) return;
    _current = null;
    page = next;
    notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    pdf?.dispose();
    super.dispose();
  }

  static List<Color> penColors(AppPalette p) => [p.notPaid, p.primary, p.text];
  static List<Color> highlightColors(AppPalette p) => [p.gold, p.primary, p.coral];

  List<Color> colors(AppPalette p) =>
      tool == MarkupTool.highlighter ? highlightColors(p) : penColors(p);

  Color color(AppPalette p) {
    final list = colors(p);
    return list[colorIndex.clamp(0, list.length - 1)];
  }

  double get _width {
    if (tool == MarkupTool.highlighter) return const [6.0, 10.0, 16.0][thickness];
    return const [1.3, 2.4, 3.8][thickness];
  }

  void toggleTool(MarkupTool t) {
    tool = tool == t ? null : t;
    colorIndex = 0;
    notifyListeners();
  }

  void setColor(int i) {
    colorIndex = i;
    notifyListeners();
  }

  void setThickness(int i) {
    thickness = i;
    notifyListeners();
  }

  void setToolbarVisible(bool v) {
    toolbarVisible = v;
    notifyListeners();
  }

  void undo() {
    if (_strokes.isEmpty) return;
    _strokes.removeLast();
    notifyListeners();
  }

  void clear() {
    if (_strokes.isEmpty) return;
    _strokes.clear();
    notifyListeners();
  }

  void _start(Offset normalised, AppPalette p) {
    if (tool == null) return;
    _current = _Stroke(tool!, color(p), _width)..points.add(normalised);
    notifyListeners();
  }

  void _extend(Offset normalised) {
    _current?.points.add(normalised);
    notifyListeners();
  }

  void _end() {
    if (_current != null && _current!.points.length > 1) _strokes.add(_current!);
    _current = null;
    notifyListeners();
  }
}

/// The in-app preview of a document: a page you can mark up with a pen or a highlighter.
///
/// Flutter ships no PDF or Office renderer, so the page face is a cover card for the file rather
/// than its pages; the reading tools around it are the same either way.
class DocumentPreview extends StatelessWidget {
  const DocumentPreview({
    super.key,
    required this.material,
    required this.controller,
    required this.fullscreen,
    this.onEnterFullscreen,
    this.onExitFullscreen,
  });

  final StudyMaterial material;
  final MarkupController controller;
  final bool fullscreen;
  final VoidCallback? onEnterFullscreen;
  final VoidCallback? onExitFullscreen;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final typeColor = material.fileType.color(palette);

    return ListenableBuilder(
      listenable: controller,
      builder: (context, _) {
        final page = _PageCard(
          material: material,
          controller: controller,
          typeColor: typeColor,
          fullscreen: fullscreen,
        );
        return fullscreen
            ? _fullscreenLayout(palette, typeColor, page)
            : _inlineLayout(palette, typeColor, page);
      },
    );
  }

  Widget _inlineLayout(AppPalette palette, Color typeColor, Widget page) {
    return SingleChildScrollView(
      // A drag with a tool in hand is a stroke, not a scroll.
      physics: controller.tool != null ? const NeverScrollableScrollPhysics() : null,
      padding: const EdgeInsets.fromLTRB(20, 14, 20, 16),
      child: Column(
        children: [
          if (controller.toolbarVisible)
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Wrap(
                alignment: WrapAlignment.center,
                crossAxisAlignment: WrapCrossAlignment.center,
                spacing: 6,
                runSpacing: 6,
                children: [
                  _ToolButton(
                    icon: Icons.edit_outlined,
                    label: 'Pen',
                    active: controller.tool == MarkupTool.pen,
                    color: typeColor,
                    onTap: () => controller.toggleTool(MarkupTool.pen),
                  ),
                  _ToolButton(
                    icon: Icons.highlight_outlined,
                    label: 'Highlight',
                    active: controller.tool == MarkupTool.highlighter,
                    color: typeColor,
                    onTap: () => controller.toggleTool(MarkupTool.highlighter),
                  ),
                  if (controller.tool != null) ...[
                    _divider(palette, vertical: false),
                    _Thickness(controller: controller, color: typeColor, axis: Axis.horizontal),
                    _divider(palette, vertical: false),
                    _Swatches(controller: controller, axis: Axis.horizontal),
                  ],
                  _divider(palette, vertical: false),
                  AppIconButton(
                    icon: Icons.undo,
                    tooltip: 'Undo last stroke',
                    size: 28,
                    iconSize: 13,
                    color: palette.textMuted,
                    onTap: controller.undo,
                  ),
                  AppIconButton(
                    icon: Icons.auto_fix_normal_outlined,
                    tooltip: 'Clear marks',
                    size: 28,
                    iconSize: 13,
                    color: palette.textMuted,
                    onTap: controller.clear,
                  ),
                  AppIconButton(
                    icon: Icons.visibility_off_outlined,
                    tooltip: 'Hide toolbar',
                    size: 28,
                    iconSize: 13,
                    color: palette.textMuted,
                    onTap: () => controller.setToolbarVisible(false),
                  ),
                  AppIconButton(
                    icon: Icons.open_in_full,
                    tooltip: 'Fullscreen',
                    size: 28,
                    iconSize: 13,
                    color: palette.textMuted,
                    onTap: onEnterFullscreen,
                  ),
                ],
              ),
            )
          else
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Pressable(
                onTap: () => controller.setToolbarVisible(true),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(
                    color: palette.surfaceRaised,
                    borderRadius: AppRadii.all(AppRadii.pill),
                    border: Border.all(color: palette.border),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.visibility_outlined, size: 12, color: palette.textMuted),
                      const SizedBox(width: 6),
                      Text('Show tools',
                          style: TextStyle(
                              fontSize: AppType.sm,
                              fontWeight: AppType.bold,
                              color: palette.textMuted)),
                    ],
                  ),
                ),
              ),
            ),
          page,
          if (controller.pageCount > 1) ...[
            const SizedBox(height: 16),
            _InlinePager(controller: controller),
          ],
        ],
      ),
    );
  }

  /// Reading mode: the page gets the whole frame and the tools move to a slim rail that can
  /// itself collapse to a thin tab, so nothing ever sits on top of the page.
  Widget _fullscreenLayout(AppPalette palette, Color typeColor, Widget page) {
    return Row(
      children: [
        Expanded(
          child: SingleChildScrollView(
            physics: controller.tool != null ? const NeverScrollableScrollPhysics() : null,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 16),
            child: Center(child: page),
          ),
        ),
        if (controller.toolbarVisible)
          Container(
            width: 56,
            decoration: BoxDecoration(
              border: Border(left: BorderSide(color: palette.borderSoft)),
            ),
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 16),
              child: Column(
                children: [
                  AppIconButton(
                    icon: Icons.close_fullscreen,
                    tooltip: 'Exit fullscreen',
                    size: 36,
                    iconSize: 15,
                    onTap: onExitFullscreen,
                  ),
                  const SizedBox(height: 10),
                  AppIconButton(
                    icon: Icons.keyboard_double_arrow_right,
                    tooltip: 'Hide tools',
                    size: 36,
                    iconSize: 15,
                    color: palette.textMuted,
                    onTap: () => controller.setToolbarVisible(false),
                  ),
                  const SizedBox(height: 10),
                  _divider(palette, vertical: true),
                  const SizedBox(height: 10),
                  _ToolButton(
                    icon: Icons.edit_outlined,
                    active: controller.tool == MarkupTool.pen,
                    color: typeColor,
                    onTap: () => controller.toggleTool(MarkupTool.pen),
                  ),
                  const SizedBox(height: 10),
                  _ToolButton(
                    icon: Icons.highlight_outlined,
                    active: controller.tool == MarkupTool.highlighter,
                    color: typeColor,
                    onTap: () => controller.toggleTool(MarkupTool.highlighter),
                  ),
                  if (controller.tool != null) ...[
                    const SizedBox(height: 10),
                    _divider(palette, vertical: true),
                    const SizedBox(height: 10),
                    _Thickness(controller: controller, color: typeColor, axis: Axis.vertical),
                    const SizedBox(height: 10),
                    _divider(palette, vertical: true),
                    const SizedBox(height: 10),
                    _Swatches(controller: controller, axis: Axis.vertical),
                  ],
                  const SizedBox(height: 10),
                  _divider(palette, vertical: true),
                  const SizedBox(height: 10),
                  AppIconButton(
                    icon: Icons.undo,
                    tooltip: 'Undo last stroke',
                    size: 36,
                    iconSize: 14,
                    color: palette.textMuted,
                    onTap: controller.undo,
                  ),
                  const SizedBox(height: 10),
                  AppIconButton(
                    icon: Icons.auto_fix_normal_outlined,
                    tooltip: 'Clear marks',
                    size: 36,
                    iconSize: 14,
                    color: palette.textMuted,
                    onTap: controller.clear,
                  ),
                  if (controller.pageCount > 1) ...[
                    const SizedBox(height: 10),
                    _divider(palette, vertical: true),
                    const SizedBox(height: 10),
                    _RailPager(controller: controller),
                  ],
                ],
              ),
            ),
          )
        else
          Container(
            width: 22,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              border: Border(left: BorderSide(color: palette.borderSoft)),
            ),
            child: Pressable(
              onTap: () => controller.setToolbarVisible(true),
              child: Padding(
                padding: const EdgeInsets.all(4),
                child: Icon(Icons.keyboard_double_arrow_left,
                    size: 15, color: palette.textFaint),
              ),
            ),
          ),
      ],
    );
  }

  Widget _divider(AppPalette palette, {required bool vertical}) => vertical
      ? Container(width: 24, height: 1, color: palette.borderSoft)
      : Container(width: 1, height: 20, color: palette.borderSoft);
}

/// "Page 2 of 5" with arrows, under the page in the normal layout.
class _InlinePager extends StatelessWidget {
  const _InlinePager({required this.controller});

  final MarkupController controller;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final first = controller.page == 0;
    final last = controller.page >= controller.pageCount - 1;
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Opacity(
          opacity: first ? 0.4 : 1,
          child: AppIconButton(
            icon: Icons.chevron_left,
            size: 32,
            iconSize: 14,
            onTap: first ? null : () => controller.setPage(controller.page - 1),
          ),
        ),
        const SizedBox(width: 14),
        Text('Page ${controller.page + 1} of ${controller.pageCount}',
            style: TextStyle(
                fontSize: AppType.smd,
                fontWeight: AppType.semi,
                color: palette.textMuted)),
        const SizedBox(width: 14),
        Opacity(
          opacity: last ? 0.4 : 1,
          child: AppIconButton(
            icon: Icons.chevron_right,
            size: 32,
            iconSize: 14,
            onTap: last ? null : () => controller.setPage(controller.page + 1),
          ),
        ),
      ],
    );
  }
}

/// The same, stacked, for the fullscreen rail.
class _RailPager extends StatelessWidget {
  const _RailPager({required this.controller});

  final MarkupController controller;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final first = controller.page == 0;
    final last = controller.page >= controller.pageCount - 1;
    return Column(
      children: [
        Opacity(
          opacity: first ? 0.4 : 1,
          child: AppIconButton(
            icon: Icons.keyboard_arrow_up,
            size: 32,
            iconSize: 14,
            onTap: first ? null : () => controller.setPage(controller.page - 1),
          ),
        ),
        const SizedBox(height: 6),
        Text('${controller.page + 1}/${controller.pageCount}',
            style: TextStyle(
                fontSize: AppType.tiny,
                fontWeight: AppType.bold,
                color: palette.textMuted)),
        const SizedBox(height: 6),
        Opacity(
          opacity: last ? 0.4 : 1,
          child: AppIconButton(
            icon: Icons.keyboard_arrow_down,
            size: 32,
            iconSize: 14,
            onTap: last ? null : () => controller.setPage(controller.page + 1),
          ),
        ),
      ],
    );
  }
}

class _ToolButton extends StatelessWidget {
  const _ToolButton({
    required this.icon,
    required this.active,
    required this.color,
    required this.onTap,
    this.label,
  });

  final IconData icon;
  final String? label;
  final bool active;
  final Color color;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final fg = active ? color : palette.textMuted;
    return Pressable(
      onTap: onTap,
      child: Container(
        width: label == null ? 36 : null,
        height: label == null ? 36 : null,
        padding: label == null
            ? null
            : const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        alignment: label == null ? Alignment.center : null,
        decoration: BoxDecoration(
          color: active ? color.withValues(alpha: 0.13) : palette.surfaceRaised,
          borderRadius: BorderRadius.circular(label == null ? 11 : 10),
          border: Border.all(color: active ? color : palette.border),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: label == null ? 14 : 12, color: fg),
            if (label != null) ...[
              const SizedBox(width: 5),
              Text(label!,
                  style: TextStyle(
                      fontSize: AppType.sm, fontWeight: AppType.bold, color: fg)),
            ],
          ],
        ),
      ),
    );
  }
}

class _Thickness extends StatelessWidget {
  const _Thickness({required this.controller, required this.color, required this.axis});

  final MarkupController controller;
  final Color color;
  final Axis axis;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    const dots = [5.0, 8.0, 11.0];
    final items = [
      for (var i = 0; i < 3; i++)
        Pressable(
          onTap: () => controller.setThickness(i),
          child: Container(
            width: 22,
            height: 22,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: controller.thickness == i
                  ? color.withValues(alpha: 0.13)
                  : palette.surfaceRaised,
              shape: BoxShape.circle,
              border: Border.all(
                  color: controller.thickness == i ? color : palette.border),
            ),
            child: Container(
              width: dots[i],
              height: dots[i],
              decoration: BoxDecoration(
                color: controller.thickness == i ? color : palette.textMuted,
                shape: BoxShape.circle,
              ),
            ),
          ),
        ),
    ];
    return Flex(
      direction: axis,
      mainAxisSize: MainAxisSize.min,
      spacing: 6,
      children: items,
    );
  }
}

class _Swatches extends StatelessWidget {
  const _Swatches({required this.controller, required this.axis});

  final MarkupController controller;
  final Axis axis;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final colors = controller.colors(palette);
    return Flex(
      direction: axis,
      mainAxisSize: MainAxisSize.min,
      spacing: 4,
      children: [
        for (var i = 0; i < colors.length; i++)
          Pressable(
            onTap: () => controller.setColor(i),
            child: Container(
              width: 18,
              height: 18,
              decoration: BoxDecoration(
                color: colors[i],
                shape: BoxShape.circle,
                border: Border.all(
                  color: controller.colorIndex == i ? palette.text : palette.border,
                  width: controller.colorIndex == i ? 2 : 1,
                ),
              ),
            ),
          ),
      ],
    );
  }
}

class _PageCard extends StatelessWidget {
  const _PageCard({
    required this.material,
    required this.controller,
    required this.typeColor,
    required this.fullscreen,
  });

  final StudyMaterial material;
  final MarkupController controller;
  final Color typeColor;
  final bool fullscreen;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final extension = material.fileName.contains('.')
        ? material.fileName.split('.').last.toUpperCase()
        : 'FILE';

    if (controller.loadingPdf) {
      return ConstrainedBox(
        constraints: BoxConstraints(maxWidth: fullscreen ? 340 : 280),
        child: Container(
          height: fullscreen ? 420 : 320,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: palette.surfaceRaised,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: palette.border),
          ),
          child: CircularProgressIndicator(color: typeColor, strokeWidth: 2),
        ),
      );
    }

    final pdf = controller.pdf;
    if (pdf != null && controller.page < pdf.pages.length) {
      final pageInfo = pdf.pages[controller.page];
      return ConstrainedBox(
        constraints: BoxConstraints(maxWidth: fullscreen ? 560 : 420),
        child: AspectRatio(
          aspectRatio: pageInfo.width / pageInfo.height,
          child: Container(
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(4),
              boxShadow: const [
                BoxShadow(color: Color(0x66000000), blurRadius: 30, offset: Offset(0, 14)),
              ],
            ),
            child: Stack(
              children: [
                Positioned.fill(
                  child: PdfPageView(
                    // Keyed per page so a quick flip never shows the previous page bitmap.
                    key: ValueKey('pdf-page-${controller.page}'),
                    document: pdf,
                    pageNumber: controller.page + 1,
                    maximumDpi: 220,
                    decoration: const BoxDecoration(color: Colors.white),
                  ),
                ),
                _overlay(palette),
              ],
            ),
          ),
        ),
      );
    }

    return ConstrainedBox(
      constraints: BoxConstraints(maxWidth: fullscreen ? 340 : 280),
      child: Stack(
        children: [
          Container(
            width: double.infinity,
            constraints: BoxConstraints(minHeight: fullscreen ? 420 : 320),
            padding: EdgeInsets.symmetric(
                horizontal: fullscreen ? 26 : 20, vertical: fullscreen ? 34 : 26),
            decoration: BoxDecoration(
              color: palette.surfaceRaised,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: palette.border),
              boxShadow: const [
                BoxShadow(color: Color(0x66000000), blurRadius: 30, offset: Offset(0, 14)),
              ],
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 40,
                  height: 5,
                  margin: const EdgeInsets.only(bottom: 20),
                  decoration: BoxDecoration(
                    color: typeColor.withValues(alpha: 0.7),
                    borderRadius: BorderRadius.circular(3),
                  ),
                ),
                Center(
                  child: Container(
                    height: 84,
                    width: 68,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: typeColor.withValues(alpha: 0.12),
                      borderRadius: AppRadii.all(AppRadii.lg),
                      border: Border.all(color: typeColor.withValues(alpha: 0.35)),
                    ),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.description_outlined, size: 26, color: typeColor),
                        const SizedBox(height: AppSpacing.xs),
                        Text(extension,
                            style: TextStyle(
                                fontSize: AppType.tiny,
                                fontWeight: AppType.heavy,
                                letterSpacing: 0.4,
                                color: typeColor)),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 18),
                Center(
                  child: Text(material.fileName,
                      textAlign: TextAlign.center,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                          fontSize: AppType.x3l,
                          fontWeight: AppType.bold,
                          color: palette.text)),
                ),
                const SizedBox(height: 8),
                Center(
                  child: Text(
                    controller.pdfError ??
                        (material.isDownloadable
                            ? 'Download it to read in your usual app.'
                            : 'This document is view-only, so it stays inside the app.'),
                    textAlign: TextAlign.center,
                    style: TextStyle(
                        fontSize: AppType.sm, color: palette.textFaint, height: 1.5),
                  ),
                ),
              ],
            ),
          ),
          _overlay(palette),
        ],
      ),
    );
  }

  Widget _overlay(AppPalette palette) {
    return Positioned.fill(
      child: LayoutBuilder(
        builder: (context, box) {
          final size = box.biggest;
          Offset norm(Offset p) => Offset(
                (p.dx / size.width).clamp(0.0, 1.0),
                (p.dy / size.height).clamp(0.0, 1.0),
              );
          return IgnorePointer(
            ignoring: controller.tool == null,
            child: MouseRegion(
              cursor: controller.tool == null
                  ? MouseCursor.defer
                  : SystemMouseCursors.precise,
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onPanStart: (d) => controller._start(norm(d.localPosition), palette),
                onPanUpdate: (d) => controller._extend(norm(d.localPosition)),
                onPanEnd: (_) => controller._end(),
                onPanCancel: controller._end,
                child: CustomPaint(
                  painter: _MarkupPainter(
                    [...controller._strokes, ?controller._current],
                  ),
                  size: Size.infinite,
                ),
              ),
            ),
          );
        },
      ),
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

/// A picture, shown in place. Tapping the corner button enlarges it; a view-only image never
/// leaves the app.
class ImagePreview extends StatelessWidget {
  const ImagePreview({
    super.key,
    required this.material,
    required this.fullscreen,
    this.onEnterFullscreen,
    this.onExitFullscreen,
  });

  final StudyMaterial material;
  final bool fullscreen;
  final VoidCallback? onEnterFullscreen;
  final VoidCallback? onExitFullscreen;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final typeColor = material.fileType.color(palette);
    final url = ApiConfig.resolveMediaUrl(material.url);

    Widget unavailable(String message) => Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.broken_image_outlined, size: 40, color: typeColor),
            const SizedBox(height: 10),
            Text(message,
                style: TextStyle(
                    fontSize: AppType.smd,
                    fontWeight: AppType.medium,
                    color: palette.textMuted)),
          ],
        );

    final Widget face = url == null
        ? unavailable('This image has no file behind it.')
        : Image.network(
            url,
            fit: BoxFit.contain,
            loadingBuilder: (context, child, progress) {
              if (progress == null) return child;
              return Center(
                child: CircularProgressIndicator(
                  color: typeColor,
                  value: progress.expectedTotalBytes == null
                      ? null
                      : progress.cumulativeBytesLoaded / progress.expectedTotalBytes!,
                ),
              );
            },
            errorBuilder: (_, _, _) => unavailable("This image couldn't be loaded."),
          );

    final frame = ConstrainedBox(
      constraints: BoxConstraints(maxWidth: fullscreen ? 420 : 280),
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: typeColor.withValues(alpha: 0.27)),
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [material.fileType.softColor(palette), palette.surfaceHigh],
          ),
        ),
        clipBehavior: Clip.antiAlias,
        child: fullscreen
            ? InteractiveViewer(maxScale: 5, child: Center(child: face))
            : AspectRatio(aspectRatio: 4 / 5, child: Center(child: face)),
      ),
    );

    return Padding(
      padding: EdgeInsets.all(fullscreen ? 12 : 20),
      child: Stack(
        children: [
          Positioned.fill(child: Center(child: frame)),
          Positioned(
            top: 0,
            right: 0,
            child: fullscreen
                ? AppIconButton(
                    icon: Icons.close_fullscreen,
                    tooltip: 'Exit full view',
                    size: 36,
                    iconSize: 15,
                    onTap: onExitFullscreen,
                  )
                : AppIconButton(
                    icon: Icons.open_in_full,
                    tooltip: 'Full view',
                    size: 32,
                    iconSize: 14,
                    color: palette.textMuted,
                    onTap: onEnterFullscreen,
                  ),
          ),
        ],
      ),
    );
  }
}
