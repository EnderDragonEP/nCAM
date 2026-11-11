import 'package:xml/xml.dart';

import 'models.dart';

/// Reply to a `?custom=1&cmd=N` request: `<Function><Cmd/><Status/>[<Value/>][<String/>]`.
class NovatekReply {
  const NovatekReply({
    required this.cmd,
    required this.status,
    this.value,
    this.string,
  });

  final int cmd;

  /// 0 = accepted. Negative values are camera error codes.
  final int status;
  final String? value;
  final String? string;

  bool get ok => status == 0;
  int get intValue => int.tryParse(value ?? '') ?? 0;
}

XmlDocument _parse(String body) {
  try {
    return XmlDocument.parse(body);
  } on XmlException catch (e) {
    throw CameraProtocolException('not XML: ${e.message}');
  }
}

String? _childText(XmlElement e, String name) =>
    e.getElement(name)?.innerText.trim();

NovatekReply parseReply(String body) {
  final root = _parse(body).rootElement;
  final cmd = int.tryParse(_childText(root, 'Cmd') ?? '');
  final status = int.tryParse(_childText(root, 'Status') ?? '');
  if (root.name.local != 'Function' || cmd == null || status == null) {
    throw const CameraProtocolException('reply has no <Cmd>/<Status>');
  }
  return NovatekReply(
    cmd: cmd,
    status: status,
    value: _childText(root, 'Value'),
    string: _childText(root, 'String'),
  );
}

/// `A:\Novatek\Movie\x.TS` -> `/Novatek/Movie/x.TS`
String fpathToUrlPath(String fpath) =>
    fpath.replaceFirst(RegExp(r'^[A-Za-z]:'), '').replaceAll(r'\', '/');

/// `/Novatek/Movie/x.TS` -> `A:\Novatek\Movie\x.TS`
String urlPathToFpath(String path) => 'A:${path.replaceAll('/', r'\')}';

// 2026/11/11 19:23:42
final _timePattern = RegExp(
  r'^(\d{4})/(\d{1,2})/(\d{1,2})\s+(\d{1,2}):(\d{2}):(\d{2})$',
);

DateTime? parseCameraTime(String? s) {
  final m = _timePattern.firstMatch(s?.trim() ?? '');
  if (m == null) return null;
  int g(int i) => int.parse(m.group(i)!);
  return DateTime(g(1), g(2), g(3), g(4), g(5), g(6));
}

/// Reply to command 3015: `<LIST><ALLFile><File>…</File></ALLFile>…</LIST>`.
List<CameraFile> parseFileList(String body) {
  final doc = _parse(body);
  if (doc.rootElement.name.local != 'LIST') {
    throw const CameraProtocolException('file list has no <LIST> root');
  }
  final files = <CameraFile>[];
  for (final f in doc.findAllElements('File')) {
    final name = _childText(f, 'NAME');
    final fpath = _childText(f, 'FPATH');
    if (name == null || fpath == null || name.isEmpty) continue;
    files.add(
      CameraFile(
        name: name,
        path: fpathToUrlPath(fpath),
        size: int.tryParse(_childText(f, 'SIZE') ?? '') ?? 0,
        writeTime: parseCameraTime(_childText(f, 'TIME')),
      ),
    );
  }
  return files;
}

String formatCameraDate(DateTime t) =>
    '${t.year.toString().padLeft(4, '0')}-${_two(t.month)}-${_two(t.day)}';

String formatCameraClock(DateTime t) =>
    '${_two(t.hour)}:${_two(t.minute)}:${_two(t.second)}';

String _two(int n) => n.toString().padLeft(2, '0');
