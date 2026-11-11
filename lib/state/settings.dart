import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../camera/camera_api.dart';
import '../camera/models.dart';
import 'session.dart';

/// Pause after a command that changes what the camera is doing, before checking on it.
final cameraSettleDelayProvider = Provider<Duration>(
  (ref) => const Duration(milliseconds: 1500),
);

final settingsProvider =
    AsyncNotifierProvider.autoDispose<SettingsController, CameraSettings>(
      SettingsController.new,
    );

/// Reads and changes camera settings.
///
/// The vendor app only allows settings while the camera is not recording. This app tries
/// the change as it is, and makes sure the camera is recording again afterwards if it was
/// recording before.
class SettingsController extends AsyncNotifier<CameraSettings> {
  CameraApi get _api => ref.read(cameraApiProvider);

  @override
  Future<CameraSettings> build() => ref.watch(cameraApiProvider).readSettings();

  Future<void> _settle() =>
      Future<void>.delayed(ref.read(cameraSettleDelayProvider));

  Future<void> _reload() async {
    try {
      final fresh = await _api.readSettings();
      if (ref.mounted) state = AsyncData(fresh);
    } catch (_) {
      // Keep showing the last known values.
    }
  }

  /// Starts recording again if it stopped. Returns a sentence for the user, or null if
  /// recording was not affected.
  Future<String?> _restoreRecording(bool wasRecording) async {
    if (!wasRecording) return null;
    await _settle();
    if (await _api.recordingSeconds() > 0) return null;
    try {
      await _api.setRecording(true);
      await _settle();
      if (await _api.recordingSeconds() > 0) {
        return 'The camera stopped recording for this; recording was restarted.';
      }
    } catch (_) {}
    return 'The camera stopped recording and did NOT restart. '
        'Press the record button on the camera.';
  }

  /// Changes one setting. Returns a message to show, or null when there is nothing to say.
  Future<String?> change(CameraSetting setting, int index) async {
    String? message;
    try {
      final wasRecording = await _api.recordingSeconds() > 0;
      try {
        await _api.setSetting(setting.cmd, index);
      } on CameraProtocolException catch (e) {
        message = wasRecording
            ? 'The camera refused the change (${e.message}). '
                  'It may only accept it while not recording.'
            : 'The camera refused the change (${e.message}).';
      }
      final note = await _restoreRecording(wasRecording);
      message ??= note;
    } catch (e) {
      message = 'Could not reach the camera: $e';
    }
    await _reload();
    ref.read(sessionProvider.notifier).refreshWhenIdle().ignore();
    return message;
  }

  /// Erases the SD card. Recording is stopped first and restarted afterwards.
  Future<String> formatCard() async {
    String message;
    try {
      final wasRecording = await _api.recordingSeconds() > 0;
      if (wasRecording) {
        await _api.setRecording(false);
        await _settle();
      }
      String? failure;
      try {
        await _api.formatCard();
      } on CameraProtocolException catch (e) {
        failure = 'The camera refused to format the card (${e.message}).';
      }
      if (wasRecording) {
        // Whatever happened, do not leave the camera stopped.
        await _api.setRecording(true);
        await _settle();
        final recording = await _api.recordingSeconds() > 0;
        message =
            '${failure ?? 'The card was formatted.'} '
            '${recording ? 'Recording was restarted.' : 'Recording did NOT restart: press the record button on the camera.'}';
      } else {
        message = failure ?? 'The card was formatted.';
      }
    } catch (e) {
      message =
          'Something went wrong while formatting: $e. '
          'Check that the camera is recording.';
    }
    ref.read(sessionProvider.notifier).refreshWhenIdle().ignore();
    return message;
  }

  Future<String> factoryReset() async {
    try {
      await _api.factoryReset();
      return 'Factory settings restored. If the Wi-Fi name or password of the camera '
          'went back to the defaults, enter them on the home screen.';
    } on CameraProtocolException catch (e) {
      return 'The camera refused the reset (${e.message}).';
    } catch (e) {
      // The camera may drop the connection as part of resetting.
      return 'The reset was sent, but the camera did not confirm it: $e';
    }
  }
}

/// Plain-language names for the camera's setting ids.
const settingTitles = <String, String>{
  'PHOTO_SIZE': 'Photo size',
  'MOVIE_SIZE': 'Video resolution',
  'EV': 'Exposure',
  'MOVIE_AUDIO': 'Record audio',
  'AUTO_POWER_OFF': 'Auto power off',
  'CYCLIC_REC': 'Loop recording',
  'GSENSOR': 'G-sensor',
  'DATE_STAMP': 'Date stamp',
  'WDR': 'WDR',
  'MOTION_DET': 'Motion detection',
};

/// Names for values the camera reports without listing choices, from the vendor app's
/// settings table.
const otherValueTitles = <int, String>{
  2003: 'Loop recording',
  2004: 'WDR',
  2006: 'Motion detection',
  2008: 'Date stamp',
  2011: 'G-sensor',
  2012: 'Auto recording',
  3008: 'Language',
  3009: 'TV mode',
};

/// `3MIN` -> `3 min`, `ON` -> `On`; anything else is shown as the camera wrote it.
String prettyOption(String label) {
  final minutes = RegExp(r'^(\d+)MIN$').firstMatch(label);
  if (minutes != null) return '${minutes.group(1)} min';
  return switch (label) {
    'ON' => 'On',
    'OFF' => 'Off',
    _ => label,
  };
}
