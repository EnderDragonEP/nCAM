import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ncam/ui/zoomable_view.dart';

void main() {
  const picture = Key('picture');

  /// A 16:9 picture in a [box]-sized space.
  Future<void> open(
    WidgetTester tester,
    Size box, {
    VoidCallback? onTap,
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Align(
            alignment: Alignment.topLeft,
            child: GestureDetector(
              onTap: onTap,
              child: SizedBox.fromSize(
                size: box,
                child: const ZoomableView(
                  aspectRatio: 16 / 9,
                  child: ColoredBox(key: picture, color: Colors.green),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Rect shown(WidgetTester tester) => tester.getRect(find.byKey(picture));

  /// Two fingers, [from] apart, spread to [to] apart around the middle of the space.
  Future<void> pinch(
    WidgetTester tester,
    Offset centre,
    double from,
    double to,
  ) async {
    final a = await tester.startGesture(centre - Offset(from / 2, 0));
    final b = await tester.startGesture(centre + Offset(from / 2, 0));
    for (var i = 1; i <= 5; i++) {
      final d = from + (to - from) * i / 5;
      await a.moveTo(centre - Offset(d / 2, 0));
      await b.moveTo(centre + Offset(d / 2, 0));
      await tester.pump(const Duration(milliseconds: 16));
    }
    await a.up();
    await b.up();
    await tester.pumpAndSettle();
  }

  // Landscape phone, wider than 16:9: the picture has bars at the sides.
  const wide = Size(800, 370);

  testWidgets('starts showing the whole picture', (tester) async {
    await open(tester, wide);
    final r = shown(tester);
    expect(r.height, closeTo(370, 0.5));
    expect(r.width, closeTo(370 * 16 / 9, 0.5));
    expect(r.center.dx, closeTo(400, 0.5));
  });

  testWidgets('pinching out fills the space; pinching in shows it all again', (
    tester,
  ) async {
    await open(tester, wide);
    await pinch(tester, const Offset(400, 185), 100, 130);
    var r = shown(tester);
    // Filled: no bars, the top and bottom cut off.
    expect(r.width, closeTo(800, 0.5));
    expect(r.height, greaterThan(370));
    expect(find.text('Zoomed to fill'), findsOneWidget);

    await pinch(tester, const Offset(400, 185), 200, 150);
    r = shown(tester);
    expect(r.height, closeTo(370, 0.5));
    expect(find.text('Best fit'), findsOneWidget);

    // The label goes away by itself.
    await tester.pump(const Duration(seconds: 2));
    expect(find.text('Best fit'), findsNothing);
  });

  testWidgets('pinching further zooms in, and a drag looks around', (
    tester,
  ) async {
    await open(tester, wide);
    await pinch(tester, const Offset(400, 185), 100, 250);
    final zoomed = shown(tester);
    expect(zoomed.height, closeTo(370 * 2.5, 2));
    expect(find.textContaining('2.5×'), findsOneWidget);

    await tester.dragFrom(const Offset(400, 185), const Offset(-200, 0));
    await tester.pumpAndSettle();
    final moved = shown(tester);
    expect(moved.size, zoomed.size);
    expect(moved.left, lessThan(zoomed.left));
    // Never past the picture's edge.
    expect(moved.right, greaterThanOrEqualTo(800 - 0.5));
  });

  testWidgets('on a tall screen pinching just zooms, with no jump to fill', (
    tester,
  ) async {
    await open(tester, const Size(380, 600));
    await pinch(tester, const Offset(190, 300), 100, 120);
    expect(shown(tester).width, closeTo(380 * 1.2, 2));
  });

  testWidgets('a small pinch still zooms where a tap is also listened for', (
    tester,
  ) async {
    var taps = 0;
    await open(tester, wide, onTap: () => taps++);
    await pinch(tester, const Offset(400, 185), 100, 120);
    expect(shown(tester).width, closeTo(800, 0.5));
    expect(taps, 0);
  });

  testWidgets('a drag on the whole picture moves nothing; taps get through', (
    tester,
  ) async {
    var taps = 0;
    await open(tester, wide, onTap: () => taps++);
    final before = shown(tester);
    await tester.dragFrom(const Offset(400, 185), const Offset(150, 60));
    await tester.pumpAndSettle();
    expect(shown(tester), before);
    await tester.tapAt(const Offset(400, 185));
    expect(taps, 1);
  });

  test('reads the picture size from a JPEG header', () {
    final jpeg = Uint8List.fromList([
      0xFF, 0xD8, // start of image
      0xFF, 0xE0, 0x00, 0x04, 0x00, 0x00, // APP0, 2 bytes of data
      0xFF, 0xC0, 0x00, 0x11, 0x08, // SOF0, 8-bit
      0x01, 0x68, // height 360
      0x02, 0x80, // width 640
      0x03, 0x01, 0x22, 0x00, 0x02, 0x11, 0x01, 0x03, 0x11, 0x01,
    ]);
    expect(jpegSize(jpeg), const Size(640, 360));
    expect(jpegSize(Uint8List.fromList([1, 2, 3, 4])), isNull);
  });
}
