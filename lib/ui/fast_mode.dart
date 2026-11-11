import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../downloads/downloader.dart';
import '../state/downloads.dart';

/// The "Fast download" switch. Turning it on asks for confirmation, because it means the
/// camera records nothing while files download.
class FastModeSwitch extends ConsumerWidget {
  const FastModeSwitch({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final enabled = ref.watch(fastModeProvider).value?.enabled ?? false;
    return SwitchListTile(
      dense: true,
      secondary: const Icon(Icons.speed),
      title: const Text('Fast download'),
      subtitle: const Text(
        'Pauses recording while downloading. About 2× faster.',
      ),
      value: enabled,
      onChanged: (on) async {
        final downloader = ref.read(downloaderProvider);
        if (!on) {
          await downloader.setFastMode(false);
          return;
        }
        final confirmed = await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('Pause recording to download faster?'),
            content: const Text(
              'While files download, the camera records nothing.\n\n'
              'Recording restarts by itself when the queue is finished or cancelled. '
              'If you close the app or drive out of range before that, recording stays '
              'off until the app reconnects to the camera.\n\n'
              'Only use this while parked.',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('Cancel'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(context, true),
                child: const Text('Turn on'),
              ),
            ],
          ),
        );
        if (confirmed == true) await downloader.setFastMode(true);
      },
    );
  }
}

/// Says so, loudly, whenever recording is off because of fast download.
/// Renders nothing in the normal case.
class RecordingPausedBanner extends ConsumerStatefulWidget {
  const RecordingPausedBanner({super.key, this.margin = EdgeInsets.zero});
  final EdgeInsets margin;

  @override
  ConsumerState<RecordingPausedBanner> createState() =>
      _RecordingPausedBannerState();
}

class _RecordingPausedBannerState extends ConsumerState<RecordingPausedBanner> {
  bool _working = false;

  Future<void> _restart() async {
    setState(() => _working = true);
    try {
      await ref.read(downloaderProvider).recoverRecording();
    } catch (_) {
      // Shown through the status message.
    } finally {
      if (mounted) setState(() => _working = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final fast = ref.watch(fastModeProvider).value;
    final phase = fast?.phase ?? FastPhase.idle;
    if (phase == FastPhase.idle) return const SizedBox.shrink();

    final downloading =
        ref.watch(downloadJobsProvider).value?.any((j) => j.active) ?? false;
    final scheme = Theme.of(context).colorScheme;
    final failed = phase == FastPhase.failed;
    final text = switch (phase) {
      FastPhase.pausing => 'Pausing recording for fast download…',
      FastPhase.paused =>
        downloading
            ? 'Recording is PAUSED while files download. It restarts when the queue is finished.'
            : 'Recording is PAUSED. It was not restarted after the last fast download.',
      FastPhase.resuming => 'Restarting recording…',
      FastPhase.failed =>
        fast?.message ??
            'Recording is still OFF. The app could not restart it.',
      FastPhase.idle => '',
    };
    final busy =
        _working || phase == FastPhase.pausing || phase == FastPhase.resuming;
    final canRestart =
        !busy && (failed || (phase == FastPhase.paused && !downloading));

    return Card(
      margin: widget.margin,
      color: failed ? scheme.errorContainer : scheme.tertiaryContainer,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 8, 12),
        child: Row(
          children: [
            busy
                ? const SizedBox(
                    width: 24,
                    height: 24,
                    child: CircularProgressIndicator(strokeWidth: 2.5),
                  )
                : Icon(
                    failed ? Icons.error_outline : Icons.pause_circle_outline,
                    color: failed
                        ? scheme.onErrorContainer
                        : scheme.onTertiaryContainer,
                  ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                text,
                style: TextStyle(
                  color: failed
                      ? scheme.onErrorContainer
                      : scheme.onTertiaryContainer,
                ),
              ),
            ),
            if (canRestart)
              TextButton(
                onPressed: _restart,
                child: const Text('Restart recording'),
              ),
          ],
        ),
      ),
    );
  }
}
