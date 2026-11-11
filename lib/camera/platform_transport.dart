import 'package:flutter/services.dart';

import 'transport.dart';

/// Talks to the Kotlin side (`CameraBridge` / `CameraLink`).
class PlatformCameraTransport implements CameraTransport {
  static const _methods = MethodChannel('ncam/camera');
  static const _events = EventChannel('ncam/camera/state');

  late final Stream<LinkState> _states = _events
      .receiveBroadcastStream()
      .map((e) => _parseState(e as String?))
      .asBroadcastStream();

  static LinkState _parseState(String? s) => switch (s) {
    'connecting' => LinkState.connecting,
    'connected' => LinkState.connected,
    'lost' => LinkState.lost,
    _ => LinkState.disconnected,
  };

  @override
  Stream<LinkState> get linkStates async* {
    yield _parseState(await _methods.invokeMethod<String>('state'));
    yield* _states;
  }

  @override
  Future<void> connect({required String ssid, required String password}) =>
      _guard(
        () => _methods.invokeMethod<void>('connect', {
          'ssid': ssid,
          'password': password,
          'timeoutMs': 60000,
        }),
      );

  @override
  Future<void> disconnect() =>
      _guard(() => _methods.invokeMethod<void>('disconnect'));

  @override
  Future<HttpReply> get(
    String url, {
    Map<String, String> headers = const {},
    Duration timeout = const Duration(seconds: 10),
    int maxBytes = 4 * 1024 * 1024,
  }) async {
    final map = await _guard(
      () => _methods.invokeMapMethod<String, Object?>('get', {
        'url': url,
        'headers': headers,
        'timeoutMs': timeout.inMilliseconds,
        'maxBytes': maxBytes,
      }),
    );
    if (map == null) throw const TransportException('io', 'empty reply');
    return HttpReply(
      map['status']! as int,
      (map['headers']! as Map).cast<String, String>(),
      map['body']! as Uint8List,
    );
  }

  @override
  Future<List<WifiNetworkInfo>> scan() async {
    final list = await _guard(
      () => _methods.invokeListMethod<Map<Object?, Object?>>('scan'),
    );
    return [
      for (final m in list ?? const <Map<Object?, Object?>>[])
        WifiNetworkInfo(m['ssid']! as String, m['level']! as int),
    ];
  }

  static const _live = EventChannel('ncam/camera/live');

  @override
  Stream<Uint8List> liveFrames(String url) => _live
      .receiveBroadcastStream({'url': url})
      .map((e) => e as Uint8List)
      .handleError(
        (Object e) => throw TransportException(
          'stream_ended',
          e is PlatformException ? (e.message ?? '') : '$e',
        ),
      );

  @override
  Future<String?> thumbnail(String fileUrl, {required String cacheKey}) =>
      _guard(
        () => _methods.invokeMethod<String>('thumbnail', {
          'url': fileUrl,
          'key': cacheKey,
        }),
      );

  @override
  Future<void> keepScreenOn(bool on) =>
      _guard(() => _methods.invokeMethod<void>('keepScreenOn', {'on': on}));

  Future<T> _guard<T>(Future<T> Function() call) async {
    try {
      return await call();
    } on PlatformException catch (e) {
      throw TransportException(e.code, e.message ?? '');
    }
  }
}
