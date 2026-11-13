import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ncam/camera/fake_transport.dart';
import 'package:ncam/downloads/downloader.dart';
import 'package:ncam/downloads/fake_downloader.dart';
import 'package:ncam/state/credentials.dart';
import 'package:ncam/state/downloads.dart';
import 'package:ncam/state/session.dart';
import 'package:ncam/ui/home_screen.dart';
import 'package:ncam/ui/recordings_screen.dart';

void main() {
  late FakeCameraTransport camera;
  late FakeDownloader downloader;

  Future<void> open(WidgetTester tester, Widget screen) async {
    tester.view.physicalSize = const Size(1080, 6000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
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
        child: MaterialApp(home: screen),
      ),
    );
    await tester.pumpAndSettle();
  }

  /// The state found on the real camera: powered, card in, not recording.
  void stopped() {
    camera.recordingSeconds = 0;
    for (final f in camera.files) {
      f.recording = false;
    }
  }

  setUp(() {
    camera = FakeCameraTransport();
    downloader = FakeDownloader();
  });

  testWidgets('a stopped camera is flagged and can be started', (tester) async {
    stopped();
    await open(tester, const HomeScreen());
    expect(find.text('The camera is NOT recording.'), findsOneWidget);

    await tester.tap(find.text('Start recording'));
    await tester.pumpAndSettle();

    expect(
      camera.requests.where((u) => u.contains('cmd=2001&par=1')),
      hasLength(1),
    );
    expect(find.text('The camera is NOT recording.'), findsNothing);
    expect(find.text('Recording'), findsOneWidget);
  });

  testWidgets('no warning while the camera records', (tester) async {
    await open(tester, const HomeScreen());
    expect(find.text('The camera is NOT recording.'), findsNothing);
    expect(find.text('Start recording'), findsNothing);
  });

  testWidgets('no warning while fast download holds recording off', (
    tester,
  ) async {
    stopped();
    downloader.fast = const FastModeStatus(
      enabled: true,
      phase: FastPhase.paused,
    );
    // Not recoverable yet, so the pause stays in force.
    downloader.recoverResult = null;
    await open(tester, const HomeScreen());
    expect(find.text('The camera is NOT recording.'), findsNothing);
    expect(find.textContaining('PAUSED'), findsOneWidget);
  });

  testWidgets('connecting never starts or stops recording by itself', (
    tester,
  ) async {
    stopped();
    await open(tester, const HomeScreen());
    expect(camera.requests.where((u) => u.contains('cmd=2001')), isEmpty);
    expect(camera.requests.where((u) => u.contains('cmd=3001')), isEmpty);
  });

  testWidgets('the camera\'s own log files are not shown as recordings', (
    tester,
  ) async {
    camera.files.add(
      FakeFile(
        '20261113_090336.log',
        1048576,
        DateTime(2026, 11, 13, 9, 3, 36),
      ),
    );
    await open(tester, const RecordingsScreen());
    expect(find.textContaining('.log'), findsNothing);
    expect(find.text('19:22:57 · 45 s'), findsOneWidget);
  });

  testWidgets('no preview is requested for the clip being recorded', (
    tester,
  ) async {
    await open(tester, const RecordingsScreen());
    expect(find.textContaining('Recording now'), findsOneWidget);
    expect(camera.thumbnailRequests.where((u) => u.contains('_047A')), isEmpty);
    expect(
      camera.thumbnailRequests.where((u) => u.contains('_045A')),
      hasLength(1),
    );
  });
}
