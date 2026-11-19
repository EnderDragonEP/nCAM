import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ncam/camera/fake_transport.dart';
import 'package:ncam/downloads/downloader.dart';
import 'package:ncam/downloads/fake_downloader.dart';
import 'package:ncam/state/credentials.dart';
import 'package:ncam/state/downloads.dart';
import 'package:ncam/state/pip.dart';
import 'package:ncam/state/session.dart';
import 'package:ncam/ui/app_shell.dart';
import 'package:ncam/ui/zoomable_view.dart';

void main() {
  late FakeCameraTransport camera;
  late FakeDownloader downloads;

  Future<void> openLive(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 2.6;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          transportProvider.overrideWithValue(camera),
          downloaderProvider.overrideWithValue(downloads),
          pipPlatformProvider.overrideWithValue(FakePipPlatform()),
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
    await tester.tap(find.byTooltip('Live'));
    for (var i = 0; i < 50 && !camera.emitFrame(); i++) {
      await tester.pump(const Duration(milliseconds: 20));
    }
    await tester.pumpAndSettle();
  }

  /// A second of live view at [fps] pictures per second.
  Future<void> stream(WidgetTester tester, int fps) async {
    for (var i = 0; i < fps; i++) {
      camera.emitFrame();
      await tester.pump(Duration(milliseconds: 1000 ~/ fps));
    }
  }

  setUp(() {
    camera = FakeCameraTransport();
    downloads = FakeDownloader();
  });

  testWidgets('nothing is said while the live view runs well', (tester) async {
    await openLive(tester);
    await stream(tester, 25);
    await stream(tester, 25);
    expect(find.textContaining('Live view limited'), findsNothing);
  });

  testWidgets('a weak signal is named', (tester) async {
    camera.signal = -82;
    await openLive(tester);
    await stream(tester, 25);
    await stream(tester, 25);
    expect(
      find.text('Live view limited: weak Wi-Fi (-82 dBm)'),
      findsOneWidget,
    );
  });

  testWidgets('few pictures getting through are noticed', (tester) async {
    await openLive(tester);
    await stream(tester, 5);
    await stream(tester, 5);
    expect(find.text('Live view limited: slow connection'), findsOneWidget);
  });

  testWidgets('the fit button works on the live picture too', (tester) async {
    await openLive(tester);
    final view = find.byType(ZoomableView);
    await tester.tap(find.byTooltip('Zoom to fill'));
    await tester.pumpAndSettle();
    expect(tester.state<ZoomableViewState>(view).fit, PictureFit.fill);
    await tester.tap(find.byTooltip('Best fit'));
    await tester.pumpAndSettle();
    expect(tester.state<ZoomableViewState>(view).fit, PictureFit.whole);

    // Zoomed in by hand: back to the whole picture first.
    final area = tester.getRect(view);
    final a = await tester.startGesture(area.center - const Offset(50, 0));
    final b = await tester.startGesture(area.center + const Offset(50, 0));
    for (var i = 1; i <= 5; i++) {
      await a.moveTo(area.center - Offset(50.0 + 20 * i, 0));
      await b.moveTo(area.center + Offset(50.0 + 20 * i, 0));
      await tester.pump(const Duration(milliseconds: 16));
    }
    await a.up();
    await b.up();
    await tester.pumpAndSettle();
    expect(tester.state<ZoomableViewState>(view).fit, PictureFit.zoomed);
    await tester.tap(find.byTooltip('Best fit'));
    await tester.pumpAndSettle();
    expect(tester.state<ZoomableViewState>(view).fit, PictureFit.whole);
    expect(tester.state<ZoomableViewState>(view).scale, 1);
  });

  testWidgets('a download sharing the link is named', (tester) async {
    await openLive(tester);
    await downloads.enqueue([
      const DownloadRequest(name: 'a.TS', url: 'u', total: 100),
    ]);
    await stream(tester, 25);
    expect(
      find.text('Live view limited: a clip is downloading'),
      findsOneWidget,
    );
  });
}
