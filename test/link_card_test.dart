import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ncam/camera/fake_transport.dart';
import 'package:ncam/downloads/fake_downloader.dart';
import 'package:ncam/state/credentials.dart';
import 'package:ncam/state/downloads.dart';
import 'package:ncam/state/session.dart';
import 'package:ncam/ui/home_screen.dart';

void main() {
  late FakeCameraTransport camera;

  Future<void> open(WidgetTester tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          transportProvider.overrideWithValue(camera),
          downloaderProvider.overrideWithValue(FakeDownloader()),
          // A saved camera: the app starts joining it straight away.
          credentialStoreProvider.overrideWithValue(
            MemoryCredentialStore(const CameraCredentials('NoodleCam', 'x')),
          ),
          cameraRetryDelayProvider.overrideWithValue(Duration.zero),
          clockProbeDelayProvider.overrideWithValue(Duration.zero),
        ],
        child: const MaterialApp(home: HomeScreen()),
      ),
    );
    await tester.pump();
    await tester.pump();
  }

  setUp(() => camera = FakeCameraTransport()..holdConnect = true);

  testWidgets('while joining, the button says Cancel and cancels cleanly', (
    tester,
  ) async {
    await open(tester);
    expect(find.text('Joining NoodleCam…'), findsOneWidget);
    expect(find.text('Cancel'), findsOneWidget);
    expect(find.text('Disconnect'), findsNothing);

    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(find.text('Not connected'), findsOneWidget);
    // Cancelling is not a failure: no error card.
    expect(find.textContaining('Could not join'), findsNothing);
    expect(find.text('Connect to NoodleCam'), findsOneWidget);
  });

  testWidgets('once connected, the button says Disconnect', (tester) async {
    await open(tester);
    camera.finishConnect();
    await tester.pumpAndSettle();
    expect(find.text('Connected to NoodleCam'), findsOneWidget);
    expect(find.text('Disconnect'), findsOneWidget);
    expect(find.text('Cancel'), findsNothing);
  });

  testWidgets('while rejoining a lost camera, the button says Cancel', (
    tester,
  ) async {
    await open(tester);
    camera.finishConnect();
    await tester.pumpAndSettle();
    camera.dropLink();
    await tester.pumpAndSettle();
    expect(find.text('Lost NoodleCam'), findsOneWidget);
    expect(find.text('Cancel'), findsOneWidget);

    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(find.text('Not connected'), findsOneWidget);
  });
}
