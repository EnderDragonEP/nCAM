import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../state/live.dart';

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

    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        leading: onBack == null ? null : BackButton(onPressed: onBack),
        title: const Text('Live view'),
        actions: [
          if (live.status == LiveStatus.playing)
            Center(
              child: Padding(
                padding: const EdgeInsets.only(right: 16),
                child: Text(
                  '${live.framesPerSecond} fps',
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
                          const CircularProgressIndicator(color: Colors.white),
                          const SizedBox(height: 12),
                          Text(
                            live.message ?? 'Starting live view…',
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
                              live.message ?? 'Live view stopped.',
                              textAlign: TextAlign.center,
                              style: const TextStyle(color: Colors.white),
                            ),
                            const SizedBox(height: 12),
                            FilledButton(
                              onPressed: controller.retry,
                              child: const Text('Try again'),
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
                            0 => 'Front',
                            1 => 'Rear',
                            2 => 'Both',
                            _ => 'View ${i + 1}',
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
                          SnackBar(
                            content: Text('Could not switch view: $error'),
                          ),
                        );
                      }
                    },
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
