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
}

/// Novatek HTTP protocol, as documented in docs/camera-protocol.md.
class NovatekCameraApi implements CameraApi {
  NovatekCameraApi(this._transport, {this.baseUrl = 'http://192.168.1.254'});

  final CameraTransport _transport;
  final String baseUrl;

  static const cmdRecordingTime = 2016;
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

  Future<String> _body(int cmd, {int? par, String? str}) async {
    final reply = await _transport.get(commandUrl(cmd, par: par, str: str));
    // The camera answers 200 even for unknown URLs, so the body decides.
    return reply.text;
  }

  Future<NovatekReply> command(int cmd, {int? par, String? str}) async {
    final reply = parseReply(await _body(cmd, par: par, str: str));
    if (reply.cmd != cmd) {
      throw CameraProtocolException('asked for $cmd, got ${reply.cmd}');
    }
    return reply;
  }

  Future<NovatekReply> _ok(int cmd, {int? par, String? str}) async {
    final reply = await command(cmd, par: par, str: str);
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
  Future<void> setTime(DateTime time) async {
    await _ok(cmdSetDate, str: formatCameraDate(time));
    await _ok(cmdSetTime, str: formatCameraClock(time));
  }
}
