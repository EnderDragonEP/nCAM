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

  setUp(() {
    camera = FakeCameraTransport();
    downloader = FakeDownloader();
  });

  testWidgets('turning fast download on needs confirmation', (tester) async {
    await open(tester, const RecordingsScreen());
    expect(downloader.fast.enabled, isFalse);

    await tester.tap(find.byType(Switch));
    await tester.pumpAndSettle();
    expect(find.text('Pause recording to download faster?'), findsOneWidget);
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(downloader.fast.enabled, isFalse);

    await tester.tap(find.byType(Switch));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Turn on'));
    await tester.pumpAndSettle();
    expect(downloader.fast.enabled, isTrue);

    // Turning it off again asks nothing.
    await tester.tap(find.byType(Switch));
    await tester.pumpAndSettle();
    expect(downloader.fast.enabled, isFalse);
    expect(find.text('Pause recording to download faster?'), findsNothing);
  });

  testWidgets('shows that recording is paused while downloading', (
    tester,
  ) async {
    await open(tester, const RecordingsScreen());
    expect(find.textContaining('PAUSED'), findsNothing);

    await tester.tap(find.text('Front · 68 MB'));
    await tester.pumpAndSettle();
    downloader.setFast(
      const FastModeStatus(enabled: true, phase: FastPhase.paused),
    );
    await tester.pump();
    await tester.pump();
    expect(
      find.textContaining('Recording PAUSED while files download'),
      findsOneWidget,
    );
    // The queue is in charge of restarting; no manual button while it runs.
    expect(find.text('Restart recording'), findsNothing);
  });

  testWidgets('on connect, restarts recording the app had left paused', (
    tester,
  ) async {
    downloader
      ..fast = const FastModeStatus(phase: FastPhase.paused)
      ..recoverResult = true;
    await open(tester, const HomeScreen());

    expect(downloader.recoverCalls, 1);
    expect(downloader.fast.phase, FastPhase.idle);
    expect(find.textContaining('PAUSED'), findsNothing);
    // Status was read again after the restart (once on connect, once after).
    expect(
      camera.requests.where((u) => u.contains('cmd=3012')).length,
      greaterThanOrEqualTo(2),
    );
  });

  testWidgets('a failed restart is shown with a way to try again', (
    tester,
  ) async {
    await open(tester, const HomeScreen());
    downloader.setFast(
      const FastModeStatus(
        phase: FastPhase.failed,
        message: 'the camera did not start recording',
      ),
    );
    await tester.pump();
    await tester.pump();
    expect(find.textContaining('Recording is still OFF'), findsOneWidget);

    downloader.recoverResult = true;
    final before = downloader.recoverCalls;
    await tester.tap(find.text('Restart recording'));
    await tester.pumpAndSettle();
    expect(downloader.recoverCalls, before + 1);
    expect(find.textContaining('Recording is still OFF'), findsNothing);
  });
}
