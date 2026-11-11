import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../camera/camera_api.dart';
import '../camera/transport.dart';
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
  });

  final LiveStatus status;

  /// The latest picture (a JPEG). Kept while reconnecting so the screen does not go black.
  final Uint8List? frame;
  final String? message;
  final int framesPerSecond;

  /// Which picture the camera is sending, as the camera's own index. Null if unknown.
  final int? viewIndex;

  static const _keep = Object();

  LiveState copyWith({
    LiveStatus? status,
    Uint8List? frame,
    Object? message = _keep,
    int? framesPerSecond,
    int? viewIndex,
  }) => LiveState(
    status: status ?? this.status,
    frame: frame ?? this.frame,
    message: message == _keep ? this.message : message as String?,
    framesPerSecond: framesPerSecond ?? this.framesPerSecond,
    viewIndex: viewIndex ?? this.viewIndex,
  );
}

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
  bool _disposed = false;

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
    _fpsTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (_disposed) return;
      if (state.framesPerSecond != _frames) {
        state = state.copyWith(framesPerSecond: _frames);
      }
      _frames = 0;
    });
    Future.microtask(_start);
    return const LiveState();
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
              _onEnded(e is TransportException ? e.message : '$e'),
          onDone: () => _onEnded('the camera closed the stream'),
        );
    _timer = Timer(ref.read(liveStartTimeoutProvider), _onSilent);
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
    _fail('The camera is not sending a picture.');
  }

  void _onEnded(String reason) {
    if (_disposed) return;
    _timer?.cancel();
    _sub?.cancel();
    _sub = null;
    _failures++;
    if (_failures > _maxFailures) {
      _fail('Live view stopped: $reason');
      return;
    }
    state = state.copyWith(
      status: LiveStatus.connecting,
      message: 'Reconnecting…',
    );
    _timer = Timer(ref.read(liveRetryDelayProvider), _open);
  }

  void _fail(String message) {
    _timer?.cancel();
    _sub?.cancel();
    _sub = null;
    state = state.copyWith(status: LiveStatus.failed, message: message);
  }

  void retry() {
    _failures = 0;
    _nudged = false;
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
