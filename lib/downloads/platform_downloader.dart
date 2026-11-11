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

  @override
  Future<Map<String, int>> localFiles() async {
    final map = await _methods.invokeMapMethod<String, Object?>('localFiles');
    return {
      for (final e in (map ?? const <String, Object?>{}).entries)
        e.key: (e.value as num?)?.toInt() ?? 0,
    };
  }
}
