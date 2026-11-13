import 'package:dynamic_color/dynamic_color.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'state/appearance.dart';
import 'ui/app_shell.dart';
import 'ui/theme.dart';

void main() {
  runApp(const ProviderScope(child: NcamApp()));
}

class NcamApp extends ConsumerWidget {
  const NcamApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final appearance = ref.watch(appearanceProvider);
    return DynamicColorBuilder(
      builder: (lightDynamic, darkDynamic) {
        final themes = buildThemes(
          appearance,
          wallpaperLight: lightDynamic?.harmonized(),
          wallpaperDark: darkDynamic?.harmonized(),
        );
        return MaterialApp(
          title: 'nCAM',
          theme: themes.light,
          darkTheme: themes.dark,
          themeMode: themes.mode,
          home: const AppShell(),
        );
      },
    );
  }
}
