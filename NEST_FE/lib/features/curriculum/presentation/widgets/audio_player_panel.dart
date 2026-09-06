import 'dart:async';
import 'dart:math' as math;

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:nest_fe/app/theme/app_tokens.dart';
import 'package:nest_fe/app/theme/app_typography.dart';
import 'package:nest_fe/core/design/buttons.dart';
import 'package:nest_fe/core/design/pressable.dart';
import 'package:nest_fe/core/design/toast.dart';
import 'package:nest_fe/core/network/api_config.dart';
import 'package:nest_fe/features/curriculum/data/material_playlist.dart';
import 'package:nest_fe/features/curriculum/data/study_material.dart';
import 'package:nest_fe/features/curriculum/data/study_material_api.dart';

/// The practice player: a spinning disk, tempo and volume arcs either side of it, and optional
/// trims that play chosen stretches back-to-back.
///
/// Tempo matters more here than in a normal player. Learning a piece means slowing it to half
/// speed and creeping back up, and returning to the same tempo tomorrow - which is why the
/// settings are saved per person per track rather than reset each time.
class AudioPlayerPanel extends ConsumerStatefulWidget {
  const AudioPlayerPanel({
    super.key,
    required this.material,
    this.autoPlay = false,
    this.onEnded,
  });

  final StudyMaterial material;
  final bool autoPlay;

  /// Advances a playlist. Null outside one, in which case the track simply stops at the end.
  final VoidCallback? onEnded;

  @override
  ConsumerState<AudioPlayerPanel> createState() => _AudioPlayerPanelState();
}

class _AudioPlayerPanelState extends ConsumerState<AudioPlayerPanel>
    with SingleTickerProviderStateMixin {
  final _player = AudioPlayer();
  late final AnimationController _spin;

  final _subscriptions = <StreamSubscription<dynamic>>[];

  Duration _position = Duration.zero;
  Duration _duration = Duration.zero;
  bool _playing = false;
  bool _ready = false;

  PlaybackSettings _settings = const PlaybackSettings();

  /// Which trim is playing. Only meaningful when the settings carry segments.
  int _segmentIndex = 0;

  /// Debounces saves - dragging an arc emits a value per frame, and one PUT per frame would be
  /// both wasteful and out of order by the time they land.
  Timer? _saveTimer;

  @override
  void initState() {
    super.initState();
    _spin = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 6),
    );
    _attach();
    _load();
  }

  @override
  void dispose() {
    _saveTimer?.cancel();
    for (final s in _subscriptions) {
      s.cancel();
    }
    _spin.dispose();
    _player.dispose();
    super.dispose();
  }

  void _attach() {
    _subscriptions.add(_player.onDurationChanged.listen((d) {
      if (mounted) setState(() => _duration = d);
    }));
    _subscriptions.add(_player.onPositionChanged.listen(_onPosition));
    _subscriptions.add(_player.onPlayerComplete.listen((_) => _onComplete()));
  }

  Future<void> _load() async {
    final url = ApiConfig.resolveMediaUrl(widget.material.url);
    if (url == null) return;
    try {
      await _player.setSourceUrl(url);
      final saved = await ref
          .read(studyMaterialApiProvider)
          .playbackSettings(widget.material.id);
      if (!mounted) return;
      setState(() {
        _settings = saved;
        _ready = true;
      });
      await _player.setVolume(saved.volume / 100);
      await _player.setPlaybackRate(_effectiveSpeed);
      // Start inside the first trim, not at zero - otherwise pressing play runs through material
      // the trim exists to skip.
      if (saved.isTrimmed) {
        await _player.seek(Duration(seconds: saved.segments.first.start));
      }
      if (widget.autoPlay) await _togglePlay();
    } catch (e) {
      if (mounted) {
        setState(() => _ready = true);
        showAppToast(context, "Couldn't load this audio.");
      }
    }
  }

  /// The rate actually playing: a trim's own tempo when one is active, otherwise the track's.
  double get _effectiveSpeed => _settings.isTrimmed &&
          _segmentIndex < _settings.segments.length
      ? _settings.segments[_segmentIndex].speed
      : _settings.speed;

  void _onPosition(Duration position) {
    if (!mounted) return;
    setState(() => _position = position);

    if (!_settings.isTrimmed || !_playing) return;
    final segment = _settings.segments[_segmentIndex];
    if (position.inSeconds < segment.end) return;

    // Reached the end of this stretch. Move to the next, loop back to the first, or stop.
    if (_segmentIndex < _settings.segments.length - 1) {
      _jumpToSegment(_segmentIndex + 1);
    } else if (_settings.loopEnabled) {
      _jumpToSegment(0);
    } else {
      _onComplete();
    }
  }

  Future<void> _jumpToSegment(int index) async {
    setState(() => _segmentIndex = index);
    final segment = _settings.segments[index];
    await _player.seek(Duration(seconds: segment.start));
    await _player.setPlaybackRate(segment.speed);
  }

  Future<void> _onComplete() async {
    if (_settings.loopEnabled && !_settings.isTrimmed) {
      await _player.seek(Duration.zero);
      await _player.resume();
      return;
    }
    setState(() => _playing = false);
    _spin.stop();
    // Advancing a playlist takes precedence over stopping, so a running order plays through.
    widget.onEnded?.call();
  }

  Future<void> _togglePlay() async {
    if (_playing) {
      await _player.pause();
      _spin.stop();
      setState(() => _playing = false);
      return;
    }
    await _player.setPlaybackRate(_effectiveSpeed);
    await _player.resume();
    _spin.repeat();
    setState(() => _playing = true);
  }

  Future<void> _seekBy(int seconds) async {
    final target = _position + Duration(seconds: seconds);
    final clamped = target < Duration.zero
        ? Duration.zero
        : (_duration > Duration.zero && target > _duration ? _duration : target);
    await _player.seek(clamped);
  }

  Future<void> _seekTo(double fraction) async {
    if (_duration == Duration.zero) return;
    await _player.seek(Duration(
        milliseconds: (_duration.inMilliseconds * fraction).round()));
  }

  /// Applies a change immediately and saves it a beat later.
  void _update(PlaybackSettings next, {bool applyRate = false, bool applyVolume = false}) {
    setState(() => _settings = next);
    if (applyRate) _player.setPlaybackRate(_effectiveSpeed);
    if (applyVolume) _player.setVolume(next.volume / 100);

    _saveTimer?.cancel();
    _saveTimer = Timer(const Duration(milliseconds: 600), () async {
      try {
        await ref
            .read(studyMaterialApiProvider)
            .savePlaybackSettings(widget.material.id, next);
      } catch (_) {
        // Deliberately silent. These are conveniences, and a failed save must not interrupt
        // someone mid-practice with a toast they cannot act on.
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final accent = palette.coral;
    final progress = _duration.inMilliseconds == 0
        ? 0.0
        : (_position.inMilliseconds / _duration.inMilliseconds).clamp(0.0, 1.0);

    return Container(
      padding: const EdgeInsets.all(AppSpacing.x4l),
      decoration: BoxDecoration(
        color: palette.surfaceRaised,
        borderRadius: AppRadii.all(AppRadii.xxl),
        border: Border.all(color: palette.borderSoft),
      ),
      child: Column(
        children: [
          SizedBox(
            height: 230,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                _ArcControl(
                  label: 'Tempo',
                  valueLabel: '${_settings.speed.toStringAsFixed(2)}x',
                  value: _settings.speed,
                  min: 0.25,
                  max: 2.0,
                  accent: palette.gold,
                  side: _ArcSide.left,
                  onChanged: (v) => _update(
                    _settings.copyWith(speed: double.parse(v.toStringAsFixed(2))),
                    applyRate: true,
                  ),
                ),
                Expanded(
                  child: _Disk(
                    spin: _spin,
                    playing: _playing,
                    progress: progress,
                    accent: accent,
                    ready: _ready,
                    onTap: _ready ? _togglePlay : null,
                  ),
                ),
                _ArcControl(
                  label: 'Volume',
                  valueLabel: '${_settings.volume}',
                  value: _settings.volume.toDouble(),
                  min: 0,
                  max: 100,
                  accent: palette.gateway,
                  side: _ArcSide.right,
                  onChanged: (v) => _update(
                    _settings.copyWith(volume: v.round()),
                    applyVolume: true,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: AppSpacing.lg),
          _scrubber(palette, accent, progress),
          const SizedBox(height: AppSpacing.lg),
          _transport(palette, accent),
          const SizedBox(height: AppSpacing.xl),
          _trimSummary(palette, accent),
        ],
      ),
    );
  }

  Widget _scrubber(AppPalette palette, Color accent, double progress) {
    return Column(
      children: [
        SliderTheme(
          data: SliderThemeData(
            trackHeight: 3,
            activeTrackColor: accent,
            inactiveTrackColor: palette.surfaceHigh,
            thumbColor: accent,
            overlayShape: const RoundSliderOverlayShape(overlayRadius: 14),
            thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6),
          ),
          child: Slider(
            value: progress,
            onChanged: _duration == Duration.zero ? null : _seekTo,
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(formatPlaybackTime(_position.inSeconds),
                  style: TextStyle(
                      fontSize: AppType.sm,
                      color: palette.textMuted,
                      fontFeatures: const [FontFeature.tabularFigures()])),
              Text(formatPlaybackTime(_duration.inSeconds),
                  style: TextStyle(
                      fontSize: AppType.sm,
                      color: palette.textMuted,
                      fontFeatures: const [FontFeature.tabularFigures()])),
            ],
          ),
        ),
      ],
    );
  }

  Widget _transport(AppPalette palette, Color accent) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        _RoundButton(
          icon: Icons.replay_10,
          onTap: () => _seekBy(-10),
        ),
        const SizedBox(width: AppSpacing.xl),
        Pressable(
          onTap: _ready ? _togglePlay : null,
          child: Container(
            height: 56,
            width: 56,
            alignment: Alignment.center,
            decoration: BoxDecoration(color: accent, shape: BoxShape.circle),
            child: Icon(
              _playing ? Icons.pause_rounded : Icons.play_arrow_rounded,
              size: 30,
              color: palette.onPrimary,
            ),
          ),
        ),
        const SizedBox(width: AppSpacing.xl),
        _RoundButton(
          icon: Icons.forward_10,
          onTap: () => _seekBy(10),
        ),
        const SizedBox(width: AppSpacing.xl),
        _RoundButton(
          icon: Icons.repeat,
          active: _settings.loopEnabled,
          activeColor: accent,
          onTap: () => _update(_settings.copyWith(loopEnabled: !_settings.loopEnabled)),
        ),
      ],
    );
  }

  Widget _trimSummary(AppPalette palette, Color accent) {
    final segments = _settings.segments;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(
              child: Text('TRIM', style: AppType.sectionLabel(palette.textMuted)),
            ),
            Pressable(
              onTap: _editTrims,
              child: Text(segments.isEmpty ? 'Add' : 'Edit',
                  style: TextStyle(
                      fontSize: AppType.sm,
                      fontWeight: AppType.bold,
                      color: accent)),
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.sm),
        if (segments.isEmpty)
          Text('Playing the whole track.',
              style: TextStyle(fontSize: AppType.sm, color: palette.textFaint))
        else
          Wrap(
            spacing: AppSpacing.xs,
            runSpacing: AppSpacing.xs,
            children: [
              for (var i = 0; i < segments.length; i++)
                Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: AppSpacing.md, vertical: 4),
                  decoration: BoxDecoration(
                    color: i == _segmentIndex && _playing
                        ? accent.withValues(alpha: 0.2)
                        : palette.surface,
                    borderRadius: AppRadii.all(AppRadii.pill),
                    border: Border.all(
                        color: i == _segmentIndex && _playing
                            ? accent
                            : palette.border),
                  ),
                  child: Text(
                    '${formatPlaybackTime(segments[i].start)}'
                    '-${formatPlaybackTime(segments[i].end)}'
                    ' · ${segments[i].speed.toStringAsFixed(2)}x',
                    style: TextStyle(
                        fontSize: AppType.sm,
                        fontWeight: AppType.medium,
                        color: palette.textMuted),
                  ),
                ),
            ],
          ),
      ],
    );
  }

  Future<void> _editTrims() async {
    final result = await showModalBottomSheet<List<PlaybackSegment>>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      barrierColor: const Color(0xB8040710),
      builder: (_) => _TrimSheet(
        segments: _settings.segments,
        trackSeconds: _duration.inSeconds,
        defaultSpeed: _settings.speed,
      ),
    );
    if (result == null) return;
    setState(() => _segmentIndex = 0);
    _update(_settings.copyWith(segments: result), applyRate: true);
    if (result.isNotEmpty) {
      await _player.seek(Duration(seconds: result.first.start));
    }
  }
}

enum _ArcSide { left, right }

/// A quarter-arc slider, dragged along its curve.
///
/// An arc rather than a straight slider because the two sit either side of the disk and mirror
/// each other - a shape that belongs to a turntable rather than a settings form.
class _ArcControl extends StatelessWidget {
  const _ArcControl({
    required this.label,
    required this.valueLabel,
    required this.value,
    required this.min,
    required this.max,
    required this.accent,
    required this.side,
    required this.onChanged,
  });

  final String label;
  final String valueLabel;
  final double value;
  final double min;
  final double max;
  final Color accent;
  final _ArcSide side;
  final ValueChanged<double> onChanged;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final fraction = ((value - min) / (max - min)).clamp(0.0, 1.0);

    return SizedBox(
      width: 58,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(label.toUpperCase(),
              style: AppType.sectionLabel(palette.textMuted)),
          const SizedBox(height: AppSpacing.sm),
          Expanded(
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onVerticalDragUpdate: (details) {
                final box = context.findRenderObject() as RenderBox?;
                if (box == null) return;
                final local = box.globalToLocal(details.globalPosition);
                // Upward is more, which matches every physical fader.
                final next = 1 - (local.dy / box.size.height).clamp(0.0, 1.0);
                onChanged(min + (max - min) * next);
              },
              child: CustomPaint(
                size: const Size(46, double.infinity),
                painter: _ArcPainter(
                  fraction: fraction,
                  accent: accent,
                  track: palette.surfaceHigh,
                  side: side,
                ),
              ),
            ),
          ),
          const SizedBox(height: AppSpacing.sm),
          Text(valueLabel,
              style: TextStyle(
                  fontSize: AppType.md,
                  fontWeight: AppType.bold,
                  color: accent,
                  fontFeatures: const [FontFeature.tabularFigures()])),
        ],
      ),
    );
  }
}

class _ArcPainter extends CustomPainter {
  _ArcPainter({
    required this.fraction,
    required this.accent,
    required this.track,
    required this.side,
  });

  final double fraction;
  final Color accent;
  final Color track;
  final _ArcSide side;

  @override
  void paint(Canvas canvas, Size size) {
    // Bows away from the disk, so the two arcs cradiate outwards rather than pinching it.
    final bow = side == _ArcSide.left ? -18.0 : 18.0;
    final path = Path()
      ..moveTo(size.width / 2 - bow / 2, size.height)
      ..quadraticBezierTo(
        size.width / 2 + bow, size.height / 2,
        size.width / 2 - bow / 2, 0,
      );

    final base = Paint()
      ..color = track
      ..strokeWidth = 5
      ..strokeCap = StrokeCap.round
      ..style = PaintingStyle.stroke;
    canvas.drawPath(path, base);

    final metric = path.computeMetrics().first;
    final filled = metric.extractPath(metric.length * (1 - fraction), metric.length);
    canvas.drawPath(
      filled,
      Paint()
        ..color = accent
        ..strokeWidth = 5
        ..strokeCap = StrokeCap.round
        ..style = PaintingStyle.stroke,
    );

    final knob = metric.getTangentForOffset(metric.length * (1 - fraction))?.position;
    if (knob != null) {
      canvas.drawCircle(knob, 7, Paint()..color = accent);
      canvas.drawCircle(knob, 3, Paint()..color = Colors.white.withValues(alpha: 0.9));
    }
  }

  @override
  bool shouldRepaint(_ArcPainter old) =>
      old.fraction != fraction || old.accent != accent;
}

/// The record. Spins while playing, and carries the progress ring on its rim.
class _Disk extends StatelessWidget {
  const _Disk({
    required this.spin,
    required this.playing,
    required this.progress,
    required this.accent,
    required this.ready,
    required this.onTap,
  });

  final AnimationController spin;
  final bool playing;
  final double progress;
  final Color accent;
  final bool ready;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return Center(
      child: Pressable(
        onTap: onTap,
        child: SizedBox(
          height: 190,
          width: 190,
          child: Stack(
            alignment: Alignment.center,
            children: [
              CustomPaint(
                size: const Size.square(190),
                painter: _ProgressRingPainter(
                  progress: progress,
                  accent: accent,
                  track: palette.surfaceHigh,
                ),
              ),
              RotationTransition(
                turns: spin,
                child: Container(
                  height: 150,
                  width: 150,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: RadialGradient(
                      colors: [
                        palette.surfaceHigh,
                        palette.surface,
                        palette.surfaceHigh,
                      ],
                      stops: const [0.18, 0.55, 1.0],
                    ),
                    border: Border.all(color: palette.border),
                  ),
                  child: Center(
                    child: Container(
                      height: 46,
                      width: 46,
                      decoration: BoxDecoration(
                        color: accent.withValues(alpha: 0.18),
                        shape: BoxShape.circle,
                        border: Border.all(color: accent.withValues(alpha: 0.5)),
                      ),
                      // The label rides the disk, so it turns with it - which is what makes the
                      // rotation legible at all on an otherwise near-symmetric circle.
                      child: Icon(Icons.music_note, size: 20, color: accent),
                    ),
                  ),
                ),
              ),
              if (!ready)
                CircularProgressIndicator(color: accent, strokeWidth: 2),
            ],
          ),
        ),
      ),
    );
  }
}

class _ProgressRingPainter extends CustomPainter {
  _ProgressRingPainter({
    required this.progress,
    required this.accent,
    required this.track,
  });

  final double progress;
  final Color accent;
  final Color track;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Rect.fromLTWH(3, 3, size.width - 6, size.height - 6);
    canvas.drawArc(
      rect, 0, math.pi * 2, false,
      Paint()
        ..color = track
        ..strokeWidth = 4
        ..style = PaintingStyle.stroke,
    );
    canvas.drawArc(
      rect,
      -math.pi / 2,
      math.pi * 2 * progress,
      false,
      Paint()
        ..color = accent
        ..strokeWidth = 4
        ..strokeCap = StrokeCap.round
        ..style = PaintingStyle.stroke,
    );
  }

  @override
  bool shouldRepaint(_ProgressRingPainter old) => old.progress != progress;
}

class _RoundButton extends StatelessWidget {
  const _RoundButton({
    required this.icon,
    required this.onTap,
    this.active = false,
    this.activeColor,
  });

  final IconData icon;
  final VoidCallback? onTap;
  final bool active;
  final Color? activeColor;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final color = active ? (activeColor ?? palette.primary) : palette.textMuted;
    return Pressable(
      onTap: onTap,
      child: Container(
        height: 40,
        width: 40,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: active
              ? (activeColor ?? palette.primary).withValues(alpha: 0.14)
              : palette.surface,
          shape: BoxShape.circle,
          border: Border.all(color: active ? color : palette.border),
        ),
        child: Icon(icon, size: 19, color: color),
      ),
    );
  }
}

/// Editor for the stretches to play. Returns the new list, or null if dismissed.
class _TrimSheet extends StatefulWidget {
  const _TrimSheet({
    required this.segments,
    required this.trackSeconds,
    required this.defaultSpeed,
  });

  final List<PlaybackSegment> segments;
  final int trackSeconds;
  final double defaultSpeed;

  @override
  State<_TrimSheet> createState() => _TrimSheetState();
}

class _TrimSheetState extends State<_TrimSheet> {
  late final List<_DraftSegment> _drafts = widget.segments.isEmpty
      ? [_DraftSegment(speed: widget.defaultSpeed)]
      : widget.segments
          .map((s) => _DraftSegment(
                start: formatPlaybackTime(s.start),
                end: formatPlaybackTime(s.end),
                speed: s.speed,
              ))
          .toList();

  String? _error;

  @override
  void dispose() {
    for (final d in _drafts) {
      d.dispose();
    }
    super.dispose();
  }

  void _apply() {
    final result = <PlaybackSegment>[];
    for (final draft in _drafts) {
      final start = parsePlaybackTime(draft.startController.text);
      final end = parsePlaybackTime(draft.endController.text);
      // A row left entirely blank is how you delete one, so it is skipped rather than rejected.
      if (start == null && end == null) continue;
      if (start == null || end == null) {
        setState(() => _error = 'Fill in both a start and an end, as m:ss.');
        return;
      }
      if (end <= start) {
        setState(() => _error = 'Each stretch has to end after it starts.');
        return;
      }
      result.add(PlaybackSegment(start: start, end: end, speed: draft.speed));
    }
    Navigator.of(context).pop(result);
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return Container(
      decoration: BoxDecoration(
        color: palette.surface,
        borderRadius: AppRadii.sheetTop,
        border: Border(top: BorderSide(color: palette.border)),
      ),
      padding: EdgeInsets.only(
        left: AppSpacing.page,
        right: AppSpacing.page,
        top: AppSpacing.lg,
        bottom: MediaQuery.of(context).viewInsets.bottom + AppSpacing.x5l,
      ),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Center(
              child: Container(
                height: 4,
                width: 38,
                decoration: BoxDecoration(
                  color: palette.border,
                  borderRadius: AppRadii.all(AppRadii.pill),
                ),
              ),
            ),
            const SizedBox(height: AppSpacing.x4l),
            Text('Play only these parts',
                style: TextStyle(
                    fontSize: AppType.title,
                    fontWeight: AppType.bold,
                    color: palette.text)),
            const SizedBox(height: AppSpacing.sm),
            Text(
              'They play back-to-back with the gaps skipped, each at its own tempo. '
              'Clear a row to remove it.'
              '${widget.trackSeconds > 0 ? ' This track runs ${formatPlaybackTime(widget.trackSeconds)}.' : ''}',
              style: TextStyle(
                  fontSize: AppType.sm, color: palette.textMuted, height: 1.5),
            ),
            const SizedBox(height: AppSpacing.x4l),
            for (var i = 0; i < _drafts.length; i++)
              _draftRow(palette, i, _drafts[i]),
            const SizedBox(height: AppSpacing.sm),
            Pressable(
              onTap: () => setState(
                  () => _drafts.add(_DraftSegment(speed: widget.defaultSpeed))),
              child: Container(
                padding: const EdgeInsets.symmetric(vertical: AppSpacing.lg),
                decoration: BoxDecoration(
                  borderRadius: AppRadii.all(AppRadii.xl),
                  border: Border.all(color: palette.border),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.add, size: 15, color: palette.primary),
                    const SizedBox(width: AppSpacing.xs),
                    Text('Add another stretch',
                        style: TextStyle(
                            fontSize: AppType.md,
                            fontWeight: AppType.bold,
                            color: palette.primary)),
                  ],
                ),
              ),
            ),
            if (_error != null) ...[
              const SizedBox(height: AppSpacing.md),
              Text(_error!,
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: AppType.sm, color: palette.notPaid)),
            ],
            const SizedBox(height: AppSpacing.x4l),
            AppPrimaryButton(label: 'Apply', icon: Icons.check, onPressed: _apply),
          ],
        ),
      ),
    );
  }

  Widget _draftRow(AppPalette palette, int index, _DraftSegment draft) {
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('STRETCH ${index + 1}',
              style: AppType.sectionLabel(palette.textMuted)),
          const SizedBox(height: AppSpacing.sm),
          Row(
            children: [
              Expanded(child: _timeField(palette, draft.startController, 'Start (0:00)')),
              const SizedBox(width: AppSpacing.sm),
              Expanded(child: _timeField(palette, draft.endController, 'End (1:30)')),
            ],
          ),
          const SizedBox(height: AppSpacing.sm),
          Row(
            children: [
              Text('Tempo',
                  style: TextStyle(fontSize: AppType.sm, color: palette.textMuted)),
              Expanded(
                child: Slider(
                  value: draft.speed,
                  min: 0.25,
                  max: 2.0,
                  divisions: 35,
                  activeColor: palette.gold,
                  onChanged: (v) => setState(() => draft.speed = v),
                ),
              ),
              SizedBox(
                width: 44,
                child: Text('${draft.speed.toStringAsFixed(2)}x',
                    textAlign: TextAlign.right,
                    style: TextStyle(
                        fontSize: AppType.md,
                        fontWeight: AppType.bold,
                        color: palette.gold)),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _timeField(
      AppPalette palette, TextEditingController controller, String hint) {
    return TextField(
      controller: controller,
      onChanged: (_) => setState(() => _error = null),
      style: TextStyle(
          fontSize: AppType.xxl, fontWeight: AppType.medium, color: palette.text),
      decoration: InputDecoration(
        isDense: true,
        hintText: hint,
        hintStyle: TextStyle(fontSize: AppType.lg, color: palette.textFaint),
        filled: true,
        fillColor: palette.surfaceRaised,
        contentPadding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.lg, vertical: AppSpacing.lg),
        border: OutlineInputBorder(
          borderRadius: AppRadii.all(AppRadii.lg),
          borderSide: BorderSide(color: palette.border),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: AppRadii.all(AppRadii.lg),
          borderSide: BorderSide(color: palette.border),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: AppRadii.all(AppRadii.lg),
          borderSide: BorderSide(color: palette.primary),
        ),
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
