import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'transport.dart';

/// In-memory camera for tests and UI work without the real device. Its replies have the
/// exact shape captured from the real camera (docs/camera-protocol.md, section 0).
class FakeCameraTransport implements CameraTransport {
  FakeCameraTransport({
    this.firmware = 'DVR52AFHW3_YL_V3.19_TS',
    this.recordingSeconds = 28,
    this.failConnect = false,
    List<FakeFile>? files,
  }) : files = files ?? sampleFiles();

  String firmware;
  int recordingSeconds;
  bool failConnect;
  List<FakeFile> files;

  /// The camera's own clock, used to stamp files that are being written.
  DateTime Function() cameraClock = DateTime.now;

  /// Status the camera returns for set-date / set-time.
  int setTimeStatus = 0;

  /// Live view: when true, frames only flow after the app sends "start live view" (2015).
  bool liveNeedsStart = false;
  bool liveStarted = false;
  int viewIndex = 2;
  bool screenKeptOn = false;

  /// URLs the app opened as a live stream.
  final List<String> liveOpened = [];
  StreamController<Uint8List>? _live;

  /// Pushes one frame to whoever is watching. Returns false if nobody is, or if the
  /// camera has not been asked to start.
  bool emitFrame([List<int> bytes = const [0xFF, 0xD8, 0xFF, 0xD9]]) {
    final live = _live;
    if (live == null || live.isClosed || !live.hasListener) return false;
    if (liveNeedsStart && !liveStarted) return false;
    live.add(Uint8List.fromList(bytes));
    return true;
  }

  /// Ends the current stream the way a dropped connection does.
  void breakLive(String message) =>
      _live?.addError(TransportException('stream_ended', message));

  @override
  Stream<Uint8List> liveFrames(String url) {
    liveOpened.add(url);
    final c = StreamController<Uint8List>();
    _live = c;
    return c.stream;
  }

  @override
  Future<void> keepScreenOn(bool on) async => screenKeptOn = on;

  @override
  Future<String> diagnosticLog() async => requests.join('\n');

  @override
  Future<void> clearDiagnosticLog() async => requests.clear();

  /// Logs "saved" to Downloads, by file name.
  final List<String> savedLogs = [];

  @override
  Future<String> saveDiagnosticLog() async {
    final name = 'nCam-test-${savedLogs.length + 1}.log';
    savedLogs.add(name);
    return name;
  }

  /// Clip URLs the app asked a preview picture for.
  final List<String> thumbnailRequests = [];

  @override
  Future<String?> thumbnail(String fileUrl, {required String cacheKey}) async {
    if (_state != LinkState.connected) {
      throw const TransportException('io', 'not connected to the camera');
    }
    thumbnailRequests.add(fileUrl);
    return null;
  }

  /// Current values by command id, as command 3014 reports them.
  final Map<int, int> settingValues = {
    2003: 3,
    2007: 1,
    2011: 1,
    3007: 0,
    1002: 0,
    2002: 0,
    2005: 0,
  };

  /// Status the camera returns when a setting is changed.
  int setSettingStatus = 0;

  /// When true, changing a setting stops recording (as some firmware does).
  bool settingStopsRecording = false;

  String? wifiSsid;
  String? wifiPassword;
  bool wifiApplied = false;
  bool formatted = false;
  bool factoryReset = false;

  /// When set, the camera answers the file list request with this status instead of a
  /// list (seen on the real camera).
  int? fileListStatus;

  /// How many times the app asked to join the camera.
  int connectCount = 0;

  /// When true, every request times out while the link still looks connected.
  bool failRequests = false;

  /// Status the camera returns for a delete.
  int deleteStatus = 0;

  /// Every URL requested, in order.
  final List<String> requests = [];

  /// Last date and time strings the app sent.
  String? dateSet;
  String? timeSet;

  LinkState _state = LinkState.disconnected;
  final _states = StreamController<LinkState>.broadcast();

  void _set(LinkState s) {
    _state = s;
    _states.add(s);
  }

  /// Simulates driving out of range and back.
  void dropLink() => _set(LinkState.lost);
  void restoreLink() => _set(LinkState.connected);

  @override
  Stream<LinkState> get linkStates async* {
    yield _state;
    yield* _states.stream;
  }

  @override
  Future<void> connect({required String ssid, required String password}) async {
    connectCount++;
    _set(LinkState.connecting);
    if (holdConnect) {
      // Stays "connecting" until the test calls finishConnect() or disconnects.
      final pending = _pendingConnect = Completer<void>();
      await pending.future;
    }
    if (failConnect) {
      _set(LinkState.disconnected);
      throw const TransportException('connect_failed', 'unavailable');
    }
    _set(LinkState.connected);
  }

  /// When true, connect() waits in the "connecting" state.
  bool holdConnect = false;
  Completer<void>? _pendingConnect;

  void finishConnect() => _pendingConnect?.complete();

  @override
  Future<void> disconnect() async {
    final pending = _pendingConnect;
    _pendingConnect = null;
    _set(LinkState.disconnected);
    if (pending != null && !pending.isCompleted) {
      // Same answer as the real camera link gives a cancelled join.
      pending.completeError(
        const TransportException('connect_failed', 'cancelled'),
      );
    }
  }

  @override
  Future<List<WifiNetworkInfo>> scan() async => const [
    WifiNetworkInfo('NoodleCam', -41),
    WifiNetworkInfo('HomeWifi', -60),
  ];

  @override
  Future<HttpReply> get(
    String url, {
    Map<String, String> headers = const {},
    Duration timeout = const Duration(seconds: 10),
    int maxBytes = 4 * 1024 * 1024,
  }) async {
    if (_state != LinkState.connected) {
      throw const TransportException('io', 'not connected to the camera');
    }
    if (failRequests) {
      // A link Android still calls connected, but nothing gets through.
      throw const TransportException('io', 'SocketTimeoutException');
    }
    requests.add(url);
    final q = Uri.parse(url).queryParameters;
    final cmd = int.tryParse(q['cmd'] ?? '');
    final String body;
    switch (cmd) {
      case 3012:
        body = _function(3012, extra: '<String>$firmware</String>');
      case 3024:
        body = _function(3024, extra: '<Value>33</Value>');
      case 3017:
        body = _function(3017, extra: '<Value>121332695040</Value>');
      case 2016:
        body = _function(2016, extra: '<Value>$recordingSeconds</Value>');
      case 3005:
        dateSet = q['str'];
        body = _function(3005, status: setTimeStatus);
      case 3006:
        timeSet = q['str'];
        body = _function(3006, status: setTimeStatus);
      case 2019:
        body =
            '<?xml version="1.0" encoding="UTF-8" ?>\n<LIST>\n'
            '<MovieLiveViewLink>http://192.168.1.254:8192</MovieLiveViewLink>\n'
            '<PhotoLiveViewLink>http://192.168.1.254:8192</PhotoLiveViewLink>\n</LIST>\n';
      case 2015:
        liveStarted = true;
        body = _function(2015);
      case 3014:
        body =
            '<?xml version="1.0" encoding="UTF-8" ?>\n<Function>\n'
            '${[for (final e in settingValues.entries) '<Cmd>${e.key}</Cmd>\n<Status>${e.value}</Status>\n'].join()}'
            '<Cmd>3028</Cmd>\n<Status>$viewIndex</Status>\n</Function>';
      case 3031:
        body = sampleSettingOptions;
      case 2007 || 3007:
        if (setSettingStatus == 0) {
          settingValues[cmd!] = int.parse(q['par']!);
          if (settingStopsRecording) _setRecording(false);
        }
        body = _function(cmd!, status: setSettingStatus);
      case 2001:
        _setRecording(q['par'] == '1');
        body = _function(2001);
      case 3010:
        formatted = true;
        files.clear();
        body = _function(3010);
      case 3011:
        factoryReset = true;
        body = _function(3011);
      case 3003:
        wifiSsid = q['str'];
        body = _function(3003);
      case 3004:
        wifiPassword = q['str'];
        body = _function(3004);
      case 3021:
        wifiApplied = true;
        body = _function(3021);
      case 3028:
        viewIndex = int.parse(q['par']!);
        body = _function(3028);
      case 4003:
        // str is the camera's own path form: A:\Novatek\Movie\name
        final name = (q['str'] ?? '').split(r'\').last;
        if (deleteStatus == 0) files.removeWhere((f) => f.name == name);
        body = _function(4003, status: deleteStatus);
      case 3015 when fileListStatus != null:
        body = _function(3015, status: fileListStatus!);
      case 3015:
        for (final f in files.where((f) => f.recording)) {
          f.size += 2 * 1024 * 1024;
          f.time = cameraClock();
        }
        body = fileListXml(files);
      default:
        // The real server answers unknown URLs with 200 and this page.
        body =
            '<html>\n<head><title>Page Not found</title></head>\n'
            '<body><h2>The requested URL was not found on this server.</h2></body>\n</html>';
    }
    return HttpReply(200, const {
      'server': 'hfs/1.00.000',
      'connection': 'close',
    }, Uint8List.fromList(utf8.encode(body)));
  }

  static String _function(int cmd, {int status = 0, String extra = ''}) =>
      '<?xml version="1.0" encoding="UTF-8" ?>\n<Function>\n<Cmd>$cmd</Cmd>\n'
      '<Status>$status</Status>\n${extra.isEmpty ? '' : '$extra\n'}</Function>';

  void _setRecording(bool on) {
    recordingSeconds = on ? 3 : 0;
    if (!on) {
      for (final f in files) {
        f.recording = false;
      }
    }
  }

  /// The real camera's reply to command 3031.
  static const sampleSettingOptions = '''<?xml version="1.0" encoding="UTF-8" ?>
<LIST>
<Item>
<Cmd>1002</Cmd>
<Name>PHOTO_SIZE</Name>
<MenuList>
<Option>
<Index>0</Index>
<Id>2MHD</Id>
</Option>
</MenuList>
</Item>
<Item>
<Cmd>2002</Cmd>
<Name>MOVIE_SIZE</Name>
<MenuList>
<Option>
<Index>0</Index>
<Id>1920x1080P30_1920x1080P30</Id>
</Option>
</MenuList>
</Item>
<Item>
<Cmd>2005</Cmd>
<Name>EV</Name>
<MenuList>
<Option>
<Index>0</Index>
<Id>0.0</Id>
</Option>
</MenuList>
</Item>
<Item>
<Cmd>2007</Cmd>
<Name>MOVIE_AUDIO</Name>
<MenuList>
<Option>
<Index>0</Index>
<Id>OFF</Id>
</Option>
<Option>
<Index>1</Index>
<Id>ON</Id>
</Option>
</MenuList>
</Item>
<Item>
<Cmd>3007</Cmd>
<Name>AUTO_POWER_OFF</Name>
<MenuList>
<Option>
<Index>0</Index>
<Id>ON</Id>
</Option>
<Option>
<Index>1</Index>
<Id>3MIN</Id>
</Option>
<Option>
<Index>2</Index>
<Id>5MIN</Id>
</Option>
<Option>
<Index>3</Index>
<Id>10MIN</Id>
</Option>
</MenuList>
</Item>
<CHK>B424</CHK>
</LIST>
''';

  static String _stamp(DateTime t) {
    String two(int n) => n.toString().padLeft(2, '0');
    return '${t.year}/${two(t.month)}/${two(t.day)} '
        '${two(t.hour)}:${two(t.minute)}:${two(t.second)}';
  }

  /// Same layout as a real 3015 reply.
  static String fileListXml(List<FakeFile> files) {
    final b = StringBuffer('<?xml version="1.0" encoding="UTF-8" ?>\n<LIST>\n');
    for (final f in files) {
      b.write(
        '<ALLFile><File>\n<NAME>${f.name}</NAME>\n'
        '<FPATH>A:\\Novatek\\Movie\\${f.name}</FPATH>\n<SIZE>${f.size}</SIZE>\n'
        '<TIMECODE>1567333109</TIMECODE>\n<TIME>${_stamp(f.time)}</TIME>\n'
        '<ATTR>32</ATTR></File>\n</ALLFile>\n',
      );
    }
    b.write('</LIST>\n');
    return b.toString();
  }

  /// Taken from the real camera: the pair being recorded (named with the wrong month, as
  /// found on the device) and two finished pairs.
  static List<FakeFile> sampleFiles() => [
    FakeFile(
      '2026_1011_195621_047A.TS',
      44040192,
      DateTime(2026, 10, 11, 19, 56, 48),
      recording: true,
    ),
    FakeFile(
      '2026_1011_195621_048B.TS',
      44040192,
      DateTime(2026, 10, 11, 19, 56, 48),
      recording: true,
    ),
    FakeFile(
      '2026_1111_191723_043A.TS',
      388700904,
      DateTime(2026, 11, 11, 19, 21, 26),
    ),
    FakeFile(
      '2026_1111_191723_044B.TS',
      388627208,
      DateTime(2026, 11, 11, 19, 21, 26),
    ),
    FakeFile(
      '2026_1111_192257_045A.TS',
      71062872,
      DateTime(2026, 11, 11, 19, 23, 42),
    ),
    FakeFile(
      '2026_1111_192257_046B.TS',
      69704572,
      DateTime(2026, 11, 11, 19, 23, 42),
    ),
  ];
}

class FakeFile {
  FakeFile(this.name, this.size, this.time, {this.recording = false});
  final String name;
  int size;
  DateTime time;

  /// Still being written: grows and is re-stamped on every listing.
  bool recording;
}
