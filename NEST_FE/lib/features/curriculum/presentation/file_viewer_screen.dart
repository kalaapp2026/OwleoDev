import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:nest_fe/app/theme/app_tokens.dart';
import 'package:nest_fe/app/theme/app_typography.dart';
import 'package:nest_fe/core/design/buttons.dart';
import 'package:nest_fe/core/design/pressable.dart';
import 'package:nest_fe/core/design/status_badge.dart';
import 'package:nest_fe/core/design/toast.dart';
import 'package:nest_fe/core/format/money.dart';
import 'package:nest_fe/core/network/api_config.dart';
import 'package:nest_fe/features/curriculum/data/study_material.dart';
import 'package:nest_fe/features/curriculum/presentation/widgets/audio_player_panel.dart';
import 'package:url_launcher/url_launcher.dart';

/// How the viewer was reached, which decides whether Prev/Next appear.
class PlaylistNavigation {
  const PlaylistNavigation({
    required this.playlistName,
    required this.index,
    required this.total,
    required this.onPrevious,
    required this.onNext,
  });

  final String playlistName;
  final int index;
  final int total;

  /// Null at the ends - the buttons grey out rather than wrapping around, because a running order
  /// that silently restarts is indistinguishable from one that never finished.
  final VoidCallback? onPrevious;
  final VoidCallback? onNext;
}

/// Opens one material: an audio player for songs, a preview for documents and images.
///
/// A single screen rather than three, because everything around the file - the title, who shared
/// it, the download rule, the playlist controls - is identical regardless of type. Only the middle
/// changes.
class FileViewerScreen extends ConsumerStatefulWidget {
  const FileViewerScreen({
    super.key,
    required this.material,
    this.playlistNav,
    this.autoPlay = false,
  });

  final StudyMaterial material;
  final PlaylistNavigation? playlistNav;
  final bool autoPlay;

  @override
  ConsumerState<FileViewerScreen> createState() => _FileViewerScreenState();
}

class _FileViewerScreenState extends ConsumerState<FileViewerScreen> {
  /// Hides everything but the file itself. Images and documents only - audio has no visual to
  /// enlarge, and its controls are the point.
  bool _fullscreen = false;

  StudyMaterial get material => widget.material;

  Future<void> _download() async {
    if (!material.isDownloadable) {
      // Should be unreachable - the button is not rendered - but a view-only file leaking a
      // download would defeat the entire permission.
      showAppToast(context, 'This file is view-only.');
      return;
    }
    final url = ApiConfig.resolveMediaUrl(material.url);
    if (url == null) return;
    final launched = await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
    if (!launched && mounted) showAppToast(context, "Couldn't open this file.");
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final accent = material.fileType.color(palette);

    if (_fullscreen) {
      return Scaffold(
        backgroundColor: Colors.black,
        body: SafeArea(
          child: Stack(
            children: [
              Positioned.fill(
                child: InteractiveViewer(
                  maxScale: 5,
                  child: Center(child: _preview(palette, accent, fullscreen: true)),
                ),
              ),
              Positioned(
                top: AppSpacing.lg,
                right: AppSpacing.lg,
                child: Pressable(
                  onTap: () => setState(() => _fullscreen = false),
                  child: Container(
                    height: 40,
                    width: 40,
                    alignment: Alignment.center,
                    decoration: const BoxDecoration(
                      color: Color(0x99000000),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(Icons.close_fullscreen,
                        size: 18, color: Colors.white),
                  ),
                ),
              ),
            ],
          ),
        ),
      );
    }

    return Scaffold(
      backgroundColor: palette.bg,
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _header(palette, accent),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(
                    AppSpacing.page, AppSpacing.xl, AppSpacing.page, AppSpacing.x5l),
                children: [
                  _preview(palette, accent, fullscreen: false),
                  const SizedBox(height: AppSpacing.x4l),
                  _meta(palette, accent),
                  if (widget.playlistNav != null) ...[
                    const SizedBox(height: AppSpacing.x4l),
                    _playlistBar(palette, accent, widget.playlistNav!),
                  ],
                  if (material.isDownloadable) ...[
                    const SizedBox(height: AppSpacing.x4l),
                    AppPrimaryButton(
                      label: 'Download',
                      icon: Icons.download_outlined,
                      background: accent,
                      onPressed: _download,
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _header(AppPalette palette, Color accent) {
    return Container(
      padding: const EdgeInsets.fromLTRB(
          AppSpacing.page, AppSpacing.x4l, AppSpacing.page, AppSpacing.xxl),
      decoration:
          BoxDecoration(border: Border(bottom: BorderSide(color: palette.borderSoft))),
      child: Row(
        children: [
          AppIconButton(
              icon: Icons.arrow_back, onTap: () => Navigator.of(context).maybePop()),
          const SizedBox(width: AppSpacing.lg),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(material.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                        fontSize: AppType.title,
                        fontWeight: AppType.bold,
                        letterSpacing: AppType.titleTracking,
                        color: palette.text)),
                const SizedBox(height: 2),
                Text('${material.fileType.label} · ${material.sizeLabel}',
                    style: TextStyle(fontSize: AppType.smd, color: palette.textMuted)),
              ],
            ),
          ),
          if (material.fileType != StudyMaterialType.audio)
            AppIconButton(
              icon: Icons.open_in_full,
              tooltip: 'Fullscreen',
              size: 38,
              iconSize: 16,
              onTap: () => setState(() => _fullscreen = true),
            ),
        ],
      ),
    );
  }

  Widget _preview(AppPalette palette, Color accent, {required bool fullscreen}) {
    switch (material.fileType) {
      case StudyMaterialType.audio:
        return AudioPlayerPanel(
          material: material,
          autoPlay: widget.autoPlay,
          onEnded: widget.playlistNav?.onNext,
        );
      case StudyMaterialType.image:
        return _ImagePreview(
          material: material,
          fullscreen: fullscreen,
          accent: accent,
          onTapToExpand: fullscreen ? null : () => setState(() => _fullscreen = true),
        );
      case StudyMaterialType.notes:
        return _DocumentPreview(
          material: material,
          fullscreen: fullscreen,
          accent: accent,
          onOpenExternally: _download,
        );
    }
  }

  Widget _meta(AppPalette palette, Color accent) {
    return Container(
      padding: const EdgeInsets.all(AppSpacing.xl),
      decoration: BoxDecoration(
        color: palette.surfaceRaised,
        borderRadius: AppRadii.all(AppRadii.xxl),
        border: Border.all(color: palette.borderSoft),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if ((material.description ?? '').isNotEmpty) ...[
            Text(material.description!,
                style: TextStyle(
                    fontSize: AppType.lg, color: palette.text, height: 1.5)),
            const SizedBox(height: AppSpacing.lg),
          ],
          Wrap(
            spacing: AppSpacing.sm,
            runSpacing: AppSpacing.xs,
            children: [
              StatusBadge(
                label: material.permission.label,
                color: material.permission.color(palette),
              ),
              if (material.visibility == StudyMaterialVisibility.selected)
                StatusBadge(
                  label: 'Shared with ${material.studentIds.length}',
                  color: palette.violet,
                ),
            ],
          ),
          const SizedBox(height: AppSpacing.lg),
          Text(
            '${material.fileName}\n'
            'Shared by ${material.uploadedByName ?? 'someone no longer listed'}'
            ' · ${formatFeeDate(material.uploadedAt)}',
            style: TextStyle(
                fontSize: AppType.sm, color: palette.textFaint, height: 1.6),
          ),
        ],
      ),
    );
  }

  Widget _playlistBar(AppPalette palette, Color accent, PlaylistNavigation nav) {
    return Container(
      padding: const EdgeInsets.all(AppSpacing.lg),
      decoration: BoxDecoration(
        color: accent.withValues(alpha: 0.08),
        borderRadius: AppRadii.all(AppRadii.xxl),
        border: Border.all(color: accent.withValues(alpha: 0.3)),
      ),
      child: Row(
        children: [
          _NavButton(
            icon: Icons.skip_previous_rounded,
            accent: accent,
            onTap: nav.onPrevious,
          ),
          Expanded(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(nav.playlistName,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                        fontSize: AppType.md,
                        fontWeight: AppType.bold,
                        color: palette.text)),
                const SizedBox(height: 2),
                Text('${nav.index + 1} of ${nav.total}',
                    style:
                        TextStyle(fontSize: AppType.sm, color: palette.textMuted)),
              ],
            ),
          ),
          _NavButton(
            icon: Icons.skip_next_rounded,
            accent: accent,
            onTap: nav.onNext,
          ),
        ],
      ),
    );
  }
}

class _NavButton extends StatelessWidget {
  const _NavButton({required this.icon, required this.accent, required this.onTap});

  final IconData icon;
  final Color accent;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final enabled = onTap != null;
    return Opacity(
      opacity: enabled ? 1 : 0.3,
      child: Pressable(
        onTap: onTap,
        child: Container(
          height: 38,
          width: 38,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: palette.surface,
            shape: BoxShape.circle,
            border: Border.all(color: accent.withValues(alpha: 0.35)),
          ),
          child: Icon(icon, size: 20, color: accent),
        ),
      ),
    );
  }
}

/// Images render inline. Tapping enlarges rather than opening another app, because the point of
/// a view-only image is that it never leaves the app.
class _ImagePreview extends StatelessWidget {
  const _ImagePreview({
    required this.material,
    required this.fullscreen,
    required this.accent,
    required this.onTapToExpand,
  });

  final StudyMaterial material;
  final bool fullscreen;
  final Color accent;
  final VoidCallback? onTapToExpand;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final url = ApiConfig.resolveMediaUrl(material.url);
    if (url == null) {
      return _Unavailable(message: 'This image has no file behind it.', accent: accent);
    }

    final image = Image.network(
      url,
      fit: fullscreen ? BoxFit.contain : BoxFit.cover,
      loadingBuilder: (context, child, progress) {
        if (progress == null) return child;
        return SizedBox(
          height: fullscreen ? null : 220,
          child: Center(
            child: CircularProgressIndicator(
              color: accent,
              value: progress.expectedTotalBytes == null
                  ? null
                  : progress.cumulativeBytesLoaded / progress.expectedTotalBytes!,
            ),
          ),
        );
      },
      errorBuilder: (_, _, _) =>
          _Unavailable(message: "This image couldn't be loaded.", accent: accent),
    );

    if (fullscreen) return image;

    return Pressable(
      onTap: onTapToExpand,
      child: ClipRRect(
        borderRadius: AppRadii.all(AppRadii.xxl),
        child: Container(
          height: 260,
          width: double.infinity,
          color: palette.surfaceRaised,
          child: Stack(
            fit: StackFit.expand,
            children: [
              image,
              Positioned(
                right: AppSpacing.md,
                bottom: AppSpacing.md,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: AppSpacing.md, vertical: 5),
                  decoration: BoxDecoration(
                    color: const Color(0xB3000000),
                    borderRadius: AppRadii.all(AppRadii.pill),
                  ),
                  child: const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.open_in_full, size: 12, color: Colors.white),
                      SizedBox(width: 5),
                      Text('Tap to enlarge',
                          style: TextStyle(fontSize: 11, color: Colors.white)),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Documents get a cover card rather than a rendered page.
///
/// Flutter has no built-in PDF or Office renderer, and pulling one in for this would be a large
/// dependency for a file that opens perfectly well in the device's own viewer. What matters is
/// that the card says clearly what it is, and that view-only files offer no way out of the app.
class _DocumentPreview extends StatelessWidget {
  const _DocumentPreview({
    required this.material,
    required this.fullscreen,
    required this.accent,
    required this.onOpenExternally,
  });

  final StudyMaterial material;
  final bool fullscreen;
  final Color accent;
  final VoidCallback onOpenExternally;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final extension = material.fileName.contains('.')
        ? material.fileName.split('.').last.toUpperCase()
        : 'FILE';

    return Container(
      padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.xl, vertical: AppSpacing.x6l),
      decoration: BoxDecoration(
        color: palette.surfaceRaised,
        borderRadius: AppRadii.all(AppRadii.xxl),
        border: Border.all(color: palette.borderSoft),
      ),
      child: Column(
        children: [
          Container(
            height: 84,
            width: 68,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: accent.withValues(alpha: 0.12),
              borderRadius: AppRadii.all(AppRadii.lg),
              border: Border.all(color: accent.withValues(alpha: 0.35)),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.description_outlined, size: 26, color: accent),
                const SizedBox(height: AppSpacing.xs),
                Text(extension,
                    style: TextStyle(
                        fontSize: AppType.tiny,
                        fontWeight: AppType.heavy,
                        letterSpacing: 0.4,
                        color: accent)),
              ],
            ),
          ),
          const SizedBox(height: AppSpacing.xl),
          Text(material.fileName,
              textAlign: TextAlign.center,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                  fontSize: AppType.x3l,
                  fontWeight: AppType.bold,
                  color: palette.text)),
          const SizedBox(height: AppSpacing.sm),
          Text(
            material.isDownloadable
                ? 'Download it to read in your usual app.'
                : 'This document is view-only, so it stays inside the app.',
            textAlign: TextAlign.center,
            style: TextStyle(
                fontSize: AppType.sm, color: palette.textFaint, height: 1.5),
          ),
        ],
      ),
    );
  }
}

class _Unavailable extends StatelessWidget {
  const _Unavailable({required this.message, required this.accent});

  final String message;
  final Color accent;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return Container(
      height: 200,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: palette.surfaceRaised,
        borderRadius: AppRadii.all(AppRadii.xxl),
        border: Border.all(color: palette.borderSoft),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.broken_image_outlined, size: 28, color: palette.textFaint),
          const SizedBox(height: AppSpacing.md),
          Text(message,
              style: TextStyle(fontSize: AppType.md, color: palette.textMuted)),
        ],
      ),
    );
  }
}
