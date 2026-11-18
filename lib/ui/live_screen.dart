import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../l10n/l10n.dart';
import '../state/live.dart';
import '../state/pip.dart';

class LiveScreen extends ConsumerWidget {
  const LiveScreen({super.key, this.onBack});

  /// When shown inside the dock, the back arrow returns to the home page.
  final VoidCallback? onBack;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final live = ref.watch(liveProvider);
    final controller = ref.read(liveProvider.notifier);
    final frame = live.frame;
    final view = live.viewIndex;
    final l = context.l10n;

    return PipHost(
      // Closing the floating window ends the live stream.
      onClosed: onBack ?? () => Navigator.maybePop(context),
      pipChild: _LivePip(live: live),
      child: Scaffold(
        backgroundColor: Colors.black,
        appBar: AppBar(
          backgroundColor: Colors.black,
          foregroundColor: Colors.white,
          leading: onBack == null ? null : BackButton(onPressed: onBack),
          title: Text(l.liveTitle),
          actions: [
            const PipButton(color: Colors.white),
            if (live.status == LiveStatus.playing)
              Center(
                child: Padding(
                  padding: const EdgeInsets.only(right: 16),
                  child: Text(
                    l.fps(live.framesPerSecond),
                    style: const TextStyle(color: Colors.white70),
                  ),
                ),
              ),
          ],
        ),
        body: SafeArea(
          child: Column(
            children: [
              Expanded(
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    if (frame != null)
                      Image.memory(
                        frame,
                        fit: BoxFit.contain,
                        // Keep showing the previous picture until the next one is decoded.
                        gaplessPlayback: true,
                        errorBuilder: (_, _, _) => const SizedBox.shrink(),
                      ),
                    if (live.status == LiveStatus.connecting)
                      Center(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const CircularProgressIndicator(
                              color: Colors.white,
                            ),
                            const SizedBox(height: 12),
                            Text(
                              live.message?.call(l) ?? l.liveStarting,
                              style: const TextStyle(color: Colors.white),
                            ),
                          ],
                        ),
                      ),
                    if (live.status == LiveStatus.failed)
                      Center(
                        child: Padding(
                          padding: const EdgeInsets.all(24),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                live.message?.call(l) ?? l.liveStoppedShort,
                                textAlign: TextAlign.center,
                                style: const TextStyle(color: Colors.white),
                              ),
                              const SizedBox(height: 12),
                              FilledButton(
                                onPressed: controller.retry,
                                child: Text(l.tryAgain),
                              ),
                            ],
                          ),
                        ),
                      ),
                  ],
                ),
              ),
              if (view != null)
                Padding(
                  padding: const EdgeInsets.all(12),
                  child: Theme(
                    data: ThemeData.dark(useMaterial3: true),
                    child: SegmentedButton<int>(
                      segments: [
                        for (final i in {0, 1, 2, view}.toList()..sort())
                          ButtonSegment(
                            value: i,
                            // Checked on the real camera.
                            label: Text(switch (i) {
                              0 => l.front,
                              1 => l.rear,
                              2 => l.both,
                              _ => l.viewNumber(i + 1),
                            }),
                          ),
                      ],
                      selected: {view},
                      showSelectedIcon: false,
                      onSelectionChanged: (s) async {
                        final messenger = ScaffoldMessenger.of(context);
                        final error = await controller.setView(s.first);
                        if (error != null) {
                          messenger.showSnackBar(
                            SnackBar(content: Text(l.viewSwitchFailed(error))),
                          );
                        }
                      },
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Live view inside the floating window: just the picture.
class _LivePip extends StatelessWidget {
  const _LivePip({required this.live});
  final LiveState live;

  @override
  Widget build(BuildContext context) {
    final frame = live.frame;
    return ColoredBox(
      color: Colors.black,
      child: Stack(
        fit: StackFit.expand,
        children: [
          if (frame != null)
            Image.memory(
              frame,
              fit: BoxFit.contain,
              gaplessPlayback: true,
              errorBuilder: (_, _, _) => const SizedBox.shrink(),
            ),
          if (live.status == LiveStatus.connecting)
            const Center(
              child: SizedBox(
                width: 24,
                height: 24,
                child: CircularProgressIndicator(
                  strokeWidth: 2.5,
                  color: Colors.white,
                ),
              ),
            ),
          // Stopped: say so instead of spinning forever. Tap the window to
          // expand it and use Try again.
          if (live.status == LiveStatus.failed)
            const Center(
              child: Icon(Icons.videocam_off_outlined, color: Colors.white70),
            ),
        ],
      ),
    );
  }
}
