import 'package:flutter/foundation.dart';

/// Where a track sits inside a playlist, handed to the player so Previous/Next work and the
/// track list can advance when a song ends.
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
