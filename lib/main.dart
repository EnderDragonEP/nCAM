import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/date_symbol_data_local.dart';

import 'l10n/l10n.dart';
import 'state/appearance.dart';
import 'state/wallpaper.dart';
import 'ui/app_shell.dart';
import 'ui/theme.dart';

Future<void> main() async {
  // Month and day names for every language (the app's localizations load them too;
  // this also covers dates formatted before they are ready).
  await initializeDateFormatting();
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
      onGenerateTitle: (context) => context.l10n.appTitle,
      // The app's texts (lib/l10n) and Flutter's own, in the phone's language when
      // there is a translation for it, otherwise in English.
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      theme: themes.light,
      darkTheme: themes.dark,
      themeMode: themes.mode,
      home: const AppShell(),
    );
  }
}
