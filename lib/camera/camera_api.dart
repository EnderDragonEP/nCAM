import 'models.dart';
import 'novatek_parsers.dart';
import 'transport.dart';

/// What the app can ask the camera to do. UI and state code depend on this interface only.
abstract class CameraApi {
  Future<CameraStatus> status();

  /// Elapsed seconds of the current recording; 0 when not recording.
  Future<int> recordingSeconds();

  /// Every file on the card, in the camera's order.
  Future<List<CameraFile>> listFiles();

  /// Sets the camera's date and time. Throws if the camera rejects either part.
  /// The new time shows in the name of the next clip, not the one being recorded.
  Future<void> setTime(DateTime time);

  /// Where the live view is served.
  Future<String> liveViewUrl();

  /// Asks the camera to start sending the live view. Only needed if the stream stays
  /// silent; the vendor app sends it before opening its player.
  Future<void> startLiveView();

  /// Which picture the camera shows (front, rear, both...), as the camera's own index, or
  /// null if the camera does not report one.
  Future<int?> viewIndex();

  Future<void> setViewIndex(int index);

  /// Deletes a file from the camera's card. Cannot be undone.
  Future<void> deleteFile(CameraFile file);

  Future<CameraSettings> readSettings();

  /// Sets [cmd] to the choice with the given [index]. Throws if the camera refuses.
  Future<void> setSetting(int cmd, int index);

  /// Starts or stops recording.
  Future<void> setRecording(bool on);

  /// Erases the SD card. Cannot be undone.
  Future<void> formatCard();

  /// Restores the camera's factory settings.
  Future<void> factoryReset();

  /// Changes the camera's Wi-Fi name and password. The camera restarts its Wi-Fi, so the
  /// current link drops.
  Future<void> setWifi(String ssid, String password);
}

/// Novatek HTTP protocol, as documented in docs/camera-protocol.md.
class NovatekCameraApi implements CameraApi {
  NovatekCameraApi(this._transport, {this.baseUrl = 'http://192.168.1.254'});

  final CameraTransport _transport;
  final String baseUrl;

  static const cmdLiveViewStart = 2015;
  static const cmdRecordingTime = 2016;
  static const cmdLiveViewLinks = 2019;
  static const cmdCurrentValues = 3014;
  static const cmdViewIndex = 3028;
  static const cmdDeleteFile = 4003;
  static const cmdRecord = 2001;
  static const cmdSetSsid = 3003;
  static const cmdSetPassword = 3004;
  static const cmdFormat = 3010;
  static const cmdFactoryReset = 3011;
  static const cmdApplyWifi = 3021;
  static const cmdSettingOptions = 3031;

  /// Used when the camera does not answer 2019. Measured on the real camera.
  static const defaultLiveViewUrl = 'http://192.168.1.254:8192';
  static const cmdSetDate = 3005;
  static const cmdSetTime = 3006;
  static const cmdFirmware = 3012;
  static const cmdFileList = 3015;
  static const cmdFreeSpace = 3017;
  static const cmdCardStatus = 3024;

  String commandUrl(int cmd, {int? par, String? str}) {
    final b = StringBuffer('$baseUrl/?custom=1&cmd=$cmd');
    if (par != null) b.write('&par=$par');
    if (str != null) b.write('&str=${Uri.encodeComponent(str)}');
    return b.toString();
  }

  Future<String> _body(
    int cmd, {
    int? par,
    String? str,
    Duration timeout = const Duration(seconds: 10),
  }) async {
    final reply = await _transport.get(
      commandUrl(cmd, par: par, str: str),
      timeout: timeout,
    );
    // The camera answers 200 even for unknown URLs, so the body decides.
    return reply.text;
  }

  Future<NovatekReply> command(
    int cmd, {
    int? par,
    String? str,
    Duration timeout = const Duration(seconds: 10),
  }) async {
    final reply = parseReply(
      await _body(cmd, par: par, str: str, timeout: timeout),
    );
    if (reply.cmd != cmd) {
      throw CameraProtocolException('asked for $cmd, got ${reply.cmd}');
    }
    return reply;
  }

  Future<NovatekReply> _ok(
    int cmd, {
    int? par,
    String? str,
    Duration timeout = const Duration(seconds: 10),
  }) async {
    final reply = await command(cmd, par: par, str: str, timeout: timeout);
    if (!reply.ok) {
      throw CameraProtocolException(
        'command $cmd failed with status ${reply.status}',
      );
    }
    return reply;
  }

  @override
  Future<CameraStatus> status() async {
    // One at a time: the camera's server handles requests sequentially anyway.
    final firmware = await _ok(cmdFirmware);
    final card = await _ok(cmdCardStatus);
    final free = await _ok(cmdFreeSpace);
    final rec = await _ok(cmdRecordingTime);
    return CameraStatus(
      firmware: firmware.string ?? '',
      cardStatus: card.intValue,
      freeBytes: free.intValue,
      recordingSeconds: rec.intValue,
    );
  }

  @override
  Future<int> recordingSeconds() async =>
      (await _ok(cmdRecordingTime)).intValue;

  @override
  Future<List<CameraFile>> listFiles() async =>
      parseFileList(await _body(cmdFileList));

  @override
  Future<String> liveViewUrl() async {
    try {
      return parseLiveViewLink(await _body(cmdLiveViewLinks)) ??
          defaultLiveViewUrl;
    } on CameraProtocolException {
      return defaultLiveViewUrl;
    }
  }

  @override
  Future<void> startLiveView() => _ok(cmdLiveViewStart, par: 1);

  @override
  Future<int?> viewIndex() async => int.tryParse(
    parseCurrentValues(await _body(cmdCurrentValues))[cmdViewIndex] ?? '',
  );

  @override
  Future<void> setViewIndex(int index) => _ok(cmdViewIndex, par: index);

  @override
  Future<CameraSettings> readSettings() async {
    final values = parseCurrentValues(await _body(cmdCurrentValues));
    final listed = parseSettings(
      await _body(cmdSettingOptions, str: 'all'),
      values,
    );
    final listedIds = {for (final s in listed) s.cmd};
    return CameraSettings(
      listed: listed,
      other: {
        for (final e in values.entries)
          if (!listedIds.contains(e.key)) e.key: e.value,
      },
    );
  }

  @override
  Future<void> setSetting(int cmd, int index) => _ok(cmd, par: index);

  @override
  Future<void> setRecording(bool on) => _ok(cmdRecord, par: on ? 1 : 0);

  @override
  Future<void> formatCard() =>
      _ok(cmdFormat, par: 1, timeout: const Duration(seconds: 90));

  @override
  Future<void> factoryReset() =>
      _ok(cmdFactoryReset, par: 1, timeout: const Duration(seconds: 30));

  @override
  Future<void> setWifi(String ssid, String password) async {
    // Same three commands, in the same order, as the vendor app.
    await _ok(cmdSetSsid, str: ssid);
    await _ok(cmdSetPassword, str: password);
    try {
      await _ok(cmdApplyWifi, timeout: const Duration(seconds: 15));
    } on TransportException {
      // The camera may restart its Wi-Fi before it answers this one.
    }
  }

  @override
  Future<void> deleteFile(CameraFile file) =>
      _ok(cmdDeleteFile, str: urlPathToFpath(file.path));

  @override
  Future<void> setTime(DateTime time) async {
    await _ok(cmdSetDate, str: formatCameraDate(time));
    await _ok(cmdSetTime, str: formatCameraClock(time));
  }
}
