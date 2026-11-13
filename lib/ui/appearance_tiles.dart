import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../state/appearance.dart';

/// Colour and light/dark choices for the app. Needs no camera.
class AppearanceTiles extends ConsumerWidget {
  const AppearanceTiles({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final appearance = ref.watch(appearanceProvider);
    final controller = ref.read(appearanceProvider.notifier);
    final theme = Theme.of(context);

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Colours', style: theme.textTheme.bodyLarge),
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
                  label: Text(c.label),
                  selected: appearance.color == c,
                  showCheckmark: false,
                  onSelected: (_) => controller.setColor(c),
                ),
            ],
          ),
          const SizedBox(height: 16),
          Text('Appearance', style: theme.textTheme.bodyLarge),
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
                  label: Text(m.label),
                  selected: appearance.mode == m,
                  showCheckmark: false,
                  onSelected: (_) => controller.setMode(m),
                ),
            ],
          ),
          if (appearance.color == ColorChoice.wallpaper)
            Padding(
              padding: const EdgeInsets.only(top: 12),
              child: Text(
                'Wallpaper colours need Android 12 or later; otherwise blue is used.',
                style: theme.textTheme.bodySmall,
              ),
            ),
        ],
      ),
    );
  }
}
