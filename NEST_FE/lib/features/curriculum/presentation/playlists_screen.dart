import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:nest_fe/app/theme/app_tokens.dart';
import 'package:nest_fe/app/theme/app_typography.dart';
import 'package:nest_fe/core/design/buttons.dart';
import 'package:nest_fe/core/design/confirm_dialog.dart';
import 'package:nest_fe/core/design/pressable.dart';
import 'package:nest_fe/core/design/toast.dart';
import 'package:nest_fe/features/curriculum/data/material_playlist.dart';
import 'package:nest_fe/features/curriculum/data/study_material.dart';
import 'package:nest_fe/features/curriculum/data/study_material_api.dart';
import 'package:nest_fe/features/curriculum/presentation/file_viewer_screen.dart';
import 'package:nest_fe/features/curriculum/presentation/material_library_screen.dart';

/// The caller's own running orders.
///
/// Private by design: a playlist is a personal teaching aid, closer to a bookmark than to shared
/// content, so there is no academy-wide list and no sharing.
class PlaylistsScreen extends ConsumerWidget {
  const PlaylistsScreen({super.key});

  Future<void> _create(BuildContext context, WidgetRef ref) async {
    final name = await _promptForName(context, title: 'New playlist');
    if (name == null) return;
    try {
      final created = await ref.read(studyMaterialApiProvider).createPlaylist(name);
      ref.invalidate(materialPlaylistsProvider);
      if (!context.mounted) return;
      // Straight into the new playlist - an empty one on the list is not the goal, adding songs
      // to it is.
      await Navigator.of(context).push(MaterialPageRoute(
        builder: (_) => PlaylistDetailScreen(playlistId: created.id),
      ));
      ref.invalidate(materialPlaylistsProvider);
    } catch (e) {
      if (context.mounted) {
        showAppToast(context, e.toString().replaceFirst('Exception: ', ''));
      }
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final palette = context.palette;
    final accent = palette.coral;
    final async = ref.watch(materialPlaylistsProvider);

    return Scaffold(
      backgroundColor: palette.bg,
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Container(
              padding: const EdgeInsets.fromLTRB(AppSpacing.page, AppSpacing.x4l,
                  AppSpacing.page, AppSpacing.xxl),
              decoration: BoxDecoration(
                  border: Border(bottom: BorderSide(color: palette.borderSoft))),
              child: Row(
                children: [
                  AppIconButton(
                      icon: Icons.arrow_back,
                      onTap: () => Navigator.of(context).maybePop()),
                  const SizedBox(width: AppSpacing.lg),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text('Playlists',
                            style: TextStyle(
                                fontSize: AppType.title,
                                fontWeight: AppType.bold,
                                letterSpacing: AppType.titleTracking,
                                color: palette.text)),
                        const SizedBox(height: 2),
                        Text('Your own running orders',
                            style: TextStyle(
                                fontSize: AppType.smd, color: palette.textMuted)),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            Expanded(
              child: async.when(
                loading: () => const Center(child: CircularProgressIndicator()),
                error: (e, _) => Center(
                  child: Padding(
                    padding: const EdgeInsets.all(AppSpacing.x4l),
                    child: Text(e.toString().replaceFirst('Exception: ', ''),
                        textAlign: TextAlign.center,
                        style: TextStyle(
                            fontSize: AppType.lg, color: palette.textMuted)),
                  ),
                ),
                data: (playlists) {
                  if (playlists.isEmpty) {
                    return Center(
                      child: Padding(
                        padding: const EdgeInsets.all(AppSpacing.x4l),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.queue_music,
                                size: 34, color: palette.textFaint),
                            const SizedBox(height: AppSpacing.lg),
                            Text(
                              'No playlists yet.\nBuild one to line up a class without hunting '
                              'for the next track between exercises.',
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                  fontSize: AppType.lg,
                                  color: palette.textMuted,
                                  height: 1.6),
                            ),
                          ],
                        ),
                      ),
                    );
                  }
                  return ListView.builder(
                    padding: const EdgeInsets.fromLTRB(AppSpacing.page,
                        AppSpacing.xl, AppSpacing.page, AppSpacing.listBottom),
                    itemCount: playlists.length,
                    itemBuilder: (context, i) => Padding(
                      padding: const EdgeInsets.only(bottom: AppSpacing.md),
                      child: _PlaylistRow(
                        playlist: playlists[i],
                        accent: accent,
                        onTap: () async {
                          await Navigator.of(context).push(MaterialPageRoute(
                            builder: (_) =>
                                PlaylistDetailScreen(playlistId: playlists[i].id),
                          ));
                          ref.invalidate(materialPlaylistsProvider);
                        },
                      ),
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
      floatingActionButton: Pressable(
        onTap: () => _create(context, ref),
        child: Container(
          padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.x4l, vertical: AppSpacing.xl),
          decoration: BoxDecoration(
            color: accent,
            borderRadius: AppRadii.all(AppRadii.pill),
            boxShadow: AppShadows.dropdown,
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.add, size: 17, color: palette.onPrimary),
              const SizedBox(width: AppSpacing.sm),
              Text('New playlist',
                  style: TextStyle(
                      fontSize: AppType.xxl,
                      fontWeight: AppType.bold,
                      color: palette.onPrimary)),
            ],
          ),
        ),
      ),
    );
  }
}

class _PlaylistRow extends StatelessWidget {
  const _PlaylistRow({
    required this.playlist,
    required this.accent,
    required this.onTap,
  });

  final MaterialPlaylist playlist;
  final Color accent;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final repeats = playlist.length - playlist.distinctMaterials;

    return Pressable(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(AppSpacing.lg),
        decoration: BoxDecoration(
          color: palette.surfaceRaised,
          borderRadius: AppRadii.all(AppRadii.xxl),
          border: Border.all(color: palette.borderSoft),
        ),
        child: Row(
          children: [
            Container(
              height: 44,
              width: 44,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: accent.withValues(alpha: 0.14),
                borderRadius: AppRadii.all(AppRadii.lg),
              ),
              child: Icon(Icons.queue_music, size: 20, color: accent),
            ),
            const SizedBox(width: AppSpacing.lg),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(playlist.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                          fontSize: AppType.x3l,
                          fontWeight: AppType.bold,
                          color: palette.text)),
                  const SizedBox(height: 3),
                  Text(
                    playlist.length == 0
                        ? 'Empty'
                        : '${playlist.countLabel}'
                            // Only worth saying when it is true - it explains why the count is
                            // higher than the number of distinct files.
                            '${repeats > 0 ? ', $repeats repeated' : ''}',
                    style:
                        TextStyle(fontSize: AppType.sm, color: palette.textFaint),
                  ),
                ],
              ),
            ),
            Icon(Icons.chevron_right, size: 18, color: palette.textFaint),
          ],
        ),
      ),
    );
  }
}

/// One playlist: its running order, reorderable by drag.
class PlaylistDetailScreen extends ConsumerStatefulWidget {
  const PlaylistDetailScreen({super.key, required this.playlistId});

  final String playlistId;

  @override
  ConsumerState<PlaylistDetailScreen> createState() => _PlaylistDetailScreenState();
}

class _PlaylistDetailScreenState extends ConsumerState<PlaylistDetailScreen> {
  /// The order shown while a save is in flight.
  ///
  /// A drag has to redraw instantly, but the server is the authority on position. Holding the
  /// dragged order here keeps the list from snapping back to the old one for the duration of the
  /// round trip.
  List<PlaylistEntry>? _optimistic;
  bool _busy = false;

  void _refresh() {
    setState(() => _optimistic = null);
    ref.invalidate(materialPlaylistProvider(widget.playlistId));
    ref.invalidate(materialPlaylistsProvider);
  }

  Future<void> _run(Future<void> Function() action) async {
    setState(() => _busy = true);
    try {
      await action();
      _refresh();
    } catch (e) {
      if (mounted) {
        setState(() => _optimistic = null);
        showAppToast(context, e.toString().replaceFirst('Exception: ', ''));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _reorder(List<PlaylistEntry> entries, int oldIndex, int newIndex) async {
    // onReorderItem already accounts for the removed row, unlike the deprecated onReorder, so
    // newIndex is used as given - adjusting it again would drop the row one place short.
    final next = [...entries];
    next.insert(newIndex, next.removeAt(oldIndex));
    setState(() => _optimistic = next);

    await _run(() => ref
        .read(studyMaterialApiProvider)
        .reorderPlaylist(widget.playlistId, next.map((e) => e.entryId).toList()));
  }

  Future<void> _addSongs(MaterialPlaylist playlist) async {
    final picked = await Navigator.of(context).push<List<String>>(MaterialPageRoute(
      builder: (_) => const _AddSongsScreen(),
    ));
    if (picked == null || picked.isEmpty) return;
    await _run(() => ref
        .read(studyMaterialApiProvider)
        .addToPlaylist(widget.playlistId, picked));
  }

  void _play(MaterialPlaylist playlist, int index) {
    Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => _PlaylistPlayer(playlist: playlist, startIndex: index),
    ));
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final accent = palette.coral;
    final async = ref.watch(materialPlaylistProvider(widget.playlistId));

    return Scaffold(
      backgroundColor: palette.bg,
      body: SafeArea(
        child: async.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (e, _) => Center(
            child: Padding(
              padding: const EdgeInsets.all(AppSpacing.x4l),
              child: Text(e.toString().replaceFirst('Exception: ', ''),
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: AppType.lg, color: palette.textMuted)),
            ),
          ),
          data: (playlist) {
            final entries = _optimistic ?? playlist.entries;
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _header(palette, accent, playlist),
                if (_busy)
                  LinearProgressIndicator(
                      minHeight: 2,
                      backgroundColor: palette.surfaceHigh,
                      color: accent),
                Expanded(
                  child: entries.isEmpty
                      ? _empty(palette)
                      : ReorderableListView.builder(
                          padding: const EdgeInsets.fromLTRB(AppSpacing.page,
                              AppSpacing.xl, AppSpacing.page, AppSpacing.listBottom),
                          itemCount: entries.length,
                          onReorderItem: (o, n) => _reorder(entries, o, n),
                          proxyDecorator: (child, _, _) => Material(
                            color: Colors.transparent,
                            child: Opacity(opacity: 0.9, child: child),
                          ),
                          itemBuilder: (context, i) {
                            final entry = entries[i];
                            return Padding(
                              key: ValueKey(entry.entryId),
                              padding: const EdgeInsets.only(bottom: AppSpacing.md),
                              child: MaterialRow(
                                material: entry.material,
                                onTap: () => _play(playlist, i),
                                leading: ReorderableDragStartListener(
                                  index: i,
                                  child: Icon(Icons.drag_indicator,
                                      size: 18, color: palette.textFaint),
                                ),
                                trailing: _entryMenu(palette, entry),
                              ),
                            );
                          },
                        ),
                ),
              ],
            );
          },
        ),
      ),
      floatingActionButton: async.valueOrNull == null
          ? null
          : Pressable(
              onTap: () => _addSongs(async.value!),
              child: Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: AppSpacing.x4l, vertical: AppSpacing.xl),
                decoration: BoxDecoration(
                  color: accent,
                  borderRadius: AppRadii.all(AppRadii.pill),
                  boxShadow: AppShadows.dropdown,
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.playlist_add, size: 17, color: palette.onPrimary),
                    const SizedBox(width: AppSpacing.sm),
                    Text('Add songs',
                        style: TextStyle(
                            fontSize: AppType.xxl,
                            fontWeight: AppType.bold,
                            color: palette.onPrimary)),
                  ],
                ),
              ),
            ),
    );
  }

  Widget _entryMenu(AppPalette palette, PlaylistEntry entry) {
    return PopupMenuButton<String>(
      icon: Icon(Icons.more_vert, size: 16, color: palette.textMuted),
      color: palette.surface,
      onSelected: (action) {
        if (action == 'duplicate') {
          _run(() => ref
              .read(studyMaterialApiProvider)
              .duplicateEntry(widget.playlistId, entry.entryId));
        } else {
          _run(() => ref
              .read(studyMaterialApiProvider)
              .removeFromPlaylist(widget.playlistId, entry.entryId));
        }
      },
      itemBuilder: (_) => [
        PopupMenuItem(
          value: 'duplicate',
          child: Text('Play again later',
              style: TextStyle(fontSize: AppType.lg, color: palette.text)),
        ),
        PopupMenuItem(
          value: 'remove',
          child: Text('Remove from playlist',
              style: TextStyle(fontSize: AppType.lg, color: palette.notPaid)),
        ),
      ],
    );
  }

  Widget _header(AppPalette palette, Color accent, MaterialPlaylist playlist) {
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
                Text(playlist.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                        fontSize: AppType.title,
                        fontWeight: AppType.bold,
                        letterSpacing: AppType.titleTracking,
                        color: palette.text)),
                const SizedBox(height: 2),
                Text(
                  playlist.length == 0
                      ? 'Empty - add some songs'
                      : '${playlist.countLabel} · drag to reorder',
                  style: TextStyle(fontSize: AppType.smd, color: palette.textMuted),
                ),
              ],
            ),
          ),
          PopupMenuButton<String>(
            icon: Icon(Icons.more_vert, size: 18, color: palette.textMuted),
            color: palette.surface,
            onSelected: (action) async {
              if (action == 'rename') {
                final name = await _promptForName(context,
                    title: 'Rename playlist', initial: playlist.name);
                if (name == null) return;
                await _run(() => ref
                    .read(studyMaterialApiProvider)
                    .renamePlaylist(widget.playlistId, name));
              } else {
                final confirmed = await showAppConfirmDialog(
                  context: context,
                  title: 'Delete this playlist?',
                  message: '"${playlist.name}" will be removed. The songs themselves '
                      'stay where they are - only the running order goes.',
                  confirmLabel: 'Delete',
                );
                if (!confirmed) return;
                try {
                  await ref
                      .read(studyMaterialApiProvider)
                      .deletePlaylist(widget.playlistId);
                  ref.invalidate(materialPlaylistsProvider);
                  if (mounted) Navigator.of(context).pop();
                } catch (e) {
                  if (mounted) {
                    showAppToast(
                        context, e.toString().replaceFirst('Exception: ', ''));
                  }
                }
              }
            },
            itemBuilder: (_) => [
              PopupMenuItem(
                value: 'rename',
                child: Text('Rename',
                    style: TextStyle(fontSize: AppType.lg, color: palette.text)),
              ),
              PopupMenuItem(
                value: 'delete',
                child: Text('Delete playlist',
                    style: TextStyle(fontSize: AppType.lg, color: palette.notPaid)),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _empty(AppPalette palette) => Center(
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.x4l),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.music_off_outlined, size: 34, color: palette.textFaint),
              const SizedBox(height: AppSpacing.lg),
              Text('Nothing in this playlist yet.',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                      fontSize: AppType.lg, color: palette.textMuted, height: 1.5)),
            ],
          ),
        ),
      );
}

/// Walks a playlist, keeping its place as tracks advance.
///
/// Holds the index here rather than pushing a new route per track, so a forty-minute class does
/// not build a forty-deep navigation stack.
class _PlaylistPlayer extends StatefulWidget {
  const _PlaylistPlayer({required this.playlist, required this.startIndex});

  final MaterialPlaylist playlist;
  final int startIndex;

  @override
  State<_PlaylistPlayer> createState() => _PlaylistPlayerState();
}

class _PlaylistPlayerState extends State<_PlaylistPlayer> {
  late int _index = widget.startIndex;

  /// False on the track opened by hand, true on every one reached by advancing - so tapping a
  /// song does not start it playing before you are ready, but a running order does not stall.
  bool _autoPlay = false;

  @override
  Widget build(BuildContext context) {
    final entries = widget.playlist.entries;
    final entry = entries[_index];

    return FileViewerScreen(
      // Rebuilds the player from scratch on every change, which is what stops the previous track
      // continuing underneath the next.
      key: ValueKey(entry.entryId),
      material: entry.material,
      autoPlay: _autoPlay,
      playlistNav: PlaylistNavigation(
        playlistName: widget.playlist.name,
        index: _index,
        total: entries.length,
        onPrevious: _index > 0
            ? () => setState(() {
                  _index--;
                  _autoPlay = true;
                })
            : null,
        onNext: _index < entries.length - 1
            ? () => setState(() {
                  _index++;
                  _autoPlay = true;
                })
            : null,
      ),
    );
  }
}

/// Picks songs to append. Returns the chosen material ids, or null if dismissed.
class _AddSongsScreen extends ConsumerStatefulWidget {
  const _AddSongsScreen();

  @override
  ConsumerState<_AddSongsScreen> createState() => _AddSongsScreenState();
}

class _AddSongsScreenState extends ConsumerState<_AddSongsScreen> {
  final _selected = <String>[];
  final _searchController = TextEditingController();
  String _query = '';

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final accent = palette.coral;
    final async = ref.watch(materialLibraryProvider(StudyMaterialType.audio));

    return Scaffold(
      backgroundColor: palette.bg,
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Container(
              padding: const EdgeInsets.fromLTRB(AppSpacing.page, AppSpacing.x4l,
                  AppSpacing.page, AppSpacing.xxl),
              decoration: BoxDecoration(
                  border: Border(bottom: BorderSide(color: palette.borderSoft))),
              child: Row(
                children: [
                  AppIconButton(
                      icon: Icons.close,
                      onTap: () => Navigator.of(context).pop()),
                  const SizedBox(width: AppSpacing.lg),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text('Add songs',
                            style: TextStyle(
                                fontSize: AppType.title,
                                fontWeight: AppType.bold,
                                color: palette.text)),
                        const SizedBox(height: 2),
                        Text(
                          _selected.isEmpty
                              ? 'Tap to add - tap twice to play it twice'
                              : '${_selected.length} selected',
                          style: TextStyle(
                              fontSize: AppType.smd, color: palette.textMuted),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(
                  AppSpacing.page, AppSpacing.xl, AppSpacing.page, AppSpacing.lg),
              child: Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: AppSpacing.lg, vertical: AppSpacing.md),
                decoration: BoxDecoration(
                  color: palette.surfaceRaised,
                  borderRadius: AppRadii.all(AppRadii.lg),
                  border: Border.all(color: palette.border),
                ),
                child: Row(
                  children: [
                    Icon(Icons.search, size: 14, color: palette.textFaint),
                    const SizedBox(width: AppSpacing.sm),
                    Expanded(
                      child: TextField(
                        controller: _searchController,
                        onChanged: (v) => setState(() => _query = v),
                        style: TextStyle(
                            fontSize: AppType.lg, color: palette.text),
                        decoration: InputDecoration(
                          isDense: true,
                          border: InputBorder.none,
                          contentPadding: EdgeInsets.zero,
                          hintText: 'Search songs',
                          hintStyle: TextStyle(
                              fontSize: AppType.lg, color: palette.textFaint),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            Expanded(
              child: async.when(
                loading: () => const Center(child: CircularProgressIndicator()),
                error: (e, _) => Center(
                  child: Text(e.toString().replaceFirst('Exception: ', ''),
                      style: TextStyle(
                          fontSize: AppType.lg, color: palette.textMuted)),
                ),
                data: (songs) {
                  final query = _query.trim().toLowerCase();
                  final visible = query.isEmpty
                      ? songs
                      : songs
                          .where((s) => s.title.toLowerCase().contains(query))
                          .toList();
                  if (visible.isEmpty) {
                    return Center(
                      child: Padding(
                        padding: const EdgeInsets.all(AppSpacing.x4l),
                        child: Text(
                          songs.isEmpty
                              ? 'No audio has been shared with you yet.'
                              : 'No songs match that search.',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                              fontSize: AppType.lg, color: palette.textMuted),
                        ),
                      ),
                    );
                  }
                  return ListView.builder(
                    padding: const EdgeInsets.fromLTRB(AppSpacing.page, 0,
                        AppSpacing.page, AppSpacing.listBottom),
                    itemCount: visible.length,
                    itemBuilder: (context, i) {
                      final song = visible[i];
                      final count =
                          _selected.where((id) => id == song.id).length;
                      return Padding(
                        padding: const EdgeInsets.only(bottom: AppSpacing.md),
                        child: MaterialRow(
                          material: song,
                          highlighted: count > 0,
                          // Adding the same song again is deliberate, not a mis-tap: playing a
                          // piece twice at different tempos is why entries have their own ids.
                          onTap: () => setState(() => _selected.add(song.id)),
                          trailing: count == 0
                              ? Icon(Icons.add_circle_outline,
                                  size: 18, color: palette.textFaint)
                              : Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Pressable(
                                      onTap: () => setState(
                                          () => _selected.remove(song.id)),
                                      child: Icon(Icons.remove_circle_outline,
                                          size: 18, color: palette.textMuted),
                                    ),
                                    const SizedBox(width: AppSpacing.sm),
                                    Text('x$count',
                                        style: TextStyle(
                                            fontSize: AppType.md,
                                            fontWeight: AppType.bold,
                                            color: accent)),
                                  ],
                                ),
                        ),
                      );
                    },
                  );
                },
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(AppSpacing.page),
              child: AppPrimaryButton(
                label: _selected.isEmpty
                    ? 'Pick at least one song'
                    : 'Add ${_selected.length} to playlist',
                icon: Icons.check,
                background: accent,
                onPressed: _selected.isEmpty
                    ? null
                    : () => Navigator.of(context).pop(_selected),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Shared name prompt for create and rename.
Future<String?> _promptForName(BuildContext context,
    {required String title, String initial = ''}) {
  final controller = TextEditingController(text: initial);
  final palette = context.palette;

  return showDialog<String>(
    context: context,
    barrierColor: const Color(0xB8040710),
    builder: (context) => Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.all(AppSpacing.x5l),
      child: Container(
        padding: const EdgeInsets.all(AppSpacing.x5l),
        decoration: BoxDecoration(
          color: palette.surface,
          borderRadius: AppRadii.all(AppRadii.sheet),
          border: Border.all(color: palette.border),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(title,
                style: TextStyle(
                    fontSize: AppType.title,
                    fontWeight: AppType.bold,
                    color: palette.text)),
            const SizedBox(height: AppSpacing.x4l),
            TextField(
              controller: controller,
              autofocus: true,
              textCapitalization: TextCapitalization.words,
              onSubmitted: (v) =>
                  v.trim().isEmpty ? null : Navigator.of(context).pop(v.trim()),
              style: TextStyle(
                  fontSize: AppType.xxl,
                  fontWeight: AppType.medium,
                  color: palette.text),
              decoration: InputDecoration(
                isDense: true,
                hintText: 'e.g. Warm-ups',
                hintStyle:
                    TextStyle(fontSize: AppType.lg, color: palette.textFaint),
                filled: true,
                fillColor: palette.surfaceRaised,
                contentPadding: const EdgeInsets.symmetric(
                    horizontal: AppSpacing.xl, vertical: AppSpacing.lg),
                border: OutlineInputBorder(
                  borderRadius: AppRadii.all(AppRadii.xl),
                  borderSide: BorderSide(color: palette.border),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: AppRadii.all(AppRadii.xl),
                  borderSide: BorderSide(color: palette.border),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: AppRadii.all(AppRadii.xl),
                  borderSide: BorderSide(color: palette.primary),
                ),
              ),
            ),
            const SizedBox(height: AppSpacing.x4l),
            AppPrimaryButton(
              label: 'Save',
              icon: Icons.check,
              onPressed: () {
                final value = controller.text.trim();
                if (value.isEmpty) return;
                Navigator.of(context).pop(value);
              },
            ),
          ],
        ),
      ),
    ),
  );
}
