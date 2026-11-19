import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ncam/l10n/l10n.dart';
import 'package:ncam/camera/fake_transport.dart';
import 'package:ncam/camera/models.dart';
import 'package:ncam/camera/recordings.dart';
import 'package:ncam/downloads/fake_downloader.dart';
import 'package:ncam/state/credentials.dart';
import 'package:ncam/state/downloads.dart';
import 'package:ncam/state/session.dart';
import 'package:ncam/ui/clip_thumbnail.dart';
import 'package:ncam/ui/recording_search.dart';
import 'package:ncam/ui/saved_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';

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

  group('names and search', () {
    const front = '2026_1111_192257_045A.TS';
    const rear = '2026_1111_192257_046B.TS';
    const older = '2026_1110_184312_001A.TS';

    setUp(() {
      downloader.local.addAll({
        front: 71062872,
        rear: 69704572,
        older: 242562488,
      });
    });

    Future<void> nameFirst(WidgetTester tester, String name) async {
      await tester.tap(find.byTooltip('More').first);
      await tester.pumpAndSettle();
      await tester.tap(find.textContaining('ame…'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField).last, name);
      await tester.tap(find.widgetWithText(FilledButton, 'Save'));
      await tester.pumpAndSettle();
    }

    Future<void> search(WidgetTester tester, String text) async {
      if (find.byType(SearchBar).evaluate().isEmpty) {
        // Behind the search button, as on Recordings.
        await tester.tap(find.byTooltip('Search'));
        await tester.pumpAndSettle();
      }
      await tester.enterText(find.byType(SearchBar), text);
      await tester.pumpAndSettle();
    }

    testWidgets('a recording can be named, and the name is kept', (
      tester,
    ) async {
      await open(tester);
      await nameFirst(tester, '  Near   miss on the A1 ');
      expect(find.text('Near miss on the A1'), findsOneWidget);
      expect(find.text('19:22:57'), findsOneWidget); // the time stays, smaller

      final prefs = await SharedPreferences.getInstance();
      final saved = prefs.getString('clip_names')!;
      expect(saved, contains(front));
      expect(saved, contains(rear));
      expect(saved, contains('Near miss on the A1'));

      // Opening the page again: still named.
      await tester.pumpWidget(const SizedBox());
      await open(tester);
      expect(find.text('Near miss on the A1'), findsOneWidget);
    });

    testWidgets('a name can be changed and removed', (tester) async {
      await open(tester);
      await nameFirst(tester, 'Parking');
      await tester.tap(find.byTooltip('More').first);
      await tester.pumpAndSettle();
      expect(find.text('Rename…'), findsOneWidget);
      await tester.tap(find.text('Rename…'));
      await tester.pumpAndSettle();
      expect(find.widgetWithText(TextField, 'Parking'), findsOneWidget);
      await tester.tap(find.text('Remove name'));
      await tester.pumpAndSettle();
      expect(find.text('Parking'), findsNothing);
      expect(find.text('19:22:57'), findsOneWidget);
    });

    testWidgets('search finds recordings by name and by date', (tester) async {
      await open(tester);
      await nameFirst(tester, 'Near miss');
      expect(find.byType(ClipThumbnail), findsNWidgets(2));

      await search(tester, 'near');
      expect(find.byType(ClipThumbnail), findsOneWidget);
      expect(find.text('Near miss'), findsOneWidget);

      await search(tester, '10 nov');
      expect(find.byType(ClipThumbnail), findsOneWidget);
      expect(find.text('Tue 10 Nov 2026'), findsOneWidget);
      expect(find.text('Wed 11 Nov 2026'), findsNothing);

      await search(tester, 'speeding');
      expect(find.byType(ClipThumbnail), findsNothing);
      expect(find.textContaining('No saved recording matches'), findsOneWidget);

      await tester.tap(find.byTooltip('Close search'));
      await tester.pumpAndSettle();
      expect(find.byType(ClipThumbnail), findsNWidgets(2));
      expect(find.byType(SearchBar), findsNothing);
    });

    testWidgets('deleting a recording forgets its name', (tester) async {
      await open(tester);
      await nameFirst(tester, 'Near miss');
      await tester.tap(find.byTooltip('More').first);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Delete from this phone'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, 'Delete'));
      await tester.pumpAndSettle();
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString('clip_names'), isNot(contains('Near miss')));
    });

    test('search words can be in any order and written several ways', () {
      CameraFile f(String name) =>
          CameraFile(name: name, path: name, size: 1, writeTime: null);
      final r = Recording(front: f(front), rear: f(rear), beingWritten: false);
      bool hit(String q, [String? name]) =>
          recordingMatches(english, r, name, q);

      expect(hit(''), isTrue);
      expect(hit('nov 11'), isTrue);
      expect(hit('11 November'), isTrue);
      expect(hit('wednesday'), isTrue);
      expect(hit('2026-11-11'), isTrue);
      expect(hit('11/11 19:22'), isTrue);
      expect(hit('rear'), isTrue);
      expect(hit('045A'), isTrue);
      expect(hit('12 nov'), isFalse);
      expect(hit('MISS a1', 'Near miss on the A1'), isTrue);
      expect(hit('miss a2', 'Near miss on the A1'), isFalse);
    });
  });

  test('the player gets the address of the phone copy', () async {
    downloader.local['a.TS'] = 1;
    expect(await downloader.localUri('a.TS'), isNotNull);
    expect(await downloader.localUri('b.TS'), isNull);
  });
}
