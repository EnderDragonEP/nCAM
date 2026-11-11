enum DownloadState { queued, running, waiting, done, failed, cancelled }

class DownloadJob {
  const DownloadJob({
    required this.id,
    required this.name,
    required this.url,
    required this.total,
    required this.received,
    required this.state,
    this.error,
    this.bytesPerSecond = 0,
  });

  final String id;

  /// File name on the camera and in the gallery.
  final String name;
  final String url;
  final int total;
  final int received;
  final DownloadState state;

  /// Last error. Set while [DownloadState.waiting] (about to retry) and when failed.
  final String? error;
  final int bytesPerSecond;

  bool get active =>
      state == DownloadState.queued ||
      state == DownloadState.running ||
      state == DownloadState.waiting;

  double? get fraction => total > 0 ? (received / total).clamp(0.0, 1.0) : null;
}

class DownloadRequest {
  const DownloadRequest({
    required this.name,
    required this.url,
    required this.total,
  });
  final String name;
  final String url;
  final int total;
}

/// The download queue. Files are fetched one at a time, resumed after interruptions, and
/// saved to the phone's gallery. The real implementation is an Android foreground service.
abstract class Downloader {
  /// Emits the whole queue on listen and on every change.
  Stream<List<DownloadJob>> get jobs;

  /// Adds files to the queue. Files already queued or running are skipped.
  Future<void> enqueue(List<DownloadRequest> requests);

  /// Re-queues a failed or cancelled job; it resumes from the bytes already on the phone.
  Future<void> retry(String id);

  /// Cancels one job, or every active job when [id] is null.
  Future<void> cancel([String? id]);

  /// Removes finished, failed and cancelled entries from the queue.
  Future<void> clearFinished();

  /// Files already saved to the gallery by this app: name -> size in bytes.
  Future<Map<String, int>> localFiles();
}
