import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ncam/state/appearance.dart';
import 'package:ncam/ui/appearance_tiles.dart';
import 'package:ncam/ui/theme.dart';
import 'package:shared_preferences/shared_preferences.dart';

Future<void> settle() async {
  for (var i = 0; i < 20; i++) {
    await Future<void>.delayed(Duration.zero);
  }
}

void main() {
  group('AppearanceController', () {
    test('defaults to wallpaper colours and following the system', () async {
      SharedPreferences.setMockInitialValues({});
      final c = ProviderContainer();
      addTearDown(c.dispose);
      c.listen(appearanceProvider, (_, _) {});
      await settle();
      expect(c.read(appearanceProvider).color, ColorChoice.wallpaper);
      expect(c.read(appearanceProvider).mode, AppearanceMode.system);
    });

    test('choices are saved and come back on the next launch', () async {
      SharedPreferences.setMockInitialValues({});
      final first = ProviderContainer();
      first.listen(appearanceProvider, (_, _) {});
      await settle();
      await first.read(appearanceProvider.notifier).setColor(ColorChoice.teal);
      await first
          .read(appearanceProvider.notifier)
          .setMode(AppearanceMode.black);
      first.dispose();

      final second = ProviderContainer();
      addTearDown(second.dispose);
      second.listen(appearanceProvider, (_, _) {});
      await settle();
      expect(second.read(appearanceProvider).color, ColorChoice.teal);
      expect(second.read(appearanceProvider).mode, AppearanceMode.black);
    });
  });

  group('buildThemes', () {
    final wallpaperLight = ColorScheme.fromSeed(seedColor: Colors.pink);
    final wallpaperDark = ColorScheme.fromSeed(
      seedColor: Colors.pink,
      brightness: Brightness.dark,
    );

    test('uses the wallpaper scheme when Android provides one', () {
      final t = buildThemes(
        const Appearance(),
        wallpaperLight: wallpaperLight,
        wallpaperDark: wallpaperDark,
      );
      expect(t.light.colorScheme.primary, wallpaperLight.primary);
      expect(t.dark.colorScheme.primary, wallpaperDark.primary);
      expect(t.mode, ThemeMode.system);
    });

    test('falls back to blue without wallpaper colours', () {
      final t = buildThemes(const Appearance());
      expect(
        t.light.colorScheme.primary,
        ColorScheme.fromSeed(seedColor: ColorChoice.blue.seed).primary,
      );
    });

    test('a preset ignores the wallpaper', () {
      final t = buildThemes(
        const Appearance(color: ColorChoice.orange),
        wallpaperLight: wallpaperLight,
        wallpaperDark: wallpaperDark,
      );
      expect(
        t.light.colorScheme.primary,
        ColorScheme.fromSeed(seedColor: ColorChoice.orange.seed).primary,
      );
    });

    test('pure black is dark with black backgrounds', () {
      final t = buildThemes(const Appearance(mode: AppearanceMode.black));
      expect(t.mode, ThemeMode.dark);
      expect(t.dark.scaffoldBackgroundColor, Colors.black);
      expect(t.dark.colorScheme.surface, Colors.black);
      // Plain dark keeps the normal dark background.
      final dark = buildThemes(const Appearance(mode: AppearanceMode.dark));
      expect(dark.mode, ThemeMode.dark);
      expect(dark.dark.scaffoldBackgroundColor, isNot(Colors.black));
    });

    test('light and system modes', () {
      expect(
        buildThemes(const Appearance(mode: AppearanceMode.light)).mode,
        ThemeMode.light,
      );
    });
  });

  testWidgets('choosing in settings updates the theme', (tester) async {
    SharedPreferences.setMockInitialValues({});
    await tester.pumpWidget(
      ProviderScope(
        child: Consumer(
          builder: (context, ref, _) {
            final themes = buildThemes(ref.watch(appearanceProvider));
            return MaterialApp(
              theme: themes.light,
              darkTheme: themes.dark,
              themeMode: themes.mode,
              home: const Scaffold(body: AppearanceTiles()),
            );
          },
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Pure black'));
    await tester.pumpAndSettle();
    final scaffold = tester.widget<Scaffold>(find.byType(Scaffold));
    expect(scaffold, isNotNull);
    expect(
      Theme.of(tester.element(find.byType(AppearanceTiles)))
          .colorScheme
          .surface,
      Colors.black,
    );

    await tester.tap(find.text('Green'));
    await tester.pumpAndSettle();
    expect(
      Theme.of(tester.element(find.byType(AppearanceTiles)))
          .colorScheme
          .primary,
      ColorScheme.fromSeed(
        seedColor: ColorChoice.green.seed,
        brightness: Brightness.dark,
      ).primary,
    );
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString('appearance_mode'), 'black');
    expect(prefs.getString('appearance_color'), 'green');
  });
}
