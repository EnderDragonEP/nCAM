import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ncam/camera/fake_transport.dart';
import 'package:ncam/downloads/fake_downloader.dart';
import 'package:ncam/state/credentials.dart';
import 'package:ncam/state/downloads.dart';
import 'package:ncam/state/session.dart';
import 'package:ncam/ui/saved_screen.dart';

void main() {
  late FakeDownloader downloader;

  Future<void> open(WidgetTester tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          // No saved camera: this screen must work without a connection.
          transportProvider.overrideWithValue(FakeCameraTransport()),
          downloaderProvider.overrideWithValue(downloader),
          credentialStoreProvider.overrideWithValue(MemoryCredentialStore()),
        ],
        child: const MaterialApp(home: SavedScreen()),
      ),
    );
    await tester.pumpAndSettle();
  }

  setUp(() => downloader = FakeDownloader());

  testWidgets('says so when nothing is saved', (tester) async {
    await open(tester);
    expect(find.textContaining('Nothing saved yet'), findsOneWidget);
  });

  testWidgets('lists saved clips as recordings without the camera', (
    tester,
  ) async {
    downloader.local.addAll({
      '2026_1111_192257_045A.TS': 71062872,
      '2026_1111_192257_046B.TS': 69704572,
      '2026_1110_184312_001A.TS': 242562488,
    });
    await open(tester);

    expect(find.text('Wed 11 Nov 2026'), findsOneWidget);
    expect(find.text('Tue 10 Nov 2026'), findsOneWidget);
    expect(find.text('19:22:57'), findsOneWidget);
    expect(find.text('Front · 68 MB'), findsOneWidget);
    expect(find.text('Rear · 66 MB'), findsOneWidget);
    expect(find.text('Front · 231 MB'), findsOneWidget);
  });

  testWidgets('deletes only the phone copy, after asking', (tester) async {
    downloader.local.addAll({
      '2026_1111_192257_045A.TS': 71062872,
      '2026_1111_192257_046B.TS': 69704572,
    });
    await open(tester);

    await tester.tap(find.byTooltip('More'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Delete from this phone'));
    await tester.pumpAndSettle();
    expect(find.text('Delete 2 files from this phone?'), findsOneWidget);
    await tester.tap(find.widgetWithText(FilledButton, 'Delete'));
    await tester.pumpAndSettle();

    expect(downloader.local, isEmpty);
    expect(find.textContaining('Nothing saved yet'), findsOneWidget);
  });

  test('the player gets the address of the phone copy', () async {
    downloader.local['a.TS'] = 1;
    expect(await downloader.localUri('a.TS'), isNotNull);
    expect(await downloader.localUri('b.TS'), isNull);
  });
}
