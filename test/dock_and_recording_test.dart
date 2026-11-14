import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ncam/camera/fake_transport.dart';
import 'package:ncam/camera/transport.dart';
import 'package:ncam/downloads/fake_downloader.dart';
import 'package:ncam/state/credentials.dart';
import 'package:ncam/state/downloads.dart';
import 'package:ncam/state/session.dart';
import 'package:ncam/ui/app_shell.dart';
import 'package:ncam/ui/diagnostic_screen.dart';
import 'package:ncam/ui/record_button.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  late FakeCameraTransport camera;

  Future<void> open(
    WidgetTester tester, {
    Widget home = const AppShell(),
  }) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 2.6;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          transportProvider.overrideWithValue(camera),
          downloaderProvider.overrideWithValue(FakeDownloader()),
          credentialStoreProvider.overrideWithValue(
            MemoryCredentialStore(const CameraCredentials('NoodleCam', 'x')),
          ),
          cameraRetryDelayProvider.overrideWithValue(Duration.zero),
          clockProbeDelayProvider.overrideWithValue(Duration.zero),
          statusPollIntervalProvider.overrideWithValue(
            const Duration(seconds: 5),
          ),
        ],
        child: MaterialApp(home: home),
      ),
    );
    await tester.pumpAndSettle();
  }

  int commands(String query) =>
      camera.requests.where((u) => u.contains(query)).length;

  setUp(() => camera = FakeCameraTransport());

  group('dock', () {
    testWidgets('opens each page and comes back home', (tester) async {
      await open(tester);
      expect(find.text('Connected to NoodleCam'), findsOneWidget);
      // Settings is on the home page's top bar, not in the dock.
      for (final label in ['Live', 'Recordings', 'Saved', 'Settings']) {
        expect(find.byTooltip(label), findsOneWidget, reason: label);
      }
      // By default the record button sits to the right of the page icons.
      expect(
        tester.getCenter(find.byType(RecordButton)).dx,
        greaterThan(tester.getCenter(find.byTooltip('Saved')).dx),
      );

      await tester.tap(find.byTooltip('Live'));
      await tester.pumpAndSettle();
      expect(find.text('Live view'), findsOneWidget);
      expect(camera.liveOpened, isNotEmpty);
      // The dock stays on screen.
      expect(find.byType(RecordButton), findsOneWidget);

      await tester.tap(find.byType(BackButton));
      await tester.pumpAndSettle();
      expect(find.text('Connected to NoodleCam'), findsOneWidget);
      // Leaving the live page closes the stream.
      expect(camera.screenKeptOn, isFalse);

      await tester.tap(find.byTooltip('Settings'));
      await tester.pumpAndSettle();
      expect(find.text('Colours'), findsOneWidget);
      // The dock stays, and its Settings-free pill has nothing highlighted.
      expect(find.byType(RecordButton), findsOneWidget);
      expect(find.byTooltip('Settings'), findsNothing);
      await tester.tap(find.byType(BackButton));
      await tester.pumpAndSettle();
      expect(find.text('Connected to NoodleCam'), findsOneWidget);

      // Tapping the open page again goes home.
      await tester.tap(find.byTooltip('Saved'));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Saved'));
      await tester.pumpAndSettle();
      expect(find.text('Connected to NoodleCam'), findsOneWidget);
    });

    testWidgets('Live waits for the camera; Saved and Settings do not', (
      tester,
    ) async {
      camera.failConnect = true;
      await open(tester);
      await tester.tap(find.byTooltip('Live'));
      await tester.pumpAndSettle();
      expect(find.text('Live view'), findsNothing);

      await tester.tap(find.byTooltip('Saved'));
      await tester.pumpAndSettle();
      expect(find.text('Saved on this phone'), findsOneWidget);

      // App settings (colours) work without the camera.
      await tester.tap(find.byType(BackButton));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Settings'));
      await tester.pumpAndSettle();
      expect(find.text('Colours'), findsOneWidget);
      expect(find.text('Not connected'), findsOneWidget);
      expect(find.text('Format SD card'), findsNothing);
    });
  });

  testWidgets('the end of a page can be scrolled clear of the floating dock', (
    tester,
  ) async {
    await open(tester);
    final list = find.byType(Scrollable).first;
    await tester.drag(list, const Offset(0, -3000));
    await tester.pumpAndSettle();
    final lastCard = tester.getRect(find.byType(Card).last);
    final dockPill = tester.getRect(find.byTooltip('Live'));
    expect(lastCard.bottom, lessThan(dockPill.top));
    // The page itself still runs behind the dock (it floats over the content).
    final page = tester.getRect(find.byType(Scrollable).first);
    expect(page.bottom, greaterThan(dockPill.top));
  });

  testWidgets('the highlight never slides past the end of the pill', (
    tester,
  ) async {
    await open(tester);
    final bubble = find.byType(AnimatedPositioned);
    final track = find.ancestor(of: bubble, matching: find.byType(Stack)).first;

    // From the first page to the last and back: the longest moves.
    for (final label in ['Live', 'Saved', 'Live']) {
      await tester.tap(find.byTooltip(label));
      for (var i = 0; i < 30; i++) {
        await tester.pump(const Duration(milliseconds: 16));
        final b = tester.getRect(bubble);
        final t = tester.getRect(track);
        expect(b.left, greaterThanOrEqualTo(t.left - 0.01), reason: label);
        expect(b.right, lessThanOrEqualTo(t.right + 0.01), reason: label);
      }
      await tester.pumpAndSettle();
    }
  });

  testWidgets('the record button can be moved to the left in Settings', (
    tester,
  ) async {
    await open(tester);
    await tester.tap(find.byTooltip('Settings'));
    await tester.pumpAndSettle();
    // Scroll the option clear of the floating dock before tapping it.
    await tester.drag(find.byType(Scrollable).first, const Offset(0, -200));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Left'));
    await tester.pumpAndSettle();
    expect(
      tester.getCenter(find.byType(RecordButton)).dx,
      lessThan(tester.getCenter(find.byTooltip('Live')).dx),
    );
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString('record_button_side'), 'left');

    await tester.tap(find.text('Right'));
    await tester.pumpAndSettle();
    expect(
      tester.getCenter(find.byType(RecordButton)).dx,
      greaterThan(tester.getCenter(find.byTooltip('Saved')).dx),
    );
  });

  testWidgets('a saved choice of side is used at start-up', (tester) async {
    SharedPreferences.setMockInitialValues({'record_button_side': 'left'});
    await open(tester);
    expect(
      tester.getCenter(find.byType(RecordButton)).dx,
      lessThan(tester.getCenter(find.byTooltip('Live')).dx),
    );
  });

  group('record button', () {
    testWidgets('a short tap while recording only explains', (tester) async {
      await open(tester);
      expect(find.byIcon(Icons.stop_rounded), findsOneWidget);
      await tester.tap(find.byType(RecordButton));
      await tester.pumpAndSettle();
      expect(find.text('Hold the button to stop recording.'), findsOneWidget);
      expect(commands('cmd=2001'), 0);
      expect(camera.recordingSeconds, greaterThan(0));
    });

    testWidgets('holding stops recording; letting go does not restart it', (
      tester,
    ) async {
      await open(tester);
      final gesture = await tester.startGesture(
        tester.getCenter(find.byType(RecordButton)),
      );
      await tester.pump(); // the ring's animation starts on this frame
      await tester.pump(const Duration(milliseconds: 700));
      // Half way: nothing sent yet, the ring is filling.
      expect(commands('cmd=2001'), 0);
      expect(find.byType(CircularProgressIndicator), findsWidgets);

      await tester.pump(holdToStop);
      await tester.pumpAndSettle();
      await gesture.up();
      await tester.pumpAndSettle();

      expect(commands('cmd=2001&par=0'), 1);
      expect(commands('cmd=2001&par=1'), 0);
      expect(camera.recordingSeconds, 0);
      expect(find.text('Recording stopped.'), findsOneWidget);
      expect(find.byIcon(Icons.stop_rounded), findsNothing);
    });

    testWidgets('a tap starts recording when stopped', (tester) async {
      camera.recordingSeconds = 0;
      for (final f in camera.files) {
        f.recording = false;
      }
      await open(tester);
      expect(find.byIcon(Icons.stop_rounded), findsNothing);
      await tester.tap(find.byType(RecordButton));
      await tester.pumpAndSettle();
      expect(commands('cmd=2001&par=1'), 1);
      expect(find.text('Recording started.'), findsOneWidget);
      expect(find.byIcon(Icons.stop_rounded), findsOneWidget);
    });
  });

  testWidgets('the clip timer follows the camera without reconnecting', (
    tester,
  ) async {
    await open(tester);
    expect(find.textContaining('Current clip: 2'), findsOneWidget);
    camera.recordingSeconds = 95;
    await tester.pump(const Duration(seconds: 5));
    await tester.pumpAndSettle();
    expect(find.text('Current clip: 1 min 35 s'), findsOneWidget);
    expect(camera.connectCount, 1);
  });

  testWidgets('the log can be saved to Downloads', (tester) async {
    // Something in the log to save.
    await camera.connect(ssid: 'NoodleCam', password: 'x');
    await camera.get('http://192.168.1.254/?custom=1&cmd=3012');
    await tester.pumpWidget(
      ProviderScope(
        overrides: [transportProvider.overrideWithValue(camera)],
        child: const MaterialApp(home: DiagnosticScreen()),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Save to Downloads'));
    await tester.pumpAndSettle();
    expect(camera.savedLogs, ['nCam-test-1.log']);
    expect(find.text('Saved to Downloads as nCam-test-1.log'), findsOneWidget);
  });

  test('a link that stops answering is rebuilt', () async {
    final store = MemoryCredentialStore(
      const CameraCredentials('NoodleCam', 'x'),
    );
    final c = ProviderContainer(
      overrides: [
        transportProvider.overrideWithValue(camera),
        credentialStoreProvider.overrideWithValue(store),
        cameraRetryDelayProvider.overrideWithValue(Duration.zero),
        clockProbeDelayProvider.overrideWithValue(Duration.zero),
        statusPollIntervalProvider.overrideWithValue(
          const Duration(milliseconds: 20),
        ),
      ],
    );
    addTearDown(c.dispose);
    c.listen(sessionProvider, (_, _) {});
    Future<void> waitFor(bool Function() done) async {
      for (var i = 0; i < 300 && !done(); i++) {
        await Future<void>.delayed(const Duration(milliseconds: 10));
      }
    }

    await waitFor(
      () => c.read(sessionProvider).connected && !c.read(sessionProvider).busy,
    );
    expect(camera.connectCount, 1);

    camera.failRequests = true;
    await waitFor(() => camera.connectCount >= 2);
    camera.failRequests = false;
    expect(camera.connectCount, 2);

    // The camera did not answer straight after the rejoin either; the next status
    // check retries until it does.
    await waitFor(() => c.read(sessionProvider).status != null);
    expect(c.read(sessionProvider).link, LinkState.connected);
    expect(c.read(sessionProvider).status, isNotNull);
  });
}
