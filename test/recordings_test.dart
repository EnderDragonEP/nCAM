import 'dart:convert';

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
import 'package:ncam/ui/player_screen.dart';
import 'package:ncam/ui/recordings_screen.dart';
import 'package:video_player_platform_interface/video_player_platform_interface.dart';

import 'fake_video_player.dart';

import 'package:shared_preferences/shared_preferences.dart';

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

    test('a size rounded by the folder page still finds the saved copy', () {
      final rounded = CameraFile(
        name: '2026_1110_184312_001A.TS',
        path: '/Novatek/Movie/2026_1110_184312_001A.TS',
        size: 242566021, // "231.33 MB"
        sizeSlack: 10486,
        writeTime: null,
      );
      FileStatus of(int saved) => FileStatusResolver(
        jobs: const [],
        local: {rounded.name: saved},
        writing: const {},
      ).view(rounded).status;
      expect(of(242562488), FileStatus.saved);
      expect(of(200000000), FileStatus.onCamera);
      // The camera's reply gives the real length; a rounded one would cut it short.
      expect(downloadRequestFor(rounded).total, 0);
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

    Future<void> open(
      WidgetTester tester, {
      bool refuseWhileRecording = false,
      bool folderPage = true,
    }) async {
      camera = FakeCameraTransport()
        ..cameraClock = (() => DateTime(2026, 11, 11, 19, 57, 54))
        ..refuseListWhileRecording = refuseWhileRecording
        ..folderPageAvailable = folderPage;
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

    testWidgets('shows the name given to a recording on the phone', (
      tester,
    ) async {
      SharedPreferences.setMockInitialValues({
        'clip_names': jsonEncode({'2026_1111_192257_045A.TS': 'Near miss'}),
      });
      await open(tester);
      expect(find.text('Near miss'), findsOneWidget);
    });

    testWidgets('while recording, the list is read from the folder page', (
      tester,
    ) async {
      await open(tester, refuseWhileRecording: true);
      expect(find.text('19:22:57 · 45 s'), findsOneWidget);
      expect(find.textContaining('Recording now'), findsOneWidget);
      expect(find.byIcon(Icons.download), findsNWidgets(4));
    });

    testWidgets('with no list at all, recording can be paused to read it', (
      tester,
    ) async {
      await open(tester, refuseWhileRecording: true, folderPage: false);
      expect(
        find.textContaining("won't send its list while recording"),
        findsOneWidget,
      );
      await tester.tap(find.text('Pause recording to read the list'));
      await tester.pumpAndSettle();
      expect(find.text('Pause recording?'), findsOneWidget);
      await tester.tap(find.text('Pause and read'));
      await tester.pumpAndSettle();

      expect(find.text('List read. Recording again.'), findsOneWidget);
      expect(find.text('19:22:57 · 45 s'), findsOneWidget);
      expect(camera.recordingSeconds, greaterThan(0));
    });

    testWidgets('a recording can be played from the camera without saving it', (
      tester,
    ) async {
      VideoPlayerPlatform.instance = FakeVideoPlayer();
      await open(tester);
      // The clip being recorded cannot be played yet; the two finished ones can.
      expect(find.byTooltip('Play'), findsNWidgets(2));
      await tester.tap(find.byTooltip('Play').first);
      await tester.pumpAndSettle();
      expect(find.byType(PlayerScreen), findsOneWidget);
      expect(find.byTooltip('Playing from the camera'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
      await tester.pump();
    });

    testWidgets('search narrows the list by name or by date and time', (
      tester,
    ) async {
      SharedPreferences.setMockInitialValues({
        'clip_names': jsonEncode({'2026_1111_192257_045A.TS': 'Near miss'}),
      });
      await open(tester);
      Future<void> search(String text) async {
        await tester.enterText(find.byType(SearchBar), text);
        await tester.pumpAndSettle();
      }

      expect(find.byType(SearchBar), findsNothing);
      await tester.tap(find.byTooltip('Search'));
      await tester.pumpAndSettle();

      await search('near');
      expect(find.text('19:22:57 · 45 s'), findsOneWidget);
      expect(find.textContaining('19:17:23'), findsNothing);
      expect(find.textContaining('Recording now'), findsNothing);

      await search('19:17');
      expect(find.textContaining('19:17:23'), findsOneWidget);
      expect(find.text('19:22:57 · 45 s'), findsNothing);

      // Select all takes only what the search shows.
      await search('near');
      await tester.tap(find.byTooltip('Select several'));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Select all'));
      await tester.pumpAndSettle();
      expect(find.text('1 selected'), findsOneWidget);
      await tester.tap(find.byTooltip('Cancel selection'));
      await tester.pumpAndSettle();

      await search('speeding');
      expect(find.text('No recording matches "speeding".'), findsOneWidget);

      await tester.tap(find.byTooltip('Close search'));
      await tester.pumpAndSettle();
      expect(find.byType(SearchBar), findsNothing);
      expect(find.text('19:22:57 · 45 s'), findsOneWidget);
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
