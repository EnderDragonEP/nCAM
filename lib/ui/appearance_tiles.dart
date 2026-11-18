import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../l10n/l10n.dart';
import '../state/appearance.dart';

/// Colour and light/dark choices for the app. Needs no camera.
class AppearanceTiles extends ConsumerWidget {
  const AppearanceTiles({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final appearance = ref.watch(appearanceProvider);
    final controller = ref.read(appearanceProvider.notifier);
    final theme = Theme.of(context);
    final l = context.l10n;

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(l.colours, style: theme.textTheme.bodyLarge),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final c in ColorChoice.values)
                ChoiceChip(
                  avatar: c == ColorChoice.wallpaper
                      ? const Icon(Icons.wallpaper, size: 18)
                      : CircleAvatar(backgroundColor: c.seed, radius: 9),
                  label: Text(switch (c) {
                    ColorChoice.wallpaper => l.colorWallpaper,
                    ColorChoice.blue => l.colorBlue,
                    ColorChoice.teal => l.colorTeal,
                    ColorChoice.green => l.colorGreen,
                    ColorChoice.orange => l.colorOrange,
                    ColorChoice.red => l.colorRed,
                    ColorChoice.purple => l.colorPurple,
                  }),
                  selected: appearance.color == c,
                  showCheckmark: false,
                  onSelected: (_) => controller.setColor(c),
                ),
            ],
          ),
          const SizedBox(height: 16),
          Text(l.appearance, style: theme.textTheme.bodyLarge),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final m in AppearanceMode.values)
                ChoiceChip(
                  avatar: Icon(switch (m) {
                    AppearanceMode.system => Icons.brightness_auto_outlined,
                    AppearanceMode.light => Icons.light_mode_outlined,
                    AppearanceMode.dark => Icons.dark_mode_outlined,
                    AppearanceMode.black => Icons.contrast,
                  }, size: 18),
                  label: Text(switch (m) {
                    AppearanceMode.system => l.modeSystem,
                    AppearanceMode.light => l.modeLight,
                    AppearanceMode.dark => l.modeDark,
                    AppearanceMode.black => l.modeBlack,
                  }),
                  selected: appearance.mode == m,
                  showCheckmark: false,
                  onSelected: (_) => controller.setMode(m),
                ),
            ],
          ),
          if (appearance.color == ColorChoice.wallpaper)
            Padding(
              padding: const EdgeInsets.only(top: 12),
              child: Text(l.wallpaperNote, style: theme.textTheme.bodySmall),
            ),
        ],
      ),
    );
  }
}
