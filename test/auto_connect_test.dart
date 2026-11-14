import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ncam/camera/fake_transport.dart';
import 'package:ncam/downloads/fake_downloader.dart';
import 'package:ncam/state/credentials.dart';
import 'package:ncam/state/downloads.dart';
import 'package:ncam/state/session.dart';
import 'package:ncam/ui/home_screen.dart';
import 'package:ncam/ui/settings_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
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

  testWidgets('on by default: a saved camera is joined at start-up', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    await open(tester, const HomeScreen());
    expect(camera.connectCount, 1);
    expect(find.text('Connected to NoodleCam'), findsOneWidget);
  });

  testWidgets('off: nothing is joined until Connect is tapped', (tester) async {
    SharedPreferences.setMockInitialValues({'auto_connect': false});
    await open(tester, const HomeScreen());
    expect(camera.connectCount, 0);
    expect(find.text('Not connected'), findsOneWidget);

    await tester.tap(find.text('Connect to NoodleCam'));
    await tester.pumpAndSettle();
    expect(camera.connectCount, 1);
    expect(find.text('Connected to NoodleCam'), findsOneWidget);
  });

  testWidgets('the Settings switch turns it off and the choice is kept', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    await open(tester, const SettingsScreen());
    final toggle = find.widgetWithText(SwitchListTile, 'Connect on start-up');
    expect(tester.widget<SwitchListTile>(toggle).value, isTrue);

    await tester.tap(toggle);
    await tester.pumpAndSettle();
    expect(tester.widget<SwitchListTile>(toggle).value, isFalse);
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getBool('auto_connect'), isFalse);
  });
}
