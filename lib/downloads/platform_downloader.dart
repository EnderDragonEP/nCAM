import 'package:flutter/services.dart';

import 'downloader.dart';

/// Talks to the Kotlin side (`DownloadBridge` / `DownloadService`).
class PlatformDownloader implements Downloader {
  static const _methods = MethodChannel('ncam/downloads');
  static const _events = EventChannel('ncam/downloads/jobs');

  late final Stream<List<DownloadJob>> _jobs = _events
      .receiveBroadcastStream()
      .map(_parse)
      .asBroadcastStream();

  static List<DownloadJob> _parse(Object? event) => [
    for (final m in (event as List? ?? const []).cast<Map<Object?, Object?>>())
      DownloadJob(
        id: m['id']! as String,
        name: m['name']! as String,
        url: m['url']! as String,
        total: (m['total'] as num?)?.toInt() ?? 0,
        received: (m['received'] as num?)?.toInt() ?? 0,
        state:
            DownloadState.values.asNameMap()[m['state']] ??
            DownloadState.failed,
        error: m['error'] as String?,
        bytesPerSecond: (m['bytesPerSecond'] as num?)?.toInt() ?? 0,
      ),
  ];

  @override
  Stream<List<DownloadJob>> get jobs async* {
    yield _parse(await _methods.invokeMethod<Object?>('snapshot'));
    yield* _jobs;
  }

  @override
  Future<void> enqueue(List<DownloadRequest> requests) =>
      _methods.invokeMethod<void>('enqueue', {
        'items': [
          for (final r in requests)
            {'name': r.name, 'url': r.url, 'total': r.total},
        ],
      });

  @override
  Future<void> retry(String id) =>
      _methods.invokeMethod<void>('retry', {'id': id});

  @override
  Future<void> cancel([String? id]) =>
      _methods.invokeMethod<void>('cancel', {'id': id});

  @override
  Future<void> clearFinished() => _methods.invokeMethod<void>('clearFinished');

  static const _fastEvents = EventChannel('ncam/downloads/fast');

  late final Stream<FastModeStatus> _fast = _fastEvents
      .receiveBroadcastStream()
      .map(_parseFast)
      .asBroadcastStream();

  static FastModeStatus _parseFast(Object? event) {
    final m = (event as Map?) ?? const {};
    return FastModeStatus(
      enabled: m['enabled'] as bool? ?? false,
      phase: FastPhase.values.asNameMap()[m['phase']] ?? FastPhase.idle,
      message: m['message'] as String?,
    );
  }

  @override
  Stream<FastModeStatus> get fastMode async* {
    yield _parseFast(await _methods.invokeMethod<Object?>('fastSnapshot'));
    yield* _fast;
  }

  @override
  Future<void> setFastMode(bool enabled) =>
      _methods.invokeMethod<void>('setFastMode', {'enabled': enabled});

  @override
  Future<bool> recoverRecording() async {
    try {
      return await _methods.invokeMethod<bool>('recoverRecording') ?? false;
    } on PlatformException catch (e) {
      throw StateError(e.message ?? 'Recording could not be restarted.');
    }
  }

  @override
  Future<Map<String, int>> localFiles() async {
    final map = await _methods.invokeMapMethod<String, Object?>('localFiles');
    return {
      for (final e in (map ?? const <String, Object?>{}).entries)
        e.key: (e.value as num?)?.toInt() ?? 0,
    };
  }
}
