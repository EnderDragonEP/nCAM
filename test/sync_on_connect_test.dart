import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ncam/camera/fake_transport.dart';
import 'package:ncam/camera/transport.dart';
import 'package:ncam/downloads/fake_downloader.dart';
import 'package:ncam/state/credentials.dart';
import 'package:ncam/state/downloads.dart';
import 'package:ncam/state/session.dart';
import 'package:ncam/ui/home_screen.dart';
import 'package:ncam/ui/settings_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';

ProviderContainer makeContainer(FakeCameraTransport fake) {
  final c = ProviderContainer(
    overrides: [
      transportProvider.overrideWithValue(fake),
      credentialStoreProvider.overrideWithValue(MemoryCredentialStore()),
      cameraRetryDelayProvider.overrideWithValue(Duration.zero),
      clockProbeDelayProvider.overrideWithValue(Duration.zero),
    ],
  );
  addTearDown(c.dispose);
  c.listen(sessionProvider, (_, _) {});
  return c;
}

Future<SessionState> settle(ProviderContainer c) async {
  var idle = 0;
  for (var i = 0; i < 500; i++) {
    await Future<void>.delayed(Duration.zero);
    final s = c.read(sessionProvider);
    idle = (s.loaded && !s.busy) ? idle + 1 : 0;
    if (idle >= 5) return s;
  }
  fail('session did not settle');
}

void main() {
  int clockCommands(FakeCameraTransport fake) => fake.requests
      .where((u) => u.contains('cmd=3005') || u.contains('cmd=3006'))
      .length;

  test('on by default: connecting sets the camera clock', () async {
    SharedPreferences.setMockInitialValues({});
    final fake = FakeCameraTransport();
    final c = makeContainer(fake);
    await settle(c);
    await c.read(sessionProvider.notifier).connect('NoodleCam', 'secret');
    final s = await settle(c);
    expect(s.timeSync!.ok, isTrue);
    expect(clockCommands(fake), 2);
  });

  test('off: the clock is left alone, files are still listed', () async {
    SharedPreferences.setMockInitialValues({'sync_on_connect': false});
    final fake = FakeCameraTransport();
    final c = makeContainer(fake);
    await settle(c);
    await c.read(sessionProvider.notifier).connect('NoodleCam', 'secret');
    final s = await settle(c);

    expect(s.link, LinkState.connected);
    expect(s.timeSync, isNull);
    expect(clockCommands(fake), 0);
    expect(s.files, isNotEmpty);
    expect(fake.requests.where((u) => u.contains('cmd=3015')), isNotEmpty);

    // Nor when the link comes back.
    fake.dropLink();
    await settle(c);
    fake.restoreLink();
    await settle(c);
    expect(clockCommands(fake), 0);

    // The Sync time button still works.
    await c.read(sessionProvider.notifier).syncTime();
    await settle(c);
    expect(clockCommands(fake), 2);
  });

  group('screens', () {
    late FakeCameraTransport camera;

    Future<void> open(WidgetTester tester, Widget screen) async {
      tester.view.physicalSize = const Size(1080, 5000);
      tester.view.devicePixelRatio = 1;
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
          ],
          child: MaterialApp(home: screen),
        ),
      );
      await tester.pumpAndSettle();
    }

    setUp(() => camera = FakeCameraTransport());

    testWidgets('the Settings switch is on, turns off, and is kept', (
      tester,
    ) async {
      SharedPreferences.setMockInitialValues({});
      await open(tester, const SettingsScreen());
      final toggle = find.widgetWithText(
        SwitchListTile,
        'Sync time on connect',
      );
      expect(tester.widget<SwitchListTile>(toggle).value, isTrue);

      await tester.tap(toggle);
      await tester.pumpAndSettle();
      expect(tester.widget<SwitchListTile>(toggle).value, isFalse);
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getBool('sync_on_connect'), isFalse);
    });

    testWidgets('with it off the home page says why the clock was not set', (
      tester,
    ) async {
      SharedPreferences.setMockInitialValues({'sync_on_connect': false});
      await open(tester, const HomeScreen());
      expect(find.text('Connected to NoodleCam'), findsOneWidget);
      expect(find.text('Sync on connect is off in Settings.'), findsOneWidget);
      expect(clockCommands(camera), 0);
    });
  });
}
