import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../camera/models.dart';
import '../camera/transport.dart';
import 'downloads.dart';
import 'session.dart';

final thumbnailLoaderProvider = Provider<ThumbnailLoader>(
  (ref) => ThumbnailLoader(ref.watch(transportProvider)),
);

/// Loads preview pictures one at a time, most recently requested first, so the clips on
/// screen are served before ones the user has already scrolled past.
class ThumbnailLoader {
  ThumbnailLoader(this._transport);

  final CameraTransport _transport;

  /// Finished lookups by file name. A null value means "this clip has no picture".
  final Map<String, String?> _done = {};
  final List<_Request> _waiting = [];
  bool _running = false;

  /// The cached result for [file], if it has been looked up already.
  String? cached(CameraFile file) => _done[file.name];

  /// Resolves to the path of a JPEG on the phone, or null when there is no picture
  /// (unreadable clip, camera unreachable, or the request was cancelled).
  Future<String?> load(CameraFile file) {
    if (_done.containsKey(file.name)) return Future.value(_done[file.name]);
    final existing = _waiting.where((r) => r.file.name == file.name);
    if (existing.isNotEmpty) return existing.first.completer.future;
    final request = _Request(file);
    _waiting.add(request);
    _pump();
    return request.completer.future;
  }

  /// Drops a request that has not started yet (its row scrolled away).
  void cancel(CameraFile file) {
    _waiting.removeWhere((r) {
      if (r.file.name != file.name) return false;
      r.completer.complete(null);
      return true;
    });
  }

  Future<void> _pump() async {
    if (_running) return;
    _running = true;
    try {
      while (_waiting.isNotEmpty) {
        final request = _waiting.removeLast();
        String? path;
        try {
          path = await _transport.thumbnail(
            downloadRequestFor(request.file).url,
            cacheKey: request.file.name,
          );
          _done[request.file.name] = path;
        } on TransportException {
          // Camera unreachable: not remembered, so it is tried again next time.
        } catch (_) {
          _done[request.file.name] = null;
        }
        request.completer.complete(path);
      }
    } finally {
      _running = false;
    }
  }
}

class _Request {
  _Request(this.file);
  final CameraFile file;
  final completer = Completer<String?>();
}
