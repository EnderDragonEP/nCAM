import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ncam/camera/camera_api.dart';
import 'package:ncam/camera/fake_transport.dart';
import 'package:ncam/camera/models.dart';
import 'package:ncam/camera/transport.dart';
import 'package:ncam/downloads/fake_downloader.dart';
import 'package:ncam/state/credentials.dart';
import 'package:ncam/state/downloads.dart';
import 'package:ncam/state/session.dart';
import 'package:ncam/state/settings.dart';
import 'package:ncam/ui/settings_screen.dart';

void main() {
  late FakeCameraTransport camera;
  late MemoryCredentialStore store;

  overrides() => [
    transportProvider.overrideWithValue(camera),
    downloaderProvider.overrideWithValue(FakeDownloader()),
    credentialStoreProvider.overrideWithValue(store),
    cameraRetryDelayProvider.overrideWithValue(Duration.zero),
    clockProbeDelayProvider.overrideWithValue(Duration.zero),
    cameraSettleDelayProvider.overrideWithValue(Duration.zero),
    wifiRestartDelayProvider.overrideWithValue(Duration.zero),
  ];

  List<String> commands() => [
    for (final u in camera.requests)
      Uri.parse(u).query.replaceFirst('custom=1&', ''),
  ];

  setUp(() {
    camera = FakeCameraTransport();
    store = MemoryCredentialStore(
      const CameraCredentials('NoodleCam', 'oldpass1'),
    );
  });

  group('readSettings', () {
    test('merges the real option list with current values', () async {
      await camera.connect(ssid: 'NoodleCam', password: 'x');
      final s = await NovatekCameraApi(camera).readSettings();

      expect(s.listed.map((x) => x.name), [
        'PHOTO_SIZE',
        'MOVIE_SIZE',
        'EV',
        'MOVIE_AUDIO',
        'AUTO_POWER_OFF',
      ]);
      final audio = s.listed.firstWhere((x) => x.name == 'MOVIE_AUDIO');
      expect(audio.cmd, 2007);
      expect(audio.changeable, isTrue);
      expect(audio.current!.label, 'ON');
      final power = s.listed.firstWhere((x) => x.name == 'AUTO_POWER_OFF');
      expect(power.options.map((o) => o.label), [
        'ON',
        '3MIN',
        '5MIN',
        '10MIN',
      ]);
      expect(power.value, 0);
      expect(s.listed.first.changeable, isFalse);

      // Reported but not listed with choices: read-only.
      expect(s.other.keys, containsAll([2003, 2011, 3028]));
      expect(s.other.keys, isNot(contains(2007)));
    });

    test('option labels are tidied only where the meaning is certain', () {
      expect(prettyOption('3MIN'), '3 min');
      expect(prettyOption('ON'), 'On');
      expect(
        prettyOption('1920x1080P30_1920x1080P30'),
        '1920x1080P30_1920x1080P30',
      );
    });
  });

  group('SettingsController', () {
    late ProviderContainer c;
    late CameraSettings settings;

    Future<void> start() async {
      await camera.connect(ssid: 'NoodleCam', password: 'x');
      c = ProviderContainer(overrides: overrides());
      addTearDown(c.dispose);
      c.listen(settingsProvider, (_, _) {});
      settings = await c.read(settingsProvider.future);
      camera.requests.clear();
    }

    CameraSetting named(String name) =>
        settings.listed.firstWhere((s) => s.name == name);

    test('changes a setting with the camera index and re-reads it', () async {
      await start();
      final message = await c
          .read(settingsProvider.notifier)
          .change(named('AUTO_POWER_OFF'), 2);
      expect(message, isNull);
      expect(commands(), contains('cmd=3007&par=2'));
      expect(camera.settingValues[3007], 2);
      final fresh = c.read(settingsProvider).value!;
      expect(
        fresh.listed.firstWhere((s) => s.cmd == 3007).current!.label,
        '5MIN',
      );
      // Recording was on and stayed on: no start command.
      expect(commands().where((q) => q.startsWith('cmd=2001')), isEmpty);
    });

    test('restarts recording if the change stopped it', () async {
      camera.settingStopsRecording = true;
      await start();
      final message = await c
          .read(settingsProvider.notifier)
          .change(named('MOVIE_AUDIO'), 0);
      expect(message, contains('recording was restarted'));
      expect(commands(), contains('cmd=2001&par=1'));
      expect(camera.recordingSeconds, greaterThan(0));
    });

    test('reports a refusal and leaves the value alone', () async {
      camera.setSettingStatus = -256;
      await start();
      final message = await c
          .read(settingsProvider.notifier)
          .change(named('MOVIE_AUDIO'), 0);
      expect(message, contains('refused'));
      expect(camera.settingValues[2007], 1);
    });

    test('format stops recording, formats, then restarts recording', () async {
      await start();
      final message = await c.read(settingsProvider.notifier).formatCard();
      final order = commands()
          .where((q) => q.startsWith('cmd=2001') || q.startsWith('cmd=3010'))
          .toList();
      expect(order, ['cmd=2001&par=0', 'cmd=3010&par=1', 'cmd=2001&par=1']);
      expect(camera.formatted, isTrue);
      expect(message, contains('Recording was restarted'));
    });

    test('format leaves a stopped camera stopped', () async {
      camera.recordingSeconds = 0;
      await start();
      await c.read(settingsProvider.notifier).formatCard();
      expect(commands().where((q) => q.startsWith('cmd=2001')), isEmpty);
      expect(camera.formatted, isTrue);
    });

    test('factory reset sends the reset command', () async {
      await start();
      final message = await c.read(settingsProvider.notifier).factoryReset();
      expect(camera.factoryReset, isTrue);
      expect(message, contains('Factory settings restored'));
    });
  });

  test(
    'changing Wi-Fi sends name, password, apply; saves; reconnects',
    () async {
      final c = ProviderContainer(overrides: overrides());
      addTearDown(c.dispose);
      c.listen(sessionProvider, (_, _) {});
      for (var i = 0; i < 50; i++) {
        await Future<void>.delayed(Duration.zero);
      }
      expect(c.read(sessionProvider).link, LinkState.connected);
      camera.requests.clear();

      final error = await c
          .read(sessionProvider.notifier)
          .changeWifi('NewCam', 'newpass99');
      expect(error, isNull);
      final sent = commands().where((q) => q.startsWith('cmd=30')).take(3);
      expect(sent, [
        'cmd=3003&str=NewCam',
        'cmd=3004&str=newpass99',
        'cmd=3021',
      ]);
      expect(camera.wifiApplied, isTrue);
      final saved = await store.load();
      expect(saved!.ssid, 'NewCam');
      expect(saved.password, 'newpass99');
      expect(c.read(sessionProvider).link, LinkState.connected);
    },
  );

  group('SettingsScreen', () {
    Future<void> open(WidgetTester tester) async {
      tester.view.physicalSize = const Size(1080, 5000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        ProviderScope(
          overrides: overrides(),
          child: const MaterialApp(home: SettingsScreen()),
        ),
      );
      await tester.pumpAndSettle();
    }

    testWidgets('shows what the camera supports and nothing else', (
      tester,
    ) async {
      await open(tester);
      expect(find.text('Record audio'), findsOneWidget);
      expect(find.text('Auto power off'), findsOneWidget);
      expect(find.text('Video resolution'), findsOneWidget);
      expect(find.text('Fixed on this camera'), findsNWidgets(3));
      // Not listed by the camera, so not offered as a setting.
      expect(find.text('G-sensor'), findsNothing);
      expect(find.text('Loop recording'), findsNothing);
    });

    testWidgets('audio switch sends the change', (tester) async {
      await open(tester);
      await tester.tap(find.byType(Switch));
      await tester.pumpAndSettle();
      expect(camera.settingValues[2007], 0);
    });

    testWidgets('picking an option sends its index', (tester) async {
      await open(tester);
      await tester.tap(find.text('Auto power off'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('10 min'));
      await tester.pumpAndSettle();
      expect(camera.settingValues[3007], 3);
      expect(find.text('10 min'), findsOneWidget);
    });

    testWidgets('format needs an explicit confirmation', (tester) async {
      await open(tester);
      await tester.tap(find.text('Format SD card'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(camera.formatted, isFalse);

      await tester.tap(find.text('Format SD card'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Erase everything'));
      await tester.pumpAndSettle();
      expect(camera.formatted, isTrue);
    });

    testWidgets('a short Wi-Fi password is rejected before anything is sent', (
      tester,
    ) async {
      await open(tester);
      await tester.tap(find.text('Change Wi-Fi name and password'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField).at(1), 'short');
      await tester.tap(find.text('Change'));
      await tester.pumpAndSettle();
      expect(find.textContaining('Password: 8 to 63'), findsOneWidget);
      expect(camera.wifiSsid, isNull);
    });
  });
}
