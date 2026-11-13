import 'dart:convert';
import 'dart:typed_data';

/// State of the app's private Wi-Fi link to the camera.
enum LinkState { disconnected, connecting, connected, lost }

class HttpReply {
  const HttpReply(this.status, this.headers, this.body);

  final int status;

  /// Header names are lower-case.
  final Map<String, String> headers;
  final Uint8List body;

  String get text => utf8.decode(body, allowMalformed: true);
}

class TransportException implements Exception {
  const TransportException(this.code, this.message);

  /// `connect_failed`, `io`, `permission_denied`, ...
  final String code;
  final String message;

  @override
  String toString() => 'TransportException($code): $message';
}

class WifiNetworkInfo {
  const WifiNetworkInfo(this.ssid, this.level);
  final String ssid;

  /// Signal strength in dBm (closer to 0 is stronger).
  final int level;
}

/// The only way the app reaches the camera. The real implementation sends every request
/// over the camera's Wi-Fi network; tests use an in-memory fake.
abstract class CameraTransport {
  /// Emits the current state on listen, then every change.
  Stream<LinkState> get linkStates;

  /// Joins the camera's Wi-Fi. Completes when the link is up; throws
  /// [TransportException] `connect_failed` otherwise.
  Future<void> connect({required String ssid, required String password});

  Future<void> disconnect();

  /// GET over the camera link. [maxBytes] caps how much of the body is read.
  Future<HttpReply> get(
    String url, {
    Map<String, String> headers = const {},
    Duration timeout = const Duration(seconds: 10),
    int maxBytes = 4 * 1024 * 1024,
  });

  /// Nearby Wi-Fi names, strongest first. May ask for a permission.
  Future<List<WifiNetworkInfo>> scan();

  /// The camera's live view at [url] as a stream of JPEG images. The stream starts when
  /// listened to, stops when cancelled, and ends with an error if the camera stops
  /// sending. Frames the listener is too slow for are dropped.
  Stream<Uint8List> liveFrames(String url);

  /// Makes (or finds in the cache) a small preview picture for the clip at [fileUrl] and
  /// returns its path on the phone, or null if the clip yields no picture. Throws
  /// [TransportException] when the camera cannot be reached.
  Future<String?> thumbnail(String fileUrl, {required String cacheKey});

  /// Everything the app has said to the camera recently, and the camera's answers, one
  /// line each with a timestamp.
  Future<String> diagnosticLog();

  Future<void> clearDiagnosticLog();

  /// Saves the log to the phone's Downloads folder and returns the file name.
  Future<String> saveDiagnosticLog();

  /// Keeps the phone's screen from turning off (for the live view).
  Future<void> keepScreenOn(bool on);
}
