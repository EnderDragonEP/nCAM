import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../camera/models.dart';
import '../camera/recordings.dart';
import '../downloads/downloader.dart';
import '../downloads/platform_downloader.dart';
import 'session.dart';

final downloaderProvider = Provider<Downloader>((ref) => PlatformDownloader());

final downloadJobsProvider = StreamProvider<List<DownloadJob>>(
  (ref) => ref.watch(downloaderProvider).jobs,
);

/// Files already in the phone's gallery (name -> size). Re-read whenever a download ends.
final localFilesProvider = FutureProvider<Map<String, int>>((ref) {
  ref.watch(
    downloadJobsProvider.select(
      (jobs) =>
          jobs.value?.where((j) => j.state == DownloadState.done).length ?? 0,
    ),
  );
  return ref.watch(downloaderProvider).localFiles();
});

final fastModeProvider = StreamProvider<FastModeStatus>(
  (ref) => ref.watch(downloaderProvider).fastMode,
);

/// Keeps recording safe around fast download. Watch it once near the root of the app.
///
/// - Every time the camera link comes up, asks the platform side to restart recording if
///   the app had left it paused (app closed or camera out of range mid-download).
/// - When recording has been restarted, re-reads the camera status so the UI shows it.
final recordingGuardProvider = Provider<void>((ref) {
  ref.listen(sessionProvider.select((s) => s.connected && s.status != null), (
    was,
    ready,
  ) async {
    if (!ready || was == true) return;
    try {
      final acted = await ref.read(downloaderProvider).recoverRecording();
      if (acted) await ref.read(sessionProvider.notifier).refreshWhenIdle();
    } catch (_) {
      // The failure is reported through fastModeProvider (phase: failed).
    }
  }, fireImmediately: true);

  ref.listen(fastModeProvider.select((f) => f.value?.phase), (was, now) {
    final changedRecording =
        (was == FastPhase.resuming && now == FastPhase.idle) ||
        (was == FastPhase.pausing && now == FastPhase.paused);
    if (changedRecording) ref.read(sessionProvider.notifier).refreshWhenIdle();
  });
});

/// The camera's files grouped into recordings, newest first.
final recordingsProvider = Provider<List<Recording>>((ref) {
  final files = ref.watch(sessionProvider.select((s) => s.files));
  final writing = ref.watch(sessionProvider.select((s) => s.writing));
  if (files == null) return const [];
  return groupRecordings(files, writing: writing);
});

/// Where one camera file stands from the user's point of view.
enum FileStatus {
  /// Only on the camera.
  onCamera,

  /// The camera is still writing it.
  writing,
  queued,
  running,

  /// A download attempt failed and will be retried automatically.
  waiting,
  failed,

  /// In the phone's gallery.
  saved,
}

class FileView {
  const FileView(this.file, this.status, [this.job]);
  final CameraFile file;
  final FileStatus status;
  final DownloadJob? job;

  /// Can be added to the queue.
  bool get downloadable =>
      status == FileStatus.onCamera || status == FileStatus.failed;
}

/// Combines the camera list, the queue and the gallery into one status per file.
class FileStatusResolver {
  FileStatusResolver({
    required List<DownloadJob> jobs,
    required this.local,
    required this.writing,
  }) : _jobs = {for (final j in jobs) j.name: j};

  final Map<String, DownloadJob> _jobs;
  final Map<String, int> local;
  final Set<String> writing;

  FileView view(CameraFile f) {
    if (writing.contains(f.path)) return FileView(f, FileStatus.writing);
    final job = _jobs[f.name];
    switch (job?.state) {
      case DownloadState.queued:
        return FileView(f, FileStatus.queued, job);
      case DownloadState.running:
        return FileView(f, FileStatus.running, job);
      case DownloadState.waiting:
        return FileView(f, FileStatus.waiting, job);
      case DownloadState.done:
        return FileView(f, FileStatus.saved, job);
      case DownloadState.failed:
        return FileView(f, FileStatus.failed, job);
      case DownloadState.cancelled:
      case null:
        break;
    }
    // Same name and same size: the copy in the gallery is this file.
    if (local[f.name] == f.size) return FileView(f, FileStatus.saved);
    return FileView(f, FileStatus.onCamera);
  }
}

final fileStatusProvider = Provider<FileStatusResolver>((ref) {
  return FileStatusResolver(
    jobs: ref.watch(downloadJobsProvider).value ?? const [],
    local: ref.watch(localFilesProvider).value ?? const {},
    writing: ref.watch(sessionProvider.select((s) => s.writing)),
  );
});

const cameraBaseUrl = 'http://192.168.1.254';

DownloadRequest downloadRequestFor(CameraFile f) => DownloadRequest(
  name: f.name,
  url: '$cameraBaseUrl${Uri.encodeFull(f.path)}',
  total: f.size,
);
