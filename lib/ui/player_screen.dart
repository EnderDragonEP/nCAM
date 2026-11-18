import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:video_player/video_player.dart';

import '../camera/models.dart';
import '../camera/recordings.dart';
import '../camera/transport.dart';
import '../l10n/l10n.dart';
import '../state/clip_names.dart';
import '../state/downloads.dart';
import '../state/pip.dart';
import '../state/session.dart';
import 'format.dart';

enum PlayerView { front, rear, both }

/// How often the player checks on its clips: that a pause from outside (a phone call
/// taking the sound) shows as paused, and, with both clips, that the rear keeps step.
const playerCheckInterval = Duration(milliseconds: 500);

/// How long the landscape controls stay up once the clip plays untouched.
const playerControlsTimeout = Duration(seconds: 3);

/// When the rear clip is too far out of step to catch up gently, it jumps this far
/// ahead of the front, because the jump itself takes a moment in these files.
const playerSeekLead = Duration(milliseconds: 300);

/// Plays a recording from the phone's copy: the front clip, the rear clip, or both
/// together (one above the other in portrait, side by side in landscape). Switching
/// keeps the position. Landscape uses the whole screen, with the controls on top.
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
  Msg? _error;
  bool _loading = true;
  int _generation = 0;
  late final CameraTransport _transport;

  /// Whether the user wants the clip playing. Not the players' own flag: Android
  /// reports "not playing" for every moment a clip is loading after a jump, and a
  /// button that followed that would show Play while the clip is about to go on.
  bool _playing = false;

  Timer? _check;
  bool _checking = false;

  /// Checks to skip after the user acts, while the players settle.
  int _quiet = 0;

  /// Checks in a row that found the leading clip stopped although it should play.
  int _stalled = 0;
  double _rearSpeed = 1;

  bool _controlsShown = true;
  Timer? _hideControls;
  bool _immersive = false;

  @override
  void initState() {
    super.initState();
    _transport = ref.read(transportProvider)..keepScreenOn(true).ignore();
    _check = Timer.periodic(playerCheckInterval, (_) => _checkClips());
    _open(_view);
  }

  @override
  void dispose() {
    _generation++;
    _check?.cancel();
    _hideControls?.cancel();
    _main?.dispose();
    _rear?.dispose();
    if (_immersive) {
      SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge).ignore();
    }
    // Not ref: it cannot be used once the page is being taken down.
    _transport.keepScreenOn(false).ignore();
    super.dispose();
  }

  static Duration _clamp(Duration d, Duration max) {
    if (d < Duration.zero) return Duration.zero;
    if (max > Duration.zero && d > max) return max;
    return d;
  }

  /// [follower] is the muted rear clip. Each Android player otherwise takes the
  /// sound focus when it starts, which pauses the app's other player, so the two
  /// clips would take turns instead of playing together.
  Future<VideoPlayerController> _load(
    CameraFile? file, {
    required bool follower,
  }) async {
    final uri = file == null
        ? null
        : await ref.read(downloaderProvider).localUri(file.name);
    if (uri == null) throw const _NotSaved();
    final c = VideoPlayerController.contentUri(
      Uri.parse(uri),
      videoPlayerOptions: VideoPlayerOptions(mixWithOthers: follower),
    );
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
    // Front and rear are recorded together (their file names nearly always share the
    // same second), so the same position in each is the same moment.
    final at = oldMain?.value.position;
    final play = oldMain == null || _playing;
    setState(() {
      _view = view;
      _loading = true;
      _error = null;
    });
    VideoPlayerController? main;
    VideoPlayerController? rear;
    try {
      // The leading clip is made first: the sound setting is shared by the players
      // made after it.
      main = await _load(
        view == PlayerView.rear
            ? widget.recording.rear
            : widget.recording.front ?? widget.recording.other,
        follower: false,
      );
      if (view == PlayerView.both) {
        rear = await _load(widget.recording.rear, follower: true);
        await rear.setVolume(0);
      }
      if (at != null) {
        await main.seekTo(_clamp(at, main.value.duration));
        await rear?.seekTo(_clamp(at, rear.value.duration));
      }
      if (gen != _generation || !mounted) {
        await main.dispose();
        await rear?.dispose();
        return;
      }
      setState(() {
        _main = main;
        _rear = rear;
        _loading = false;
      });
      _rearSpeed = 1;
      _stalled = 0;
      _quiet = 2;
      // The old players go once their pictures have left the screen, and the new
      // ones do not wait for that.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        oldMain?.dispose();
        oldRear?.dispose();
      });
      if (play) await _play();
    } catch (e) {
      await main?.dispose();
      await rear?.dispose();
      if (gen != _generation || !mounted) return;
      setState(() {
        _loading = false;
        _error = e is _NotSaved
            ? (l) => l.clipNotSaved
            : (l) => l.clipPlayFailed('$e');
      });
    }
  }

  // ---- Controls drive both clips -----------------------------------------------------

  Future<void> _play() async {
    final m = _main;
    if (m == null) return;
    setState(() => _playing = true);
    _quiet = 2;
    _stalled = 0;
    _touchControls();
    final v = m.value;
    if (v.duration > Duration.zero && v.position >= v.duration) {
      await _seek(Duration.zero);
    }
    final r = _rear;
    await Future.wait([
      m.play(),
      // A rear clip that has already ended stays there; playing it would restart it.
      if (r != null && r.value.position < r.value.duration) r.play(),
    ]);
  }

  Future<void> _pause() async {
    if (mounted) setState(() => _playing = false);
    _showControls();
    await Future.wait([?_main?.pause(), ?_rear?.pause()]);
  }

  /// Moves both clips to [position].
  Future<void> _seek(Duration position) async {
    final m = _main;
    if (m == null) return;
    _quiet = 2;
    _touchControls();
    final r = _rear;
    await Future.wait([
      m.seekTo(_clamp(position, m.value.duration)),
      if (r != null) r.seekTo(_clamp(position, r.value.duration)),
    ]);
    if (r != null) await _setRearSpeed(r, 1);
  }

  /// While the seek bar is dragged only the leading clip follows; the rear joins it
  /// when the bar is let go.
  Future<void> _preview(Duration position) async {
    final m = _main;
    if (m == null) return;
    _quiet = 2;
    _touchControls();
    await m.seekTo(_clamp(position, m.value.duration));
  }

  Future<void> _setRearSpeed(VideoPlayerController r, double speed) async {
    if (speed == _rearSpeed) return;
    _rearSpeed = speed;
    await r.setPlaybackSpeed(speed);
  }

  Future<void> _checkClips() async {
    final m = _main;
    if (m == null || _loading || _checking || !_playing) return;
    if (_quiet > 0) {
      _quiet--;
      return;
    }
    final mv = m.value;
    if (mv.isCompleted ||
        (mv.duration > Duration.zero && mv.position >= mv.duration)) {
      await _pause(); // reached the end
      return;
    }
    if (!mv.isPlaying && !mv.isBuffering) {
      // Stopped from outside, for example a phone call took the sound: show it as
      // paused and stop the rear too, rather than leave Pause over a still picture.
      if (++_stalled >= 2) await _pause();
      return;
    }
    _stalled = 0;
    final r = _rear;
    if (r == null || !mv.isPlaying) return;
    _checking = true;
    try {
      await _keepInStep(m, r);
    } finally {
      _checking = false;
    }
  }

  /// Keeps the rear clip on the front clip's moment: small differences are made up by
  /// running it slightly faster or slower, which looks smooth; only a big one is a
  /// jump, because each jump in these files makes the picture pause briefly.
  Future<void> _keepInStep(
    VideoPlayerController m,
    VideoPlayerController r,
  ) async {
    final at = await Future.wait([m.position, r.position]);
    final front = at[0];
    final rear = at[1];
    if (front == null || rear == null || !mounted || r != _rear) return;
    final rv = r.value;
    if (front >= rv.duration) return; // the rear clip is shorter and has ended
    if (!rv.isPlaying && !rv.isBuffering) {
      await r.play();
      _quiet = 2;
      return;
    }
    final ahead = (rear - front).inMilliseconds;
    if (ahead.abs() > 1500) {
      await r.seekTo(_clamp(front + playerSeekLead, rv.duration));
      await _setRearSpeed(r, 1);
      _quiet = 3;
    } else if (ahead.abs() > 80) {
      final speed = (1 - ahead / 2000).clamp(0.75, 1.25);
      await _setRearSpeed(r, (speed * 20).round() / 20);
    } else {
      await _setRearSpeed(r, 1);
    }
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

  // ---- Landscape controls ------------------------------------------------------------

  void _showControls() {
    _hideControls?.cancel();
    if (!_controlsShown && mounted) setState(() => _controlsShown = true);
  }

  /// Shows the controls and, while playing, hides them again after a while.
  void _touchControls() {
    _showControls();
    _hideControls = Timer(playerControlsTimeout, () {
      if (mounted && _playing) setState(() => _controlsShown = false);
    });
  }

  void _toggleControls() {
    if (_controlsShown && _playing) {
      _hideControls?.cancel();
      setState(() => _controlsShown = false);
    } else {
      _touchControls();
    }
  }

  /// Landscape hides the status and navigation bars so the clips get the screen.
  void _setImmersive(bool on) {
    if (_immersive == on) return;
    _immersive = on;
    SystemChrome.setEnabledSystemUIMode(
      on ? SystemUiMode.immersiveSticky : SystemUiMode.edgeToEdge,
    ).ignore();
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
        final l = context.l10n;
        final a = _video(front, label: labels ? l.front : null);
        final b = _video(rear, label: labels ? l.rear : null);
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

  Widget _picker() {
    final l = context.l10n;
    return Theme(
      data: ThemeData.dark(useMaterial3: true),
      child: SegmentedButton<PlayerView>(
        segments: [
          ButtonSegment(value: PlayerView.front, label: Text(l.front)),
          ButtonSegment(value: PlayerView.rear, label: Text(l.rear)),
          ButtonSegment(value: PlayerView.both, label: Text(l.both)),
        ],
        selected: {_view},
        showSelectedIcon: false,
        onSelectionChanged: (s) {
          _touchControls();
          if (s.first != _view) _open(s.first);
        },
      ),
    );
  }

  /// Fades a landscape control bar in and out; hidden bars cannot be tapped.
  Widget _overlay({required Widget child, required bool top}) {
    return IgnorePointer(
      ignoring: !_controlsShown,
      child: AnimatedOpacity(
        key: ValueKey(top ? 'player-top-bar' : 'player-bottom-bar'),
        opacity: _controlsShown ? 1 : 0,
        duration: const Duration(milliseconds: 200),
        child: DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: top ? Alignment.topCenter : Alignment.bottomCenter,
              end: top ? Alignment.bottomCenter : Alignment.topCenter,
              colors: const [Color(0xB0000000), Color(0x00000000)],
            ),
          ),
          child: SafeArea(top: top, bottom: !top, child: child),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final local = ref.watch(localFilesProvider).value ?? const {};
    final inPip = ref.watch(pipProvider.select((s) => s.inPip));
    final r = widget.recording;
    final bothSaved =
        r.front != null &&
        r.rear != null &&
        local.containsKey(r.front!.name) &&
        local.containsKey(r.rear!.name);
    final main = _main;
    final rear = _rear;
    final time = r.time;
    final date = time == null ? r.files.first.name : formatDateTime(time);
    final name = clipName(ref.watch(clipNamesProvider), r);
    final ratio = main?.value.aspectRatio ?? 16 / 9;
    final landscape =
        MediaQuery.orientationOf(context) == Orientation.landscape;
    _setImmersive(landscape && !inPip);

    final Widget picture = _error != null
        ? Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Text(
                _error!(l),
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

    Widget controls({required bool compact}) => _Controls(
      controller: main!,
      playing: _playing,
      play: _play,
      pause: _pause,
      seek: _seek,
      preview: _preview,
      compact: compact,
      trailing: compact && bothSaved ? _picker() : null,
    );

    final Widget page;
    if (landscape) {
      // The camera cut-out takes one side; both sides give way so the clips stay
      // centred.
      final pad = MediaQuery.paddingOf(context);
      final side = math.max(pad.left, pad.right);
      page = Scaffold(
        backgroundColor: Colors.black,
        body: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: _toggleControls,
          child: Stack(
            children: [
              Positioned.fill(
                child: Padding(
                  padding: EdgeInsets.symmetric(horizontal: side),
                  child: picture,
                ),
              ),
              Positioned(
                left: 0,
                right: 0,
                top: 0,
                child: _overlay(
                  top: true,
                  child: Row(
                    children: [
                      const BackButton(color: Colors.white),
                      Expanded(
                        child: Text(
                          name == null ? date : l.titleWithName(name, date),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 18,
                          ),
                        ),
                      ),
                      const PipButton(color: Colors.white),
                    ],
                  ),
                ),
              ),
              if (main != null)
                Positioned(
                  left: 0,
                  right: 0,
                  bottom: 0,
                  child: _overlay(top: false, child: controls(compact: true)),
                ),
            ],
          ),
        ),
      );
    } else {
      page = Scaffold(
        backgroundColor: Colors.black,
        appBar: AppBar(
          backgroundColor: Colors.black,
          foregroundColor: Colors.white,
          title: name == null
              ? Text(date)
              : Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(name, maxLines: 1, overflow: TextOverflow.ellipsis),
                    Text(
                      date,
                      style: const TextStyle(
                        fontSize: 13,
                        color: Colors.white70,
                      ),
                    ),
                  ],
                ),
          actions: const [PipButton(color: Colors.white)],
        ),
        body: SafeArea(
          child: Column(
            children: [
              Expanded(child: picture),
              if (main != null) controls(compact: false),
              if (bothSaved)
                Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: _picker(),
                ),
            ],
          ),
        ),
      );
    }

    return PipHost(
      // Like YouTube: only a clip that is playing goes into the window by itself.
      autoEnter: _playing,
      // Both clips float side by side.
      aspectRatio: rear != null ? ratio * 2 : ratio,
      actions: main == null
          ? const []
          : ['rewind', _playing ? 'pause' : 'play', 'forward'],
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
      child: page,
    );
  }
}

class _Controls extends StatelessWidget {
  const _Controls({
    required this.controller,
    required this.playing,
    required this.play,
    required this.pause,
    required this.seek,
    required this.preview,
    this.compact = false,
    this.trailing,
  });

  /// The leading clip: its position and length are shown.
  final VideoPlayerController controller;

  /// What the play button shows: the user's choice, not the player's moment-to-moment
  /// state.
  final bool playing;

  // These act on every clip on screen.
  final Future<void> Function() play;
  final Future<void> Function() pause;
  final Future<void> Function(Duration) seek;
  final Future<void> Function(Duration) preview;

  /// Landscape: one slim bar with the times beside the seek bar.
  final bool compact;

  /// Shown at the end of the button row in [compact] mode.
  final Widget? trailing;

  static String _clock(Duration d) {
    final s = d.inSeconds;
    final mm = (s ~/ 60).toString().padLeft(2, '0');
    final ss = (s % 60).toString().padLeft(2, '0');
    return '$mm:$ss';
  }

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    const timeStyle = TextStyle(color: Colors.white70);
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
          final slider = Slider(
            value: at,
            max: total <= 0 ? 1 : total,
            onChanged: total <= 0
                ? null
                : (x) => preview(Duration(milliseconds: x.round())),
            onChangeEnd: total <= 0
                ? null
                : (x) => seek(Duration(milliseconds: x.round())),
          );
          final buttons = [
            IconButton(
              tooltip: l.back10,
              iconSize: compact ? 28 : 32,
              onPressed: () => seek(v.position - const Duration(seconds: 10)),
              icon: const Icon(Icons.replay_10),
            ),
            SizedBox(width: compact ? 8 : 16),
            IconButton.filled(
              tooltip: playing ? l.pause : l.play,
              iconSize: compact ? 32 : 40,
              onPressed: playing ? pause : play,
              icon: Icon(playing ? Icons.pause : Icons.play_arrow),
            ),
            SizedBox(width: compact ? 8 : 16),
            IconButton(
              tooltip: l.forward10,
              iconSize: compact ? 28 : 32,
              onPressed: () => seek(v.position + const Duration(seconds: 10)),
              icon: const Icon(Icons.forward_10),
            ),
          ];
          if (compact) {
            return Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    children: [
                      Text(_clock(v.position), style: timeStyle),
                      Expanded(child: slider),
                      Text(_clock(v.duration), style: timeStyle),
                    ],
                  ),
                  Row(children: [...buttons, const Spacer(), ?trailing]),
                ],
              ),
            );
          }
          return Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              slider,
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 24),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(_clock(v.position), style: timeStyle),
                    Text(_clock(v.duration), style: timeStyle),
                  ],
                ),
              ),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: buttons,
              ),
              const SizedBox(height: 8),
            ],
          );
        },
      ),
    );
  }
}

/// The clip is not (or no longer) in the phone's gallery.
class _NotSaved implements Exception {
  const _NotSaved();
}
