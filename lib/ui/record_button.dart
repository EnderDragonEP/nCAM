import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../downloads/downloader.dart';
import '../l10n/l10n.dart';
import '../state/downloads.dart';
import '../state/session.dart';

/// How long the record button must be held to stop recording.
const holdToStop = Duration(milliseconds: 1500);

/// How much bigger the record button grows while a finger is on it, so the icon and
/// the hold ring show around the thumb instead of under it.
const pressedScale = 2.3;

/// Big round record button for the dock.
///
/// Not recording: a tap starts recording. Recording: a tap only explains; the button has
/// to be held while a ring fills, so a mis-tap on the road never stops the camera.
/// While pressed, the button grows above the thumb, drawn over the rest of the page.
class RecordButton extends ConsumerStatefulWidget {
  const RecordButton({super.key, this.size = 56});
  final double size;

  @override
  ConsumerState<RecordButton> createState() => _RecordButtonState();
}

class _RecordButtonState extends ConsumerState<RecordButton>
    with TickerProviderStateMixin {
  late final AnimationController _hold = AnimationController(
    vsync: this,
    duration: holdToStop,
  )..addStatusListener(_onHold);

  /// 0 at rest, 1 fully enlarged.
  late final AnimationController _grow =
      AnimationController(
        vsync: this,
        duration: const Duration(milliseconds: 140),
      )..addStatusListener((status) {
        if (status == AnimationStatus.dismissed && _portal.isShowing) {
          _portal.hide();
          if (mounted) setState(() {});
        }
      });

  /// The enlarged copy is drawn in the page's overlay, so the dock pill beside the
  /// button cannot paint over it.
  final _portal = OverlayPortalController();
  final _link = LayerLink();

  /// Sideways nudge that keeps the enlarged button on the screen.
  double _shift = 0;

  bool _working = false;

  /// What the camera was doing when the current press began; null when no press is
  /// pending (none started, or a hold already stopped recording). The release is judged
  /// by this, not by the state at release time: after a completed hold the camera has
  /// stopped, and the release must not start it again.
  bool? _pressWhileRecording;

  @override
  void dispose() {
    _hold.dispose();
    _grow.dispose();
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

  Future<void> _run(Future<Msg?> Function() action, Msg done) async {
    setState(() => _working = true);
    final error = await action();
    if (!mounted) return;
    setState(() => _working = false);
    _say((error ?? done)(context.l10n));
  }

  void _onHold(AnimationStatus status) {
    if (status != AnimationStatus.completed) return;
    _pressWhileRecording = null;
    HapticFeedback.heavyImpact();
    _hold.reset();
    _run(
      ref.read(sessionProvider.notifier).stopRecording,
      (l) => l.recordingStopped,
    );
  }

  void _enlarge() {
    // The button grows upwards from its bottom edge (the thumb comes from below) and
    // is moved in from the screen edge if it would stick out.
    var shift = 0.0;
    final box = context.findRenderObject() as RenderBox?;
    if (box != null && box.hasSize) {
      const margin = 8.0;
      final width = MediaQuery.sizeOf(context).width;
      final centre = box.localToGlobal(box.size.center(Offset.zero)).dx;
      final radius = widget.size * pressedScale / 2;
      if (centre - radius < margin) {
        shift = margin - (centre - radius);
      } else if (centre + radius > width - margin) {
        shift = width - margin - (centre + radius);
      }
    }
    setState(() => _shift = shift);
    _portal.show();
    _grow.forward();
  }

  void _shrink() => _grow.reverse();

  Widget _face({
    required bool available,
    required bool recording,
    required FastPhase fastPhase,
    required ColorScheme scheme,
  }) {
    final size = widget.size;
    return SizedBox(
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
                  : scheme.surfaceContainer,
              border: Border.all(
                color: available ? Colors.red : scheme.outline,
                width: 3,
              ),
              boxShadow: const [
                BoxShadow(
                  color: Color(0x33000000),
                  blurRadius: 12,
                  offset: Offset(0, 4),
                ),
              ],
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
                    !available && fastPhase != FastPhase.idle
                        ? Icons.pause_rounded
                        : recording
                        ? Icons.stop_rounded
                        : Icons.circle,
                    size: recording ? size * 0.5 : size * 0.42,
                    color: !available
                        ? scheme.outline
                        : recording
                        ? Colors.white
                        : Colors.red,
                  ),
          ),
          // The ring that fills while the button is held to stop.
          AnimatedBuilder(
            animation: _hold,
            builder: (context, _) => _hold.value == 0
                ? const SizedBox.shrink()
                : SizedBox(
                    width: size,
                    height: size,
                    child: CircularProgressIndicator(
                      value: _hold.value,
                      strokeWidth: 5,
                      color: recording ? Colors.white : scheme.onSurface,
                    ),
                  ),
          ),
        ],
      ),
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
    final face = _face(
      available: available,
      recording: recording,
      fastPhase: fastPhase,
      scheme: scheme,
    );

    // No visible label in the floating dock: the state is in the icon and colour, and
    // spelled out for screen readers here.
    final l = context.l10n;
    final String label;
    if (!available) {
      label = fastPhase != FastPhase.idle
          ? l.a11yRecordPaused
          : l.a11yRecordUnavailable;
    } else if (_working) {
      label = recording ? l.a11yStopping : l.a11yStarting;
    } else {
      label = recording ? l.a11yRecording : l.a11yNotRecording;
    }

    return OverlayPortal(
      controller: _portal,
      overlayChildBuilder: (context) => Align(
        alignment: Alignment.topLeft,
        child: CompositedTransformFollower(
          link: _link,
          showWhenUnlinked: false,
          targetAnchor: Alignment.center,
          followerAnchor: Alignment.center,
          // Only a picture: the finger stays on the real button underneath.
          child: IgnorePointer(
            child: ExcludeSemantics(
              child: AnimatedBuilder(
                animation: _grow,
                builder: (context, child) {
                  final t = Curves.easeOutCubic.transform(_grow.value);
                  return Transform.translate(
                    offset: Offset(_shift * t, 0),
                    child: Transform.scale(
                      scale: 1 + (pressedScale - 1) * t,
                      alignment: Alignment.bottomCenter,
                      child: child,
                    ),
                  );
                },
                child: KeyedSubtree(
                  key: const ValueKey('record-button-enlarged'),
                  child: face,
                ),
              ),
            ),
          ),
        ),
      ),
      child: CompositedTransformTarget(
        link: _link,
        child: Semantics(
          button: true,
          enabled: enabled,
          label: label,
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTapDown: !enabled
                ? null
                : (_) {
                    _pressWhileRecording = recording;
                    _enlarge();
                    if (recording) {
                      HapticFeedback.selectionClick();
                      _hold.forward(from: 0);
                    }
                  },
            onTapUp: (_) {
              _shrink();
              final wasRecording = _pressWhileRecording;
              _pressWhileRecording = null;
              if (wasRecording == null || !mounted) return;
              if (wasRecording) {
                // Let go before the ring filled: explain, do not stop.
                _hold.reverse();
                HapticFeedback.lightImpact();
                _say(l.holdToStop);
              } else {
                HapticFeedback.mediumImpact();
                _run(
                  ref.read(sessionProvider.notifier).startRecording,
                  (l) => l.recordingStarted,
                );
              }
            },
            onTapCancel: () {
              _shrink();
              if (_pressWhileRecording == true) _hold.reverse();
              _pressWhileRecording = null;
            },
            // Hidden while the enlarged copy is up, so only one button shows.
            child: Opacity(opacity: _portal.isShowing ? 0 : 1, child: face),
          ),
        ),
      ),
    );
  }
}
