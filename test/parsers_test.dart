import 'package:flutter_test/flutter_test.dart';
import 'package:ncam/camera/fake_transport.dart';
import 'package:ncam/camera/models.dart';
import 'package:ncam/camera/novatek_parsers.dart';

void main() {
  test('parses a command reply captured from the camera', () {
    final r = parseReply(
      '<?xml version="1.0" encoding="UTF-8" ?>\n<Function>\n<Cmd>3012</Cmd>\n'
      '<Status>0</Status>\n<String>DVR52AFHW3_YL_V3.19_TS</String>\n</Function>',
    );
    expect(r.cmd, 3012);
    expect(r.ok, isTrue);
    expect(r.string, 'DVR52AFHW3_YL_V3.19_TS');
  });

  test('keeps a negative status (thumbnail refused while recording)', () {
    final r = parseReply(
      '<?xml version="1.0" encoding="UTF-8" ?>\n<Function>\n<Cmd>4001</Cmd>\n'
      '<Status>-3</Status>\n</Function>',
    );
    expect(r.ok, isFalse);
    expect(r.status, -3);
  });

  test('rejects the "Page Not found" page the camera serves with HTTP 200', () {
    expect(
      () => parseReply(
        '<html>\n<head><title>Page Not found</title></head>\n'
        '<body><h2>The requested URL was not found on this server.</h2></body>\n</html>',
      ),
      throwsA(isA<CameraProtocolException>()),
    );
    expect(
      () => parseReply('garbage'),
      throwsA(isA<CameraProtocolException>()),
    );
  });

  test('parses the file list', () {
    final files = parseFileList(
      FakeCameraTransport.fileListXml(FakeCameraTransport.sampleFiles()),
    );
    expect(files, hasLength(6));

    final f = files.firstWhere((f) => f.name == '2026_1111_192257_045A.TS');
    expect(f.path, '/Novatek/Movie/2026_1111_192257_045A.TS');
    expect(f.size, 71062872);
    expect(f.lens, Lens.front);
    expect(f.sequence, 45);
    expect(f.startTime, DateTime(2026, 11, 11, 19, 22, 57));
    expect(f.writeTime, DateTime(2026, 11, 11, 19, 23, 42));
    expect(f.isVideo, isTrue);

    expect(files.firstWhere((f) => f.name.endsWith('046B.TS')).lens, Lens.rear);
  });

  test('a status reply instead of a file list is reported with its status', () {
    expect(
      () => parseFileList(
        '<?xml version="1.0" encoding="UTF-8" ?>\n<Function>\n<Cmd>3015</Cmd>\n'
        '<Status>-256</Status>\n</Function>',
      ),
      throwsA(
        isA<FileListUnavailable>().having((e) => e.status, 'status', -256),
      ),
    );
    expect(
      () => parseFileList('<html><body>Page Not found</body></html>'),
      throwsA(
        isA<FileListUnavailable>().having(
          (e) => e.message,
          'message',
          contains('Page Not found'),
        ),
      ),
    );
  });

  test('an empty list is just empty', () {
    expect(
      parseFileList(
        '<?xml version="1.0" encoding="UTF-8" ?>\n<LIST>\n</LIST>\n',
      ),
      isEmpty,
    );
  });

  test('a file with an unexpected name still lists', () {
    final f = CameraFile(
      name: 'CardStatus.txt',
      path: '/CardStatus.txt',
      size: 0,
      writeTime: null,
    );
    expect(f.lens, Lens.unknown);
    expect(f.startTime, isNull);
    expect(f.isVideo, isFalse);
  });

  group('folder page', () {
    // Captured from the camera (11 Nov), trimmed.
    const movie =
        '<html>\n<body>\n<div id=folderlabel>folder</div>\n'
        '<div id=folder>/Novatek/Movie</div>\n<div id=body>\n<table cellpadding=5>\n'
        '<th>Filename\n<th>Filesize\n<th>Filetime\n'
        '<tr><td><a href="/Novatek/Movie/2026_1110_184312_001A.TS"><b>2026_1110_184312_001A.TS</b></a><td align=right> 231.33 MB<td align=right>2026/11/10 18:45:48\n'
        '<td align=right><a href="/Novatek/Movie/2026_1110_184312_001A.TS?del=1">Remove</a>\n'
        '<tr><td><a href="/Novatek/Movie/2026_1110_190726_003A.TS"><b>2026_1110_190726_003A.TS</b></a><td align=right> 2.28 MB<td align=right>2026/11/10 19:07:26\n'
        '<td align=right><a href="/Novatek/Movie/2026_1110_190726_003A.TS?del=1">Remove</a>\n'
        '<tr><td colspan="4"><hr size=1 noshade align=top></td></tr></table>\n';
    const root =
        '<html>\n<body>\n<div id=folderlabel>folder</div>\n<div id=folder>/</div>\n'
        '<div id=body>\n<table cellpadding=5>\n<th>Filename\n<th>Filesize\n<th>Filetime\n'
        '<tr><td><a href="/LOG"><b>LOG</b></a><td align=center><i>folder</i><td align=right>2026/11/10 18:43:06\n'
        '<tr><td><a href="/CardStatus.txt"><b>CardStatus.txt</b></a><td align=right> 0 B<td align=right>2026/11/10 18:43:06\n'
        '<td align=right><a href="/CardStatus.txt?del=1">Remove</a>\n'
        '<tr><td><a href="/NOVATEK"><b>NOVATEK</b></a><td align=center><i>folder</i><td align=right>2026/11/10 18:43:12\n'
        '<tr><td colspan="4"><hr size=1 noshade align=top></td></tr></table>\n';

    test('lists the files with rounded sizes', () {
      final files = parseFolderPage(movie)!;
      expect(files, hasLength(2));
      final f = files.first;
      expect(f.name, '2026_1110_184312_001A.TS');
      expect(f.path, '/Novatek/Movie/2026_1110_184312_001A.TS');
      expect(f.writeTime, DateTime(2026, 11, 10, 18, 45, 48));
      expect(f.lens, Lens.front);
      // The file list gave 242562488 bytes for this clip.
      expect(f.sizeMatches(242562488), isTrue);
      expect(f.sizeMatches(242562488 + 20000), isFalse);
      expect(files[1].sizeMatches((2.28 * 1024 * 1024).round()), isTrue);
    });

    test('skips folders', () {
      final files = parseFolderPage(root)!;
      expect(files.map((f) => f.name), ['CardStatus.txt']);
      expect(files.single.size, 0);
    });

    test('a "Page Not found" page is not a folder', () {
      expect(
        parseFolderPage(
          '<html>\n<head><title>Page Not found</title></head>\n<body></body></html>',
        ),
        isNull,
      );
    });

    test('reads the fake camera page like the real one', () {
      final fake = FakeCameraTransport();
      final files = parseFolderPage(
        FakeCameraTransport.folderPageHtml(fake.files),
      )!;
      expect(files, hasLength(fake.files.length));
      for (var i = 0; i < files.length; i++) {
        expect(files[i].sizeMatches(fake.files[i].size), isTrue);
      }
    });
  });

  test('path mapping round-trips', () {
    const fpath = r'A:\Novatek\Movie\2026_1111_192257_045A.TS';
    final path = fpathToUrlPath(fpath);
    expect(path, '/Novatek/Movie/2026_1111_192257_045A.TS');
    expect(urlPathToFpath(path), fpath);
  });

  test('formats date and time the way the camera expects', () {
    final t = DateTime(2026, 3, 5, 7, 8, 9);
    expect(formatCameraDate(t), '2026-03-05');
    expect(formatCameraClock(t), '07:08:09');
  });
}
