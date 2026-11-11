import 'dart:async';

import 'downloader.dart';

/// In-memory queue for tests. Nothing moves until the test calls [finish], [fail] or
/// [progress].
class FakeDownloader implements Downloader {
  final List<DownloadJob> _jobs = [];
  final Map<String, int> local = {};
  final _controller = StreamController<List<DownloadJob>>.broadcast();
  int _nextId = 1;

  List<DownloadJob> get current => List.unmodifiable(_jobs);

  void _emit() => _controller.add(List.unmodifiable(_jobs));

  void _replace(String id, DownloadJob Function(DownloadJob) f) {
    final i = _jobs.indexWhere((j) => j.id == id);
    if (i >= 0) _jobs[i] = f(_jobs[i]);
    _emit();
  }

  static DownloadJob _with(
    DownloadJob j, {
    DownloadState? state,
    int? received,
    String? error,
  }) => DownloadJob(
    id: j.id,
    name: j.name,
    url: j.url,
    total: j.total,
    received: received ?? j.received,
    state: state ?? j.state,
    error: error,
  );

  void progress(String id, int received) => _replace(
    id,
    (j) => _with(j, state: DownloadState.running, received: received),
  );

  void finish(String id) {
    final job = _jobs.firstWhere((j) => j.id == id);
    local[job.name] = job.total;
    _replace(id, (j) => _with(j, state: DownloadState.done, received: j.total));
  }

  void fail(String id, String error) =>
      _replace(id, (j) => _with(j, state: DownloadState.failed, error: error));

  @override
  Stream<List<DownloadJob>> get jobs async* {
    yield List.unmodifiable(_jobs);
    yield* _controller.stream;
  }

  @override
  Future<void> enqueue(List<DownloadRequest> requests) async {
    for (final r in requests) {
      if (_jobs.any((j) => j.name == r.name && j.active)) continue;
      _jobs.removeWhere((j) => j.name == r.name);
      _jobs.add(
        DownloadJob(
          id: '${_nextId++}',
          name: r.name,
          url: r.url,
          total: r.total,
          received: 0,
          state: DownloadState.queued,
        ),
      );
    }
    _emit();
  }

  @override
  Future<void> retry(String id) async =>
      _replace(id, (j) => _with(j, state: DownloadState.queued));

  @override
  Future<void> cancel([String? id]) async {
    for (var i = 0; i < _jobs.length; i++) {
      if ((id == null || _jobs[i].id == id) && _jobs[i].active) {
        _jobs[i] = _with(_jobs[i], state: DownloadState.cancelled);
      }
    }
    _emit();
  }

  @override
  Future<void> clearFinished() async {
    _jobs.removeWhere((j) => !j.active);
    _emit();
  }

  @override
  Future<Map<String, int>> localFiles() async => Map.of(local);

  @override
  Future<String?> localUri(String name) async =>
      local.containsKey(name) ? 'content://media/fake/$name' : null;

  @override
  Future<bool> deleteLocal(String name) async {
    final had = local.remove(name) != null;
    _jobs.removeWhere((j) => j.name == name && !j.active);
    _emit();
    return had;
  }

  FastModeStatus fast = const FastModeStatus();
  final _fastController = StreamController<FastModeStatus>.broadcast();

  /// How many times the app asked to restart recording.
  int recoverCalls = 0;

  /// What [recoverRecording] does: null = nothing was paused.
  bool? recoverResult;

  void setFast(FastModeStatus status) {
    fast = status;
    _fastController.add(status);
  }

  @override
  Stream<FastModeStatus> get fastMode async* {
    yield fast;
    yield* _fastController.stream;
  }

  @override
  Future<void> setFastMode(bool enabled) async => setFast(
    FastModeStatus(enabled: enabled, phase: fast.phase, message: fast.message),
  );

  @override
  Future<bool> recoverRecording() async {
    recoverCalls++;
    final result = recoverResult;
    if (result == null) return false;
    if (!result) throw StateError('Recording is still OFF.');
    setFast(FastModeStatus(enabled: fast.enabled));
    return true;
  }
}
