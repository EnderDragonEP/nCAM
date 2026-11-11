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
