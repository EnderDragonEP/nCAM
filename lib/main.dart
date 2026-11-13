import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'state/appearance.dart';
import 'state/wallpaper.dart';
import 'ui/app_shell.dart';
import 'ui/theme.dart';

void main() {
  runApp(const ProviderScope(child: NcamApp()));
}

class NcamApp extends ConsumerWidget {
  const NcamApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final themes = buildThemes(
      ref.watch(appearanceProvider),
      wallpaperSeed: ref.watch(wallpaperColorProvider).value,
    );
    return MaterialApp(
      title: 'nCAM',
      theme: themes.light,
      darkTheme: themes.dark,
      themeMode: themes.mode,
      home: const AppShell(),
    );
  }
}
