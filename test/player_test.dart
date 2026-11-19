import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ncam/camera/fake_transport.dart';
import 'package:ncam/camera/models.dart';
import 'package:ncam/camera/recordings.dart';
import 'package:ncam/downloads/fake_downloader.dart';
import 'package:ncam/state/downloads.dart';
import 'package:ncam/state/pip.dart';
import 'package:ncam/state/session.dart';
import 'package:ncam/ui/player_screen.dart';
import 'package:ncam/ui/zoomable_view.dart';
import 'package:ncam/state/credentials.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:video_player/video_player.dart';
import 'package:video_player_platform_interface/video_player_platform_interface.dart';

import 'fake_video_player.dart';

// Names a second apart, as happens when a pair starts just before a second ticks
// over; the two are still recorded together.
const frontName = '2026_1111_192257_045A.TS';
const rearName = '2026_1111_192258_046B.TS';

/// Galaxy S24 Ultra at its default resolution: 384 x 832 logical pixels.
const dpr = 2.8125;
const portrait = Size(1080, 2340);
const landscape = Size(2340, 1080);

CameraFile file(String name) =>
    CameraFile(name: name, path: name, size: 100, writeTime: null);

void main() {
  late FakeVideoPlayer video;
  late FakeDownloader downloads;
  late FakePipPlatform pip;

  final recording = Recording(
    front: file(frontName),
    rear: file(rearName),
    beingWritten: false,
  );

  Future<void> open(
    WidgetTester tester, {
    Size size = portrait,
    Recording? clip,
    bool connected = false,
    bool screenReader = false,
  }) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = dpr;
    addTearDown(tester.view.reset);
    final player = PlayerScreen(recording: clip ?? recording, lens: Lens.front);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          transportProvider.overrideWithValue(FakeCameraTransport()),
          downloaderProvider.overrideWithValue(downloads),
          pipPlatformProvider.overrideWithValue(pip),
          // Connected: the saved camera is joined at start-up.
          credentialStoreProvider.overrideWithValue(
            connected
                ? MemoryCredentialStore(
                    const CameraCredentials('NoodleCam', 'x'),
                  )
                : MemoryCredentialStore(),
          ),
          cameraRetryDelayProvider.overrideWithValue(Duration.zero),
          clockProbeDelayProvider.overrideWithValue(Duration.zero),
        ],
        child: MaterialApp(
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context)
                .copyWith(accessibleNavigation: screenReader),
            child: child!,
          ),
          home: connected ? const _WaitForCamera() : player,
        ),
      ),
    );
    await tester.pumpAndSettle();
    if (connected) {
      // Opened once the camera is joined, as from Recordings.
      Navigator.of(tester.element(find.byType(_WaitForCamera)))
          .push(MaterialPageRoute<void>(builder: (_) => player));
      await tester.pumpAndSettle();
    }
  }

  /// Two fingers spread apart (or together) in the middle of [area].
  Future<void> pinch(
    WidgetTester tester,
    Rect area,
    double from,
    double to,
  ) async {
    final centre = area.center;
    final a = await tester.startGesture(centre - Offset(from / 2, 0));
    final b = await tester.startGesture(centre + Offset(from / 2, 0));
    for (var i = 1; i <= 5; i++) {
      final d = from + (to - from) * i / 5;
      await a.moveTo(centre - Offset(d / 2, 0));
      await b.moveTo(centre + Offset(d / 2, 0));
      await tester.pump(const Duration(milliseconds: 16));
    }
    await a.up();
    await b.up();
    await tester.pumpAndSettle();
  }

  Future<void> pickSpeed(WidgetTester tester, String speed) async {
    await tester.tap(find.byTooltip('Playback speed'));
    await tester.pumpAndSettle();
    await tester.tap(find.text(speed).last);
    await tester.pumpAndSettle();
  }

  /// Switching clips: a player's dispose only finishes after a real event-loop turn,
  /// which widget tests' fake time never gives it.
  Future<void> switchTo(WidgetTester tester, String view) async {
    await tester.tap(
      find.descendant(
        of: find.byType(SegmentedButton<PlayerView>),
        matching: find.text(view),
      ),
    );
    await tester.pumpAndSettle();
    await tester.runAsync(() => Future<void>.delayed(Duration.zero));
    await tester.pumpAndSettle();
  }

  /// Lets the players report where the fake clips are.
  Future<void> tick(WidgetTester tester) async {
    await tester.pump(const Duration(milliseconds: 150));
    await tester.pumpAndSettle();
  }

  /// Opens Both and waits out the checks skipped while the players settle.
  Future<(FakeVideo, FakeVideo)> openBoth(WidgetTester tester) async {
    await open(tester);
    await switchTo(tester, 'Both');
    await tester.pump(const Duration(milliseconds: 1600));
    return (video.open(frontName), video.open(rearName));
  }

  Future<void> close(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox());
    await tester.pump();
  }

  setUp(() {
    video = FakeVideoPlayer();
    VideoPlayerPlatform.instance = video;
    downloads = FakeDownloader()..local.addAll({frontName: 100, rearName: 100});
    pip = FakePipPlatform();
  });

  testWidgets('Both plays the two clips together from the same moment', (
    tester,
  ) async {
    await open(tester);
    expect(find.byType(VideoPlayer), findsOneWidget);
    expect(video.open(frontName).playing, isTrue);

    // Twenty seconds into the front clip, then Both.
    video.open(frontName).position = const Duration(seconds: 20);
    await tick(tester);
    await switchTo(tester, 'Both');

    expect(find.byType(VideoPlayer), findsNWidgets(2));
    final front = video.open(frontName);
    final rear = video.open(rearName);
    expect(video.live, hasLength(2));
    expect(front.position, const Duration(seconds: 20));
    expect(rear.position, const Duration(seconds: 20));
    expect(front.playing && rear.playing, isTrue);
    // Only the front clip has sound, and only it takes the sound focus: on Android
    // a second player taking the focus pauses the first, so they took turns.
    expect(rear.volume, 0);
    expect(front.volume, 1);
    expect(front.mixWithOthers, isFalse);
    expect(rear.mixWithOthers, isTrue);

    // The controls move both.
    await tester.tap(find.byTooltip('Forward 10 seconds'));
    await tester.pumpAndSettle();
    expect(front.position, const Duration(seconds: 30));
    expect(rear.position, const Duration(seconds: 30));

    await tester.tap(find.byTooltip('Pause'));
    await tester.pumpAndSettle();
    expect(front.playing || rear.playing, isFalse);

    // One press is enough to play again.
    await tester.tap(find.byTooltip('Play'));
    await tester.pumpAndSettle();
    expect(front.playing && rear.playing, isTrue);
    expect(find.byTooltip('Pause'), findsOneWidget);
    await close(tester);
  });

  testWidgets('a clip loading after a jump keeps the Pause button', (
    tester,
  ) async {
    final (front, rear) = await openBoth(tester);
    // Android says "not playing" while it loads.
    front.startBuffering();
    await tester.pump(const Duration(seconds: 2));
    expect(find.byTooltip('Pause'), findsOneWidget);
    expect(rear.playing, isTrue);

    front.endBuffering();
    await tester.pump(const Duration(seconds: 1));
    expect(find.byTooltip('Pause'), findsOneWidget);
    expect(front.playing && rear.playing, isTrue);
    await close(tester);
  });

  testWidgets(
    'a clip stopped from outside shows as paused and stops the rear',
    (tester) async {
      final (front, rear) = await openBoth(tester);
      front.stoppedFromOutside(); // for example a phone call took the sound
      await tester.pump(const Duration(milliseconds: 1600));
      expect(find.byTooltip('Play'), findsOneWidget);
      expect(rear.playing, isFalse);
      await close(tester);
    },
  );

  testWidgets('a rear clip slightly out of step is eased back, not jumped', (
    tester,
  ) async {
    final (front, rear) = await openBoth(tester);
    final jumps = rear.seeks.length;

    front.position = const Duration(seconds: 30);
    rear.position = const Duration(seconds: 29, milliseconds: 700);
    await tester.pump(const Duration(milliseconds: 600));
    expect(rear.speed, greaterThan(1)); // behind: runs faster

    rear.position = const Duration(seconds: 30, milliseconds: 400);
    await tester.pump(const Duration(milliseconds: 600));
    expect(rear.speed, lessThan(1)); // ahead: runs slower

    rear.position = const Duration(seconds: 30);
    await tester.pump(const Duration(milliseconds: 600));
    expect(rear.speed, 1);
    expect(rear.seeks.length, jumps);
    await close(tester);
  });

  testWidgets('a rear clip far out of step jumps to the front clip', (
    tester,
  ) async {
    final (front, rear) = await openBoth(tester);
    front.position = const Duration(seconds: 30);
    rear.position = const Duration(seconds: 20);
    await tester.pump(const Duration(milliseconds: 600));
    expect(rear.seeks.last, const Duration(seconds: 30) + playerSeekLead);
    expect(rear.speed, 1);

    // It is given time to settle before being measured again.
    final jumps = rear.seeks.length;
    await tester.pump(const Duration(milliseconds: 1000));
    expect(rear.seeks.length, jumps);
    await close(tester);
  });

  testWidgets('portrait stacks the clips; landscape puts them side by side', (
    tester,
  ) async {
    await open(tester);
    await switchTo(tester, 'Both');
    var players = find.byType(VideoPlayer);
    var a = tester.getCenter(players.at(0));
    var b = tester.getCenter(players.at(1));
    expect(b.dy, greaterThan(a.dy + 50));
    expect(b.dx, closeTo(a.dx, 1));
    await close(tester);

    await open(tester, size: landscape);
    await switchTo(tester, 'Both');
    players = find.byType(VideoPlayer);
    a = tester.getCenter(players.at(0));
    b = tester.getCenter(players.at(1));
    expect(b.dx, greaterThan(a.dx + 50));
    expect(b.dy, closeTo(a.dy, 1));
    await close(tester);
  });

  testWidgets('landscape gives the clips the whole screen', (tester) async {
    final modes = <Object?>[];
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (call) async {
        if (call.method == 'SystemChrome.setEnabledSystemUIMode') {
          modes.add(call.arguments);
        }
        return null;
      },
    );
    addTearDown(
      () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        null,
      ),
    );
    const screen = Size(2340 / dpr, 1080 / dpr);

    await open(tester, size: landscape);
    expect(find.byType(AppBar), findsNothing);
    expect(modes, ['SystemUiMode.immersiveSticky']);
    // One clip: the full height.
    expect(
      tester.getRect(find.byType(VideoPlayer)).height,
      closeTo(screen.height, 0.5),
    );

    // Both: each half of the width.
    await switchTo(tester, 'Both');
    for (final player in find.byType(VideoPlayer).evaluate()) {
      final box = player.renderObject! as RenderBox;
      expect(box.size.width, closeTo((screen.width - 4) / 2, 0.5));
    }

    // Leaving restores the bars.
    await close(tester);
    expect(modes.last, 'SystemUiMode.edgeToEdge');
  });

  testWidgets(
    'a pinch fills the screen with the clip, another shows it whole',
    (tester) async {
      await open(tester, size: landscape);
      const screen = Size(2340 / dpr, 1080 / dpr);
      final centre = screen.center(Offset.zero);
      Future<void> pinch(double from, double to) async {
        final a = await tester.startGesture(centre - Offset(from / 2, 0));
        final b = await tester.startGesture(centre + Offset(from / 2, 0));
        for (var i = 1; i <= 5; i++) {
          final d = from + (to - from) * i / 5;
          await a.moveTo(centre - Offset(d / 2, 0));
          await b.moveTo(centre + Offset(d / 2, 0));
          await tester.pump(const Duration(milliseconds: 16));
        }
        await a.up();
        await b.up();
        await tester.pumpAndSettle();
      }

      expect(
        tester.getRect(find.byType(VideoPlayer)).width,
        lessThan(screen.width - 100),
      );
      await pinch(100, 130);
      expect(
        tester.getRect(find.byType(VideoPlayer)).width,
        closeTo(screen.width, 1),
      );
      expect(find.text('Zoomed to fill'), findsOneWidget);
      await pinch(200, 150);
      expect(
        tester.getRect(find.byType(VideoPlayer)).height,
        closeTo(screen.height, 1),
      );
      await close(tester);
    },
  );

  testWidgets('landscape controls hide while playing and come back on a tap', (
    tester,
  ) async {
    await open(tester, size: landscape);
    double shown() => tester
        .widget<AnimatedOpacity>(
          find.byKey(const ValueKey('player-bottom-bar')),
        )
        .opacity;
    expect(shown(), 1);

    await tester.pump(
      playerControlsTimeout + const Duration(milliseconds: 500),
    );
    await tester.pumpAndSettle();
    expect(shown(), 0);

    await tester.tapAt(tester.getCenter(find.byType(VideoPlayer)));
    await tester.pumpAndSettle();
    expect(shown(), 1);

    // Paused, they still lie over the clips, so they still fade.
    await tester.tap(find.byTooltip('Pause'));
    await tester.pumpAndSettle();
    expect(shown(), 1);
    await tester.pump(const Duration(seconds: 6));
    await tester.pumpAndSettle();
    expect(shown(), 0);
    await close(tester);
  });

  testWidgets('the floating window is twice as wide for Both', (tester) async {
    await open(tester);
    expect(
      pip.last!.aspectWidth / pip.last!.aspectHeight,
      closeTo(16 / 9, 0.01),
    );
    await switchTo(tester, 'Both');
    expect(
      pip.last!.aspectWidth / pip.last!.aspectHeight,
      closeTo(32 / 9, 0.01),
    );

    // Back to one clip: one clip's shape, at the same moment.
    video.open(frontName).position = const Duration(seconds: 12);
    await tick(tester);
    await switchTo(tester, 'Rear');
    expect(find.byType(VideoPlayer), findsOneWidget);
    expect(video.live, hasLength(1));
    expect(video.open(rearName).position, const Duration(seconds: 12));
    expect(video.open(rearName).volume, 1);
    expect(video.open(rearName).mixWithOthers, isFalse);
    expect(
      pip.last!.aspectWidth / pip.last!.aspectHeight,
      closeTo(16 / 9, 0.01),
    );
    await close(tester);
  });

  testWidgets("the title shows the recording's name", (tester) async {
    SharedPreferences.setMockInitialValues({
      'clip_names': jsonEncode({frontName: 'Near miss'}),
    });
    await open(tester);
    expect(find.text('Near miss'), findsOneWidget);
    expect(find.text('2026-11-11 19:22:57'), findsOneWidget);
    await close(tester);
  });

  testWidgets('the speed can be changed, for both clips', (tester) async {
    await open(tester);
    expect(find.text('1×'), findsOneWidget);
    await pickSpeed(tester, '2×');
    expect(video.open(frontName).speed, 2);
    expect(find.text('2×'), findsOneWidget);

    // Both: the rear runs at the same speed, still eased back into step.
    await switchTo(tester, 'Both');
    await tester.pump(const Duration(milliseconds: 1600));
    final front = video.open(frontName);
    final rear = video.open(rearName);
    expect(front.speed, 2);
    expect(rear.speed, 2);
    front.position = const Duration(seconds: 30);
    rear.position = const Duration(seconds: 29, milliseconds: 700);
    await tester.pump(const Duration(milliseconds: 600));
    expect(rear.speed, closeTo(2 * 1.15, 0.01));

    await pickSpeed(tester, '0.25×');
    expect(front.speed, 0.25);
    await close(tester);
  });

  testWidgets('zooming keeps everything in place; the bars then fade away', (
    tester,
  ) async {
    await open(tester);
    await tester.tap(find.byTooltip('Pause'));
    await tester.pumpAndSettle();
    final play = tester.getCenter(find.byTooltip('Play'));
    final title = tester.getTopLeft(find.text('2026-11-11 19:22:57'));
    final picture = tester.getCenter(find.byType(ZoomableView));
    double shown() => tester
        .widget<AnimatedOpacity>(
          find.byKey(const ValueKey('player-bottom-bar')),
        )
        .opacity;

    await pinch(tester, tester.getRect(find.byType(VideoPlayer)), 100, 300);
    // Nothing moved: not the buttons, not the title, not the picture's space.
    expect(tester.getCenter(find.byTooltip('Play')), play);
    expect(tester.getTopLeft(find.text('2026-11-11 19:22:57')), title);
    expect(tester.getCenter(find.byType(ZoomableView)), picture);
    // The zoomed picture spreads under the bars, which got out of the way at once.
    final zoomed = tester.getRect(find.byType(VideoPlayer));
    expect(
      zoomed.height,
      greaterThan(tester.getSize(find.byType(ZoomableView)).height),
    );
    expect(shown(), 0);

    // A tap brings them back; zoomed, they fade again even while paused.
    await tester.tapAt(picture);
    await tester.pumpAndSettle();
    expect(shown(), 1);
    await tester.pump(
      playerControlsTimeout + const Duration(milliseconds: 500),
    );
    await tester.pumpAndSettle();
    expect(shown(), 0);
    await tester.tapAt(picture);
    await tester.pumpAndSettle();
    expect(shown(), 1);

    // Back to the whole picture: still nothing moves, and the bars stay.
    await pinch(tester, tester.getRect(find.byType(ZoomableView)), 300, 60);
    expect(tester.getCenter(find.byTooltip('Play')), play);
    await tester.pump(playerControlsTimeout * 2);
    await tester.pumpAndSettle();
    expect(shown(), 1);
    await close(tester);
  });

  testWidgets('turning to landscape side by side hides the bars too', (
    tester,
  ) async {
    await open(tester);
    await switchTo(tester, 'Both');
    double shown() => tester
        .widget<AnimatedOpacity>(
          find.byKey(const ValueKey('player-bottom-bar')),
        )
        .opacity;
    // Portrait: the bars are beside the clips and stay.
    await tester.pump(playerControlsTimeout * 2);
    await tester.pumpAndSettle();
    expect(shown(), 1);

    tester.view.physicalSize = landscape;
    await tester.pumpAndSettle();
    expect(shown(), 1);
    await tester.pump(
      playerControlsTimeout + const Duration(milliseconds: 500),
    );
    await tester.pumpAndSettle();
    expect(shown(), 0);
    await close(tester);
  });

  testWidgets(
    'zooming in Both hides the bars; each clip spreads but not over the other',
    (tester) async {
      await open(tester);
      await switchTo(tester, 'Both');
      await tester.tap(find.byTooltip('Pause'));
      await tester.pumpAndSettle();
      double shown() => tester
          .widget<AnimatedOpacity>(
            find.byKey(const ValueKey('player-bottom-bar')),
          )
          .opacity;
      final panes = find.byType(ZoomableView);
      final front = tester.getRect(panes.at(0));
      final rear = tester.getRect(panes.at(1));
      await pinch(tester, front, 100, 300);
      expect(shown(), 0);
      await pinch(tester, rear, 100, 300);

      // The front clip spreads up under the top bar but stops at the rear clip, and the
      // rear clip spreads down under the bottom bar but stops at the front clip.
      final frontClip = tester.renderObject<RenderClipRect>(
        find.ancestor(of: panes.at(0), matching: find.byType(ClipRect)).first,
      );
      expect(frontClip.clipper!.getClip(front.size).bottom, front.height);
      expect(
        frontClip.clipper!.getClip(front.size).top,
        lessThan(-front.height),
      );
      final pictures = find.byType(VideoPlayer);
      expect(tester.getRect(pictures.at(0)).top, lessThan(front.top));
      expect(tester.getRect(pictures.at(1)).bottom, greaterThan(rear.bottom));
      await close(tester);
    },
  );

  testWidgets('the fit button fills, then fits; zoomed, it fits first', (
    tester,
  ) async {
    await open(tester, size: landscape);
    final zoom = tester.state<ZoomableViewState>(find.byType(ZoomableView));
    expect(zoom.fit, PictureFit.whole);

    // Whole picture: the button fills the screen.
    await tester.tap(find.byTooltip('Zoom to fill'));
    await tester.pumpAndSettle();
    expect(zoom.fit, PictureFit.fill);
    expect(
      tester.getRect(find.byType(VideoPlayer)).width,
      closeTo(2340 / dpr, 1),
    );
    expect(find.text('Zoomed to fill'), findsOneWidget);

    // Filled: back to the whole picture.
    await tester.tap(find.byTooltip('Best fit'));
    await tester.pumpAndSettle();
    expect(zoom.fit, PictureFit.whole);
    expect(zoom.scale, 1);
    expect(find.text('Best fit'), findsOneWidget);

    // Zoomed in by hand: the first press shows the whole picture.
    await pinch(tester, tester.getRect(find.byType(ZoomableView)), 100, 300);
    await tester.drag(find.byType(ZoomableView), const Offset(-80, 30));
    await tester.pumpAndSettle();
    expect(zoom.fit, PictureFit.zoomed);
    // The bars went away for the pinch; a tap brings them, and the button, back.
    await tester.tapAt(tester.getCenter(find.byType(ZoomableView)));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Best fit'));
    await tester.pumpAndSettle();
    expect(zoom.fit, PictureFit.whole);
    expect(zoom.scale, 1);
    expect(
      tester.getCenter(find.byType(VideoPlayer)),
      tester.getCenter(find.byType(ZoomableView)),
    );
    expect(find.byTooltip('Zoom to fill'), findsOneWidget);
    await close(tester);
  });

  testWidgets('in Both, the fit button acts on both clips', (tester) async {
    await open(tester);
    await switchTo(tester, 'Both');
    final views = find.byType(ZoomableView);
    await tester.tap(find.byTooltip('Zoom to fill'));
    await tester.pumpAndSettle();
    expect(tester.state<ZoomableViewState>(views.at(0)).fit, PictureFit.fill);
    expect(tester.state<ZoomableViewState>(views.at(1)).fit, PictureFit.fill);

    // One clip zoomed by hand: the next press brings both back whole.
    await pinch(tester, tester.getRect(views.at(1)), 100, 300);
    await tester.tapAt(tester.getCenter(views.at(0)));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Best fit'));
    await tester.pumpAndSettle();
    expect(tester.state<ZoomableViewState>(views.at(0)).fit, PictureFit.whole);
    expect(tester.state<ZoomableViewState>(views.at(1)).fit, PictureFit.whole);
    await close(tester);
  });

  testWidgets('with a screen reader on, the controls do not hide', (
    tester,
  ) async {
    await open(tester, size: landscape, screenReader: true);
    await tester.pump(playerControlsTimeout * 3);
    await tester.pumpAndSettle();
    expect(
      tester
          .widget<AnimatedOpacity>(
            find.byKey(const ValueKey('player-bottom-bar')),
          )
          .opacity,
      1,
    );
    await close(tester);
  });

  testWidgets('a clip not on the phone plays straight from the camera', (
    tester,
  ) async {
    downloads.local.clear();
    final onCamera = Recording(
      front: CameraFile(
        name: frontName,
        path: '/Novatek/Movie/$frontName',
        size: 100,
        writeTime: null,
      ),
      rear: CameraFile(
        name: rearName,
        path: '/Novatek/Movie/$rearName',
        size: 100,
        writeTime: null,
      ),
      beingWritten: false,
    );
    await open(tester, clip: onCamera, connected: true);
    expect(find.byType(VideoPlayer), findsOneWidget);
    final front = video.open(frontName);
    expect(front.uri, startsWith('http://127.0.0.1'));
    expect(front.uri, endsWith('/Novatek/Movie/$frontName'));
    expect(find.byTooltip('Playing from the camera'), findsOneWidget);
    // Front or rear, one at a time: the camera's Wi-Fi cannot carry two.
    expect(find.text('Rear'), findsOneWidget);
    expect(find.text('Both'), findsNothing);

    await switchTo(tester, 'Rear');
    expect(video.open(rearName).uri, startsWith('http://127.0.0.1'));
    await close(tester);

    // With one of them saved, Both is offered again.
    downloads.local[frontName] = 100;
    await open(tester, clip: onCamera, connected: true);
    expect(find.text('Both'), findsOneWidget);
    await close(tester);
  });

  testWidgets('Both is offered only when both clips are on the phone', (
    tester,
  ) async {
    downloads.local.remove(rearName);
    await open(tester);
    expect(find.byType(VideoPlayer), findsOneWidget);
    expect(find.text('Both'), findsNothing);
    await close(tester);
  });
}

/// Stands in for the page the player is opened from, once the camera is joined.
class _WaitForCamera extends StatelessWidget {
  const _WaitForCamera();

  @override
  Widget build(BuildContext context) => const SizedBox.expand();
}
