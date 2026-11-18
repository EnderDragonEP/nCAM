import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:video_player/video_player.dart';

import '../camera/models.dart';
import '../camera/recordings.dart';
import '../camera/transport.dart';
import '../state/downloads.dart';
import '../state/pip.dart';
import '../state/session.dart';
import 'format.dart';

enum PlayerView { front, rear, both }

/// Plays a recording from the phone's copy: the front clip, the rear clip, or both
/// together (one above the other in portrait, side by side in landscape). Switching
/// keeps the position.
class PlayerScreen extends ConsumerStatefulWidget {
  const PlayerScreen({super.key, required this.recording, required this.lens});
  final Recording recording;
  final Lens lens;

  @override
  ConsumerState<PlayerScreen> createState() => _PlayerScreenState();
}

class _PlayerScreenState extends ConsumerState<PlayerScreen> {
  /// The clip that leads: the one shown, or the front clip when both are shown. The
  /// controls, the position and the picture-in-picture window follow it.
  VideoPlayerController? _main;

  /// The rear clip, only while both are shown. It follows [_main], muted.
  VideoPlayerController? _rear;

  late PlayerView _view = widget.lens == Lens.rear
      ? PlayerView.rear
      : PlayerView.front;
  String? _error;
  bool _loading = true;
  int _generation = 0;
  Timer? _follow;
  late final CameraTransport _transport;

  /// Play/pause changes the window's buttons and whether it may open by itself.
  bool _wasPlaying = false;

  /// How much later the rear clip started than the front one, from their file names
  /// (often a second). Positions are converted with it so both show the same moment.
  Duration get _rearOffset {
    final f = widget.recording.front?.startTime;
    final r = widget.recording.rear?.startTime;
    if (f == null || r == null) return Duration.zero;
    final d = r.difference(f);
    return d.abs() > const Duration(seconds: 10) ? Duration.zero : d;
  }

  CameraFile? _fileFor(PlayerView view) => switch (view) {
    PlayerView.rear => widget.recording.rear,
    _ => widget.recording.front ?? widget.recording.other,
  };

  @override
  void initState() {
    super.initState();
    _transport = ref.read(transportProvider)..keepScreenOn(true).ignore();
    _open(_view);
  }

  @override
  void dispose() {
    _generation++;
    _follow?.cancel();
    _main?.removeListener(_onTick);
    _main?.dispose();
    _rear?.dispose();
    // Not ref: it cannot be used once the page is being taken down.
    _transport.keepScreenOn(false).ignore();
    super.dispose();
  }

  void _onTick() {
    final playing = _main?.value.isPlaying ?? false;
    if (playing != _wasPlaying && mounted) {
      setState(() => _wasPlaying = playing);
    }
  }

  /// The current moment, on the front clip's timeline.
  Duration? _moment() {
    final m = _main;
    if (m == null) return null;
    return _view == PlayerView.rear
        ? m.value.position + _rearOffset
        : m.value.position;
  }

  static Duration _clamp(Duration d, Duration max) {
    if (d < Duration.zero) return Duration.zero;
    if (max > Duration.zero && d > max) return max;
    return d;
  }

  Future<VideoPlayerController> _load(CameraFile? file) async {
    final uri = file == null
        ? null
        : await ref.read(downloaderProvider).localUri(file.name);
    if (uri == null) throw StateError('This clip is not saved on the phone.');
    final c = VideoPlayerController.contentUri(Uri.parse(uri));
    try {
      await c.initialize();
    } catch (_) {
      await c.dispose();
      rethrow;
    }
    return c;
  }

  Future<void> _open(PlayerView view) async {
    final gen = ++_generation;
    final oldMain = _main;
    final oldRear = _rear;
    final moment = _moment();
    final wasPlaying = oldMain?.value.isPlaying ?? true;
    setState(() {
      _view = view;
      _loading = true;
      _error = null;
    });
    VideoPlayerController? main;
    VideoPlayerController? rear;
    try {
      if (view == PlayerView.both) {
        main = await _load(widget.recording.front);
        rear = await _load(widget.recording.rear);
        // One soundtrack is enough; both cameras record the same cabin.
        await rear.setVolume(0);
      } else {
        main = await _load(_fileFor(view));
      }
      if (moment != null) {
        final mainAt = view == PlayerView.rear ? moment - _rearOffset : moment;
        await main.seekTo(_clamp(mainAt, main.value.duration));
        await rear?.seekTo(_clamp(moment - _rearOffset, rear.value.duration));
      }
      if (gen != _generation || !mounted) {
        await main.dispose();
        await rear?.dispose();
        return;
      }
      _follow?.cancel();
      oldMain?.removeListener(_onTick);
      main.addListener(_onTick);
      setState(() {
        _main = main;
        _rear = rear;
        _loading = false;
      });
      // The old players go once their pictures have left the screen, and the new
      // ones do not wait for that.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        oldMain?.dispose();
        oldRear?.dispose();
      });
      if (rear != null) {
        _follow = Timer.periodic(
          const Duration(seconds: 1),
          (_) => _keepTogether(),
        );
      }
      if (wasPlaying) await _play();
    } catch (e) {
      await main?.dispose();
      await rear?.dispose();
      if (gen != _generation || !mounted) return;
      setState(() {
        _loading = false;
        _error = e is StateError
            ? e.message
            : 'This clip could not be played: $e';
      });
    }
  }

  // ---- Controls drive both clips -----------------------------------------------------

  Future<void> _play() async {
    final m = _main;
    if (m == null) return;
    final v = m.value;
    if (v.duration > Duration.zero && v.position >= v.duration) {
      await _seek(Duration.zero);
    }
    await m.play();
    await _rear?.play();
  }

  Future<void> _pause() async {
    await _main?.pause();
    await _rear?.pause();
  }

  /// [position] is on the leading clip's timeline.
  Future<void> _seek(Duration position) async {
    final m = _main;
    if (m == null) return;
    await m.seekTo(_clamp(position, m.value.duration));
    final r = _rear;
    if (r != null) {
      await r.seekTo(_clamp(position - _rearOffset, r.value.duration));
    }
  }

  /// Every second while both play: the rear clip is nudged back in step if it drifts,
  /// and follows play/pause (for example when the front clip reaches its end).
  void _keepTogether() {
    final m = _main;
    final r = _rear;
    if (m == null || r == null) return;
    final mv = m.value;
    final rv = r.value;
    final target = mv.position - _rearOffset;
    if (!mv.isPlaying) {
      if (rv.isPlaying) r.pause();
      return;
    }
    if (target < Duration.zero) return; // rear clip has not started yet
    final drift = (rv.position - target).abs();
    if (drift > const Duration(milliseconds: 300) && target <= rv.duration) {
      r.seekTo(target);
    }
    if (!rv.isPlaying && rv.position < rv.duration) r.play();
  }

  void _onPipAction(String action) {
    final m = _main;
    if (m == null) return;
    switch (action) {
      case 'play':
        _play();
      case 'pause':
        _pause();
      case 'rewind' || 'forward':
        _seek(
          m.value.position + Duration(seconds: action == 'rewind' ? -10 : 10),
        );
    }
  }

  // ---- Layout ------------------------------------------------------------------------

  static Widget _video(VideoPlayerController c, {String? label}) {
    return Center(
      child: AspectRatio(
        aspectRatio: c.value.aspectRatio,
        child: Stack(
          children: [
            Positioned.fill(child: VideoPlayer(c)),
            if (label != null)
              Positioned(
                left: 8,
                top: 8,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: Colors.black54,
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 6,
                      vertical: 2,
                    ),
                    child: Text(
                      label,
                      style: const TextStyle(color: Colors.white, fontSize: 12),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  /// Both clips: one above the other when the space is taller than wide, side by side
  /// otherwise.
  Widget _pair(
    VideoPlayerController front,
    VideoPlayerController rear, {
    bool labels = true,
    bool? sideBySide,
  }) {
    return LayoutBuilder(
      builder: (context, box) {
        final wide = sideBySide ?? box.maxWidth > box.maxHeight;
        final a = _video(front, label: labels ? 'Front' : null);
        final b = _video(rear, label: labels ? 'Rear' : null);
        return wide
            ? Row(
                children: [
                  Expanded(child: a),
                  const SizedBox(width: 4),
                  Expanded(child: b),
                ],
              )
            : Column(
                children: [
                  Expanded(child: a),
                  const SizedBox(height: 4),
                  Expanded(child: b),
                ],
              );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final local = ref.watch(localFilesProvider).value ?? const {};
    final r = widget.recording;
    final bothSaved =
        r.front != null &&
        r.rear != null &&
        local.containsKey(r.front!.name) &&
        local.containsKey(r.rear!.name);
    final main = _main;
    final rear = _rear;
    final time = r.time;
    final playing = main?.value.isPlaying ?? false;
    final ratio = main?.value.aspectRatio ?? 16 / 9;

    final Widget picture = _error != null
        ? Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Text(
                _error!,
                textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.white),
              ),
            ),
          )
        : main == null
        ? const Center(child: CircularProgressIndicator(color: Colors.white))
        : Stack(
            children: [
              Positioned.fill(
                child: rear != null ? _pair(main, rear) : _video(main),
              ),
              if (_loading)
                const Center(
                  child: CircularProgressIndicator(color: Colors.white),
                ),
            ],
          );

    return PipHost(
      // Like YouTube: only a clip that is playing goes into the window by itself.
      autoEnter: playing,
      // Both clips float side by side.
      aspectRatio: rear != null ? ratio * 2 : ratio,
      actions: main == null
          ? const []
          : ['rewind', playing ? 'pause' : 'play', 'forward'],
      onAction: _onPipAction,
      // Closing the floating window stops the clip.
      onClosed: _pause,
      pipChild: ColoredBox(
        color: Colors.black,
        child: main == null
            ? const SizedBox.expand()
            : rear != null
            ? _pair(main, rear, labels: false, sideBySide: true)
            : _video(main),
      ),
      child: Scaffold(
        backgroundColor: Colors.black,
        appBar: AppBar(
          backgroundColor: Colors.black,
          foregroundColor: Colors.white,
          title: Text(time == null ? r.files.first.name : formatDateTime(time)),
          actions: const [PipButton(color: Colors.white)],
        ),
        body: SafeArea(
          child: Column(
            children: [
              Expanded(child: picture),
              if (main != null)
                _Controls(
                  controller: main,
                  play: _play,
                  pause: _pause,
                  seek: _seek,
                ),
              if (bothSaved)
                Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: Theme(
                    data: ThemeData.dark(useMaterial3: true),
                    child: SegmentedButton<PlayerView>(
                      segments: const [
                        ButtonSegment(
                          value: PlayerView.front,
                          label: Text('Front'),
                        ),
                        ButtonSegment(
                          value: PlayerView.rear,
                          label: Text('Rear'),
                        ),
                        ButtonSegment(
                          value: PlayerView.both,
                          label: Text('Both'),
                        ),
                      ],
                      selected: {_view},
                      showSelectedIcon: false,
                      onSelectionChanged: (s) {
                        if (s.first != _view) _open(s.first);
                      },
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

class _Controls extends StatelessWidget {
  const _Controls({
    required this.controller,
    required this.play,
    required this.pause,
    required this.seek,
  });

  /// The leading clip: its position and length are shown.
  final VideoPlayerController controller;

  // These act on every clip on screen.
  final Future<void> Function() play;
  final Future<void> Function() pause;
  final Future<void> Function(Duration) seek;

  static String _clock(Duration d) {
    final s = d.inSeconds;
    final mm = (s ~/ 60).toString().padLeft(2, '0');
    final ss = (s % 60).toString().padLeft(2, '0');
    return '$mm:$ss';
  }

  @override
  Widget build(BuildContext context) {
    return Theme(
      data: ThemeData.dark(useMaterial3: true),
      child: ValueListenableBuilder<VideoPlayerValue>(
        valueListenable: controller,
        builder: (context, v, _) {
          final total = v.duration.inMilliseconds.toDouble();
          final at = v.position.inMilliseconds.toDouble().clamp(
            0.0,
            total <= 0 ? 0.0 : total,
          );
          return Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Slider(
                value: at,
                max: total <= 0 ? 1 : total,
                onChanged: total <= 0
                    ? null
                    : (x) => seek(Duration(milliseconds: x.round())),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 24),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      _clock(v.position),
                      style: const TextStyle(color: Colors.white70),
                    ),
                    Text(
                      _clock(v.duration),
                      style: const TextStyle(color: Colors.white70),
                    ),
                  ],
                ),
              ),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  IconButton(
                    tooltip: 'Back 10 seconds',
                    iconSize: 32,
                    onPressed: () =>
                        seek(v.position - const Duration(seconds: 10)),
                    icon: const Icon(Icons.replay_10),
                  ),
                  const SizedBox(width: 16),
                  IconButton.filled(
                    tooltip: v.isPlaying ? 'Pause' : 'Play',
                    iconSize: 40,
                    onPressed: v.isPlaying ? pause : play,
                    icon: Icon(v.isPlaying ? Icons.pause : Icons.play_arrow),
                  ),
                  const SizedBox(width: 16),
                  IconButton(
                    tooltip: 'Forward 10 seconds',
                    iconSize: 32,
                    onPressed: () =>
                        seek(v.position + const Duration(seconds: 10)),
                    icon: const Icon(Icons.forward_10),
                  ),
                ],
              ),
              const SizedBox(height: 8),
            ],
          );
        },
      ),
    );
  }
}
