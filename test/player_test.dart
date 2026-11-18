import 'package:flutter/material.dart';
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
import 'package:video_player/video_player.dart';
import 'package:video_player_platform_interface/video_player_platform_interface.dart';

import 'fake_video_player.dart';

// The rear clip's name is a second later than the front one's, as on the camera.
const frontName = '2026_1111_192257_045A.TS';
const rearName = '2026_1111_192258_046B.TS';

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

  Future<void> open(WidgetTester tester, {bool landscape = false}) async {
    tester.view.physicalSize = landscape
        ? const Size(2400, 1080)
        : const Size(1080, 2400);
    tester.view.devicePixelRatio = 2.6;
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
    expect(find.text('Front'), findsWidgets);
    expect(find.text('Rear'), findsWidgets);
    final front = video.open(frontName);
    final rear = video.open(rearName);
    expect(video.live, hasLength(2));
    expect(front.position, const Duration(seconds: 20));
    // The rear clip started a second later: 19 s into it is the same moment.
    expect(rear.position, const Duration(seconds: 19));
    expect(front.playing && rear.playing, isTrue);
    // Only one soundtrack.
    expect(rear.volume, 0);
    expect(front.volume, 1);

    // The controls move both.
    await tester.tap(find.byTooltip('Forward 10 seconds'));
    await tester.pumpAndSettle();
    expect(front.position, const Duration(seconds: 30));
    expect(rear.position, const Duration(seconds: 29));

    await tester.tap(find.byTooltip('Pause'));
    await tester.pumpAndSettle();
    expect(front.playing || rear.playing, isFalse);

    await tester.tap(find.byTooltip('Play'));
    await tester.pumpAndSettle();
    expect(front.playing && rear.playing, isTrue);
    await close(tester);
  });

  testWidgets('a rear clip that drifts is pulled back in step', (tester) async {
    await open(tester);
    await switchTo(tester, 'Both');
    final front = video.open(frontName);
    final rear = video.open(rearName);

    front.position = const Duration(seconds: 30);
    rear.position = const Duration(seconds: 27);
    await tester.pump(const Duration(milliseconds: 1100));
    expect(rear.seeks.last, const Duration(seconds: 29));
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

    await open(tester, landscape: true);
    await switchTo(tester, 'Both');
    players = find.byType(VideoPlayer);
    a = tester.getCenter(players.at(0));
    b = tester.getCenter(players.at(1));
    expect(b.dx, greaterThan(a.dx + 50));
    expect(b.dy, closeTo(a.dy, 1));
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
    expect(video.open(rearName).position, const Duration(seconds: 11));
    expect(video.open(rearName).volume, 1);
    expect(
      pip.last!.aspectWidth / pip.last!.aspectHeight,
      closeTo(16 / 9, 0.01),
    );
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
