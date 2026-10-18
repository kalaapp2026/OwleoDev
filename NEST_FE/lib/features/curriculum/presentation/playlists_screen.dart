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
import 'package:nest_fe/features/curriculum/presentation/widgets/material_row.dart';
import 'package:nest_fe/features/curriculum/presentation/widgets/playlist_navigation.dart';

void _showError(BuildContext context, Object e) {
  if (context.mounted) {
    showAppToast(context, e.toString().replaceFirst('Exception: ', ''), error: true);
  }
}

/// A full-width dashed-outline button: "New Playlist", "Add songs".
class _DashedButton extends StatelessWidget {
  const _DashedButton({required this.icon, required this.label, required this.onTap});

  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return Pressable(
      onTap: onTap,
      child: CustomPaint(
        painter: _DashedBorderPainter(palette.border),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 12),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, size: 15, color: palette.primary),
              const SizedBox(width: 7),
              Text(label,
                  style: TextStyle(
                      fontSize: AppType.lg,
                      fontWeight: AppType.bold,
                      color: palette.primary)),
            ],
          ),
        ),
      ),
    );
  }
}

class _DashedBorderPainter extends CustomPainter {
  _DashedBorderPainter(this.color);
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final path = Path()
      ..addRRect(RRect.fromRectAndRadius(
          Offset.zero & size, const Radius.circular(AppRadii.xl)));
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5;
    for (final metric in path.computeMetrics()) {
      var distance = 0.0;
      while (distance < metric.length) {
        canvas.drawPath(metric.extractPath(distance, distance + 5), paint);
        distance += 9;
      }
    }
  }

  @override
  bool shouldRepaint(_DashedBorderPainter old) => old.color != color;
}

Widget _topBar(
  BuildContext context, {
  required String title,
  required String subtitle,
  Widget? right,
  IconData backIcon = Icons.arrow_back,
}) {
  final palette = context.palette;
  return Container(
    padding: const EdgeInsets.fromLTRB(20, 20, 20, 16),
    decoration: BoxDecoration(border: Border(bottom: BorderSide(color: palette.borderSoft))),
    child: Row(
      children: [
        AppIconButton(icon: backIcon, onTap: () => Navigator.of(context).maybePop()),
        const SizedBox(width: AppSpacing.lg),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                      fontSize: AppType.title,
                      fontWeight: AppType.bold,
                      letterSpacing: AppType.titleTracking,
                      color: palette.text)),
              const SizedBox(height: 2),
              Text(subtitle,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: AppType.smd, color: palette.textMuted)),
            ],
          ),
        ),
        ?right,
      ],
    ),
  );
}

Widget _emptyNote(AppPalette palette, String text) => Padding(
      padding: const EdgeInsets.fromLTRB(20, 30, 20, 0),
      child: Text(text,
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: AppType.lg, color: palette.textFaint, height: 1.6)),
    );

/// The caller's own running orders.
///
/// Private by design: a playlist is a personal teaching aid, closer to a bookmark than to shared
/// content, so there is no academy-wide list and no sharing.
class PlaylistsScreen extends ConsumerStatefulWidget {
  const PlaylistsScreen({super.key, this.onOpenLibrary});

  /// What the player's song-library button does from inside a playlist. Handed in by whoever
  /// opened this screen, because the library itself opens playlists.
  final VoidCallback? onOpenLibrary;

  @override
  ConsumerState<PlaylistsScreen> createState() => _PlaylistsScreenState();
}

class _PlaylistsScreenState extends ConsumerState<PlaylistsScreen> {
  final _nameController = TextEditingController();
  bool _creating = false;

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  Future<void> _create() async {
    final name = _nameController.text.trim();
    if (name.isEmpty) return;
    try {
      final created = await ref.read(studyMaterialApiProvider).createPlaylist(name);
      ref.invalidate(materialPlaylistsProvider);
      if (!mounted) return;
      setState(() {
        _creating = false;
        _nameController.clear();
      });
      showAppToast(context, 'Playlist created');
      // Straight into the new playlist - an empty one on the list is not the goal, adding songs
      // to it is.
      await Navigator.of(context).push(MaterialPageRoute(
        builder: (_) => PlaylistDetailScreen(
            playlistId: created.id, onOpenLibrary: widget.onOpenLibrary),
      ));
      ref.invalidate(materialPlaylistsProvider);
    } catch (e) {
      if (mounted) _showError(context, e);
    }
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final async = ref.watch(materialPlaylistsProvider);
    final count = async.valueOrNull?.length;

    return Scaffold(
      backgroundColor: palette.bg,
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _topBar(
              context,
              title: 'Playlists',
              subtitle: count == null ? 'Your own running orders' : '$count playlist${count == 1 ? '' : 's'}',
            ),
            Expanded(
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
                data: (playlists) => ListView(
                  padding: const EdgeInsets.fromLTRB(20, 14, 20, 24),
                  children: [
                    _creating ? _nameRow(palette) : _DashedButton(
                      icon: Icons.add,
                      label: 'New Playlist',
                      onTap: () => setState(() => _creating = true),
                    ),
                    const SizedBox(height: 14),
                    if (playlists.isEmpty && !_creating)
                      _emptyNote(palette,
                          'No playlists yet — group songs together to play them in order.'),
                    for (final playlist in playlists)
                      Padding(
                        padding: const EdgeInsets.only(bottom: AppSpacing.sm),
                        child: _PlaylistRow(
                          playlist: playlist,
                          onTap: () async {
                            await Navigator.of(context).push(MaterialPageRoute(
                              builder: (_) => PlaylistDetailScreen(
                                  playlistId: playlist.id,
                                  onOpenLibrary: widget.onOpenLibrary),
                            ));
                            ref.invalidate(materialPlaylistsProvider);
                          },
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _nameRow(AppPalette palette) {
    return Row(
      spacing: 8,
      children: [
        Expanded(
          child: TextField(
            controller: _nameController,
            autofocus: true,
            textCapitalization: TextCapitalization.words,
            onSubmitted: (_) => _create(),
            style: TextStyle(
                fontSize: AppType.lg, fontWeight: AppType.bold, color: palette.text),
            decoration: InputDecoration(
              isDense: true,
              hintText: 'Playlist name',
              hintStyle: TextStyle(fontSize: AppType.lg, color: palette.textFaint),
              filled: true,
              fillColor: palette.surfaceRaised,
              contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
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
        ),
        Pressable(
          onTap: _create,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: BoxDecoration(
                color: palette.primary, borderRadius: AppRadii.all(AppRadii.lg)),
            child: Text('Create',
                style: TextStyle(
                    fontSize: AppType.md,
                    fontWeight: AppType.bold,
                    color: palette.onPrimary)),
          ),
        ),
        Pressable(
          onTap: () => setState(() {
            _creating = false;
            _nameController.clear();
          }),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
            decoration: BoxDecoration(
              borderRadius: AppRadii.all(AppRadii.lg),
              border: Border.all(color: palette.border),
            ),
            child: Text('Cancel',
                style: TextStyle(
                    fontSize: AppType.md,
                    fontWeight: AppType.bold,
                    color: palette.textMuted)),
          ),
        ),
      ],
    );
  }
}

class _PlaylistRow extends StatelessWidget {
  const _PlaylistRow({required this.playlist, required this.onTap});

  final MaterialPlaylist playlist;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final first = playlist.entries.isEmpty ? null : playlist.entries.first.material;

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
              height: 40,
              width: 40,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: palette.primarySoft,
                borderRadius: AppRadii.all(AppRadii.lg),
              ),
              child: Icon(Icons.format_list_numbered, size: 18, color: palette.primary),
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
                          fontSize: AppType.xl,
                          fontWeight: AppType.semi,
                          color: palette.text)),
                  const SizedBox(height: 3),
                  Text(
                    '${playlist.countLabel}'
                    '${first != null ? ' · Starts with "${first.title}"' : ''}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: AppType.sm, color: palette.textFaint),
                  ),
                ],
              ),
            ),
            Icon(Icons.chevron_right, size: 16, color: palette.textFaint),
          ],
        ),
      ),
    );
  }
}

/// One playlist: its running order, reorderable by drag.
class PlaylistDetailScreen extends ConsumerStatefulWidget {
  const PlaylistDetailScreen({super.key, required this.playlistId, this.onOpenLibrary});

  final String playlistId;
  final VoidCallback? onOpenLibrary;

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

  /// The entry the player last landed on, so the list can say "Playing" against it.
  String? _playingEntryId;

  void _refresh() {
    setState(() => _optimistic = null);
    ref.invalidate(materialPlaylistProvider(widget.playlistId));
    ref.invalidate(materialPlaylistsProvider);
  }

  Future<void> _run(Future<void> Function() action, {String? toast}) async {
    setState(() => _busy = true);
    try {
      await action();
      _refresh();
      if (toast != null && mounted) showAppToast(context, toast);
    } catch (e) {
      if (mounted) setState(() => _optimistic = null);
      if (mounted) _showError(context, e);
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
      builder: (_) => _AddSongsScreen(playlist: playlist),
    ));
    if (picked == null || picked.isEmpty) return;
    await _run(
      () => ref.read(studyMaterialApiProvider).addToPlaylist(widget.playlistId, picked),
      toast: '${picked.length} song${picked.length == 1 ? '' : 's'} added',
    );
  }

  Future<void> _delete(MaterialPlaylist playlist) async {
    final confirmed = await showAppConfirmDialog(
      context: context,
      title: 'Delete this playlist?',
      message: '"${playlist.name}" will be deleted. The songs inside it won\'t be affected.',
      confirmLabel: 'Delete',
    );
    if (!confirmed) return;
    try {
      await ref.read(studyMaterialApiProvider).deletePlaylist(widget.playlistId);
      ref.invalidate(materialPlaylistsProvider);
      if (!mounted) return;
      showAppToast(context, 'Playlist deleted');
      Navigator.of(context).pop();
    } catch (e) {
      if (mounted) _showError(context, e);
    }
  }

  void _play(MaterialPlaylist playlist, String entryId) {
    // By id, not by row: the list may be showing a dragged order the server has not confirmed yet.
    final index = playlist.entries.indexWhere((e) => e.entryId == entryId);
    if (index == -1) return;
    setState(() => _playingEntryId = entryId);
    Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => _PlaylistPlayer(
        playlist: playlist,
        startIndex: index,
        onOpenLibrary: widget.onOpenLibrary,
        onEntryChanged: (id) {
          if (mounted) setState(() => _playingEntryId = id);
        },
      ),
    ));
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
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
                _topBar(
                  context,
                  title: playlist.name,
                  subtitle: playlist.countLabel,
                  right: AppIconButton(
                    icon: Icons.delete_outline,
                    tooltip: 'Delete playlist',
                    color: palette.notPaid,
                    iconSize: 15,
                    onTap: () => _delete(playlist),
                  ),
                ),
                if (_busy)
                  LinearProgressIndicator(
                      minHeight: 2,
                      backgroundColor: palette.surfaceHigh,
                      color: palette.primary),
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 14, 20, 0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      _DashedButton(
                        icon: Icons.add,
                        label: 'Add songs',
                        onTap: () => _addSongs(playlist),
                      ),
                      const SizedBox(height: 14),
                      if (entries.isNotEmpty)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 8),
                          child: Text(
                            'Drag the handle to reorder. Duplicate a song to repeat it later in the sequence.',
                            style: TextStyle(fontSize: AppType.tiny, color: palette.textFaint),
                          ),
                        ),
                    ],
                  ),
                ),
                Expanded(
                  child: entries.isEmpty
                      ? Align(
                          alignment: Alignment.topCenter,
                          child: _emptyNote(palette, 'No songs in this playlist yet.'),
                        )
                      : ReorderableListView.builder(
                          buildDefaultDragHandles: false,
                          padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
                          itemCount: entries.length,
                          onReorderItem: (o, n) => _reorder(entries, o, n),
                          proxyDecorator: (child, _, _) => Material(
                            color: Colors.transparent,
                            child: Opacity(opacity: 0.92, child: child),
                          ),
                          itemBuilder: (context, i) => Padding(
                            key: ValueKey(entries[i].entryId),
                            padding: const EdgeInsets.only(bottom: AppSpacing.sm),
                            child: _entryRow(palette, playlist, entries, i),
                          ),
                        ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }

  Widget _entryRow(
      AppPalette palette, MaterialPlaylist playlist, List<PlaylistEntry> entries, int i) {
    final entry = entries[i];
    final m = entry.material;
    final active = entry.entryId == _playingEntryId;
    final audio = StudyMaterialType.audio;

    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: active ? palette.primarySoft : palette.surfaceRaised,
        borderRadius: AppRadii.all(AppRadii.xxl),
        border: Border.all(color: active ? palette.primary : palette.borderSoft),
      ),
      child: Row(
        children: [
          ReorderableDragStartListener(
            index: i,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 10),
              child: Icon(Icons.drag_indicator, size: 16, color: palette.textFaint),
            ),
          ),
          Expanded(
            child: Pressable(
              onTap: () => _play(playlist, entry.entryId),
              child: Row(
                children: [
                  Container(
                    width: 36,
                    height: 36,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: audio.softColor(palette),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Icon(audio.icon, size: 16, color: audio.color(palette)),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(m.title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                                fontSize: AppType.lg,
                                fontWeight: AppType.semi,
                                color: palette.text)),
                        const SizedBox(height: 2),
                        Text(m.sizeLabel,
                            style: TextStyle(
                                fontSize: AppType.tiny, color: palette.textFaint)),
                      ],
                    ),
                  ),
                  if (active)
                    Padding(
                      padding: const EdgeInsets.only(right: 4),
                      child: Text('Playing',
                          style: TextStyle(
                              fontSize: AppType.micro,
                              fontWeight: AppType.heavy,
                              color: palette.primary)),
                    ),
                ],
              ),
            ),
          ),
          Tooltip(
            message: 'Duplicate in this playlist',
            child: Pressable(
              onTap: () => _run(
                () => ref
                    .read(studyMaterialApiProvider)
                    .duplicateEntry(widget.playlistId, entry.entryId),
                toast: 'Song duplicated',
              ),
              child: Padding(
                padding: const EdgeInsets.all(4),
                child: Icon(Icons.copy_outlined, size: 14, color: palette.textFaint),
              ),
            ),
          ),
          Tooltip(
            message: 'Remove from playlist',
            child: Pressable(
              onTap: () => _run(() => ref
                  .read(studyMaterialApiProvider)
                  .removeFromPlaylist(widget.playlistId, entry.entryId)),
              child: Padding(
                padding: const EdgeInsets.all(4),
                child: Icon(Icons.close, size: 14, color: palette.textFaint),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Walks a playlist, keeping its place as tracks advance.
///
/// Holds the index here rather than pushing a new route per track, so a forty-minute class does
/// not build a forty-deep navigation stack.
class _PlaylistPlayer extends StatefulWidget {
  const _PlaylistPlayer({
    required this.playlist,
    required this.startIndex,
    required this.onEntryChanged,
    this.onOpenLibrary,
  });

  final MaterialPlaylist playlist;
  final int startIndex;
  final ValueChanged<String> onEntryChanged;
  final VoidCallback? onOpenLibrary;

  @override
  State<_PlaylistPlayer> createState() => _PlaylistPlayerState();
}

class _PlaylistPlayerState extends State<_PlaylistPlayer> {
  late int _index = widget.startIndex;

  /// False on the track opened by hand, true on every one reached by advancing - so tapping a
  /// song does not start it playing before you are ready, but a running order does not stall.
  bool _autoPlay = false;

  void _go(int index) {
    setState(() {
      _index = index;
      _autoPlay = true;
    });
    widget.onEntryChanged(widget.playlist.entries[index].entryId);
  }

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
      onOpenLibrary: widget.onOpenLibrary,
      playlistNav: PlaylistNavigation(
        playlistName: widget.playlist.name,
        index: _index,
        total: entries.length,
        onPrevious: _index > 0 ? () => _go(_index - 1) : null,
        onNext: _index < entries.length - 1 ? () => _go(_index + 1) : null,
      ),
    );
  }
}

/// Picks songs to append. Returns the chosen material ids, or null if dismissed.
///
/// Songs already in the playlist are left out - repeating one is what Duplicate is for.
class _AddSongsScreen extends ConsumerStatefulWidget {
  const _AddSongsScreen({required this.playlist});

  final MaterialPlaylist playlist;

  @override
  ConsumerState<_AddSongsScreen> createState() => _AddSongsScreenState();
}

class _AddSongsScreenState extends ConsumerState<_AddSongsScreen> {
  final _selected = <String>[];

  void _toggle(String id) =>
      setState(() => _selected.contains(id) ? _selected.remove(id) : _selected.add(id));

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final async = ref.watch(materialLibraryProvider(StudyMaterialType.audio));
    final inPlaylist = widget.playlist.entries.map((e) => e.material.id).toSet();

    return Scaffold(
      backgroundColor: palette.bg,
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _topBar(context, title: 'Add Songs', subtitle: widget.playlist.name),
            Expanded(
              child: async.when(
                loading: () => const Center(child: CircularProgressIndicator()),
                error: (e, _) => Center(
                  child: Text(e.toString().replaceFirst('Exception: ', ''),
                      style: TextStyle(fontSize: AppType.lg, color: palette.textMuted)),
                ),
                data: (songs) {
                  final available = songs.where((s) => !inPlaylist.contains(s.id)).toList();
                  if (available.isEmpty) {
                    return Align(
                      alignment: Alignment.topCenter,
                      child: _emptyNote(palette, 'Every uploaded song is already in this playlist.'),
                    );
                  }
                  return ListView.builder(
                    padding: const EdgeInsets.fromLTRB(20, 14, 20, 24),
                    itemCount: available.length,
                    itemBuilder: (context, i) {
                      final song = available[i];
                      final on = _selected.contains(song.id);
                      return Padding(
                        padding: const EdgeInsets.only(bottom: AppSpacing.sm),
                        child: MaterialRow(
                          material: song,
                          highlighted: on,
                          highlightColor: palette.primary,
                          onTap: () => _toggle(song.id),
                          trailing: Container(
                            width: 22,
                            height: 22,
                            alignment: Alignment.center,
                            decoration: BoxDecoration(
                              color: on ? palette.primary : Colors.transparent,
                              borderRadius: BorderRadius.circular(6),
                              border: Border.all(
                                  color: on ? palette.primary : palette.border, width: 1.5),
                            ),
                            child: on
                                ? Icon(Icons.check, size: 14, color: palette.onPrimary)
                                : null,
                          ),
                        ),
                      );
                    },
                  );
                },
              ),
            ),
            Container(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 18),
              decoration: BoxDecoration(
                  border: Border(top: BorderSide(color: palette.borderSoft))),
              child: AppPrimaryButton(
                label: 'Add ${_selected.isEmpty ? '' : '${_selected.length} '}'
                    'song${_selected.length == 1 ? '' : 's'}',
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
