import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../l10n/l10n.dart';
import '../state/dock_side.dart';
import '../state/pip.dart';
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
      // extendBody: pages run behind the floating dock instead of stopping above it.
      child: Scaffold(
        extendBody: true,
        body: page,
        // Inside the floating window only the picture is shown.
        bottomNavigationBar: ref.watch(pipProvider.select((s) => s.inPip))
            ? null
            : const Dock(),
      ),
    );
  }
}

/// One page in the floating dock.
class _Destination {
  const _Destination(this.tab, this.icon, this.selectedIcon);
  final ShellTab tab;
  final IconData icon;
  final IconData selectedIcon;

  String label(AppLocalizations l) => switch (tab) {
    ShellTab.live => l.tabLive,
    ShellTab.recordings => l.tabRecordings,
    ShellTab.saved => l.tabSaved,
    ShellTab.settings => l.settingsTitle,
  };
}

const _destinations = [
  _Destination(ShellTab.live, Icons.live_tv_outlined, Icons.live_tv),
  _Destination(
    ShellTab.recordings,
    Icons.video_library_outlined,
    Icons.video_library,
  ),
  _Destination(ShellTab.saved, Icons.smartphone_outlined, Icons.smartphone),
];

/// Floating navigation: a pill of page icons with a highlight that slides to the open
/// page, and the record button beside it, on the side chosen in Settings (right by
/// default). Settings opens from the home page. Pages scroll behind the dock over a
/// soft fade.
class Dock extends ConsumerWidget {
  const Dock({super.key});

  static const itemWidth = 56.0;
  static const itemHeight = 48.0;
  static const itemGap = 2.0;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tab = ref.watch(shellTabProvider);
    final session = ref.watch(sessionProvider);
    final side = ref.watch(recordButtonSideProvider);
    final ready = session.connected && session.status != null;
    final scheme = Theme.of(context).colorScheme;
    final background = Theme.of(context).scaffoldBackgroundColor;

    bool enabled(ShellTab t) => t != ShellTab.live || ready;
    final selected = _destinations.indexWhere((d) => d.tab == tab);

    final pill = DecoratedBox(
      decoration: BoxDecoration(
        color: scheme.surfaceContainer,
        borderRadius: BorderRadius.circular(100),
        boxShadow: const [
          BoxShadow(
            color: Color(0x33000000),
            blurRadius: 12,
            offset: Offset(0, 4),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.all(4),
        child: SizedBox(
          width:
              _destinations.length * itemWidth +
              (_destinations.length - 1) * itemGap,
          height: itemHeight,
          child: Stack(
            children: [
              // The highlight behind the open page; hidden on the home page.
              AnimatedPositioned(
                // Material 3's emphasized easing: lively, but it never overshoots,
                // so the highlight cannot slide past the end of the pill and get
                // cut off (easeOutBack did).
                duration: const Duration(milliseconds: 400),
                curve: Curves.easeInOutCubicEmphasized,
                left: (selected < 0 ? 0 : selected) * (itemWidth + itemGap),
                top: 0,
                width: itemWidth,
                height: itemHeight,
                child: AnimatedOpacity(
                  duration: const Duration(milliseconds: 200),
                  opacity: selected < 0 ? 0 : 1,
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      color: scheme.secondaryContainer,
                      borderRadius: BorderRadius.circular(100),
                    ),
                  ),
                ),
              ),
              Row(
                children: [
                  for (var i = 0; i < _destinations.length; i++) ...[
                    if (i > 0) const SizedBox(width: itemGap),
                    _DockItem(
                      destination: _destinations[i],
                      selected: i == selected,
                      enabled: enabled(_destinations[i].tab),
                      // Tapping the open page again goes back home.
                      onTap: () => ref
                          .read(shellTabProvider.notifier)
                          .show(i == selected ? null : _destinations[i].tab),
                    ),
                  ],
                ],
              ),
            ],
          ),
        ),
      ),
    );

    return DecoratedBox(
      // Pages scroll behind the dock; this fade keeps it readable over them.
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [background.withValues(alpha: 0), background],
        ),
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              if (side == RecordButtonSide.left) ...[
                const RecordButton(),
                const SizedBox(width: 12),
              ],
              // Shrinks only if the screen is very narrow or the text is huge.
              Flexible(
                child: FittedBox(fit: BoxFit.scaleDown, child: pill),
              ),
              if (side == RecordButtonSide.right) ...[
                const SizedBox(width: 12),
                const RecordButton(),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _DockItem extends StatelessWidget {
  const _DockItem({
    required this.destination,
    required this.selected,
    required this.enabled,
    required this.onTap,
  });

  final _Destination destination;
  final bool selected;
  final bool enabled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final color = !enabled
        ? scheme.outline.withValues(alpha: 0.6)
        : selected
        ? scheme.onSecondaryContainer
        : scheme.onSurfaceVariant;
    final label = destination.label(context.l10n);
    return Tooltip(
      message: label,
      child: Semantics(
        button: true,
        selected: selected,
        enabled: enabled,
        label: label,
        excludeSemantics: true,
        child: InkWell(
          onTap: enabled ? onTap : null,
          customBorder: const StadiumBorder(),
          child: SizedBox(
            width: Dock.itemWidth,
            height: Dock.itemHeight,
            child: Icon(
              selected ? destination.selectedIcon : destination.icon,
              size: 24,
              color: color,
            ),
          ),
        ),
      ),
    );
  }
}
