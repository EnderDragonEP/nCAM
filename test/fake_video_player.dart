import 'dart:async';

import 'package:flutter/material.dart';
import 'package:video_player_platform_interface/video_player_platform_interface.dart';

/// One clip opened through [FakeVideoPlayer]. Its position only moves when the app
/// seeks or a test sets it, so tests decide exactly where each clip is.
class FakeVideo {
  FakeVideo(this.uri, this.duration);
  final String uri;
  final Duration duration;
  Duration position = Duration.zero;
  bool playing = false;
  bool disposed = false;
  double volume = 1;
  final seeks = <Duration>[];
}

/// Stands in for the platform video player in widget tests.
class FakeVideoPlayer extends VideoPlayerPlatform {
  final videos = <int, FakeVideo>{};
  Duration duration = const Duration(minutes: 1);
  int _next = 1;

  /// The open (not disposed) clip whose address ends with [name].
  FakeVideo open(String name) =>
      videos.values.lastWhere((v) => !v.disposed && v.uri.endsWith(name));

  Iterable<FakeVideo> get live => videos.values.where((v) => !v.disposed);

  int _add(DataSource source) {
    final id = _next++;
    videos[id] = FakeVideo(source.uri ?? source.asset ?? '', duration);
    return id;
  }

  @override
  Future<void> init() async {}

  @override
  Future<int?> create(DataSource dataSource) async => _add(dataSource);

  @override
  Future<int?> createWithOptions(VideoCreationOptions options) async =>
      _add(options.dataSource);

  @override
  Stream<VideoEvent> videoEventsFor(int playerId) {
    // Left open, as a real player's events are: cancelling a finished stream waits
    // for real time, which widget tests never let pass.
    late final StreamController<VideoEvent> events;
    events = StreamController<VideoEvent>(
      onListen: () => events.add(
        VideoEvent(
          eventType: VideoEventType.initialized,
          duration: videos[playerId]!.duration,
          size: const Size(1920, 1080),
        ),
      ),
    );
    return events.stream;
  }

  @override
  Future<void> dispose(int playerId) async => videos[playerId]!.disposed = true;

  @override
  Future<void> setLooping(int playerId, bool looping) async {}

  @override
  Future<void> play(int playerId) async => videos[playerId]!.playing = true;

  @override
  Future<void> pause(int playerId) async => videos[playerId]!.playing = false;

  @override
  Future<void> setVolume(int playerId, double volume) async =>
      videos[playerId]!.volume = volume;

  @override
  Future<void> seekTo(int playerId, Duration position) async {
    videos[playerId]!
      ..position = position
      ..seeks.add(position);
  }

  @override
  Future<void> setPlaybackSpeed(int playerId, double speed) async {}

  @override
  Future<Duration> getPosition(int playerId) async =>
      videos[playerId]!.position;

  @override
  Widget buildView(int playerId) => const ColoredBox(color: Colors.grey);

  @override
  Widget buildViewWithOptions(VideoViewOptions options) =>
      const ColoredBox(color: Colors.grey);

  @override
  Future<void> setMixWithOthers(bool mixWithOthers) async {}

  @override
  Future<void> setAllowBackgroundPlayback(bool allowBackgroundPlayback) async {}
}
