import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ncam/camera/fake_transport.dart';
import 'package:ncam/downloads/fake_downloader.dart';
import 'package:ncam/state/credentials.dart';
import 'package:ncam/state/downloads.dart';
import 'package:ncam/state/pip.dart';
import 'package:ncam/state/session.dart';
import 'package:ncam/ui/app_shell.dart';
import 'package:ncam/ui/record_button.dart';

void main() {
  late FakeCameraTransport camera;
  late FakePipPlatform pip;

  Future<void> open(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 2.6;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          transportProvider.overrideWithValue(camera),
          downloaderProvider.overrideWithValue(FakeDownloader()),
          pipPlatformProvider.overrideWithValue(pip),
          credentialStoreProvider.overrideWithValue(
            MemoryCredentialStore(const CameraCredentials('NoodleCam', 'x')),
          ),
          cameraRetryDelayProvider.overrideWithValue(Duration.zero),
          clockProbeDelayProvider.overrideWithValue(Duration.zero),
        ],
        child: const MaterialApp(home: AppShell()),
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<void> openLive(WidgetTester tester) async {
    await tester.tap(find.byTooltip('Live'));
    // Send the first picture once the stream is open.
    for (var i = 0; i < 50 && !camera.emitFrame(); i++) {
      await tester.pump(const Duration(milliseconds: 20));
    }
    await tester.pumpAndSettle();
  }

  setUp(() {
    camera = FakeCameraTransport();
    pip = FakePipPlatform();
  });

  testWidgets('Live view offers the window and auto-enter while open', (
    tester,
  ) async {
    await open(tester);
    await openLive(tester);
    final config = pip.last!;
    expect(config.available, isTrue);
    expect(config.autoEnter, isTrue);
    expect(config.aspectWidth / config.aspectHeight, closeTo(16 / 9, 0.01));

    // Leaving Live view: nothing to put in a window any more.
    await tester.tap(find.byType(BackButton));
    await tester.pumpAndSettle();
    expect(pip.last!.available, isFalse);
    expect(pip.last!.autoEnter, isFalse);
  });

  testWidgets('turning the setting off keeps the button but stops auto-enter', (
    tester,
  ) async {
    await open(tester);
    await openLive(tester);
    final container = ProviderScope.containerOf(
      tester.element(find.byType(AppShell)),
    );
    await container.read(pipAutoEnterProvider.notifier).set(false);
    await tester.pumpAndSettle();
    expect(pip.last!.available, isTrue);
    expect(pip.last!.autoEnter, isFalse);

    await tester.tap(find.byTooltip('Picture-in-picture'));
    await tester.pumpAndSettle();
    expect(pip.enterCalls, 1);
  });

  testWidgets('in the window only the picture shows', (tester) async {
    await open(tester);
    await openLive(tester);
    expect(find.byType(RecordButton), findsOneWidget);
    expect(find.text('Live view'), findsOneWidget);

    await tester.tap(find.byTooltip('Picture-in-picture'));
    await tester.pumpAndSettle();
    expect(find.byType(RecordButton), findsNothing);
    expect(find.text('Live view'), findsNothing);
    expect(find.byType(Image), findsOneWidget);
    // The stream keeps running in the window.
    expect(camera.screenKeptOn, isTrue);

    // Expanded back to full screen.
    pip.emit(const PipChanged(inPip: false, closed: false));
    await tester.pumpAndSettle();
    expect(find.text('Live view'), findsOneWidget);
    expect(find.byType(RecordButton), findsOneWidget);
  });

  testWidgets('closing the window ends the live stream', (tester) async {
    await open(tester);
    await openLive(tester);
    pip.emit(const PipChanged(inPip: true, closed: false));
    await tester.pumpAndSettle();
    pip.emit(const PipChanged(inPip: false, closed: true));
    await tester.pumpAndSettle();
    expect(find.text('Connected to NoodleCam'), findsOneWidget);
    expect(camera.screenKeptOn, isFalse);
    expect(pip.last!.available, isFalse);
  });

  testWidgets('a refused window is explained', (tester) async {
    pip.allowEnter = false;
    await open(tester);
    await openLive(tester);
    await tester.tap(find.byTooltip('Picture-in-picture'));
    await tester.pumpAndSettle();
    expect(
      find.textContaining('Picture-in-picture is not available'),
      findsOneWidget,
    );
  });

  test('window buttons reach the page that is in charge', () async {
    final platform = FakePipPlatform();
    final c = ProviderContainer(
      overrides: [pipPlatformProvider.overrideWithValue(platform)],
    );
    addTearDown(c.dispose);
    final controller = c.read(pipProvider.notifier);
    final pressed = <String>[];
    var closed = 0;
    controller.register(
      PipRequest(
        autoEnter: true,
        actions: const ['rewind', 'pause', 'forward'],
        onAction: pressed.add,
        onClosed: () => closed++,
      ),
    );
    expect(platform.last!.actions, ['rewind', 'pause', 'forward']);

    platform.emit(const PipAction('pause'));
    platform.emit(const PipAction('forward'));
    platform.emit(const PipChanged(inPip: false, closed: true));
    await Future<void>.delayed(Duration.zero);
    expect(pressed, ['pause', 'forward']);
    expect(closed, 1);
  });
}
