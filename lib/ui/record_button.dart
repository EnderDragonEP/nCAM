import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../downloads/downloader.dart';
import '../state/downloads.dart';
import '../state/session.dart';

/// How long the record button must be held to stop recording.
const holdToStop = Duration(milliseconds: 1500);

/// Big round record button for the dock.
///
/// Not recording: a tap starts recording. Recording: a tap only explains; the button has
/// to be held while a ring fills, so a mis-tap on the road never stops the camera.
class RecordButton extends ConsumerStatefulWidget {
  const RecordButton({super.key, this.size = 64});
  final double size;

  @override
  ConsumerState<RecordButton> createState() => _RecordButtonState();
}

class _RecordButtonState extends ConsumerState<RecordButton>
    with SingleTickerProviderStateMixin {
  late final AnimationController _hold = AnimationController(
    vsync: this,
    duration: holdToStop,
  )..addStatusListener(_onHold);
  bool _working = false;

  /// What the camera was doing when the current press began; null when no press is
  /// pending (none started, or a hold already stopped recording). The release is judged
  /// by this, not by the state at release time: after a completed hold the camera has
  /// stopped, and the release must not start it again.
  bool? _pressWhileRecording;

  @override
  void dispose() {
    _hold.dispose();
    super.dispose();
  }

  void _say(String text) {
    final messenger = ScaffoldMessenger.maybeOf(context);
    messenger
      ?..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(content: Text(text), duration: const Duration(seconds: 3)),
      );
  }

  Future<void> _run(Future<String?> Function() action, String done) async {
    setState(() => _working = true);
    final error = await action();
    if (!mounted) return;
    setState(() => _working = false);
    _say(error ?? done);
  }

  void _onHold(AnimationStatus status) {
    if (status != AnimationStatus.completed) return;
    _pressWhileRecording = null;
    HapticFeedback.heavyImpact();
    _hold.reset();
    _run(
      ref.read(sessionProvider.notifier).stopRecording,
      'Recording stopped.',
    );
  }

  @override
  Widget build(BuildContext context) {
    final session = ref.watch(sessionProvider);
    final fastPhase =
        ref.watch(fastModeProvider).value?.phase ?? FastPhase.idle;
    final status = session.status;
    final recording = status?.isRecording ?? false;
    final available =
        session.connected &&
        status != null &&
        status.hasCard &&
        // Fast download holds recording off on purpose and restarts it itself.
        fastPhase == FastPhase.idle;
    final enabled = available && !_working;
    final scheme = Theme.of(context).colorScheme;
    final size = widget.size;

    final String label;
    if (!available) {
      label = fastPhase != FastPhase.idle ? 'Paused' : 'Record';
    } else if (_working) {
      label = recording ? 'Stopping…' : 'Starting…';
    } else {
      label = recording ? 'Hold to stop' : 'Record';
    }

    return Semantics(
      button: true,
      enabled: enabled,
      label: recording
          ? 'Recording. Press and hold to stop.'
          : 'Not recording. Tap to start.',
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTapDown: !enabled
            ? null
            : (_) {
                _pressWhileRecording = recording;
                if (recording) {
                  HapticFeedback.selectionClick();
                  _hold.forward(from: 0);
                }
              },
        onTapUp: (_) {
          final wasRecording = _pressWhileRecording;
          _pressWhileRecording = null;
          if (wasRecording == null || !mounted) return;
          if (wasRecording) {
            // Let go before the ring filled: explain, do not stop.
            _hold.reverse();
            HapticFeedback.lightImpact();
            _say('Hold the button to stop recording.');
          } else {
            HapticFeedback.mediumImpact();
            _run(
              ref.read(sessionProvider.notifier).startRecording,
              'Recording started.',
            );
          }
        },
        onTapCancel: () {
          if (_pressWhileRecording == true) _hold.reverse();
          _pressWhileRecording = null;
        },
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              width: size,
              height: size,
              child: Stack(
                alignment: Alignment.center,
                children: [
                  Container(
                    width: size,
                    height: size,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: !available
                          ? scheme.surfaceContainerHighest
                          : recording
                          ? Colors.red
                          : scheme.surfaceContainerHigh,
                      border: Border.all(
                        color: available ? Colors.red : scheme.outline,
                        width: 3,
                      ),
                    ),
                    child: _working
                        ? Padding(
                            padding: EdgeInsets.all(size * 0.3),
                            child: CircularProgressIndicator(
                              strokeWidth: 3,
                              color: recording ? Colors.white : Colors.red,
                            ),
                          )
                        : Icon(
                            recording ? Icons.stop_rounded : Icons.circle,
                            size: recording ? size * 0.5 : size * 0.42,
                            color: !available
                                ? scheme.outline
                                : recording
                                ? Colors.white
                                : Colors.red,
                          ),
                  ),
                  AnimatedBuilder(
                    animation: _hold,
                    builder: (context, _) => _hold.value == 0
                        ? const SizedBox.shrink()
                        : SizedBox(
                            width: size + 8,
                            height: size + 8,
                            child: CircularProgressIndicator(
                              value: _hold.value,
                              strokeWidth: 5,
                              color: scheme.onSurface,
                            ),
                          ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 4),
            Text(
              label,
              maxLines: 1,
              softWrap: false,
              overflow: TextOverflow.fade,
              style: Theme.of(context).textTheme.labelMedium
                  ?.copyWith(color: available ? null : scheme.outline),
            ),
          ],
        ),
      ),
    );
  }
}
