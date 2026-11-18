import 'dart:convert';

import 'package:flutter/material.dart';
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

  Future<void> open(WidgetTester tester, {Size size = portrait}) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = dpr;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          transportProvider.overrideWithValue(FakeCameraTransport()),
          downloaderProvider.overrideWithValue(downloads),
          pipPlatformProvider.overrideWithValue(pip),
        ],
        child: MaterialApp(
          home: PlayerScreen(recording: recording, lens: Lens.front),
        ),
      ),
    );
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

    // Paused, they stay up.
    await tester.tap(find.byTooltip('Pause'));
    await tester.pumpAndSettle();
    await tester.pump(const Duration(seconds: 6));
    await tester.pumpAndSettle();
    expect(shown(), 1);
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
