import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ncam/camera/fake_transport.dart';
import 'package:ncam/downloads/fake_downloader.dart';
import 'package:ncam/state/camera_watch.dart';
import 'package:ncam/state/credentials.dart';
import 'package:ncam/state/downloads.dart';
import 'package:ncam/state/session.dart';
import 'package:ncam/ui/home_screen.dart';
import 'package:ncam/ui/settings_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  late FakeWatchPlatform watch;
  late MemoryCredentialStore store;

  late FakeCameraTransport camera;

  Future<ProviderContainer> open(
    WidgetTester tester, {
    Widget screen = const SettingsScreen(),
  }) async {
    tester.view.physicalSize = const Size(1080, 6000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          transportProvider.overrideWithValue(camera),
          downloaderProvider.overrideWithValue(FakeDownloader()),
          credentialStoreProvider.overrideWithValue(store),
          watchPlatformProvider.overrideWithValue(watch),
          cameraRetryDelayProvider.overrideWithValue(Duration.zero),
          clockProbeDelayProvider.overrideWithValue(Duration.zero),
        ],
        child: MaterialApp(home: screen),
      ),
    );
    await tester.pumpAndSettle();
    return ProviderScope.containerOf(
      tester.element(find.byType(screen.runtimeType)),
    );
  }

  Finder tile(String title) => find.widgetWithText(SwitchListTile, title);

  setUp(() {
    camera = FakeCameraTransport();
    SharedPreferences.setMockInitialValues({});
    watch = FakeWatchPlatform();
    store = MemoryCredentialStore(const CameraCredentials('NoodleCam', 'x'));
  });

  testWidgets('off by default; turning it on starts it for the saved camera', (
    tester,
  ) async {
    await open(tester);
    expect(
      tester.widget<SwitchListTile>(tile("Background clock sync")).value,
      isFalse,
    );
    expect(watch.running, isFalse);
    // The extra choices only show while it is on.
    expect(find.text('Hide notification'), findsNothing);

    await tester.tap(tile("Background clock sync"));
    await tester.pumpAndSettle();
    expect(watch.running, isTrue);
    expect(watch.ssid, 'NoodleCam');
    expect(watch.newClip, isTrue);
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getBool('camera_watch'), isTrue);

    // Cutting the misnamed clip short can be turned off.
    await tester.tap(tile('New clip after sync'));
    await tester.pumpAndSettle();
    expect(watch.newClip, isFalse);
    expect(prefs.getBool('camera_watch_new_clip'), isFalse);

    await tester.tap(tile("Background clock sync"));
    await tester.pumpAndSettle();
    expect(watch.running, isFalse);
  });

  testWidgets('the notification and battery shortcuts open Android settings', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({'camera_watch': true});
    await open(tester);
    expect(watch.running, isTrue); // started again with the app
    expect(find.text('Keeps Android from stopping the sync.'), findsOneWidget);

    await tester.tap(find.text('No battery limits'));
    await tester.pumpAndSettle();
    expect(watch.calls, contains('askUnrestricted'));
    expect(
      find.text('Keeps Android from stopping the sync. (Allowed)'),
      findsOneWidget,
    );

    await tester.tap(find.text('Hide notification'));
    await tester.pumpAndSettle();
    expect(watch.calls, contains('openNotificationSettings'));
  });

  testWidgets('needs a saved camera, and stops when it is forgotten', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({'camera_watch': true});
    final c = await open(tester);
    expect(watch.running, isTrue);
    await c.read(sessionProvider.notifier).forget();
    await tester.pumpAndSettle();
    expect(watch.running, isFalse);
    expect(find.text('Connect to the camera first.'), findsOneWidget);
  });

  testWidgets(
    'while it waits for the camera, the home page has nothing to cancel',
    (tester) async {
      SharedPreferences.setMockInitialValues({'camera_watch': true});
      await open(tester, screen: const HomeScreen());
      expect(find.text('Connected to NoodleCam'), findsOneWidget);

      // The camera goes away (the car is off): the clock sync waits for it.
      camera.dropLink();
      await tester.pumpAndSettle();
      expect(find.text('Waiting for NoodleCam'), findsOneWidget);
      expect(
        find.text('Background clock sync joins it when it starts.'),
        findsOneWidget,
      );
      expect(find.widgetWithText(TextButton, 'Cancel'), findsNothing);
    },
  );

  testWidgets('without it, a lost camera can still be cancelled', (
    tester,
  ) async {
    await open(tester, screen: const HomeScreen());
    camera.dropLink();
    await tester.pumpAndSettle();
    expect(find.text('Lost NoodleCam'), findsOneWidget);
    expect(find.widgetWithText(TextButton, 'Cancel'), findsOneWidget);
  });

  testWidgets('cannot be turned on without a saved camera', (tester) async {
    store = MemoryCredentialStore();
    await open(tester);
    expect(
      tester.widget<SwitchListTile>(tile("Background clock sync")).onChanged,
      isNull,
    );
  });
}
