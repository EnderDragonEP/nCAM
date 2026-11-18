import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../camera/camera_api.dart';
import '../camera/models.dart';
import '../l10n/l10n.dart';
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
  Future<Msg?> _restoreRecording(bool wasRecording) async {
    if (!wasRecording) return null;
    await _settle();
    if (await _api.recordingSeconds() > 0) return null;
    try {
      await _api.setRecording(true);
      await _settle();
      if (await _api.recordingSeconds() > 0) {
        return (AppLocalizations l) => l.recordingRestarted;
      }
    } catch (_) {}
    return (AppLocalizations l) => l.recordingNotRestarted;
  }

  /// Changes one setting. Returns a message to show, or null when there is nothing to say.
  Future<Msg?> change(CameraSetting setting, int index) async {
    Msg? message;
    try {
      final wasRecording = await _api.recordingSeconds() > 0;
      try {
        await _api.setSetting(setting.cmd, index);
      } on CameraProtocolException catch (e) {
        message = wasRecording
            ? (AppLocalizations l) => l.changeRefusedRecording(e.message)
            : (AppLocalizations l) => l.changeRefused(e.message);
      }
      final note = await _restoreRecording(wasRecording);
      message ??= note;
    } catch (e) {
      message = (AppLocalizations l) => l.cameraUnreachable('$e');
    }
    await _reload();
    ref.read(sessionProvider.notifier).refreshWhenIdle().ignore();
    return message;
  }

  /// Erases the SD card. Recording is stopped first and restarted afterwards.
  Future<Msg> formatCard() async {
    Msg message;
    try {
      final wasRecording = await _api.recordingSeconds() > 0;
      if (wasRecording) {
        await _api.setRecording(false);
        await _settle();
      }
      Msg? failure;
      try {
        await _api.formatCard();
      } on CameraProtocolException catch (e) {
        failure = (AppLocalizations l) => l.formatRefused(e.message);
      }
      if (wasRecording) {
        // Whatever happened, do not leave the camera stopped.
        await _api.setRecording(true);
        await _settle();
        final recording = await _api.recordingSeconds() > 0;
        final result = failure;
        message = (AppLocalizations l) =>
            '${result == null ? l.formatDone : result(l)} '
            '${recording ? l.recordingRestartedShort : l.recordingDidNotRestart}';
      } else {
        message = failure ?? (AppLocalizations l) => l.formatDone;
      }
    } catch (e) {
      message = (AppLocalizations l) => l.formatFailed('$e');
    }
    ref.read(sessionProvider.notifier).refreshWhenIdle().ignore();
    return message;
  }

  Future<Msg> factoryReset() async {
    try {
      await _api.factoryReset();
      return (AppLocalizations l) => l.resetDone;
    } on CameraProtocolException catch (e) {
      return (AppLocalizations l) => l.resetRefused(e.message);
    } catch (e) {
      // The camera may drop the connection as part of resetting.
      return (AppLocalizations l) => l.resetUnconfirmed('$e');
    }
  }
}

/// Plain-language name for one of the camera's setting ids, or the id itself.
String settingTitle(AppLocalizations l, String name) => switch (name) {
  'PHOTO_SIZE' => l.settingPhotoSize,
  'MOVIE_SIZE' => l.settingVideoResolution,
  'EV' => l.settingExposure,
  'MOVIE_AUDIO' => l.settingRecordAudio,
  'AUTO_POWER_OFF' => l.settingAutoPowerOff,
  'CYCLIC_REC' => l.settingLoopRecording,
  'GSENSOR' => l.settingGSensor,
  'DATE_STAMP' => l.settingDateStamp,
  'WDR' => l.settingWdr,
  'MOTION_DET' => l.settingMotionDetection,
  _ => name,
};

/// Name for a value the camera reports without listing choices, from the vendor app's
/// settings table.
String otherValueTitle(AppLocalizations l, int cmd) => switch (cmd) {
  2003 => l.settingLoopRecording,
  2004 => l.settingWdr,
  2006 => l.settingMotionDetection,
  2008 => l.settingDateStamp,
  2011 => l.settingGSensor,
  2012 => l.settingAutoRecording,
  3008 => l.settingLanguage,
  3009 => l.settingTvMode,
  _ => l.settingNumber(cmd),
};

/// `3MIN` -> `3 min`, `ON` -> `On`; anything else is shown as the camera wrote it.
String prettyOption(AppLocalizations l, String label) {
  final minutes = RegExp(r'^(\d+)MIN$').firstMatch(label);
  if (minutes != null) return l.optionMinutes(int.parse(minutes.group(1)!));
  return switch (label) {
    'ON' => l.optionOn,
    'OFF' => l.optionOff,
    _ => label,
  };
}
