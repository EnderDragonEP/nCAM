import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ncam/camera/fake_transport.dart';
import 'package:ncam/camera/models.dart';
import 'package:ncam/camera/transport.dart';
import 'package:ncam/downloads/fake_downloader.dart';
import 'package:ncam/state/credentials.dart';
import 'package:ncam/state/downloads.dart';
import 'package:ncam/state/session.dart';
import 'package:ncam/state/thumbnails.dart';
import 'package:ncam/ui/recordings_screen.dart';

/// Transport whose thumbnails are scripted by the test.
class ThumbCamera extends FakeCameraTransport {
  final Map<String, String?> pictures = {};
  bool unreachable = false;

  @override
  Future<String?> thumbnail(String fileUrl, {required String cacheKey}) async {
    thumbnailRequests.add(cacheKey);
    await Future<void>.delayed(Duration.zero);
    if (unreachable) throw const TransportException('io', 'not connected');
    return pictures[cacheKey];
  }
}

CameraFile file(String name) => CameraFile(
  name: name,
  path: '/Novatek/Movie/$name',
  size: 1,
  writeTime: null,
);

void main() {
  group('ThumbnailLoader', () {
    test(
      'serves the most recently requested clip first, one at a time',
      () async {
        final camera = ThumbCamera()..pictures['b.TS'] = '/cache/b.jpg';
        final loader = ThumbnailLoader(camera);
        final a = loader.load(file('a.TS'));
        final b = loader.load(file('b.TS'));
        final c = loader.load(file('c.TS'));
        expect(await b, '/cache/b.jpg');
        expect(await a, isNull);
        expect(await c, isNull);
        // "a" started straight away; of the two that waited, the newer went first.
        expect(camera.thumbnailRequests, ['a.TS', 'c.TS', 'b.TS']);
      },
    );

    test('remembers results, including "no picture"', () async {
      final camera = ThumbCamera()..pictures['a.TS'] = '/cache/a.jpg';
      final loader = ThumbnailLoader(camera);
      await loader.load(file('a.TS'));
      await loader.load(file('b.TS'));
      await loader.load(file('a.TS'));
      await loader.load(file('b.TS'));
      expect(camera.thumbnailRequests, ['a.TS', 'b.TS']);
      expect(loader.cached(file('a.TS')), '/cache/a.jpg');
    });

    test('tries again after the camera was unreachable', () async {
      final camera = ThumbCamera()..unreachable = true;
      final loader = ThumbnailLoader(camera);
      expect(await loader.load(file('a.TS')), isNull);
      camera
        ..unreachable = false
        ..pictures['a.TS'] = '/cache/a.jpg';
      expect(await loader.load(file('a.TS')), '/cache/a.jpg');
    });

    test('a cancelled request is never sent', () async {
      final camera = ThumbCamera();
      final loader = ThumbnailLoader(camera);
      final a = loader.load(file('a.TS'));
      final b = loader.load(file('b.TS'));
      loader.cancel(file('b.TS'));
      await a;
      expect(await b, isNull);
      expect(camera.thumbnailRequests, ['a.TS']);
    });
  });

  group('delete', () {
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

    List<String> deletes() => [
      for (final u in camera.requests)
        if (u.contains('cmd=4003')) Uri.parse(u).queryParameters['str']!,
    ];

    testWidgets('one recording: asks first, then deletes both clips', (
      tester,
    ) async {
      await open(tester);
      // The clip being recorded offers no menu; the two finished ones do.
      expect(find.byTooltip('More'), findsNWidgets(2));

      await tester.tap(find.byTooltip('More').first);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Delete from camera'));
      await tester.pumpAndSettle();
      expect(find.text('Delete 2 files from the camera?'), findsOneWidget);
      expect(
        find.textContaining('None of them has been saved to this phone'),
        findsOneWidget,
      );

      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(deletes(), isEmpty);

      await tester.tap(find.byTooltip('More').first);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Delete from camera'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, 'Delete'));
      await tester.pumpAndSettle();

      expect(deletes(), [
        r'A:\Novatek\Movie\2026_1111_192257_045A.TS',
        r'A:\Novatek\Movie\2026_1111_192257_046B.TS',
      ]);
      expect(find.text('19:22:57 · 45 s'), findsNothing);
      expect(find.textContaining('Deleted 2 files'), findsOneWidget);
    });

    testWidgets('batch delete respects the filter and skips the live clip', (
      tester,
    ) async {
      await open(tester);
      await tester.tap(find.text('Front'));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Select several'));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Select all'));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Delete selected from camera'));
      await tester.pumpAndSettle();
      expect(find.text('Delete 2 files from the camera?'), findsOneWidget);
      await tester.tap(find.widgetWithText(FilledButton, 'Delete'));
      await tester.pumpAndSettle();

      expect(deletes(), [
        r'A:\Novatek\Movie\2026_1111_192257_045A.TS',
        r'A:\Novatek\Movie\2026_1111_191723_043A.TS',
      ]);
      // Rear clips and the pair being recorded are still on the camera.
      expect(camera.files.map((f) => f.name), [
        '2026_1011_195621_047A.TS',
        '2026_1011_195621_048B.TS',
        '2026_1111_191723_044B.TS',
        '2026_1111_192257_046B.TS',
      ]);
    });

    testWidgets('a refusal from the camera is reported and nothing vanishes', (
      tester,
    ) async {
      await open(tester);
      camera.deleteStatus = -1;
      await tester.tap(find.byTooltip('More').first);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Delete from camera'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, 'Delete'));
      await tester.pumpAndSettle();

      expect(find.textContaining('The camera refused'), findsOneWidget);
      expect(find.text('19:22:57 · 45 s'), findsOneWidget);
    });

    testWidgets('will not delete a clip that is downloading', (tester) async {
      await open(tester);
      await tester.tap(find.text('Front · 68 MB'));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('More').first);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Delete from camera'));
      await tester.pumpAndSettle();
      expect(
        find.textContaining('Some of these are downloading'),
        findsOneWidget,
      );
      expect(deletes(), isEmpty);
    });
  });
}
