import 'package:flutter/material.dart';

import '../state/appearance.dart';

/// Light and dark themes for an [Appearance]. [wallpaperLight] and [wallpaperDark] are
/// the phone's wallpaper schemes when Android provides them.
({ThemeData light, ThemeData dark, ThemeMode mode}) buildThemes(
  Appearance appearance, {
  ColorScheme? wallpaperLight,
  ColorScheme? wallpaperDark,
}) {
  final useWallpaper =
      appearance.color == ColorChoice.wallpaper &&
      wallpaperLight != null &&
      wallpaperDark != null;
  final seed = appearance.color.seed;

  final lightScheme = useWallpaper
      ? wallpaperLight
      : ColorScheme.fromSeed(seedColor: seed);
  var darkScheme = useWallpaper
      ? wallpaperDark
      : ColorScheme.fromSeed(seedColor: seed, brightness: Brightness.dark);

  final black = appearance.mode == AppearanceMode.black;
  if (black) darkScheme = pureBlack(darkScheme);

  return (
    light: ThemeData(colorScheme: lightScheme),
    dark: ThemeData(
      colorScheme: darkScheme,
      scaffoldBackgroundColor: black ? Colors.black : null,
    ),
    mode: switch (appearance.mode) {
      AppearanceMode.system => ThemeMode.system,
      AppearanceMode.light => ThemeMode.light,
      AppearanceMode.dark || AppearanceMode.black => ThemeMode.dark,
    },
  );
}

/// The dark scheme with black backgrounds. Cards and bars keep a faint lift so they stay
/// distinguishable from the background.
ColorScheme pureBlack(ColorScheme dark) => dark.copyWith(
  surface: Colors.black,
  surfaceDim: Colors.black,
  surfaceContainerLowest: Colors.black,
  surfaceContainerLow: const Color(0xFF0A0A0A),
  surfaceContainer: const Color(0xFF111111),
  surfaceContainerHigh: const Color(0xFF181818),
  surfaceContainerHighest: const Color(0xFF202020),
);
