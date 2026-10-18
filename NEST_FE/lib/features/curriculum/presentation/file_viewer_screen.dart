import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:nest_fe/app/theme/app_tokens.dart';
import 'package:nest_fe/app/theme/app_typography.dart';
import 'package:nest_fe/core/design/buttons.dart';
import 'package:nest_fe/core/design/pressable.dart';
import 'package:nest_fe/core/design/toast.dart';
import 'package:nest_fe/core/network/api_config.dart';
import 'package:nest_fe/features/curriculum/data/study_material.dart';
import 'package:nest_fe/features/curriculum/presentation/widgets/audio_player_panel.dart';
import 'package:nest_fe/features/curriculum/presentation/widgets/file_previews.dart';
import 'package:nest_fe/features/curriculum/presentation/widgets/permission_badge.dart';
import 'package:nest_fe/features/curriculum/presentation/widgets/playlist_navigation.dart';
import 'package:url_launcher/url_launcher.dart';

/// Opens one material: the practice player for songs, a markable page for documents, a picture
/// for images.
///
/// A single screen rather than three, because everything around the file - the title, the note,
/// the download rule - is identical regardless of type. Only the middle changes.
class FileViewerScreen extends ConsumerStatefulWidget {
  const FileViewerScreen({
    super.key,
    required this.material,
    this.playlistNav,
    this.autoPlay = false,
    this.onOpenLibrary,
    this.onEdit,
  });

  final StudyMaterial material;
  final PlaylistNavigation? playlistNav;
  final bool autoPlay;

  /// The song-library shortcut beside the player's transport.
  final VoidCallback? onOpenLibrary;

  /// Shown as "Edit file details" under the download rule. Only passed to people who can edit.
  final VoidCallback? onEdit;

  @override
  ConsumerState<FileViewerScreen> createState() => _FileViewerScreenState();
}

class _FileViewerScreenState extends ConsumerState<FileViewerScreen> {
  /// Hides everything but the file itself. Documents and images only - audio has no visual to
  /// enlarge, and its controls are the point.
  bool _fullscreen = false;

  final _markup = MarkupController();

  StudyMaterial get material => widget.material;

  bool get _isPdf =>
      material.fileType == StudyMaterialType.notes &&
      (material.fileName.toLowerCase().endsWith('.pdf') ||
          material.contentType == 'application/pdf');

  @override
  void initState() {
    super.initState();
    // Real pages for a PDF; any other document keeps the cover card.
    if (_isPdf) {
      final url = ApiConfig.resolveMediaUrl(material.url);
      if (url != null) _markup.loadPdf(Uri.parse(url));
    }
  }

  @override
  void dispose() {
    _markup.dispose();
    super.dispose();
  }

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
    if (launched && mounted) showAppToast(context, 'Download started');
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final type = material.fileType;

    // Fullscreen: the title bar, note and footer step aside so the page gets the whole frame.
    if (_fullscreen && type != StudyMaterialType.audio) {
      return Scaffold(
        backgroundColor: palette.bg,
        body: SafeArea(child: _preview(fullscreen: true)),
      );
    }

    return Scaffold(
      backgroundColor: palette.bg,
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _header(palette),
            if ((material.description ?? '').isNotEmpty)
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
                child: Text(material.description!,
                    style: TextStyle(
                        fontSize: AppType.base, color: palette.textMuted, height: 1.5)),
              ),
            Expanded(child: _preview(fullscreen: false)),
            _footer(palette),
          ],
        ),
      ),
    );
  }

  Widget _header(AppPalette palette) {
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 16),
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
                Text(material.fileName,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: AppType.smd, color: palette.textMuted)),
              ],
            ),
          ),
          const SizedBox(width: AppSpacing.md),
          PermissionBadge(permission: material.permission),
        ],
      ),
    );
  }

  Widget _preview({required bool fullscreen}) {
    switch (material.fileType) {
      case StudyMaterialType.audio:
        return SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(14, 14, 14, 16),
          child: Center(
            child: AudioPlayerPanel(
              material: material,
              autoPlay: widget.autoPlay,
              playlistNav: widget.playlistNav,
              onOpenLibrary: widget.onOpenLibrary,
            ),
          ),
        );
      case StudyMaterialType.image:
        return ImagePreview(
          material: material,
          fullscreen: fullscreen,
          onEnterFullscreen: () => setState(() => _fullscreen = true),
          onExitFullscreen: () => setState(() => _fullscreen = false),
        );
      case StudyMaterialType.notes:
        return DocumentPreview(
          material: material,
          controller: _markup,
          fullscreen: fullscreen,
          onEnterFullscreen: () => setState(() => _fullscreen = true),
          onExitFullscreen: () => setState(() => _fullscreen = false),
        );
    }
  }

  Widget _footer(AppPalette palette) {
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 14, 20, 18),
      decoration:
          BoxDecoration(border: Border(top: BorderSide(color: palette.borderSoft))),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (material.isDownloadable)
            AppPrimaryButton(
              label: 'Download file',
              icon: Icons.download_outlined,
              onPressed: _download,
            )
          else
            Container(
              padding: const EdgeInsets.symmetric(vertical: 13),
              decoration: BoxDecoration(
                color: palette.surfaceHigh,
                borderRadius: AppRadii.all(AppRadii.xl),
                border: Border.all(color: palette.border),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.lock_outline, size: 14, color: palette.textMuted),
                  const SizedBox(width: 8),
                  Text('View only — download disabled',
                      style: TextStyle(
                          fontSize: AppType.md,
                          fontWeight: AppType.bold,
                          color: palette.textMuted)),
                ],
              ),
            ),
          if (widget.onEdit != null)
            Pressable(
              onTap: widget.onEdit,
              child: Padding(
                padding: const EdgeInsets.only(top: 10),
                child: Text('Edit file details',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                        fontSize: AppType.base,
                        fontWeight: AppType.bold,
                        color: palette.primary)),
              ),
            ),
        ],
      ),
    );
  }
}
