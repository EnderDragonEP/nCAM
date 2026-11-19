import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
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
import 'zoomable_view.dart';

enum PlayerView { front, rear, both }

/// How often the player checks on its clips: that a pause from outside (a phone call
/// taking the sound) shows as paused, and, with both clips, that the rear keeps step.
const playerCheckInterval = Duration(milliseconds: 500);

/// How long overlaid controls stay up untouched, unless the phone's accessibility
/// settings ask for longer.
const playerControlsTimeout = Duration(seconds: 3);

/// The playback speeds offered.
const playerSpeeds = [
  0.25,
  0.5,
  0.75,
  1.0,
  1.25,
  1.5,
  1.75,
  2.0,
  2.5,
  3.0,
  4.0,
];

/// How long on-screen controls may stay before hiding by themselves: Android's "time to
/// take action" accessibility setting when it is longer than [playerControlsTimeout].
final controlsTimeoutProvider = FutureProvider<Duration>((ref) async {
  const fallback = playerControlsTimeout;
  try {
    final ms = await const MethodChannel('ncam/camera')
        .invokeMethod<int>('controlsTimeout', {'ms': fallback.inMilliseconds});
    return ms == null || ms < fallback.inMilliseconds
        ? fallback
        : Duration(milliseconds: ms);
  } catch (_) {
    return fallback;
  }
});

/// When the rear clip is too far out of step to catch up gently, it jumps this far
/// ahead of the front, because the jump itself takes a moment in these files.
const playerSeekLead = Duration(milliseconds: 300);

/// Plays a recording: the front clip, the rear clip, or both together (one above the
/// other in portrait, side by side in landscape). Each clip plays from the phone's copy,
/// or straight from the camera when it is not saved. Switching keeps the position.
/// Landscape, and a zoomed picture, use the whole screen with the controls on top.
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

  /// The speed the user picked; the rear clip runs at this times [_rearFactor].
  double _speed = 1;
  double _rearFactor = 1;

  /// A clip on screen comes from the camera rather than the phone.
  bool _streaming = false;

  bool _controlsShown = true;
  Timer? _hideControls;
  bool _immersive = false;
  Duration _hideAfter = playerControlsTimeout;

  /// A screen reader is on: controls never hide by themselves.
  bool _accessible = false;

  /// How each clip on screen sits; a clip not listed shows whole.
  final _fits = <Object, PictureFit>{};
  bool get _isZoomed => _fits.values.any((f) => f != PictureFit.whole);

  /// Keeps the pictures (and their zoom) when the layout around them changes.
  final _pictureKey = GlobalKey();

  /// Tells every clip on screen how to sit (the fit button).
  final _fitCommand = FitCommand();

  @override
  void initState() {
    super.initState();
    _transport = ref.read(transportProvider)..keepScreenOn(true).ignore();
    _check = Timer.periodic(playerCheckInterval, (_) => _checkClips());
    ref.read(controlsTimeoutProvider.future).then((d) => _hideAfter = d);
    _open(_view);
  }

  @override
  void dispose() {
    _generation++;
    _check?.cancel();
    _hideControls?.cancel();
    _fitCommand.dispose();
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

  /// Whether [f] can be played from the camera: connected, a real file on the card,
  /// and not the clip being recorded (it is still growing).
  bool _onCamera(CameraFile f) {
    final s = ref.read(sessionProvider);
    return s.connected && f.path.startsWith('/') && !s.writing.contains(f.path);
  }

  /// The phone's copy of [file], or the camera's. [follower] is the muted rear clip.
  /// Each Android player otherwise takes the sound focus when it starts, which pauses
  /// the app's other player, so the two clips would take turns instead of playing
  /// together.
  Future<({VideoPlayerController controller, bool streamed})> _load(
    CameraFile? file, {
    required bool follower,
  }) async {
    if (file == null) throw const _NotSaved();
    final options = VideoPlayerOptions(mixWithOthers: follower);
    final local = await ref.read(downloaderProvider).localUri(file.name);
    final VideoPlayerController c;
    if (local != null) {
      c = VideoPlayerController.contentUri(
        Uri.parse(local),
        videoPlayerOptions: options,
      );
    } else if (_onCamera(file)) {
      final url = await _transport.streamUrl(file.path);
      c = VideoPlayerController.networkUrl(
        Uri.parse(url),
        videoPlayerOptions: options,
      );
    } else {
      throw const _NotSaved();
    }
    try {
      await c.initialize();
    } catch (_) {
      await c.dispose();
      rethrow;
    }
    return (controller: c, streamed: local == null);
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
    var streamed = false;
    try {
      // The leading clip is made first: the sound setting is shared by the players
      // made after it.
      final first = await _load(
        view == PlayerView.rear
            ? widget.recording.rear
            : widget.recording.front ?? widget.recording.other,
        follower: false,
      );
      main = first.controller;
      streamed = first.streamed;
      if (view == PlayerView.both) {
        final second = await _load(widget.recording.rear, follower: true);
        rear = second.controller;
        streamed |= second.streamed;
        await rear.setVolume(0);
      }
      await main.setPlaybackSpeed(_speed);
      await rear?.setPlaybackSpeed(_speed);
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
        _streaming = streamed;
        _fits.clear();
      });
      _rearFactor = 1;
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
    _touchControls();
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
    if (r != null) await _setRearFactor(r, 1);
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

  Future<void> _setSpeed(double speed) async {
    setState(() => _speed = speed);
    _touchControls();
    await _main?.setPlaybackSpeed(speed);
    await _rear?.setPlaybackSpeed(speed * _rearFactor);
  }

  /// Runs the rear clip a little faster or slower than the chosen speed.
  Future<void> _setRearFactor(VideoPlayerController r, double factor) async {
    if (factor == _rearFactor) return;
    _rearFactor = factor;
    await r.setPlaybackSpeed(_speed * factor);
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
      await _setRearFactor(r, 1);
      _quiet = 3;
    } else if (ahead.abs() > 80) {
      final factor = (1 - ahead / 2000).clamp(0.75, 1.25);
      await _setRearFactor(r, (factor * 20).round() / 20);
    } else {
      await _setRearFactor(r, 1);
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

  // ---- Overlaid controls -------------------------------------------------------------

  bool _landscape = false;

  /// The bars hide by themselves whenever they lie over the clips (landscape, or a
  /// zoomed picture spreading under them), but never with a screen reader on.
  bool get _autoHide => (_landscape || _isZoomed) && !_accessible;

  void _showControls() {
    _hideControls?.cancel();
    if (!_controlsShown && mounted) setState(() => _controlsShown = true);
  }

  /// Shows the controls and, where they hide by themselves, hides them again after a
  /// while.
  void _touchControls() {
    _showControls();
    if (!_autoHide) return;
    _hideControls = Timer(_hideAfter, () {
      if (mounted && _autoHide) setState(() => _controlsShown = false);
    });
  }

  /// Two fingers on a picture: the bars get out of the way at once. A tap brings them
  /// back.
  void _hideForZoom() {
    if (_accessible || !mounted) return;
    _hideControls?.cancel();
    if (_controlsShown) setState(() => _controlsShown = false);
  }

  void _onFit(Object clip, PictureFit fit) {
    if (!mounted) return;
    setState(() => _fits[clip] = fit);
    // Back to the whole picture: the bars return (and stay where they may).
    if (!_isZoomed) _touchControls();
  }

  void _toggleControls() {
    if (_controlsShown && _autoHide) {
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

  /// One clip. On the page it can be pinched to fill the space or zoomed (each clip on
  /// its own when both are shown); the floating window shows it whole.
  Widget _video(VideoPlayerController c, {String? label, bool zoom = true}) {
    final picture = VideoPlayer(c);
    return Stack(
      clipBehavior: Clip.none,
      children: [
        Positioned.fill(
          child: zoom
              ? ZoomableView(
                  // A new clip starts whole again.
                  key: ObjectKey(c),
                  aspectRatio: c.value.aspectRatio,
                  // A zoomed clip may spread under the bars; the page decides
                  // where it must stop (see _pair).
                  clip: false,
                  fitCommand: _fitCommand,
                  onPinch: _hideForZoom,
                  onFitChanged: (f) => _onFit(c, f),
                  child: picture,
                )
              : Center(
                  child: AspectRatio(
                    aspectRatio: c.value.aspectRatio,
                    child: picture,
                  ),
                ),
        ),
        if (label != null)
          Positioned(
            left: 8,
            top: 8,
            child: IgnorePointer(
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
          ),
      ],
    );
  }

  /// Both clips: one above the other when the space is taller than wide, side by side
  /// otherwise.
  Widget _pair(
    VideoPlayerController front,
    VideoPlayerController rear, {
    bool labels = true,
    bool? sideBySide,
    bool zoom = true,
  }) {
    return LayoutBuilder(
      builder: (context, box) {
        final wide = sideBySide ?? box.maxWidth > box.maxHeight;
        final l = context.l10n;
        // A zoomed clip may spread under the bars and off the screen, but never
        // over the other clip: each is cut only along the edge they share.
        Widget cut(Widget clip, AxisDirection edge) =>
            ClipRect(clipper: _CutAlong(edge), child: clip);
        final a = _video(front, label: labels ? l.front : null, zoom: zoom);
        final b = _video(rear, label: labels ? l.rear : null, zoom: zoom);
        return wide
            ? Row(
                children: [
                  Expanded(child: cut(a, AxisDirection.right)),
                  const SizedBox(width: 4),
                  Expanded(child: cut(b, AxisDirection.left)),
                ],
              )
            : Column(
                children: [
                  Expanded(child: cut(a, AxisDirection.down)),
                  const SizedBox(height: 4),
                  Expanded(child: cut(b, AxisDirection.up)),
                ],
              );
      },
    );
  }

  Widget _picker(Set<PlayerView> views) {
    final l = context.l10n;
    return Theme(
      data: ThemeData.dark(useMaterial3: true),
      child: SegmentedButton<PlayerView>(
        segments: [
          if (views.contains(PlayerView.front))
            ButtonSegment(value: PlayerView.front, label: Text(l.front)),
          if (views.contains(PlayerView.rear))
            ButtonSegment(value: PlayerView.rear, label: Text(l.rear)),
          if (views.contains(PlayerView.both))
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

  /// Fades a bar in and out; hidden bars cannot be tapped.
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
    // Rebuilt when the camera comes or goes, for what can be streamed; a clip that
    // could not be opened without it is tried again once it is there.
    ref.watch(sessionProvider.select((s) => (s.connected, s.writing)));
    ref.listen(sessionProvider.select((s) => s.connected), (was, now) {
      if (now && was != true && _main == null && _error != null) _open(_view);
    });
    _accessible = MediaQuery.accessibleNavigationOf(context);
    final r = widget.recording;
    bool saved(CameraFile? f) => f != null && local.containsKey(f.name);
    bool playable(CameraFile? f) => saved(f) || (f != null && _onCamera(f));
    final views = {
      if (playable(r.front)) PlayerView.front,
      if (playable(r.rear)) PlayerView.rear,
      if (playable(r.front) &&
          playable(r.rear) &&
          (saved(r.front) || saved(r.rear)))
        PlayerView.both,
    };
    final canPick = r.front != null && r.rear != null && views.length > 1;
    final main = _main;
    final rear = _rear;
    final time = r.time;
    final date = time == null ? r.files.first.name : formatDateTime(time);
    final name = clipName(ref.watch(clipNamesProvider), r);
    final ratio = main?.value.aspectRatio ?? 16 / 9;
    final landscape =
        MediaQuery.orientationOf(context) == Orientation.landscape;
    if (landscape != _landscape) {
      // Turned: the bars now lie over the clips (or no longer do).
      _landscape = landscape;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _touchControls();
      });
    }
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
            clipBehavior: Clip.none,
            children: [
              Positioned.fill(
                child: rear != null ? _pair(main, rear) : _video(main),
              ),
              // Loading, or waiting for the camera's Wi-Fi to catch up.
              Positioned.fill(
                child: ValueListenableBuilder<VideoPlayerValue>(
                  valueListenable: main,
                  builder: (context, v, _) =>
                      _loading || (_playing && v.isBuffering)
                      ? const Center(
                          child: CircularProgressIndicator(color: Colors.white),
                        )
                      : const SizedBox.shrink(),
                ),
              ),
              if (_streaming)
                Positioned(
                  right: 8,
                  top: 8,
                  child: IgnorePointer(
                    child: Tooltip(
                      message: l.streamingFromCamera,
                      child: const Icon(
                        Icons.wifi,
                        size: 18,
                        color: Colors.white70,
                      ),
                    ),
                  ),
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
      speed: _speed,
      setSpeed: _setSpeed,
      compact: compact,
      trailing: compact && canPick ? _picker(views) : null,
    );
    final pictureHere = KeyedSubtree(key: _pictureKey, child: picture);
    // One layout whether the picture is zoomed or not, so nothing moves: zooming only
    // makes the bars see-through and lets them fade away.
    final topBar = SizedBox(
      height: kToolbarHeight,
      child: Row(
        children: [
          const BackButton(color: Colors.white),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  name ?? date,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(color: Colors.white, fontSize: 20),
                ),
                if (name != null)
                  Text(
                    date,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 13, color: Colors.white70),
                  ),
              ],
            ),
          ),
          if (main != null)
            FitButton(
              color: Colors.white,
              current: [
                for (final c in [main, ?rear]) _fits[c] ?? PictureFit.whole,
              ],
              onPressed: (fit) {
                _fitCommand.apply(fit);
                _touchControls();
              },
            ),
          const PipButton(color: Colors.white),
          const SizedBox(width: 4),
        ],
      ),
    );
    final Widget bottomBar = main == null
        ? const SizedBox.shrink()
        : landscape
        ? controls(compact: true)
        : Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              controls(compact: false),
              if (canPick)
                Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: _picker(views),
                ),
            ],
          );
    final top = _overlay(top: true, child: topBar);
    final bottom = _overlay(top: false, child: bottomBar);

    final Widget body;
    if (landscape) {
      // The clips get the whole screen, the bars float over them. The camera cut-out
      // takes one side; both sides give way so the clips stay centred.
      final pad = MediaQuery.paddingOf(context);
      final side = math.max(pad.left, pad.right);
      body = Stack(
        children: [
          Positioned.fill(
            child: Padding(
              padding: EdgeInsets.symmetric(horizontal: side),
              child: pictureHere,
            ),
          ),
          Positioned(left: 0, right: 0, top: 0, child: top),
          Positioned(left: 0, right: 0, bottom: 0, child: bottom),
        ],
      );
    } else {
      // The clips get the space between the bars; zoomed in, a clip may spread
      // under them, where it shows through.
      body = CustomMultiChildLayout(
        delegate: _BetweenBars(),
        children: [
          LayoutId(id: _Slot.picture, child: pictureHere),
          LayoutId(id: _Slot.top, child: top),
          LayoutId(id: _Slot.bottom, child: bottom),
        ],
      );
    }
    final page = Scaffold(
      backgroundColor: Colors.black,
      body: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: _toggleControls,
        child: body,
      ),
    );

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
            ? _pair(main, rear, labels: false, sideBySide: true, zoom: false)
            : _video(main, zoom: false),
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
    required this.speed,
    required this.setSpeed,
    this.compact = false,
    this.trailing,
  });

  final double speed;
  final Future<void> Function(double) setSpeed;

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
          final speedButton = _SpeedButton(speed: speed, setSpeed: setSpeed);
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
                  Row(
                    children: [
                      ...buttons,
                      const SizedBox(width: 8),
                      speedButton,
                      const Spacer(),
                      ?trailing,
                    ],
                  ),
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
                children: [
                  const Spacer(),
                  ...buttons,
                  Expanded(child: Center(child: speedButton)),
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

/// Shows the speed ("1×", "0.5×") and offers the others.
class _SpeedButton extends StatelessWidget {
  const _SpeedButton({required this.speed, required this.setSpeed});
  final double speed;
  final Future<void> Function(double) setSpeed;

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    String label(double s) =>
        l.speedValue(NumberFormat.decimalPattern(l.localeName).format(s));
    return PopupMenuButton<double>(
      tooltip: l.playbackSpeed,
      initialValue: speed,
      onSelected: setSpeed,
      itemBuilder: (context) => [
        for (final s in playerSpeeds)
          PopupMenuItem(
            value: s,
            child: Text(s == 1 ? l.speedNormal : label(s)),
          ),
      ],
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 12),
        child: Text(
          label(speed),
          style: const TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
    );
  }
}

/// The clip is not (or no longer) in the phone's gallery.
class _NotSaved implements Exception {
  const _NotSaved();
}

enum _Slot { picture, top, bottom }

/// Portrait: the bars at the top and bottom, the clips in the space between them. The
/// clips are painted first, so a zoomed one that spreads past its space shows through
/// the bars.
class _BetweenBars extends MultiChildLayoutDelegate {
  @override
  void performLayout(Size size) {
    final bar = BoxConstraints(
      minWidth: size.width,
      maxWidth: size.width,
      maxHeight: size.height,
    );
    final top = layoutChild(_Slot.top, bar);
    final bottom = layoutChild(_Slot.bottom, bar);
    final height = math.max(0.0, size.height - top.height - bottom.height);
    layoutChild(_Slot.picture, BoxConstraints.tight(Size(size.width, height)));
    positionChild(_Slot.top, Offset.zero);
    positionChild(_Slot.picture, Offset(0, top.height));
    positionChild(_Slot.bottom, Offset(0, size.height - bottom.height));
  }

  @override
  bool shouldRelayout(_BetweenBars oldDelegate) => false;
}

/// Clips only along one [edge] of the child, leaving the other sides open.
class _CutAlong extends CustomClipper<Rect> {
  _CutAlong(this.edge);
  final AxisDirection edge;

  @override
  Rect getClip(Size size) {
    const far = 100000.0;
    return switch (edge) {
      AxisDirection.down => Rect.fromLTRB(-far, -far, far, size.height),
      AxisDirection.up => Rect.fromLTRB(-far, 0, far, far),
      AxisDirection.right => Rect.fromLTRB(-far, -far, size.width, far),
      AxisDirection.left => Rect.fromLTRB(0, -far, far, far),
    };
  }

  @override
  bool shouldReclip(_CutAlong oldClipper) => oldClipper.edge != edge;
}
