import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:video_player/video_player.dart';

import '../camera/models.dart';
import '../camera/recordings.dart';
import '../state/downloads.dart';
import '../state/pip.dart';
import '../state/session.dart';
import 'format.dart';

/// Plays a recording from the phone's copy. Front and rear clips of the same moment can
/// be switched without losing the position.
class PlayerScreen extends ConsumerStatefulWidget {
  const PlayerScreen({super.key, required this.recording, required this.lens});
  final Recording recording;
  final Lens lens;

  @override
  ConsumerState<PlayerScreen> createState() => _PlayerScreenState();
}

class _PlayerScreenState extends ConsumerState<PlayerScreen> {
  VideoPlayerController? _controller;
  late Lens _lens = widget.lens;
  String? _error;
  bool _loading = true;
  int _generation = 0;

  CameraFile? _fileFor(Lens lens) => switch (lens) {
    Lens.front => widget.recording.front,
    Lens.rear => widget.recording.rear,
    Lens.unknown => widget.recording.other,
  };

  @override
  void initState() {
    super.initState();
    ref.read(transportProvider).keepScreenOn(true).ignore();
    _open(_lens);
  }

  /// Play/pause changes the window's buttons and whether it may open by itself.
  bool _wasPlaying = false;

  void _onTick() {
    final playing = _controller?.value.isPlaying ?? false;
    if (playing != _wasPlaying && mounted) {
      setState(() => _wasPlaying = playing);
    }
  }

  void _onPipAction(String action) {
    final c = _controller;
    if (c == null) return;
    final v = c.value;
    switch (action) {
      case 'play':
        if (v.duration > Duration.zero && v.position >= v.duration) {
          c.seekTo(Duration.zero);
        }
        c.play();
      case 'pause':
        c.pause();
      case 'rewind' || 'forward':
        var target =
            v.position + Duration(seconds: action == 'rewind' ? -10 : 10);
        if (target < Duration.zero) target = Duration.zero;
        if (target > v.duration) target = v.duration;
        c.seekTo(target);
    }
  }

  @override
  void dispose() {
    _generation++;
    _controller?.removeListener(_onTick);
    _controller?.dispose();
    ref.read(transportProvider).keepScreenOn(false).ignore();
    super.dispose();
  }

  Future<void> _open(Lens lens) async {
    final gen = ++_generation;
    final old = _controller;
    final position = old?.value.position;
    final wasPlaying = old?.value.isPlaying ?? true;
    setState(() {
      _lens = lens;
      _loading = true;
      _error = null;
    });
    VideoPlayerController? next;
    try {
      final file = _fileFor(lens);
      final uri = file == null
          ? null
          : await ref.read(downloaderProvider).localUri(file.name);
      if (uri == null) {
        throw StateError('This clip is not saved on the phone.');
      }
      next = VideoPlayerController.contentUri(Uri.parse(uri));
      await next.initialize();
      if (position != null && position < next.value.duration) {
        await next.seekTo(position);
      }
      if (gen != _generation || !mounted) {
        await next.dispose();
        return;
      }
      old?.removeListener(_onTick);
      next.addListener(_onTick);
      setState(() {
        _controller = next;
        _loading = false;
      });
      await old?.dispose();
      if (wasPlaying) await next.play();
    } catch (e) {
      await next?.dispose();
      if (gen != _generation || !mounted) return;
      setState(() {
        _loading = false;
        _error = e is StateError
            ? e.message
            : 'This clip could not be played: $e';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final local = ref.watch(localFilesProvider).value ?? const {};
    final r = widget.recording;
    final lenses = [
      if (r.front != null && local.containsKey(r.front!.name)) Lens.front,
      if (r.rear != null && local.containsKey(r.rear!.name)) Lens.rear,
    ];
    final controller = _controller;
    final time = r.time;

    final playing = controller?.value.isPlaying ?? false;
    return PipHost(
      // Like YouTube: only a clip that is playing goes into the window by itself.
      autoEnter: playing,
      aspectRatio: controller?.value.aspectRatio ?? 16 / 9,
      actions: controller == null
          ? const []
          : ['rewind', playing ? 'pause' : 'play', 'forward'],
      onAction: _onPipAction,
      // Closing the floating window stops the clip.
      onClosed: () => _controller?.pause(),
      pipChild: ColoredBox(
        color: Colors.black,
        child: controller == null
            ? const SizedBox.expand()
            : Center(
                child: AspectRatio(
                  aspectRatio: controller.value.aspectRatio,
                  child: VideoPlayer(controller),
                ),
              ),
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
              Expanded(
                child: Center(
                  child: _error != null
                      ? Padding(
                          padding: const EdgeInsets.all(24),
                          child: Text(
                            _error!,
                            textAlign: TextAlign.center,
                            style: const TextStyle(color: Colors.white),
                          ),
                        )
                      : controller == null
                      ? const CircularProgressIndicator(color: Colors.white)
                      : Stack(
                          alignment: Alignment.center,
                          children: [
                            AspectRatio(
                              aspectRatio: controller.value.aspectRatio,
                              child: VideoPlayer(controller),
                            ),
                            if (_loading)
                              const CircularProgressIndicator(
                                color: Colors.white,
                              ),
                          ],
                        ),
                ),
              ),
              if (controller != null) _Controls(controller: controller),
              if (lenses.length > 1)
                Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: Theme(
                    data: ThemeData.dark(useMaterial3: true),
                    child: SegmentedButton<Lens>(
                      segments: const [
                        ButtonSegment(value: Lens.front, label: Text('Front')),
                        ButtonSegment(value: Lens.rear, label: Text('Rear')),
                      ],
                      selected: {_lens},
                      showSelectedIcon: false,
                      onSelectionChanged: (s) {
                        if (s.first != _lens) _open(s.first);
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
  const _Controls({required this.controller});
  final VideoPlayerController controller;

  static String _clock(Duration d) {
    final s = d.inSeconds;
    final mm = (s ~/ 60).toString().padLeft(2, '0');
    final ss = (s % 60).toString().padLeft(2, '0');
    return '$mm:$ss';
  }

  void _skip(int seconds) {
    final v = controller.value;
    var target = v.position + Duration(seconds: seconds);
    if (target < Duration.zero) target = Duration.zero;
    if (target > v.duration) target = v.duration;
    controller.seekTo(target);
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
          final ended = total > 0 && v.position >= v.duration && !v.isPlaying;
          return Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Slider(
                value: at,
                max: total <= 0 ? 1 : total,
                onChanged: total <= 0
                    ? null
                    : (x) =>
                          controller.seekTo(Duration(milliseconds: x.round())),
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
                    onPressed: () => _skip(-10),
                    icon: const Icon(Icons.replay_10),
                  ),
                  const SizedBox(width: 16),
                  IconButton.filled(
                    tooltip: v.isPlaying ? 'Pause' : 'Play',
                    iconSize: 40,
                    onPressed: () async {
                      if (v.isPlaying) {
                        await controller.pause();
                      } else {
                        if (ended) await controller.seekTo(Duration.zero);
                        await controller.play();
                      }
                    },
                    icon: Icon(v.isPlaying ? Icons.pause : Icons.play_arrow),
                  ),
                  const SizedBox(width: 16),
                  IconButton(
                    tooltip: 'Forward 10 seconds',
                    iconSize: 32,
                    onPressed: () => _skip(10),
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
