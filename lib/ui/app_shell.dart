import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../state/session.dart';
import '../state/wallpaper.dart';
import 'home_screen.dart';
import 'live_screen.dart';
import 'record_button.dart';
import 'recordings_screen.dart';
import 'saved_screen.dart';
import 'settings_screen.dart';

enum ShellTab { live, recordings, saved, settings }

/// Which page the dock shows. Null is the home page (connection, status, clock).
final shellTabProvider = NotifierProvider<ShellTabController, ShellTab?>(
  ShellTabController.new,
);

class ShellTabController extends Notifier<ShellTab?> {
  @override
  ShellTab? build() => null;

  void show(ShellTab? tab) => state = tab;
}

/// The app's frame: the page on top, and a dock at the bottom that is always in reach,
/// with the record button in the middle.
class AppShell extends ConsumerStatefulWidget {
  const AppShell({super.key});

  @override
  ConsumerState<AppShell> createState() => _AppShellState();
}

class _AppShellState extends ConsumerState<AppShell> {
  late final AppLifecycleListener _lifecycle;

  @override
  void initState() {
    super.initState();
    // Nothing is polled while the app is in the background.
    _lifecycle = AppLifecycleListener(
      onResume: () {
        ref.read(sessionProvider.notifier).setForeground(true);
        // The wallpaper may have changed while the app was away.
        ref.invalidate(wallpaperColorProvider);
      },
      onHide: () => ref.read(sessionProvider.notifier).setForeground(false),
    );
  }

  @override
  void dispose() {
    _lifecycle.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final tab = ref.watch(shellTabProvider);
    void home() => ref.read(shellTabProvider.notifier).show(null);

    final page = switch (tab) {
      null => const HomeScreen(),
      ShellTab.live => LiveScreen(onBack: home),
      ShellTab.recordings => RecordingsScreen(onBack: home),
      ShellTab.saved => SavedScreen(onBack: home),
      ShellTab.settings => SettingsScreen(onBack: home),
    };

    return PopScope(
      // Back goes to the home page first, then leaves the app.
      canPop: tab == null,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) home();
      },
      child: Scaffold(body: page, bottomNavigationBar: const Dock()),
    );
  }
}

class Dock extends ConsumerWidget {
  const Dock({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tab = ref.watch(shellTabProvider);
    final session = ref.watch(sessionProvider);
    final ready = session.connected && session.status != null;
    final scheme = Theme.of(context).colorScheme;

    Widget item(ShellTab target, IconData icon, String label, bool enabled) =>
        Expanded(
          child: _DockItem(
            icon: icon,
            label: label,
            selected: tab == target,
            enabled: enabled,
            // Tapping the open page again goes back home.
            onTap: () => ref
                .read(shellTabProvider.notifier)
                .show(tab == target ? null : target),
          ),
        );

    return Material(
      color: scheme.surfaceContainer,
      elevation: 8,
      child: SafeArea(
        top: false,
        // Sized by its contents, so large system text never overflows it.
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 6),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              item(ShellTab.live, Icons.live_tv_outlined, 'Live', ready),
              item(
                ShellTab.recordings,
                Icons.video_library_outlined,
                'Recordings',
                true,
              ),
              const Expanded(child: RecordButton()),
              item(ShellTab.saved, Icons.smartphone, 'Saved', true),
              item(
                ShellTab.settings,
                Icons.settings_outlined,
                'Settings',
                true, // app settings work without the camera
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _DockItem extends StatelessWidget {
  const _DockItem({
    required this.icon,
    required this.label,
    required this.selected,
    required this.enabled,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final bool selected;
  final bool enabled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final color = !enabled
        ? scheme.outline
        : selected
        ? scheme.primary
        : scheme.onSurfaceVariant;
    return Semantics(
      button: true,
      selected: selected,
      enabled: enabled,
      label: label,
      excludeSemantics: true,
      child: InkWell(
        onTap: enabled ? onTap : null,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 4,
                ),
                decoration: BoxDecoration(
                  color: selected ? scheme.secondaryContainer : null,
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Icon(icon, size: 28, color: color),
              ),
              const SizedBox(height: 4),
              Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.fade,
                softWrap: false,
                style: Theme.of(context).textTheme.labelMedium
                    ?.copyWith(color: color),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
