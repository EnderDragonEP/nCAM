import 'dart:async';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

import '../l10n/l10n.dart';

/// Above this, filling the space would crop too much of the picture for a pinch to
/// snap to it (a wide clip on a tall screen); pinching then simply zooms. The fit
/// button can still fill.
const _maxFillCrop = 1.5;

/// How a picture sits in its space.
enum PictureFit {
  /// The whole picture, as large as it fits ("best fit"), with bars where its shape differs from the
  /// space's.
  whole,

  /// Filling the space ("zoomed to fill"), the edges cut off.
  fill,

  /// Zoomed in by hand.
  zoomed,
}

/// What a page's fit button does next with pictures that sit as [current]: anything
/// other than the whole picture goes back to it first; the whole picture goes to
/// filling.
PictureFit nextFit(Iterable<PictureFit> current) =>
    current.every((f) => f == PictureFit.whole)
    ? PictureFit.fill
    : PictureFit.whole;

/// Tells the pictures on a page how to sit (the page's fit button).
class FitCommand extends ChangeNotifier {
  PictureFit _fit = PictureFit.whole;

  /// The last fit asked for.
  PictureFit get fit => _fit;

  void apply(PictureFit fit) {
    _fit = fit;
    notifyListeners();
  }
}

/// Shows [child], a picture of [aspectRatio], the way the YouTube app does: the whole
/// picture to start with; pinch out to fill the space (cropping the edges a little),
/// pinch in to see the whole picture again, and keep pinching to zoom further, then
/// drag to look around. A short label says which it is. The page's fit button
/// ([fitCommand]) switches between the whole picture and filling.
///
/// Taps are left to the widgets around it.
class ZoomableView extends StatefulWidget {
  const ZoomableView({
    super.key,
    required this.aspectRatio,
    required this.child,
    this.onFitChanged,
    this.clip = true,
    this.fitCommand,
    this.onPinch,
  });

  /// Told when two fingers start to zoom (the page can get its controls out of the
  /// way).
  final VoidCallback? onPinch;

  /// Each time this notifies, the picture takes the fit it asks for.
  final FitCommand? fitCommand;

  /// Keep a zoomed picture inside the space; false lets it spread past the edges (the
  /// page around it decides what shows there).
  final bool clip;

  final double aspectRatio;
  final Widget child;

  /// Told each time the picture starts to sit differently.
  final ValueChanged<PictureFit>? onFitChanged;

  @override
  State<ZoomableView> createState() => ZoomableViewState();
}

class ZoomableViewState extends State<ZoomableView>
    with SingleTickerProviderStateMixin {
  /// 1 shows the whole picture; [_fillScale] fills the space.
  double _scale = 1;

  /// How far the picture's centre is from the space's centre, in pixels.
  Offset _offset = Offset.zero;
  PictureFit _fit = PictureFit.whole;
  Size _box = Size.zero;

  /// Filling was asked for with the fit button, so it stays even where a pinch would
  /// not snap to it.
  bool _fillChosen = false;

  double _startScale = 1;
  Offset _startOffset = Offset.zero;
  Offset _startFocal = Offset.zero;
  bool _pinched = false;

  late final AnimationController _settle = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 180),
  )..addListener(_onSettle);
  double _fromScale = 1, _toScale = 1;
  Offset _fromOffset = Offset.zero, _toOffset = Offset.zero;

  String? _label;
  Timer? _hideLabel;
  PictureFit _toldFit = PictureFit.whole;

  void _tellFit() {
    if (_fit == _toldFit) return;
    _toldFit = _fit;
    widget.onFitChanged?.call(_fit);
  }

  /// The zoom, where 1 is the whole picture.
  double get scale => _scale;

  /// How the picture sits now.
  PictureFit get fit => _fit;

  @override
  void initState() {
    super.initState();
    widget.fitCommand?.addListener(_onCommand);
  }

  @override
  void didUpdateWidget(ZoomableView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.fitCommand != widget.fitCommand) {
      oldWidget.fitCommand?.removeListener(_onCommand);
      widget.fitCommand?.addListener(_onCommand);
    }
  }

  @override
  void dispose() {
    widget.fitCommand?.removeListener(_onCommand);
    _settle.dispose();
    _hideLabel?.cancel();
    super.dispose();
  }

  void _onCommand() => setFit(widget.fitCommand!.fit);

  /// Shows the whole picture, or fills the space, centred.
  void setFit(PictureFit fit) {
    if (!mounted || fit == PictureFit.zoomed) return;
    _fit = fit;
    _fillChosen = fit == PictureFit.fill;
    _animateTo(fit == PictureFit.fill ? _fillScale(_box) : 1, Offset.zero);
    _tellFit();
    final l = context.l10n;
    _say(fit == PictureFit.fill ? l.zoomFill : l.zoomFit);
  }

  Size _fitSize(Size box) {
    final ar = widget.aspectRatio > 0 ? widget.aspectRatio : 16 / 9;
    if (box.isEmpty) return Size.zero;
    return box.width / box.height > ar
        ? Size(box.height * ar, box.height)
        : Size(box.width, box.width / ar);
  }

  double _fillScale(Size box) {
    final fit = _fitSize(box);
    if (fit.isEmpty) return 1;
    return math.max(box.width / fit.width, box.height / fit.height);
  }

  bool _fillIsAMode(Size box) {
    final fill = _fillScale(box);
    return fill > 1.01 && fill <= _maxFillCrop;
  }

  double _maxScale(Size box) => math.max(4, _fillScale(box) * 2);

  Offset _clampOffset(Offset o, double scale, Size box) {
    final fit = _fitSize(box);
    final dx = math.max(0.0, (fit.width * scale - box.width) / 2);
    final dy = math.max(0.0, (fit.height * scale - box.height) / 2);
    return Offset(o.dx.clamp(-dx, dx), o.dy.clamp(-dy, dy));
  }

  void _onSettle() {
    final t = Curves.easeOutCubic.transform(_settle.value);
    setState(() {
      _scale = _fromScale + (_toScale - _fromScale) * t;
      _offset = Offset.lerp(_fromOffset, _toOffset, t)!;
    });
  }

  void _animateTo(double scale, Offset offset) {
    _fromScale = _scale;
    _fromOffset = _offset;
    _toScale = scale;
    _toOffset = offset;
    _settle.forward(from: 0);
  }

  void _say(String text) {
    _hideLabel?.cancel();
    setState(() => _label = text);
    _hideLabel = Timer(const Duration(milliseconds: 1200), () {
      if (mounted) setState(() => _label = null);
    });
  }

  void _onStart(ScaleStartDetails d) {
    _settle.stop();
    _startScale = _scale;
    _startOffset = _offset;
    _startFocal = d.localFocalPoint;
    _pinched = d.pointerCount > 1;
    if (_pinched) widget.onPinch?.call();
  }

  void _onUpdate(ScaleUpdateDetails d) {
    if (d.pointerCount > 1 && !_pinched) {
      _pinched = true;
      widget.onPinch?.call();
    }
    final box = _box;
    final centre = box.center(Offset.zero);
    // Slightly past the ends while pinching, so the snap back can be felt.
    final scale = (_startScale * d.scale).clamp(0.8, _maxScale(box) * 1.1);
    // Keep the point under the fingers where it is.
    final under = (_startFocal - centre - _startOffset) / _startScale;
    final offset = d.localFocalPoint - centre - under * scale;
    setState(() {
      _scale = scale;
      _offset = _clampOffset(offset, scale, box);
      if (_pinched) _fit = PictureFit.zoomed;
    });
  }

  void _onEnd(ScaleEndDetails d) {
    final box = _box;
    final l = context.l10n;
    final fill = _fillScale(box);
    final fillMode = _fillIsAMode(box);
    double target;
    if (!_pinched) {
      // A drag: only the position changes.
      target = _scale;
      if (_offset != Offset.zero && _fit == PictureFit.fill) {
        _fit = PictureFit.zoomed;
      }
    } else if (_scale <= 1.02) {
      target = 1;
      _fit = PictureFit.whole;
    } else if (fillMode && _scale < fill) {
      // Between the two: pinching out fills, pinching in shows everything.
      final zoomingIn = _scale > _startScale;
      target = zoomingIn ? fill : 1;
      _fit = zoomingIn ? PictureFit.fill : PictureFit.whole;
    } else if (fillMode && _scale <= fill * 1.25) {
      // Just past filling: a pinch rarely stops exactly there.
      target = fill;
      _fit = PictureFit.fill;
    } else {
      target = _scale.clamp(1, _maxScale(box));
      _fit = PictureFit.zoomed;
    }
    if (_pinched) _fillChosen = false;
    _animateTo(
      target,
      _fit == PictureFit.zoomed
          ? _clampOffset(_offset, target, box)
          : Offset.zero,
    );
    _tellFit();
    if (_pinched) {
      _say(switch (_fit) {
        PictureFit.whole => l.zoomFit,
        PictureFit.fill => l.zoomFill,
        PictureFit.zoomed => l.zoomFactor(target.toStringAsFixed(1)),
      });
    }
  }

  /// A new size (the phone turned): keep showing everything, or keep filling.
  void _resize(Size box) {
    if (_box == box) return;
    _box = box;
    _settle.stop();
    switch (_fit) {
      case PictureFit.whole:
        _scale = 1;
        _offset = Offset.zero;
      case PictureFit.fill:
        if (_fillChosen || _fillIsAMode(box)) {
          _scale = _fillScale(box);
        } else {
          _scale = 1;
          _fit = PictureFit.whole;
        }
        _offset = Offset.zero;
      case PictureFit.zoomed:
        _scale = _scale.clamp(1, _maxScale(box));
        _offset = _clampOffset(_offset, _scale, box);
    }
    // Filling may have stopped making sense; say so once this frame is built.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _tellFit();
    });
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final box = constraints.biggest;
        _resize(box);
        final fit = _fitSize(box);
        final w = fit.width * _scale;
        final h = fit.height * _scale;
        return RawGestureDetector(
          // The whole space, bars beside the picture included, takes a pinch.
          behavior: HitTestBehavior.opaque,
          gestures: {
            _PinchRecognizer:
                GestureRecognizerFactoryWithHandlers<_PinchRecognizer>(
                  _PinchRecognizer.new,
                  (r) {
                    r
                      ..onStart = _onStart
                      ..onUpdate = _onUpdate
                      ..onEnd = _onEnd;
                  },
                ),
          },
          child: ClipRect(
            clipBehavior: widget.clip ? Clip.hardEdge : Clip.none,
            child: SizedBox.fromSize(
              size: box,
              child: Stack(
                clipBehavior: Clip.none,
                children: [
                  Positioned(
                    left: (box.width - w) / 2 + _offset.dx,
                    top: (box.height - h) / 2 + _offset.dy,
                    width: w,
                    height: h,
                    child: widget.child,
                  ),
                  if (_label != null)
                    Align(
                      alignment: const Alignment(0, -0.6),
                      child: IgnorePointer(
                        child: DecoratedBox(
                          decoration: BoxDecoration(
                            color: Colors.black54,
                            borderRadius: BorderRadius.circular(16),
                          ),
                          child: Padding(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 6,
                            ),
                            child: Text(
                              _label!,
                              style: const TextStyle(color: Colors.white),
                            ),
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

/// A page's fit button: shows the whole picture when anything else is on screen, and
/// fills the space when the whole picture is. Its icon and tooltip say which comes next.
class FitButton extends StatelessWidget {
  const FitButton({
    super.key,
    required this.current,
    required this.onPressed,
    this.color,
  });

  /// How the page's pictures sit now.
  final Iterable<PictureFit> current;

  /// Called with the fit to apply.
  final ValueChanged<PictureFit> onPressed;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final next = nextFit(current);
    final fill = next == PictureFit.fill;
    return IconButton(
      tooltip: fill ? l.zoomToFill : l.zoomToFit,
      color: color,
      icon: Icon(fill ? Icons.zoom_out_map : Icons.fit_screen_outlined),
      onPressed: () => onPressed(next),
    );
  }
}

/// Pinch and drag, but a second finger settles it at once: two fingers on the picture
/// are always a zoom, never a tap for the page around it, however little they move.
class _PinchRecognizer extends ScaleGestureRecognizer {
  @override
  void addAllowedPointer(PointerDownEvent event) {
    // The new finger is only counted once its down event arrives, after this.
    final second = pointerCount >= 1;
    super.addAllowedPointer(event);
    if (second) resolve(GestureDisposition.accepted);
  }
}

/// Width and height from a JPEG's frame header, or null if [bytes] does not have one.
Size? jpegSize(Uint8List bytes) {
  var i = 2; // after the start-of-image marker
  if (bytes.length < 4 || bytes[0] != 0xFF || bytes[1] != 0xD8) return null;
  while (i + 9 < bytes.length) {
    if (bytes[i] != 0xFF) return null;
    final marker = bytes[i + 1];
    if (marker == 0xFF) {
      i++; // padding
      continue;
    }
    final length = (bytes[i + 2] << 8) | bytes[i + 3];
    // Start-of-frame markers C0–CF, except C4 (tables), C8 and CC.
    if (marker >= 0xC0 &&
        marker <= 0xCF &&
        marker != 0xC4 &&
        marker != 0xC8 &&
        marker != 0xCC) {
      final height = (bytes[i + 5] << 8) | bytes[i + 6];
      final width = (bytes[i + 7] << 8) | bytes[i + 8];
      if (width == 0 || height == 0) return null;
      return Size(width.toDouble(), height.toDouble());
    }
    if (length < 2) return null;
    i += 2 + length;
  }
  return null;
}
