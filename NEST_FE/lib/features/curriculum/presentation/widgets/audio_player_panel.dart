import 'dart:async';
import 'dart:math' as math;

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:nest_fe/app/theme/app_tokens.dart';
import 'package:nest_fe/app/theme/app_typography.dart';
import 'package:nest_fe/core/design/pressable.dart';
import 'package:nest_fe/core/design/toast.dart';
import 'package:nest_fe/core/network/api_config.dart';
import 'package:nest_fe/features/curriculum/data/material_playlist.dart';
import 'package:nest_fe/features/curriculum/data/study_material.dart';
import 'package:nest_fe/features/curriculum/data/study_material_api.dart';
import 'package:nest_fe/features/curriculum/presentation/widgets/playlist_navigation.dart';

// The radial cluster is laid out on a fixed 340x330 canvas and scaled to fit, so every
// coordinate below is in that space. One circle, two levers whose ends sit exactly on a larger
// circle concentric with it, and a disk at the centre.
const double _vbW = 340;
const double _vbH = 330;
const double _cx = 170;
const double _cy = 165;
const double _radius = 110; // backdrop circle
const double _leverR = _radius + 38; // concentric with the backdrop
const double _leverSpan = 46; // half-angle each lever sweeps either side of due west/east
const double _leverBoxW = 100;

enum _Side { left, right }

/// Angles in the prototype's convention: degrees clockwise from straight up.
({double bottom, double top}) _leverAngles(_Side side) => side == _Side.left
    ? (bottom: -90 - _leverSpan, top: -90 + _leverSpan)
    : (bottom: 90 + _leverSpan, top: 90 - _leverSpan);

Offset _polar(double r, double angleDeg) {
  final rad = angleDeg * math.pi / 180;
  return Offset(_cx + r * math.sin(rad), _cy - r * math.cos(rad));
}

/// The vertical extent of a lever's drag area, which is also where its label and value sit.
({double top, double height}) _leverBox(_Side side) {
  final a = _leverAngles(side);
  final top = _polar(_leverR, a.top);
  final bottom = _polar(_leverR, a.bottom);
  return (
    top: math.min(top.dy, bottom.dy) - 26,
    height: (bottom.dy - top.dy).abs() + 60,
  );
}

String _formatSpeed(double v) {
  if ((v - 0.25).abs() < 0.001) return '0.25×';
  if (v == v.roundToDouble()) return '${v.toInt()}×';
  return '${v.toStringAsFixed(1)}×';
}

/// The practice player: a disk with tempo and volume levers curving round it, a seek bar, and
/// "Custom Play" trims that play chosen stretches back-to-back.
///
/// Tempo matters more here than in a normal player. Learning a piece means slowing it to half
/// speed and creeping back up, and returning to the same tempo tomorrow - which is why the
/// settings are saved per person per track rather than reset each time.
class AudioPlayerPanel extends ConsumerStatefulWidget {
  const AudioPlayerPanel({
    super.key,
    required this.material,
    this.autoPlay = false,
    this.playlistNav,
    this.onOpenLibrary,
  });

  final StudyMaterial material;
  final bool autoPlay;

  /// Present when the track was opened from a playlist: drives Previous/Next and advancing.
  final PlaylistNavigation? playlistNav;

  /// The song library shortcut beside the transport.
  final VoidCallback? onOpenLibrary;

  @override
  ConsumerState<AudioPlayerPanel> createState() => _AudioPlayerPanelState();
}

class _AudioPlayerPanelState extends ConsumerState<AudioPlayerPanel> {
  final _player = AudioPlayer();
  final _subscriptions = <StreamSubscription<dynamic>>[];

  Duration _position = Duration.zero;
  Duration _duration = Duration.zero;
  bool _playing = false;
  bool _muted = false;

  PlaybackSettings _settings = const PlaybackSettings();

  /// Which trim is playing. Only meaningful when the settings carry segments.
  int _segmentIndex = 0;

  /// Ignores position ticks for a beat after a jump - the player can still report the old
  /// position for a moment, which would otherwise trigger a second jump.
  bool _jumping = false;

  bool _rangeOpen = false;
  String _rangeError = '';
  late List<_DraftSegment> _drafts = [_DraftSegment(speed: 1)];

  /// Debounces saves - dragging a lever emits a value per frame, and one PUT per frame would be
  /// both wasteful and out of order by the time they land.
  Timer? _saveTimer;

  PlaylistNavigation? get _nav => widget.playlistNav;

  @override
  void initState() {
    super.initState();
    _playing = widget.autoPlay;
    _subscriptions.add(_player.onDurationChanged.listen((d) {
      if (mounted) setState(() => _duration = d);
    }));
    _subscriptions.add(_player.onPositionChanged.listen(_onPosition));
    _subscriptions.add(_player.onPlayerComplete.listen((_) => _onComplete()));
    _subscriptions.add(_player.onPlayerStateChanged.listen((s) {
      if (mounted) setState(() => _playing = s == PlayerState.playing);
    }));
    _load();
  }

  @override
  void dispose() {
    _saveTimer?.cancel();
    for (final s in _subscriptions) {
      s.cancel();
    }
    for (final d in _drafts) {
      d.dispose();
    }
    _player.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final url = ApiConfig.resolveMediaUrl(widget.material.url);
    if (url == null) return;
    try {
      await _player.setSourceUrl(url);
      final saved = await ref.read(studyMaterialApiProvider).playbackSettings(widget.material.id);
      if (!mounted) return;
      setState(() {
        _settings = saved;
        _resetDrafts(saved);
      });
      await _player.setVolume(saved.volume / 100);
      await _player.setPlaybackRate(_effectiveSpeed);
      // Saved parts are this song's default window: land on the first part's start rather than
      // the very beginning, otherwise pressing play runs through material the trim exists to skip.
      if (saved.isTrimmed) {
        await _player.seek(Duration(seconds: saved.segments.first.start));
      }
      if (widget.autoPlay) await _player.resume();
    } catch (e) {
      if (mounted) showAppToast(context, "Couldn't load this audio.");
    }
  }

  void _resetDrafts(PlaybackSettings s) {
    for (final d in _drafts) {
      d.dispose();
    }
    _drafts = s.isTrimmed
        ? s.segments
            .map((g) => _DraftSegment(
                start: formatPlaybackTime(g.start),
                end: formatPlaybackTime(g.end),
                speed: g.speed))
            .toList()
        : [_DraftSegment(speed: s.speed)];
  }

  /// The rate actually playing: a trim's own tempo when one is active, otherwise the track's.
  double get _effectiveSpeed =>
      _settings.isTrimmed && _segmentIndex < _settings.segments.length
          ? _settings.segments[_segmentIndex].speed
          : _settings.speed;

  void _onPosition(Duration position) {
    if (!mounted) return;
    setState(() => _position = position);
    if (_jumping || !_settings.isTrimmed || !_playing) return;

    final segments = _settings.segments;
    final index = _segmentIndex.clamp(0, segments.length - 1);
    if (position.inMilliseconds / 1000 < segments[index].end) return;

    // End of this stretch: on to the next, round to the first, to the next song, or stop.
    if (index < segments.length - 1) {
      _jumpToSegment(index + 1);
    } else if (_settings.loopEnabled) {
      _jumpToSegment(0);
    } else if (_nav?.onNext != null) {
      _nav!.onNext!();
    } else {
      _player.pause();
      _player.seek(Duration(seconds: segments[index].end));
    }
  }

  Future<void> _jumpToSegment(int index) async {
    _jumping = true;
    setState(() => _segmentIndex = index);
    final segment = _settings.segments[index];
    await _player.seek(Duration(seconds: segment.start));
    await _player.setPlaybackRate(segment.speed);
    Future.delayed(const Duration(milliseconds: 300), () => _jumping = false);
  }

  Future<void> _onComplete() async {
    if (!mounted) return;
    if (_settings.loopEnabled && !_settings.isTrimmed) {
      await _player.seek(Duration.zero);
      await _player.resume();
      return;
    }
    // Advancing a playlist takes precedence over stopping, so a running order plays through.
    if (_nav?.onNext != null) {
      _nav!.onNext!();
    } else {
      setState(() => _playing = false);
    }
  }

  Future<void> _togglePlay() async {
    if (_playing) {
      await _player.pause();
      return;
    }
    if (_duration > Duration.zero && _position >= _duration) {
      await _player.seek(Duration.zero);
    }
    await _player.setPlaybackRate(_effectiveSpeed);
    await _player.resume();
  }

  Future<void> _skip(int seconds) async {
    final target = _position + Duration(seconds: seconds);
    final clamped = target < Duration.zero
        ? Duration.zero
        : (_duration > Duration.zero && target > _duration ? _duration : target);
    await _player.seek(clamped);
  }

  Future<void> _seekToFraction(double fraction) async {
    if (_duration == Duration.zero) return;
    await _player.seek(Duration(
        milliseconds: (_duration.inMilliseconds * fraction.clamp(0.0, 1.0)).round()));
  }

  /// Applies a change immediately and saves it a beat later.
  void _update(PlaybackSettings next, {bool applyRate = false, bool applyVolume = false}) {
    setState(() => _settings = next);
    if (applyRate) _player.setPlaybackRate(_effectiveSpeed);
    if (applyVolume && !_muted) _player.setVolume(next.volume / 100);

    _saveTimer?.cancel();
    _saveTimer = Timer(const Duration(milliseconds: 600), () async {
      try {
        await ref.read(studyMaterialApiProvider).savePlaybackSettings(widget.material.id, next);
      } catch (_) {
        // Deliberately silent. These are conveniences, and a failed save must not interrupt
        // someone mid-practice with a toast they cannot act on.
      }
    });
  }

  void _changeSpeed(double v) {
    final value = double.parse(v.toStringAsFixed(2));
    if (_settings.isTrimmed) {
      final index = _segmentIndex.clamp(0, _settings.segments.length - 1);
      final updated = [
        for (var i = 0; i < _settings.segments.length; i++)
          i == index
              ? PlaybackSegment(
                  start: _settings.segments[i].start,
                  end: _settings.segments[i].end,
                  speed: value)
              : _settings.segments[i],
      ];
      _update(_settings.copyWith(segments: updated), applyRate: true);
    } else {
      _update(_settings.copyWith(speed: value), applyRate: true);
    }
  }

  void _changeVolume(double v) =>
      _update(_settings.copyWith(volume: v.round()), applyVolume: true);

  void _toggleMute() {
    setState(() => _muted = !_muted);
    _player.setVolume(_muted ? 0 : _settings.volume / 100);
  }

  void _toggleLoop() => _update(_settings.copyWith(loopEnabled: !_settings.loopEnabled));

  // ---- Custom Play -------------------------------------------------------------------------

  void _toggleRange() {
    if (!_rangeOpen && !_settings.isTrimmed) {
      for (final d in _drafts) {
        d.dispose();
      }
      _drafts = [
        _DraftSegment(
          start: formatPlaybackTime(_position.inSeconds),
          end: formatPlaybackTime(_duration.inSeconds),
          speed: _settings.speed,
        ),
      ];
    }
    setState(() => _rangeOpen = !_rangeOpen);
  }

  void _addDraft() {
    final last = _drafts.isEmpty ? null : _drafts.last;
    setState(() => _drafts.add(_DraftSegment(
          start: last?.endController.text ?? '',
          end: formatPlaybackTime(_duration.inSeconds),
          speed: last?.speed ?? _settings.speed,
        )));
  }

  void _removeDraft(int i) {
    if (_drafts.length <= 1) return;
    setState(() => _drafts.removeAt(i).dispose());
  }

  List<PlaybackSegment>? _buildSegments() {
    final parsed = <PlaybackSegment>[];
    for (final d in _drafts) {
      final s = parsePlaybackTime(d.startController.text);
      final e = parsePlaybackTime(d.endController.text);
      if (s == null || e == null || s < 0 || e <= s) {
        setState(() => _rangeError = 'Enter a valid start and end time for every part.');
        return null;
      }
      if (_duration > Duration.zero && e > _duration.inSeconds) {
        setState(() =>
            _rangeError = "End time can't be past ${formatPlaybackTime(_duration.inSeconds)}.");
        return null;
      }
      parsed.add(PlaybackSegment(start: s, end: e, speed: d.speed.clamp(0.25, 2.0)));
    }
    setState(() => _rangeError = '');
    return parsed;
  }

  Future<void> _playSegments() async {
    final parsed = _buildSegments();
    if (parsed == null) return;
    setState(() => _segmentIndex = 0);
    _update(_settings.copyWith(segments: parsed));
    await _player.setPlaybackRate(parsed.first.speed);
    await _player.seek(Duration(seconds: parsed.first.start));
    await _player.resume();
  }

  /// Saves the parts, tempo and loop without jumping into playback - for setting things up ahead
  /// of time without it starting right now.
  void _saveSegmentsOnly() {
    final parsed = _buildSegments();
    if (parsed == null) return;
    setState(() => _segmentIndex = 0);
    _update(_settings.copyWith(segments: parsed), applyRate: true);
  }

  void _clearSegments() {
    setState(() {
      _segmentIndex = 0;
      _rangeError = '';
    });
    _update(_settings.copyWith(segments: const []), applyRate: true);
    for (final d in _drafts) {
      d.dispose();
    }
    setState(() => _drafts = [_DraftSegment(speed: _settings.speed)]);
  }

  // ---- build -------------------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final progress = _duration.inMilliseconds == 0
        ? 0.0
        : (_position.inMilliseconds / _duration.inMilliseconds).clamp(0.0, 1.0);
    final durationSec = _duration.inMilliseconds / 1000;

    return Column(
      children: [
        _cluster(palette, progress, durationSec),
        const SizedBox(height: 14),
        _seekRow(palette, progress, durationSec),
        const SizedBox(height: 14),
        _transport(palette),
        if (_nav != null) ...[
          const SizedBox(height: 14),
          Text(
            '${_nav!.playlistName} · ${_nav!.index + 1}/${_nav!.total}',
            style: TextStyle(
                fontSize: AppType.tiny,
                fontWeight: AppType.semi,
                color: palette.textFaint),
          ),
        ],
        const SizedBox(height: 14),
        ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 300),
          child: _customPlay(palette),
        ),
      ],
    );
  }

  Widget _cluster(AppPalette palette, double progress, double durationSec) {
    final accent = palette.primary;
    final segments = _settings.segments;
    final rightBottom = _polar(_leverR, _leverAngles(_Side.right).bottom);

    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: _vbW),
      child: AspectRatio(
        aspectRatio: _vbW / _vbH,
        child: FittedBox(
          fit: BoxFit.contain,
          child: SizedBox(
            width: _vbW,
            height: _vbH,
            child: Stack(
              clipBehavior: Clip.none,
              children: [
                Positioned.fill(
                  child: CustomPaint(
                    painter: _ClusterPainter(
                      accent: accent,
                      accentSoft: palette.primarySoft,
                      surfaceRaised: palette.surfaceRaised,
                      surfaceHigh: palette.surfaceHigh,
                      border: palette.border,
                      textFaint: palette.textFaint,
                      tick: palette.text,
                      speed: _effectiveSpeed,
                      volume: _settings.volume.toDouble(),
                      muted: _muted,
                    ),
                  ),
                ),
                _leverHitArea(_Side.left, 0.25, 2.0, _changeSpeed, stamps: const [0.25, 0.5, 1, 1.5, 2]),
                _leverHitArea(_Side.right, 0, 100, _changeVolume),
                Positioned(
                  left: _cx - 61,
                  top: _cy - 61,
                  child: _VinylDisk(
                    playing: _playing,
                    progress: progress,
                    accent: accent,
                    soft: palette.primarySoft,
                    segments: durationSec > 0 && segments.isNotEmpty
                        ? [
                            for (final s in segments)
                              (s.start / durationSec, s.end / durationSec),
                          ]
                        : const [],
                  ),
                ),
                Positioned(
                  left: rightBottom.dx - 15,
                  top: rightBottom.dy + 30,
                  child: Tooltip(
                    message: _muted ? 'Unmute' : 'Mute',
                    child: Pressable(
                      onTap: _toggleMute,
                      child: Container(
                        width: 30,
                        height: 30,
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          color: _muted ? palette.notPaidSoft : palette.surfaceRaised,
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(
                              color: _muted ? palette.notPaid : palette.border),
                        ),
                        child: Icon(
                          _muted ? Icons.volume_off_rounded : Icons.volume_up_rounded,
                          size: 14,
                          color: _muted ? palette.notPaid : palette.textMuted,
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// The strip a finger drags to move a lever. Taller than the arc itself, as in the prototype -
  /// position maps across the whole strip, so the ends are easy to reach.
  Widget _leverHitArea(
    _Side side,
    double min,
    double max,
    ValueChanged<double> onChanged, {
    List<double> stamps = const [],
  }) {
    final box = _leverBox(side);
    final window = (max - min) * 0.035;

    double nearestStamp(double raw) {
      var best = raw;
      var bestDist = double.infinity;
      for (final s in stamps) {
        final dist = (raw - s).abs();
        if (dist < bestDist) {
          bestDist = dist;
          best = s;
        }
      }
      return bestDist <= window ? best : raw;
    }

    void apply(double dy) {
      final pct = 1 - (dy / box.height).clamp(0.0, 1.0);
      onChanged(nearestStamp(min + pct * (max - min)));
    }

    return Positioned(
      left: side == _Side.left ? 0 : _vbW - _leverBoxW,
      top: box.top,
      width: _leverBoxW,
      height: box.height,
      child: MouseRegion(
        cursor: SystemMouseCursors.grab,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onPanDown: (d) => apply(d.localPosition.dy),
          onPanUpdate: (d) => apply(d.localPosition.dy),
        ),
      ),
    );
  }

  Widget _seekRow(AppPalette palette, double progress, double durationSec) {
    final accent = palette.primary;
    final segments = _settings.segments;
    TextStyle time() => TextStyle(
        fontSize: AppType.xs, fontWeight: AppType.semi, color: palette.textFaint);

    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 300),
      child: Row(
        children: [
          SizedBox(width: 34, child: Text(formatPlaybackTime(_position.inSeconds), style: time())),
          Expanded(
            child: LayoutBuilder(
              builder: (context, box) {
                final width = box.maxWidth;
                return GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTapDown: (d) => _seekToFraction(d.localPosition.dx / width),
                  onHorizontalDragUpdate: (d) => _seekToFraction(d.localPosition.dx / width),
                  child: SizedBox(
                    height: 14,
                    child: Stack(
                      alignment: Alignment.centerLeft,
                      clipBehavior: Clip.none,
                      children: [
                        Container(
                          height: 4,
                          decoration: BoxDecoration(
                            color: palette.surfaceHigh,
                            borderRadius: BorderRadius.circular(2),
                          ),
                        ),
                        if (durationSec > 0)
                          for (var i = 0; i < segments.length; i++)
                            Positioned(
                              left: segments[i].start / durationSec * width,
                              width: (segments[i].end - segments[i].start) / durationSec * width,
                              top: 2,
                              height: 10,
                              child: Container(
                                decoration: BoxDecoration(
                                  color: palette.gold.withValues(
                                      alpha: i == _segmentIndex ? 0.33 : 0.2),
                                  borderRadius: BorderRadius.circular(4),
                                  border: Border.all(color: palette.gold),
                                ),
                              ),
                            ),
                        Container(
                          height: 4,
                          width: progress * width,
                          decoration: BoxDecoration(
                            color: accent,
                            borderRadius: BorderRadius.circular(2),
                          ),
                        ),
                        Positioned(
                          left: progress * width - 6,
                          child: Container(
                            width: 12,
                            height: 12,
                            decoration: BoxDecoration(
                              color: accent,
                              shape: BoxShape.circle,
                              boxShadow: const [
                                BoxShadow(color: Color(0x59000000), spreadRadius: 3),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
          SizedBox(
            width: 34,
            child: Text(formatPlaybackTime(_duration.inSeconds),
                textAlign: TextAlign.right, style: time()),
          ),
        ],
      ),
    );
  }

  Widget _transport(AppPalette palette) {
    final accent = palette.primary;

    Widget plain(IconData icon, String tip, VoidCallback? onTap) => Tooltip(
          message: tip,
          child: Opacity(
            opacity: onTap == null ? 0.35 : 1,
            child: Pressable(
              onTap: onTap,
              child: Padding(
                padding: const EdgeInsets.all(5),
                child: Icon(icon, size: 22, color: palette.textMuted),
              ),
            ),
          ),
        );

    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 300),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Tooltip(
            message: 'Song library',
            child: Pressable(
              onTap: widget.onOpenLibrary,
              child: Container(
                width: 38,
                height: 38,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: palette.surfaceRaised,
                  borderRadius: AppRadii.all(AppRadii.lg),
                  border: Border.all(color: palette.border),
                ),
                child: Icon(Icons.library_music_outlined, size: 16, color: palette.textMuted),
              ),
            ),
          ),
          Row(
            mainAxisSize: MainAxisSize.min,
            spacing: 6,
            children: [
              plain(Icons.skip_previous_rounded, 'Previous song', _nav?.onPrevious),
              plain(Icons.fast_rewind_rounded, 'Back 10s', () => _skip(-10)),
              Pressable(
                onTap: _togglePlay,
                child: Container(
                  width: 58,
                  height: 58,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(color: accent, shape: BoxShape.circle),
                  child: Icon(
                    _playing ? Icons.pause_rounded : Icons.play_arrow_rounded,
                    size: 30,
                    color: palette.onPrimary,
                  ),
                ),
              ),
              plain(Icons.fast_forward_rounded, 'Forward 10s', () => _skip(10)),
              plain(Icons.skip_next_rounded, 'Next song', _nav?.onNext),
            ],
          ),
          const SizedBox(width: 38, height: 38),
        ],
      ),
    );
  }

  Widget _customPlay(AppPalette palette) {
    final segments = _settings.segments;
    final trimmed = segments.isNotEmpty;
    final loop = _settings.loopEnabled;
    final verb = loop ? 'Looping' : 'Playing';

    final label = !trimmed
        ? 'Custom Play'
        : segments.length == 1
            ? '$verb ${formatPlaybackTime(segments.first.start)}–${formatPlaybackTime(segments.first.end)}'
            : '$verb ${segments.length} parts';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Pressable(
          onTap: _toggleRange,
          child: Container(
            padding: const EdgeInsets.symmetric(vertical: 9),
            decoration: BoxDecoration(
              color: trimmed ? palette.goldSoft : palette.surfaceRaised,
              borderRadius: AppRadii.all(AppRadii.lg),
              border: Border.all(color: trimmed ? palette.gold : palette.border),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(loop ? Icons.repeat : Icons.queue_music_outlined,
                    size: 13, color: trimmed ? palette.gold : palette.textMuted),
                const SizedBox(width: 7),
                Text(label,
                    style: TextStyle(
                        fontSize: AppType.base,
                        fontWeight: AppType.bold,
                        color: trimmed ? palette.gold : palette.textMuted)),
              ],
            ),
          ),
        ),
        if (_rangeOpen) _rangePanel(palette),
      ],
    );
  }

  Widget _rangePanel(AppPalette palette) {
    final trimmed = _settings.isTrimmed;
    final loop = _settings.loopEnabled;

    Widget caps(String text) => Text(text.toUpperCase(),
        style: TextStyle(
            fontSize: 10,
            fontWeight: AppType.bold,
            letterSpacing: 0.4,
            color: palette.textFaint));

    Widget timeField(TextEditingController c, String hint) => TextField(
          controller: c,
          onChanged: (_) {
            if (_rangeError.isNotEmpty) setState(() => _rangeError = '');
          },
          style: TextStyle(
              fontSize: AppType.md, fontWeight: AppType.bold, color: palette.gold),
          decoration: InputDecoration(
            isDense: true,
            hintText: hint,
            hintStyle: TextStyle(
                fontSize: AppType.md,
                fontWeight: AppType.bold,
                color: palette.textFaint),
            filled: true,
            fillColor: palette.surfaceHigh,
            contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide: BorderSide(color: palette.gold.withValues(alpha: 0.33)),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide: BorderSide(color: palette.gold.withValues(alpha: 0.33)),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide: BorderSide(color: palette.gold),
            ),
          ),
        );

    Widget chip({
      required IconData icon,
      required String text,
      required Color color,
      required Color border,
      Color? fill,
      required VoidCallback onTap,
    }) =>
        Pressable(
          onTap: onTap,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 7),
            decoration: BoxDecoration(
              color: fill ?? Colors.transparent,
              borderRadius: AppRadii.all(AppRadii.pill),
              border: Border.all(color: border),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(icon, size: 12, color: color),
                const SizedBox(width: 6),
                Text(text,
                    style: TextStyle(
                        fontSize: AppType.smd, fontWeight: AppType.bold, color: color)),
              ],
            ),
          ),
        );

    return Container(
      margin: const EdgeInsets.only(top: 10),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: palette.surfaceRaised,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: palette.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (var i = 0; i < _drafts.length; i++)
            Container(
              margin: EdgeInsets.only(bottom: i < _drafts.length - 1 ? 14 : 0),
              padding: EdgeInsets.only(bottom: i < _drafts.length - 1 ? 12 : 0),
              decoration: BoxDecoration(
                border: i < _drafts.length - 1
                    ? Border(bottom: BorderSide(color: palette.borderSoft))
                    : null,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    spacing: 8,
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            caps('Part ${i + 1} start'),
                            const SizedBox(height: 5),
                            timeField(_drafts[i].startController, '0:00'),
                          ],
                        ),
                      ),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            caps('End'),
                            const SizedBox(height: 5),
                            timeField(_drafts[i].endController,
                                formatPlaybackTime(_duration.inSeconds)),
                          ],
                        ),
                      ),
                      if (_drafts.length > 1)
                        Tooltip(
                          message: 'Remove this part',
                          child: Pressable(
                            onTap: () => _removeDraft(i),
                            child: Padding(
                              padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 2),
                              child: Icon(Icons.close, size: 14, color: palette.textFaint),
                            ),
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  caps('Speed for this part'),
                  const SizedBox(height: 5),
                  _MiniSlider(
                    value: _drafts[i].speed,
                    min: 0.25,
                    max: 2.0,
                    color: palette.primary,
                    label: _formatSpeed,
                    onChanged: (v) => setState(() => _drafts[i].speed = v),
                  ),
                ],
              ),
            ),
          const SizedBox(height: 10),
          Align(
            alignment: Alignment.centerLeft,
            child: Pressable(
              onTap: _addDraft,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.add, size: 13, color: palette.primary),
                  const SizedBox(width: 5),
                  Text('Add another part',
                      style: TextStyle(
                          fontSize: AppType.smd,
                          fontWeight: AppType.bold,
                          color: palette.primary)),
                ],
              ),
            ),
          ),
          if (_rangeError.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(_rangeError,
                style: TextStyle(fontSize: AppType.xs, color: palette.notPaid)),
          ],
          const SizedBox(height: 10),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              chip(
                icon: Icons.repeat,
                text: 'Loop these parts',
                color: loop ? palette.gold : palette.textMuted,
                border: loop ? palette.gold : palette.border,
                fill: loop ? palette.goldSoft : null,
                onTap: _toggleLoop,
              ),
              Tooltip(
                message: 'Save without starting playback',
                child: chip(
                  icon: Icons.check,
                  text: 'Save changes',
                  color: palette.primary,
                  border: palette.primary.withValues(alpha: 0.4),
                  onTap: _saveSegmentsOnly,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            spacing: 8,
            children: [
              Expanded(
                child: Pressable(
                  onTap: _playSegments,
                  child: Container(
                    padding: const EdgeInsets.symmetric(vertical: 10),
                    decoration: BoxDecoration(
                      color: palette.primary,
                      borderRadius: AppRadii.all(AppRadii.xl),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.play_arrow_rounded, size: 16, color: palette.onPrimary),
                        const SizedBox(width: 8),
                        Text(_drafts.length > 1 ? 'Play parts' : 'Play range',
                            style: TextStyle(
                                fontSize: AppType.md,
                                fontWeight: AppType.bold,
                                color: palette.onPrimary)),
                      ],
                    ),
                  ),
                ),
              ),
              if (trimmed)
                Pressable(
                  onTap: _clearSegments,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 11),
                    decoration: BoxDecoration(
                      borderRadius: AppRadii.all(AppRadii.lg),
                      border: Border.all(color: palette.border),
                    ),
                    child: Text('Clear',
                        style: TextStyle(
                            fontSize: AppType.md,
                            fontWeight: AppType.bold,
                            color: palette.textMuted)),
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

class _DraftSegment {
  _DraftSegment({String start = '', String end = '', required this.speed})
      : startController = TextEditingController(text: start),
        endController = TextEditingController(text: end);

  final TextEditingController startController;
  final TextEditingController endController;
  double speed;

  void dispose() {
    startController.dispose();
    endController.dispose();
  }
}

/// A straight slider with a value readout, for the per-part tempo inside Custom Play.
class _MiniSlider extends StatelessWidget {
  const _MiniSlider({
    required this.value,
    required this.min,
    required this.max,
    required this.color,
    required this.label,
    required this.onChanged,
  });

  final double value;
  final double min;
  final double max;
  final Color color;
  final String Function(double) label;
  final ValueChanged<double> onChanged;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final pct = ((value - min) / (max - min)).clamp(0.0, 1.0);

    return Row(
      children: [
        Expanded(
          child: LayoutBuilder(
            builder: (context, box) {
              final width = box.maxWidth;
              void apply(double dx) =>
                  onChanged(min + (dx / width).clamp(0.0, 1.0) * (max - min));
              return GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTapDown: (d) => apply(d.localPosition.dx),
                onHorizontalDragUpdate: (d) => apply(d.localPosition.dx),
                child: SizedBox(
                  height: 28,
                  child: Stack(
                    alignment: Alignment.centerLeft,
                    clipBehavior: Clip.none,
                    children: [
                      Container(
                        height: 4,
                        decoration: BoxDecoration(
                          color: palette.surfaceHigh,
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                      Container(
                        height: 4,
                        width: pct * width,
                        decoration: BoxDecoration(
                          color: color,
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                      Positioned(
                        left: pct * width - 8,
                        child: Container(
                          width: 16,
                          height: 16,
                          decoration: BoxDecoration(
                            color: color,
                            shape: BoxShape.circle,
                            boxShadow: const [
                              BoxShadow(color: Color(0x59000000), spreadRadius: 3),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
        ),
        const SizedBox(width: 10),
        SizedBox(
          width: 40,
          child: Text(label(value),
              textAlign: TextAlign.right,
              style: TextStyle(
                  fontSize: AppType.smd, fontWeight: AppType.heavy, color: color)),
        ),
      ],
    );
  }
}

/// The record: a static disk with a progress ring on its rim (gold bands where trims play), and
/// a small tonearm that swings onto it on play and lifts clear on pause.
class _VinylDisk extends StatelessWidget {
  const _VinylDisk({
    required this.playing,
    required this.progress,
    required this.accent,
    required this.soft,
    required this.segments,
  });

  final bool playing;
  final double progress;
  final Color accent;
  final Color soft;

  /// (startFraction, endFraction) of each trim.
  final List<(double, double)> segments;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return SizedBox(
      width: 122,
      height: 122,
      child: Stack(
        alignment: Alignment.center,
        clipBehavior: Clip.none,
        children: [
          Positioned.fill(
            child: CustomPaint(
              painter: _RingPainter(
                progress: progress,
                accent: accent,
                track: palette.surfaceHigh,
                gold: palette.gold,
                segments: segments,
              ),
            ),
          ),
          Container(
            width: 92,
            height: 92,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: palette.surfaceHigh,
              shape: BoxShape.circle,
              border: Border.all(color: palette.border),
              boxShadow: const [
                BoxShadow(color: Color(0x80000000), blurRadius: 20, offset: Offset(0, 8)),
              ],
            ),
            child: Container(
              width: 42,
              height: 42,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: soft,
                shape: BoxShape.circle,
                border: Border.all(color: accent, width: 2),
              ),
              child: Icon(Icons.music_note_outlined, size: 17, color: accent),
            ),
          ),
          Positioned(
            top: -2,
            right: 16,
            width: 10,
            height: 44,
            child: TweenAnimationBuilder<double>(
              tween: Tween(end: playing ? 16 : -26),
              duration: const Duration(milliseconds: 450),
              curve: const Cubic(0.3, 0.7, 0.3, 1),
              builder: (context, degrees, child) => Transform.rotate(
                angle: degrees * math.pi / 180,
                alignment: Alignment.topCenter,
                child: child,
              ),
              child: Stack(
                clipBehavior: Clip.none,
                children: [
                  Positioned(
                    top: -5,
                    left: 0,
                    child: Container(
                      width: 10,
                      height: 10,
                      decoration: BoxDecoration(
                        color: palette.surfaceHigh,
                        shape: BoxShape.circle,
                        border: Border.all(color: accent, width: 2),
                      ),
                    ),
                  ),
                  Positioned(
                    top: 3,
                    left: 3.5,
                    child: Container(
                      width: 3,
                      height: 34,
                      decoration: BoxDecoration(
                        color: accent.withValues(alpha: 0.85),
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  ),
                  Positioned(
                    top: 39,
                    left: 1.5,
                    child: Container(
                      width: 7,
                      height: 7,
                      decoration: BoxDecoration(
                        color: accent,
                        shape: BoxShape.circle,
                        boxShadow: [
                          BoxShadow(color: accent.withValues(alpha: 0.67), blurRadius: 5),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _RingPainter extends CustomPainter {
  _RingPainter({
    required this.progress,
    required this.accent,
    required this.track,
    required this.gold,
    required this.segments,
  });

  final double progress;
  final Color accent;
  final Color track;
  final Color gold;
  final List<(double, double)> segments;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Rect.fromCircle(center: size.center(Offset.zero), radius: 54);
    Paint stroke(Color c) => Paint()
      ..color = c
      ..strokeWidth = 3
      ..strokeCap = StrokeCap.round
      ..style = PaintingStyle.stroke;

    canvas.drawArc(rect, 0, math.pi * 2, false, stroke(track));
    // The same gold bands as the seek bar, wrapped round the ring.
    for (final (start, end) in segments) {
      canvas.drawArc(rect, -math.pi / 2 + math.pi * 2 * start.clamp(0.0, 1.0),
          math.pi * 2 * (end - start).clamp(0.0, 1.0), false, stroke(gold));
    }
    canvas.drawArc(rect, -math.pi / 2, math.pi * 2 * progress, false, stroke(accent));
  }

  @override
  bool shouldRepaint(_RingPainter old) =>
      old.progress != progress || old.accent != accent || old.segments != segments;
}

/// The backdrop circle, both levers (arc, ticks, handle) and their labels.
class _ClusterPainter extends CustomPainter {
  _ClusterPainter({
    required this.accent,
    required this.accentSoft,
    required this.surfaceRaised,
    required this.surfaceHigh,
    required this.border,
    required this.textFaint,
    required this.tick,
    required this.speed,
    required this.volume,
    required this.muted,
  });

  final Color accent;
  final Color accentSoft;
  final Color surfaceRaised;
  final Color surfaceHigh;
  final Color border;
  final Color textFaint;
  final Color tick;
  final double speed;
  final double volume;
  final bool muted;

  static const _speedStamps = [0.25, 0.5, 1.0, 1.5, 2.0];

  @override
  void paint(Canvas canvas, Size size) {
    final centre = const Offset(_cx, _cy);
    final backdrop = Rect.fromCircle(center: centre, radius: _radius);
    canvas.drawCircle(
      centre,
      _radius,
      Paint()
        ..shader = RadialGradient(
          colors: [accentSoft, surfaceRaised, const Color(0x00000000)],
          stops: const [0, 0.55, 1],
        ).createShader(backdrop),
    );
    canvas.drawCircle(
      centre,
      _radius,
      Paint()
        ..color = border
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1,
    );

    _lever(canvas,
        side: _Side.left,
        value: speed,
        min: 0.25,
        max: 2,
        color: accent,
        label: 'Speed',
        valueLabel: _formatSpeed(speed),
        stamps: _speedStamps,
        valueColor: accent);
    _lever(canvas,
        side: _Side.right,
        value: volume,
        min: 0,
        max: 100,
        color: muted ? textFaint : accent,
        label: 'Volume',
        valueLabel: muted ? 'Muted' : '${volume.round()}%',
        stamps: const [],
        valueColor: muted ? textFaint : accent);
  }

  void _lever(
    Canvas canvas, {
    required _Side side,
    required double value,
    required double min,
    required double max,
    required Color color,
    required String label,
    required String valueLabel,
    required List<double> stamps,
    required Color valueColor,
  }) {
    final angles = _leverAngles(side);
    final pct = ((value - min) / (max - min)).clamp(0.0, 1.0);
    final arcRect = Rect.fromCircle(center: const Offset(_cx, _cy), radius: _leverR);
    final start = (angles.bottom - 90) * math.pi / 180;
    final sweep = (angles.top - angles.bottom) * math.pi / 180;
    double angleAt(double t) => angles.bottom + t * (angles.top - angles.bottom);

    Paint arc(Color c) => Paint()
      ..color = c
      ..style = PaintingStyle.stroke
      ..strokeWidth = 6
      ..strokeCap = StrokeCap.round;

    canvas.drawArc(arcRect, start, sweep, false, arc(surfaceHigh));
    if (pct > 0) {
      canvas.drawArc(
        arcRect,
        start,
        sweep * pct,
        false,
        arc(color.withValues(alpha: 0.53))..maskFilter = const MaskFilter.blur(BlurStyle.normal, 3),
      );
      canvas.drawArc(arcRect, start, sweep * pct, false, arc(color));
    }

    final window = (max - min) * 0.035;
    for (final s in stamps) {
      final a = angleAt(((s - min) / (max - min)).clamp(0.0, 1.0));
      final active = (value - s).abs() <= window;
      final tickPaint = Paint()
        ..color = tick.withValues(alpha: active ? 1 : 0.7)
        ..strokeWidth = active ? 3.2 : 2.4
        ..strokeCap = StrokeCap.round;
      if (active) {
        canvas.drawLine(
          _polar(_leverR - 8, a),
          _polar(_leverR + 8, a),
          Paint()
            ..color = color
            ..strokeWidth = 6
            ..strokeCap = StrokeCap.round
            ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 2),
        );
      }
      canvas.drawLine(_polar(_leverR - 8, a), _polar(_leverR + 8, a), tickPaint);
      _text(canvas, _formatSpeed(s), _polar(_leverR + 20, a),
          size: 9, weight: FontWeight.w700, color: active ? color : textFaint, center: true);
    }

    // Handle, riding the arc.
    final handle = _polar(_leverR, angleAt(pct));
    canvas.drawCircle(handle, 8, Paint()..color = surfaceRaised);
    canvas.drawCircle(
      handle,
      8,
      Paint()
        ..color = color
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3,
    );

    // Label at the top of the drag strip, value at the bottom.
    final box = _leverBox(side);
    final alignRight = side == _Side.right;
    final x = alignRight ? _vbW : 0.0;
    _text(canvas, label.toUpperCase(), Offset(x, box.top),
        size: 9.5, weight: FontWeight.w800, color: textFaint, spacing: 0.6, right: alignRight);
    _text(canvas, valueLabel, Offset(x, box.top + box.height),
        size: 12, weight: FontWeight.w800, color: valueColor, right: alignRight, bottom: true);
  }

  void _text(
    Canvas canvas,
    String text,
    Offset at, {
    required double size,
    required FontWeight weight,
    required Color color,
    double spacing = 0,
    bool center = false,
    bool right = false,
    bool bottom = false,
  }) {
    final painter = TextPainter(
      text: TextSpan(
        text: text,
        style: TextStyle(
            fontSize: size, fontWeight: weight, color: color, letterSpacing: spacing),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    var dx = at.dx;
    var dy = at.dy;
    if (center) {
      dx -= painter.width / 2;
      dy -= painter.height / 2;
    } else {
      if (right) dx -= painter.width;
      if (bottom) dy -= painter.height;
    }
    painter.paint(canvas, Offset(dx, dy));
  }

  @override
  bool shouldRepaint(_ClusterPainter old) =>
      old.speed != speed ||
      old.volume != volume ||
      old.muted != muted ||
      old.accent != accent ||
      old.surfaceRaised != surfaceRaised ||
      old.textFaint != textFaint;
}
