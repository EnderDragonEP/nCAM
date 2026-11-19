import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'credentials.dart';
import 'session.dart';

/// The Android side of the background clock sync (CameraWatch.kt).
abstract class WatchPlatform {
  /// Starts the service, or gives it new camera details.
  Future<void> start({
    required String ssid,
    required String password,
    required bool newClip,
  });

  Future<void> stop();

  /// Whether Android lets nCAM run in the background without battery limits.
  Future<bool> batteryUnrestricted();

  /// Shows Android's own question about running without battery limits.
  Future<void> askUnrestricted();

  /// Opens Android's settings for the clock sync's notification, where it can be
  /// switched off.
  Future<void> openNotificationSettings();
}

class MethodChannelWatchPlatform implements WatchPlatform {
  static const _channel = MethodChannel('ncam/watch');

  @override
  Future<void> start({
    required String ssid,
    required String password,
    required bool newClip,
  }) => _channel.invokeMethod('start', {
    'ssid': ssid,
    'password': password,
    'newClip': newClip,
  });

  @override
  Future<void> stop() => _channel.invokeMethod('stop');

  @override
  Future<bool> batteryUnrestricted() async =>
      await _channel.invokeMethod<bool>('batteryUnrestricted') ?? false;

  @override
  Future<void> askUnrestricted() => _channel.invokeMethod('askUnrestricted');

  @override
  Future<void> openNotificationSettings() =>
      _channel.invokeMethod('openNotificationSettings');
}

/// Records what the app asks of the service; for tests.
class FakeWatchPlatform implements WatchPlatform {
  final calls = <String>[];
  bool running = false;
  String? ssid;
  bool? newClip;
  bool unrestricted = false;

  @override
  Future<void> start({
    required String ssid,
    required String password,
    required bool newClip,
  }) async {
    calls.add('start');
    running = true;
    this.ssid = ssid;
    this.newClip = newClip;
  }

  @override
  Future<void> stop() async {
    calls.add('stop');
    running = false;
  }

  @override
  Future<bool> batteryUnrestricted() async => unrestricted;

  @override
  Future<void> askUnrestricted() async {
    calls.add('askUnrestricted');
    unrestricted = true;
  }

  @override
  Future<void> openNotificationSettings() async =>
      calls.add('openNotificationSettings');
}

final watchPlatformProvider = Provider<WatchPlatform>(
  (ref) => MethodChannelWatchPlatform(),
);

class WatchSettings {
  const WatchSettings({this.enabled = false, this.newClip = true});

  /// The background clock sync is on.
  final bool enabled;

  /// After setting the clock, cut short a clip the camera started with the wrong time.
  final bool newClip;

  WatchSettings copyWith({bool? enabled, bool? newClip}) => WatchSettings(
    enabled: enabled ?? this.enabled,
    newClip: newClip ?? this.newClip,
  );
}

final cameraWatchProvider =
    NotifierProvider<CameraWatchController, WatchSettings>(
      CameraWatchController.new,
    );

/// The background clock sync's settings, kept between launches. The service runs
/// while it is on and a camera is saved, with the saved camera's details.
class CameraWatchController extends Notifier<WatchSettings> {
  static const _enabledKey = 'camera_watch';
  static const _newClipKey = 'camera_watch_new_clip';
  final _loaded = Completer<void>();

  /// The stored choices, once they have been read.
  Future<void> get ready => _loaded.future;

  @override
  WatchSettings build() {
    // A new password, another camera or Forget: the service follows.
    ref.listen(
      sessionProvider.select((s) => s.saved),
      (_, saved) => _apply(saved),
    );
    Future.microtask(_load);
    return const WatchSettings();
  }

  Future<void> _load() async {
    var value = const WatchSettings();
    try {
      final prefs = await SharedPreferences.getInstance();
      value = WatchSettings(
        enabled: prefs.getBool(_enabledKey) ?? false,
        newClip: prefs.getBool(_newClipKey) ?? true,
      );
    } catch (_) {
      // Storage unavailable: keep the defaults.
    }
    if (!ref.mounted) return;
    state = value;
    if (!_loaded.isCompleted) _loaded.complete();
    // Make sure the service runs with today's details (after an app update, say).
    await _apply(ref.read(sessionProvider).saved);
  }

  Future<void> _apply(CameraCredentials? saved) async {
    if (!_loaded.isCompleted || !ref.mounted) return;
    final platform = ref.read(watchPlatformProvider);
    try {
      if (state.enabled && saved != null) {
        await platform.start(
          ssid: saved.ssid,
          password: saved.password,
          newClip: state.newClip,
        );
      } else {
        await platform.stop();
      }
    } catch (_) {
      // No Android service (tests, other platforms): nothing to run.
    }
  }

  Future<void> _save() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_enabledKey, state.enabled);
      await prefs.setBool(_newClipKey, state.newClip);
    } catch (_) {}
  }

  Future<void> setEnabled(bool on) async {
    await ready;
    state = state.copyWith(enabled: on);
    await _save();
    await _apply(ref.read(sessionProvider).saved);
  }

  Future<void> setNewClip(bool on) async {
    await ready;
    state = state.copyWith(newClip: on);
    await _save();
    await _apply(ref.read(sessionProvider).saved);
  }
}

/// Re-read when the app comes back on screen (the user may have changed it).
final batteryUnrestrictedProvider = FutureProvider.autoDispose<bool>((
  ref,
) async {
  try {
    return await ref.watch(watchPlatformProvider).batteryUnrestricted();
  } catch (_) {
    return false;
  }
});
