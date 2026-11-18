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

/// Reply to command 3014: a flat run of `<Cmd>id</Cmd><Status>value</Status>` pairs giving
/// the current value of every setting.
Map<int, String> parseCurrentValues(String body) {
  final root = _parse(body).rootElement;
  final values = <int, String>{};
  int? cmd;
  for (final e in root.childElements) {
    if (e.name.local == 'Cmd') {
      cmd = int.tryParse(e.innerText.trim());
    } else if (e.name.local == 'Status' && cmd != null) {
      values[cmd] = e.innerText.trim();
      cmd = null;
    }
  }
  return values;
}

/// Reply to command 3031 (`str=all`): the settings the camera supports and their choices.
/// [values] are the current values from command 3014.
List<CameraSetting> parseSettings(String body, Map<int, String> values) {
  final doc = _parse(body);
  final settings = <CameraSetting>[];
  for (final item in doc.findAllElements('Item')) {
    final cmd = int.tryParse(_childText(item, 'Cmd') ?? '');
    if (cmd == null) continue;
    final options = <SettingOption>[];
    for (final o in item.findAllElements('Option')) {
      final index = int.tryParse(_childText(o, 'Index') ?? '');
      if (index == null) continue;
      options.add(SettingOption(index, _childText(o, 'Id') ?? '$index'));
    }
    settings.add(
      CameraSetting(
        cmd: cmd,
        name: _childText(item, 'Name') ?? '$cmd',
        options: options,
        value: int.tryParse(values[cmd] ?? ''),
      ),
    );
  }
  return settings;
}

/// Reply to command 2019. Returns the movie-mode live view URL, or null if absent.
String? parseLiveViewLink(String body) {
  final link = _parse(body)
      .findAllElements('MovieLiveViewLink')
      .firstOrNull
      ?.innerText
      .trim();
  return (link == null || link.isEmpty) ? null : link;
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

final _folderRow = RegExp(
  r'<tr><td><a href="([^"]+)"><b>([^<]+)</b></a><td align=\w+>\s*([^<]*?)\s*'
  r'<td align=\w+>\s*([0-9/: ]+)',
  caseSensitive: false,
);
final _pageSize = RegExp(
  r'^(\d+)(?:\.(\d+))?\s*([KMGT]?B)$',
  caseSensitive: false,
);

/// The page the camera's web server shows for a folder, such as `/Novatek/Movie/`:
///
///     <div id=folder>/Novatek/Movie</div> …
///     <tr><td><a href="/Novatek/Movie/x.TS"><b>x.TS</b></a><td align=right> 231.33 MB
///     <td align=right>2026/11/10 18:45:48
///
/// Sub-folders (`<i>folder</i>` instead of a size) are skipped. Sizes are rounded, so
/// each file carries how far off its size may be. Returns null when [body] is not a
/// folder page (the server answers missing paths with a "Page Not found" page).
List<CameraFile>? parseFolderPage(String body) {
  if (!body.contains('<div id=folder>')) return null;
  final files = <CameraFile>[];
  for (final m in _folderRow.allMatches(body)) {
    final size = _pageSize.firstMatch(m.group(3)!.trim());
    if (size == null) continue;
    final unit = switch (size.group(3)!.toUpperCase()) {
      'KB' => 1024,
      'MB' => 1024 * 1024,
      'GB' => 1024 * 1024 * 1024,
      'TB' => 1024 * 1024 * 1024 * 1024,
      _ => 1,
    };
    final decimals = size.group(2) ?? '';
    final value = double.parse(
      '${size.group(1)}.${decimals.isEmpty ? '0' : decimals}',
    );
    var step = unit.toDouble();
    for (var i = 0; i < decimals.length; i++) {
      step /= 10;
    }
    files.add(
      CameraFile(
        name: m.group(2)!.trim(),
        path: m.group(1)!.replaceAll('&amp;', '&'),
        size: (value * unit).round(),
        // A whole step of the last digit, whether the page rounds or cuts off.
        sizeSlack: step.ceil(),
        writeTime: parseCameraTime(m.group(4)),
      ),
    );
  }
  return files;
}

/// Reply to command 3015: `<LIST><ALLFile><File>…</File></ALLFile>…</LIST>`.
List<CameraFile> parseFileList(String body) {
  final doc = _parse(body);
  final root = doc.rootElement;
  if (root.name.local != 'LIST') {
    // Instead of an empty list the camera can answer like a plain command:
    // <Function><Cmd>3015</Cmd><Status>n</Status></Function>.
    final status = int.tryParse(_childText(root, 'Status') ?? '');
    if (root.name.local == 'Function' && status != null) {
      throw FileListUnavailable('status $status', status: status);
    }
    final start = body.trim().replaceAll(RegExp(r'\s+'), ' ');
    throw FileListUnavailable(
      'unexpected reply: '
      '${start.length > 120 ? '${start.substring(0, 120)}...' : start}',
    );
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
