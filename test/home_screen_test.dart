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
  testWidgets('first run: enter credentials, connect, see status', (
    tester,
  ) async {
    final fake = FakeCameraTransport();
    // Tall screen so every card on the home screen is built.
    tester.view.physicalSize = const Size(1080, 6000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          transportProvider.overrideWithValue(fake),
          downloaderProvider.overrideWithValue(FakeDownloader()),
          credentialStoreProvider.overrideWithValue(MemoryCredentialStore()),
          cameraRetryDelayProvider.overrideWithValue(Duration.zero),
          clockProbeDelayProvider.overrideWithValue(Duration.zero),
        ],
        child: const MaterialApp(home: HomeScreen()),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Not connected'), findsOneWidget);

    await tester.enterText(find.byType(TextField).at(0), 'NoodleCam');
    await tester.enterText(find.byType(TextField).at(1), 'secret');
    await tester.tap(find.widgetWithText(FilledButton, 'Connect'));
    await tester.pumpAndSettle();

    expect(find.text('Connected to NoodleCam'), findsOneWidget);
    expect(find.text('Recording'), findsOneWidget);
    expect(find.text('DVR52AFHW3_YL_V3.19_TS'), findsOneWidget);
    expect(find.textContaining('Clock synced at'), findsOneWidget);
    expect(find.text('Live view'), findsOneWidget);
    expect(find.text('Saved on this phone'), findsOneWidget);
    expect(find.text('3 recordings'), findsOneWidget);
    expect(fake.timeSet, isNotNull);
  });
}
