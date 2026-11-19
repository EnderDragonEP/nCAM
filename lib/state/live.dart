import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../camera/camera_api.dart';
import '../camera/transport.dart';
import '../l10n/l10n.dart';
import 'session.dart';

/// How long to wait for the first picture before nudging the camera.
final liveStartTimeoutProvider = Provider<Duration>(
  (ref) => const Duration(seconds: 4),
);

/// Pause before reopening a stream that broke.
final liveRetryDelayProvider = Provider<Duration>(
  (ref) => const Duration(seconds: 2),
);

enum LiveStatus { connecting, playing, failed }

class LiveState {
  const LiveState({
    this.status = LiveStatus.connecting,
    this.frame,
    this.message,
    this.framesPerSecond = 0,
    this.viewIndex,
    this.signal,
  });

  final LiveStatus status;

  /// The latest picture (a JPEG). Kept while reconnecting so the screen does not go black.
  final Uint8List? frame;
  final Msg? message;
  final int framesPerSecond;

  /// Which picture the camera is sending, as the camera's own index. Null if unknown.
  final int? viewIndex;

  /// The camera link's Wi-Fi signal in dBm, read every few seconds; null if unknown.
  final int? signal;

  static const _keep = Object();

  LiveState copyWith({
    LiveStatus? status,
    Uint8List? frame,
    Object? message = _keep,
    int? framesPerSecond,
    int? viewIndex,
    Object? signal = _keep,
  }) => LiveState(
    status: status ?? this.status,
    frame: frame ?? this.frame,
    message: message == _keep ? this.message : message as Msg?,
    framesPerSecond: framesPerSecond ?? this.framesPerSecond,
    viewIndex: viewIndex ?? this.viewIndex,
    signal: signal == _keep ? this.signal : signal as int?,
  );
}

/// Live pictures per second below which the live view counts as slowed down.
const liveSlowFps = 12;

/// Signal below which the camera's Wi-Fi counts as weak, in dBm.
const liveWeakSignal = -75;

/// Alive only while the live screen is open; leaving the screen closes the stream.
final liveProvider = NotifierProvider.autoDispose<LiveController, LiveState>(
  LiveController.new,
);

class LiveController extends Notifier<LiveState> {
  static const _maxFailures = 3;

  late CameraTransport _transport;
  late CameraApi _api;
  StreamSubscription<Uint8List>? _sub;
  Timer? _timer;
  Timer? _fpsTimer;
  String _url = NovatekCameraApi.defaultLiveViewUrl;
  bool _nudged = false;
  int _failures = 0;
  int _frames = 0;
  int _ticks = 0;
  bool _disposed = false;

  /// The camera link itself is down; the stream reopens when it is back.
  bool _waitingForLink = false;

  /// The link has already been rebuilt once for this run of failures.
  bool _rebuiltLink = false;

  @override
  LiveState build() {
    _transport = ref.watch(transportProvider);
    _api = ref.watch(cameraApiProvider);
    ref.onDispose(() {
      _disposed = true;
      _timer?.cancel();
      _fpsTimer?.cancel();
      _sub?.cancel();
      _transport.keepScreenOn(false).ignore();
    });
    _transport.keepScreenOn(true).ignore();
    ref.listen(sessionProvider.select((s) => s.link), _onLink);
    _fpsTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (_disposed) return;
      if (state.framesPerSecond != _frames) {
        state = state.copyWith(framesPerSecond: _frames);
      }
      _frames = 0;
      if (++_ticks % 3 == 1) _readSignal();
    });
    Future.microtask(_start);
    return const LiveState();
  }

  Future<void> _readSignal() async {
    int? dbm;
    try {
      dbm = await _transport.signalStrength();
    } catch (_) {}
    if (!_disposed && dbm != state.signal) state = state.copyWith(signal: dbm);
  }

  Future<void> _start() async {
    try {
      _url = await _api.liveViewUrl();
    } catch (_) {
      // Fall back to the address measured on the real camera.
    }
    if (_disposed) return;
    _open();
    try {
      final index = await _api.viewIndex();
      if (!_disposed && index != null) state = state.copyWith(viewIndex: index);
    } catch (_) {
      // The view switch is simply not offered.
    }
  }

  void _open() {
    _timer?.cancel();
    _sub?.cancel();
    if (_disposed) return;
    state = state.copyWith(status: LiveStatus.connecting);
    var gotFrame = false;
    _sub = _transport
        .liveFrames(_url)
        .listen(
          (frame) {
            if (_disposed) return;
            if (!gotFrame) {
              gotFrame = true;
              _timer?.cancel();
            }
            _failures = 0;
            _frames++;
            state = state.copyWith(
              status: LiveStatus.playing,
              frame: frame,
              message: null,
            );
          },
          onError: (Object e) =>
              _onEnded((_) => e is TransportException ? e.message : '$e'),
          onDone: () => _onEnded((AppLocalizations l) => l.liveStreamClosed),
        );
    _timer = Timer(ref.read(liveStartTimeoutProvider), _onSilent);
  }

  void _onLink(LinkState? previous, LinkState next) {
    if (_disposed) return;
    if (next == LinkState.connected) {
      if (!_waitingForLink) return;
      _waitingForLink = false;
      _failures = 0;
      _nudged = false;
      _open();
    } else if (previous == LinkState.connected || _waitingForLink) {
      _waitingForLink = true;
      _timer?.cancel();
      _sub?.cancel();
      _sub = null;
      state = state.copyWith(
        status: LiveStatus.connecting,
        message: (AppLocalizations l) => l.liveConnectionLost,
      );
    }
  }

  bool get _linkUp => ref.read(sessionProvider).link == LinkState.connected;

  /// The stream keeps failing. Rebuild the camera link once (what fixed it by hand:
  /// Disconnect, then Connect) before asking the user.
  void _giveUp(Msg message) {
    final session = ref.read(sessionProvider);
    if (!_rebuiltLink && session.saved != null) {
      _rebuiltLink = true;
      _waitingForLink = true;
      _timer?.cancel();
      _sub?.cancel();
      _sub = null;
      state = state.copyWith(
        status: LiveStatus.connecting,
        message: (AppLocalizations l) => l.liveRestarting,
      );
      ref.read(sessionProvider.notifier).reconnect().ignore();
      return;
    }
    _fail(message);
  }

  /// Connected, but no picture arrived.
  Future<void> _onSilent() async {
    if (_disposed) return;
    if (!_nudged) {
      // The vendor app sends this before opening its player; try it once.
      _nudged = true;
      try {
        await _api.startLiveView();
      } catch (_) {}
      _open();
      return;
    }
    _giveUp((AppLocalizations l) => l.liveNoPicture);
  }

  void _onEnded(Msg reason) {
    if (_disposed) return;
    _timer?.cancel();
    _sub?.cancel();
    _sub = null;
    // A dropped link ends the stream too; _onLink reopens it when the link is back.
    if (_waitingForLink || !_linkUp) {
      _onLink(LinkState.connected, ref.read(sessionProvider).link);
      return;
    }
    _failures++;
    if (_failures > _maxFailures) {
      _giveUp((AppLocalizations l) => l.liveStopped(reason(l)));
      return;
    }
    state = state.copyWith(
      status: LiveStatus.connecting,
      message: (AppLocalizations l) => l.liveReconnecting,
    );
    _timer = Timer(ref.read(liveRetryDelayProvider), _open);
  }

  void _fail(Msg message) {
    _timer?.cancel();
    _sub?.cancel();
    _sub = null;
    state = state.copyWith(status: LiveStatus.failed, message: message);
  }

  void retry() {
    _failures = 0;
    _nudged = false;
    _rebuiltLink = false;
    if (!_linkUp) {
      // Reopening the stream cannot work without the link: rebuild the link instead.
      _waitingForLink = true;
      state = state.copyWith(
        status: LiveStatus.connecting,
        message: (AppLocalizations l) => l.liveReconnecting,
      );
      ref.read(sessionProvider.notifier).reconnect().ignore();
      return;
    }
    state = state.copyWith(message: null);
    _open();
  }

  /// Switches which picture the camera sends. Returns an error message, or null.
  Future<String?> setView(int index) async {
    try {
      await _api.setViewIndex(index);
      if (!_disposed) state = state.copyWith(viewIndex: index);
      return null;
    } catch (e) {
      return '$e';
    }
  }
}
