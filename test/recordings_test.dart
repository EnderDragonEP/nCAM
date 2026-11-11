import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ncam/camera/fake_transport.dart';
import 'package:ncam/camera/models.dart';
import 'package:ncam/camera/recordings.dart';
import 'package:ncam/downloads/downloader.dart';
import 'package:ncam/downloads/fake_downloader.dart';
import 'package:ncam/state/credentials.dart';
import 'package:ncam/state/downloads.dart';
import 'package:ncam/state/session.dart';
import 'package:ncam/ui/recordings_screen.dart';

CameraFile file(String name, int size, DateTime written) => CameraFile(
  name: name,
  path: '/Novatek/Movie/$name',
  size: size,
  writeTime: written,
);

void main() {
  group('groupRecordings', () {
    test('pairs front and rear clips and sorts newest first', () {
      final files = [
        file(
          '2026_1111_191723_043A.TS',
          10,
          DateTime(2026, 11, 11, 19, 21, 26),
        ),
        file(
          '2026_1111_191723_044B.TS',
          11,
          DateTime(2026, 11, 11, 19, 21, 26),
        ),
        file(
          '2026_1111_192257_045A.TS',
          20,
          DateTime(2026, 11, 11, 19, 23, 42),
        ),
        file(
          '2026_1111_192257_046B.TS',
          21,
          DateTime(2026, 11, 11, 19, 23, 42),
        ),
      ];
      final r = groupRecordings(files);
      expect(r, hasLength(2));
      expect(r[0].front!.name, '2026_1111_192257_045A.TS');
      expect(r[0].rear!.name, '2026_1111_192257_046B.TS');
      expect(r[0].size, 41);
      expect(r[0].length, const Duration(seconds: 45));
      expect(r[1].front!.sequence, 43);
    });

    test(
      'pairs clips whose names differ by one second (seen on the camera)',
      () {
        final r = groupRecordings([
          file(
            '2026_1111_190808_035A.TS',
            1,
            DateTime(2026, 11, 11, 19, 8, 34),
          ),
          file(
            '2026_1111_190809_036B.TS',
            1,
            DateTime(2026, 11, 11, 19, 8, 34),
          ),
        ]);
        expect(r, hasLength(1));
        expect(r.single.front, isNotNull);
        expect(r.single.rear, isNotNull);
      },
    );

    test('a clip without its partner stands alone', () {
      final r = groupRecordings([
        file('2026_1111_190808_035A.TS', 1, DateTime(2026, 11, 11, 19, 8, 34)),
        file('2026_1111_191107_040B.TS', 1, DateTime(2026, 11, 11, 19, 12, 6)),
        file('CardStatus.txt', 0, DateTime(2026, 11, 10, 18, 43, 6)),
      ]);
      expect(r, hasLength(3));
      expect(r.where((x) => x.front != null && x.rear != null), isEmpty);
      expect(r.where((x) => x.other != null), hasLength(1));
    });

    test('a clip started with a wrong clock is dated by its write time', () {
      // Named one month early; the camera clock was corrected while it recorded.
      final r = groupRecordings(
        [
          file(
            '2026_1011_195621_047A.TS',
            1,
            DateTime(2026, 11, 11, 20, 5, 40),
          ),
          file(
            '2026_1011_195621_048B.TS',
            1,
            DateTime(2026, 11, 11, 20, 5, 38),
          ),
          file(
            '2026_1111_192257_045A.TS',
            1,
            DateTime(2026, 11, 11, 19, 23, 42),
          ),
        ],
        writing: {'/Novatek/Movie/2026_1011_195621_047A.TS'},
      );
      expect(r.first.front!.sequence, 47);
      expect(r.first.nameDateSuspect, isTrue);
      expect(r.first.time, DateTime(2026, 11, 11, 20, 5, 40));
      expect(r.first.length, isNull);
      expect(r.first.beingWritten, isTrue);
      expect(r.last.nameDateSuspect, isFalse);
    });
  });

  group('FileStatusResolver', () {
    final f = file('a_045A.TS', 100, DateTime(2026));
    DownloadJob job(DownloadState s) => DownloadJob(
      id: '1',
      name: f.name,
      url: 'u',
      total: 100,
      received: 40,
      state: s,
    );

    FileStatus status({
      List<DownloadJob> jobs = const [],
      Map<String, int> local = const {},
      Set<String> writing = const {},
    }) => FileStatusResolver(
      jobs: jobs,
      local: local,
      writing: writing,
    ).view(f).status;

    test('follows the queue, the gallery and the camera', () {
      expect(status(), FileStatus.onCamera);
      expect(status(jobs: [job(DownloadState.running)]), FileStatus.running);
      expect(status(jobs: [job(DownloadState.failed)]), FileStatus.failed);
      expect(status(jobs: [job(DownloadState.cancelled)]), FileStatus.onCamera);
      expect(status(local: {f.name: 100}), FileStatus.saved);
      expect(status(writing: {f.path}), FileStatus.writing);
    });

    test('a gallery file of a different size is not the same clip', () {
      expect(status(local: {f.name: 99}), FileStatus.onCamera);
    });
  });

  test('download URL points at the file on the camera', () {
    final r = downloadRequestFor(
      file('2026_1111_192257_045A.TS', 71062872, DateTime(2026)),
    );
    expect(
      r.url,
      'http://192.168.1.254/Novatek/Movie/2026_1111_192257_045A.TS',
    );
    expect(r.total, 71062872);
  });

  group('RecordingsScreen', () {
    late FakeCameraTransport camera;
    late FakeDownloader downloader;

    Future<void> open(WidgetTester tester) async {
      camera = FakeCameraTransport()
        ..cameraClock = () => DateTime(2026, 11, 11, 19, 57, 54);
      downloader = FakeDownloader();
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            transportProvider.overrideWithValue(camera),
            downloaderProvider.overrideWithValue(downloader),
            credentialStoreProvider.overrideWithValue(
              MemoryCredentialStore(const CameraCredentials('NoodleCam', 'x')),
            ),
            cameraRetryDelayProvider.overrideWithValue(Duration.zero),
            clockProbeDelayProvider.overrideWithValue(Duration.zero),
          ],
          child: const MaterialApp(home: RecordingsScreen()),
        ),
      );
      await tester.pumpAndSettle();
    }

    testWidgets('lists recordings and blocks the clip being recorded', (
      tester,
    ) async {
      await open(tester);
      expect(find.text('Wed 11 Nov 2026'), findsOneWidget);
      expect(find.textContaining('Recording now'), findsOneWidget);
      expect(find.text('19:22:57 · 45 s'), findsOneWidget);
      // Two finished pairs can be downloaded; the pair being written cannot.
      expect(find.byIcon(Icons.download), findsNWidgets(4));
    });

    testWidgets('tapping a clip queues it and shows progress, then saved', (
      tester,
    ) async {
      await open(tester);
      await tester.tap(find.text('Front · 68 MB'));
      await tester.pumpAndSettle();

      expect(downloader.current.single.name, '2026_1111_192257_045A.TS');
      expect(
        downloader.current.single.url,
        'http://192.168.1.254/Novatek/Movie/2026_1111_192257_045A.TS',
      );
      expect(find.text('Front · queued'), findsOneWidget);
      expect(find.textContaining('Downloading 1 of 1'), findsOneWidget);

      downloader.progress('1', 35531436);
      await tester.pump();
      await tester.pump();
      expect(find.text('Front · 50%'), findsOneWidget);

      downloader.finish('1');
      await tester.pump();
      await tester.pumpAndSettle();
      expect(find.text('Front · saved'), findsOneWidget);
      expect(find.textContaining('Downloading'), findsNothing);
    });

    testWidgets('batch download respects the lens filter', (tester) async {
      await open(tester);
      await tester.tap(find.text('Rear'));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Select several'));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Select all'));
      await tester.pumpAndSettle();
      expect(find.text('2 selected'), findsOneWidget);
      await tester.tap(find.byTooltip('Download selected'));
      await tester.pumpAndSettle();

      expect(downloader.current.map((j) => j.name), [
        '2026_1111_192257_046B.TS',
        '2026_1111_191723_044B.TS',
      ]);
    });

    testWidgets('a failed download offers to resume', (tester) async {
      await open(tester);
      await tester.tap(find.text('Front · 68 MB'));
      await tester.pumpAndSettle();
      downloader.fail('1', 'not connected to the camera');
      await tester.pump();
      await tester.pumpAndSettle();
      expect(find.textContaining('1 download failed'), findsOneWidget);

      await tester.tap(find.text('Resume'));
      await tester.pumpAndSettle();
      expect(downloader.current.single.state, DownloadState.queued);
    });
  });
}
