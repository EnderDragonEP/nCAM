import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../camera/camera_api.dart';
import '../camera/models.dart';
import '../camera/platform_transport.dart';
import '../camera/transport.dart';
import 'credentials.dart';

final transportProvider = Provider<CameraTransport>(
  (ref) => PlatformCameraTransport(),
);

final cameraApiProvider = Provider<CameraApi>(
  (ref) => NovatekCameraApi(ref.watch(transportProvider)),
);

final credentialStoreProvider = Provider<CredentialStore>(
  (ref) => DeviceCredentialStore(),
);

/// The phone's clock. Overridden in tests.
final clockProvider = Provider<DateTime Function()>((ref) => DateTime.now);

/// How long to wait between attempts while the camera's web server comes up after joining.
final cameraRetryDelayProvider = Provider<Duration>(
  (ref) => const Duration(seconds: 1),
);

/// How long the camera needs to bring its Wi-Fi back up under a new name.
final wifiRestartDelayProvider = Provider<Duration>(
  (ref) => const Duration(seconds: 10),
);

/// Gap between the two file listings used to spot the clip being recorded.
final clockProbeDelayProvider = Provider<Duration>(
  (ref) => const Duration(milliseconds: 1500),
);

/// Result of the last attempt to set the camera's clock.
class TimeSync {
  const TimeSync({required this.at, this.error, this.cameraAheadBy});

  /// Phone time that was sent.
  final DateTime at;
  final String? error;

  /// How far the camera's clock was ahead of the phone's just before the sync (negative =
  /// behind). Only known when the camera was recording, because the clip being written
  /// carries the camera's current time.
  final Duration? cameraAheadBy;

  bool get ok => error == null;
}

class SessionState {
  const SessionState({
    this.loaded = false,
    this.saved,
    this.link = LinkState.disconnected,
    this.busy = false,
    this.error,
    this.status,
    this.files,
    this.writing = const {},
    this.timeSync,
  });

  /// False until saved credentials have been read.
  final bool loaded;
  final CameraCredentials? saved;
  final LinkState link;

  /// A connect or a camera query is in progress.
  final bool busy;
  final String? error;
  final CameraStatus? status;
  final List<CameraFile>? files;

  /// Paths of the clips the camera is writing right now. They are still growing, so they
  /// are not offered for download.
  final Set<String> writing;
  final TimeSync? timeSync;

  bool get connected => link == LinkState.connected;

  static const _keep = Object();

  SessionState copyWith({
    bool? loaded,
    Object? saved = _keep,
    LinkState? link,
    bool? busy,
    Object? error = _keep,
    Object? status = _keep,
    Object? files = _keep,
    Set<String>? writing,
    Object? timeSync = _keep,
  }) => SessionState(
    loaded: loaded ?? this.loaded,
    saved: saved == _keep ? this.saved : saved as CameraCredentials?,
    link: link ?? this.link,
    busy: busy ?? this.busy,
    error: error == _keep ? this.error : error as String?,
    status: status == _keep ? this.status : status as CameraStatus?,
    files: files == _keep ? this.files : files as List<CameraFile>?,
    writing: writing ?? this.writing,
    timeSync: timeSync == _keep ? this.timeSync : timeSync as TimeSync?,
  );
}

final sessionProvider = NotifierProvider<SessionController, SessionState>(
  SessionController.new,
);

/// Connects to the camera and keeps its status. Every time the link comes up - first
/// connect or an automatic rejoin - it reads the status and sets the camera's clock.
class SessionController extends Notifier<SessionState> {
  late CameraTransport _transport;
  late CameraApi _api;
  int _generation = 0;

  @override
  SessionState build() {
    _transport = ref.watch(transportProvider);
    _api = ref.watch(cameraApiProvider);
    final sub = _transport.linkStates.listen(_onLink);
    ref.onDispose(sub.cancel);
    Future.microtask(_loadSaved);
    return const SessionState();
  }

  Future<void> _loadSaved() async {
    final saved = await ref.read(credentialStoreProvider).load();
    if (!ref.mounted) return;
    state = state.copyWith(loaded: true, saved: saved);
    if (saved != null && state.link == LinkState.disconnected) {
      await connect(saved.ssid, saved.password);
    }
  }

  void _onLink(LinkState link) {
    final was = state.link;
    state = state.copyWith(link: link);
    if (link == LinkState.connected && was != LinkState.connected) {
      unawaited(_onConnected());
    } else if (link != LinkState.connected) {
      _generation++;
      state = state.copyWith(busy: link == LinkState.connecting);
    }
  }

  /// Joins the camera's Wi-Fi and remembers the credentials once it works.
  Future<void> connect(String ssid, String password) async {
    state = state.copyWith(busy: true, error: null);
    try {
      await _transport.connect(ssid: ssid, password: password);
      final creds = CameraCredentials(ssid, password);
      await ref.read(credentialStoreProvider).save(creds);
      if (ref.mounted) state = state.copyWith(saved: creds);
    } on TransportException catch (e) {
      if (!ref.mounted) return;
      state = state.copyWith(
        busy: false,
        error: e.message == 'unavailable'
            ? 'Could not join "$ssid". Check that the camera is on and in range, '
                  'that the password is right, and that you accepted the system prompt.'
            : 'Could not join "$ssid": ${e.message}',
      );
    }
  }

  Future<void> disconnect() async {
    _generation++;
    await _transport.disconnect();
    if (ref.mounted) {
      state = state.copyWith(
        busy: false,
        status: null,
        files: null,
        writing: const {},
      );
    }
  }

  /// Disconnects and forgets the saved camera.
  Future<void> forget() async {
    await disconnect();
    await ref.read(credentialStoreProvider).clear();
    if (ref.mounted) state = state.copyWith(saved: null, timeSync: null);
  }

  Future<void> _onConnected() async {
    final gen = ++_generation;
    bool stale() => !ref.mounted || gen != _generation;
    state = state.copyWith(busy: true, error: null);
    try {
      // The Wi-Fi link is reported up slightly before the camera's web server answers.
      final delay = ref.read(cameraRetryDelayProvider);
      CameraStatus? status;
      Object? lastError;
      for (var attempt = 0; attempt < 6 && status == null; attempt++) {
        try {
          status = await _api.status();
        } catch (e) {
          lastError = e;
          await Future<void>.delayed(delay);
          if (stale()) return;
        }
      }
      if (stale()) return;
      if (status == null) {
        state = state.copyWith(
          busy: false,
          error: 'Joined the Wi-Fi but the camera did not answer: $lastError',
        );
        return;
      }
      final files = await _api.listFiles();
      if (stale()) return;
      state = state.copyWith(status: status, files: files);
      await _sync(status: status, before: files, stale: stale);
    } catch (e) {
      if (stale()) return;
      state = state.copyWith(error: 'Camera error: $e');
    } finally {
      if (!stale()) state = state.copyWith(busy: false);
    }
  }

  /// Re-reads status and the file list.
  Future<void> refresh() async {
    if (!state.connected || state.busy) return;
    final gen = _generation;
    state = state.copyWith(busy: true, error: null);
    try {
      final status = await _api.status();
      final files = await _api.listFiles();
      if (!ref.mounted || gen != _generation) return;
      state = state.copyWith(status: status, files: files);
      await _probeWriting(
        status: status,
        before: files,
        stale: () => !ref.mounted || gen != _generation,
      );
    } catch (e) {
      if (!ref.mounted || gen != _generation) return;
      state = state.copyWith(error: 'Camera error: $e');
    } finally {
      if (ref.mounted && gen == _generation) {
        state = state.copyWith(busy: false);
      }
    }
  }

  /// Like [refresh], but waits for a query already in progress to finish first.
  Future<void> refreshWhenIdle() async {
    for (var i = 0; i < 100 && ref.mounted && state.busy; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 150));
    }
    if (ref.mounted) await refresh();
  }

  /// Deletes [files] from the camera, one after another, skipping clips that are still
  /// being written. Returns how many were deleted and the first error, if any.
  Future<({int deleted, String? error})> deleteFiles(
    List<CameraFile> files,
  ) async {
    var deleted = 0;
    String? error;
    for (final f in files) {
      if (state.writing.contains(f.path)) continue;
      try {
        await _api.deleteFile(f);
        deleted++;
        if (!ref.mounted) break;
        state = state.copyWith(
          files: [
            for (final x in state.files ?? const <CameraFile>[])
              if (x.path != f.path) x,
          ],
        );
      } catch (e) {
        error = '$e';
        break;
      }
    }
    if (ref.mounted) await refreshWhenIdle();
    return (deleted: deleted, error: error);
  }

  /// Gives the camera's Wi-Fi a new name and password, then rejoins it under them.
  /// Returns an error message, or null when the app is connected again.
  Future<String?> changeWifi(String ssid, String password) async {
    try {
      await _api.setWifi(ssid, password);
    } catch (e) {
      return 'The camera did not accept the new Wi-Fi settings: $e';
    }
    // Saved before reconnecting: from here on the old credentials are useless.
    final creds = CameraCredentials(ssid, password);
    await ref.read(credentialStoreProvider).save(creds);
    if (!ref.mounted) return null;
    state = state.copyWith(saved: creds);
    await disconnect();
    await Future<void>.delayed(ref.read(wifiRestartDelayProvider));
    if (!ref.mounted) return null;
    await connect(ssid, password);
    return ref.mounted ? state.error : null;
  }

  /// Manual "Sync time".
  Future<void> syncTime() async {
    if (!state.connected || state.busy) return;
    final gen = _generation;
    bool stale() => !ref.mounted || gen != _generation;
    state = state.copyWith(busy: true, error: null);
    try {
      final status = await _api.status();
      final files = await _api.listFiles();
      if (stale()) return;
      state = state.copyWith(status: status, files: files);
      await _sync(status: status, before: files, stale: stale);
    } catch (e) {
      if (stale()) return;
      state = state.copyWith(
        timeSync: TimeSync(at: ref.read(clockProvider)(), error: '$e'),
      );
    } finally {
      if (!stale()) state = state.copyWith(busy: false);
    }
  }

  Future<void> _sync({
    required CameraStatus status,
    required List<CameraFile> before,
    required bool Function() stale,
  }) async {
    Duration? ahead;
    try {
      final after = await _probeWriting(
        status: status,
        before: before,
        stale: stale,
      );
      if (stale()) return;
      if (after != null) {
        ahead = estimateCameraAhead(before, after, ref.read(clockProvider)());
      }
    } catch (_) {
      // The estimate is a nicety; the sync itself still goes ahead.
    }
    final now = ref.read(clockProvider)();
    try {
      await _api.setTime(now);
      if (stale()) return;
      state = state.copyWith(
        timeSync: TimeSync(at: now, cameraAheadBy: ahead),
      );
    } catch (e) {
      if (stale()) return;
      state = state.copyWith(
        timeSync: TimeSync(at: now, error: '$e', cameraAheadBy: ahead),
      );
    }
  }

  /// Lists the files a second time to find the clips that are still growing. Returns the
  /// second listing, or null when the camera is not recording.
  Future<List<CameraFile>?> _probeWriting({
    required CameraStatus status,
    required List<CameraFile> before,
    required bool Function() stale,
  }) async {
    if (!status.isRecording) {
      state = state.copyWith(writing: const {});
      return null;
    }
    await Future<void>.delayed(ref.read(clockProbeDelayProvider));
    if (stale()) return null;
    final after = await _api.listFiles();
    if (stale()) return null;
    state = state.copyWith(
      files: after,
      writing: {for (final f in filesBeingWritten(before, after)) f.path},
    );
    return after;
  }
}

/// Files that changed between two listings, or appeared in the second one: the clips being
/// recorded.
List<CameraFile> filesBeingWritten(
  List<CameraFile> before,
  List<CameraFile> after,
) {
  final old = {for (final f in before) f.path: f};
  return [
    for (final f in after)
      if (switch (old[f.path]) {
        null => true,
        final o => o.size != f.size || o.writeTime != f.writeTime,
      })
        f,
  ];
}

/// The camera cannot be asked for its clock. While it records, though, the clip being
/// written is stamped with the camera's current time every second or two. So the write
/// time of that clip, in a listing taken at [phoneNow], is the camera's clock to within a
/// few seconds. Returns null when no clip is being written.
Duration? estimateCameraAhead(
  List<CameraFile> before,
  List<CameraFile> after,
  DateTime phoneNow,
) {
  DateTime? newest;
  for (final f in filesBeingWritten(before, after)) {
    final t = f.writeTime;
    if (t != null && (newest == null || t.isAfter(newest))) newest = t;
  }
  if (newest == null) return null;
  final ahead = newest.difference(phoneNow);
  // Below this the estimate is just the stamping interval, not a real offset.
  return ahead.abs() < const Duration(seconds: 5) ? Duration.zero : ahead;
}
