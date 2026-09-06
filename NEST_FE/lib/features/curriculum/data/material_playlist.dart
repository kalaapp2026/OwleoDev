import 'package:nest_fe/features/curriculum/data/study_material.dart';

/// A trainer's running order over the audio they have uploaded.
class MaterialPlaylist {
  const MaterialPlaylist({
    required this.id,
    required this.name,
    required this.createdAt,
    required this.entries,
  });

  final String id;
  final String name;
  final DateTime createdAt;
  final List<PlaylistEntry> entries;

  int get length => entries.length;

  /// Total playing time is not knowable without decoding every file, so the list shows a count.
  String get countLabel => '$length song${length == 1 ? '' : 's'}';

  /// How many distinct pieces, which differs from [length] whenever one repeats.
  int get distinctMaterials => entries.map((e) => e.material.id).toSet().length;

  factory MaterialPlaylist.fromJson(Map<String, dynamic> json) => MaterialPlaylist(
        id: json['id'] as String,
        name: json['name'] as String? ?? 'Untitled',
        createdAt: DateTime.parse(json['createdAt'] as String),
        entries: ((json['entries'] as List?) ?? const [])
            .map((e) => PlaylistEntry.fromJson(e as Map<String, dynamic>))
            .toList(),
      );
}

/// One appearance of a material in a playlist.
///
/// Addressed by [entryId], never by the material's id: the same piece legitimately appears twice
/// in one running order - once slowly, once up to tempo - and acting on the material would hit
/// both.
class PlaylistEntry {
  const PlaylistEntry({
    required this.entryId,
    required this.position,
    required this.material,
  });

  final String entryId;
  final int position;
  final StudyMaterial material;

  factory PlaylistEntry.fromJson(Map<String, dynamic> json) => PlaylistEntry(
        entryId: json['entryId'] as String,
        position: (json['position'] as num?)?.toInt() ?? 0,
        material: StudyMaterial.fromJson(json['material'] as Map<String, dynamic>),
      );
}

/// One stretch of a track to play, with the tempo for that stretch specifically.
///
/// Several of these play back-to-back with the gaps skipped - the intro and the coda without the
/// middle - which is why each carries its own speed rather than inheriting one for the whole file.
class PlaybackSegment {
  const PlaybackSegment({
    required this.start,
    required this.end,
    required this.speed,
  });

  /// Seconds from the start of the file.
  final int start;
  final int end;
  final double speed;

  Duration get duration => Duration(seconds: end - start);

  bool get isValid => end > start;

  Map<String, dynamic> toJson() => {'start': start, 'end': end, 'speed': speed};

  factory PlaybackSegment.fromJson(Map<String, dynamic> json) => PlaybackSegment(
        start: (json['start'] as num?)?.toInt() ?? 0,
        end: (json['end'] as num?)?.toInt() ?? 0,
        speed: (json['speed'] as num?)?.toDouble() ?? 1.0,
      );
}

/// How one person plays one track. Saved per person, so two trainers practising the same piece
/// keep their own tempo.
class PlaybackSettings {
  const PlaybackSettings({
    this.speed = 1.0,
    this.volume = 80,
    this.loopEnabled = false,
    this.segments = const [],
  });

  /// 0.25x to 2x.
  final double speed;

  /// 0 to 100.
  final int volume;
  final bool loopEnabled;

  /// Empty means play the whole file.
  final List<PlaybackSegment> segments;

  bool get isTrimmed => segments.isNotEmpty;

  PlaybackSettings copyWith({
    double? speed,
    int? volume,
    bool? loopEnabled,
    List<PlaybackSegment>? segments,
  }) =>
      PlaybackSettings(
        speed: speed ?? this.speed,
        volume: volume ?? this.volume,
        loopEnabled: loopEnabled ?? this.loopEnabled,
        segments: segments ?? this.segments,
      );

  Map<String, dynamic> toJson() => {
        'speed': speed,
        'volume': volume,
        'loopEnabled': loopEnabled,
        'segments': segments.map((s) => s.toJson()).toList(),
      };

  factory PlaybackSettings.fromJson(Map<String, dynamic> json) => PlaybackSettings(
        speed: (json['speed'] as num?)?.toDouble() ?? 1.0,
        volume: (json['volume'] as num?)?.toInt() ?? 80,
        loopEnabled: json['loopEnabled'] as bool? ?? false,
        segments: ((json['segments'] as List?) ?? const [])
            .map((e) => PlaybackSegment.fromJson(e as Map<String, dynamic>))
            .toList(),
      );
}

/// Formats seconds as `m:ss`, the only format the player shows.
String formatPlaybackTime(int seconds) {
  final safe = seconds < 0 ? 0 : seconds;
  return '${safe ~/ 60}:${(safe % 60).toString().padLeft(2, '0')}';
}

/// Parses `m:ss` or a bare second count back, for the trim fields. Null when unparseable, so the
/// caller can tell "not entered" from "zero".
int? parsePlaybackTime(String input) {
  final text = input.trim();
  if (text.isEmpty) return null;
  if (!text.contains(':')) return int.tryParse(text);
  final parts = text.split(':');
  if (parts.length != 2) return null;
  final minutes = int.tryParse(parts[0].trim());
  final seconds = int.tryParse(parts[1].trim());
  if (minutes == null || seconds == null || seconds >= 60) return null;
  return minutes * 60 + seconds;
}
