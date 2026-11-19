import 'dart:async';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

import '../l10n/l10n.dart';

/// Above this, filling the space would crop too much of the picture to be a sensible
/// "mode" (a wide clip on a tall screen); pinching then simply zooms.
const _maxFillCrop = 1.5;

/// Shows [child], a picture of [aspectRatio], the way the YouTube app does: the whole
/// picture to start with; pinch out to fill the space (cropping the edges a little),
/// pinch in to see the whole picture again, and keep pinching to zoom further, then
/// drag to look around. A short label says which it is.
///
/// Taps are left to the widgets around it.
class ZoomableView extends StatefulWidget {
  const ZoomableView({
    super.key,
    required this.aspectRatio,
    required this.child,
  });

  final double aspectRatio;
  final Widget child;

  @override
  State<ZoomableView> createState() => ZoomableViewState();
}

enum _Mode { fit, fill, zoom }

class ZoomableViewState extends State<ZoomableView>
    with SingleTickerProviderStateMixin {
  /// 1 shows the whole picture; [_fillScale] fills the space.
  double _scale = 1;

  /// How far the picture's centre is from the space's centre, in pixels.
  Offset _offset = Offset.zero;
  _Mode _mode = _Mode.fit;
  Size _box = Size.zero;

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

  /// The zoom, where 1 is the whole picture.
  double get scale => _scale;

  @override
  void dispose() {
    _settle.dispose();
    _hideLabel?.cancel();
    super.dispose();
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
  }

  void _onUpdate(ScaleUpdateDetails d) {
    if (d.pointerCount > 1) _pinched = true;
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
      _mode = _Mode.zoom;
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
      _mode = _scale <= 1.001
          ? _Mode.fit
          : (fillMode && (_scale - fill).abs() < 0.001)
          ? _Mode.fill
          : _Mode.zoom;
    } else if (_scale <= 1.02) {
      target = 1;
      _mode = _Mode.fit;
    } else if (fillMode && _scale < fill) {
      // Between the two: pinching out fills, pinching in shows everything.
      final zoomingIn = _scale > _startScale;
      target = zoomingIn ? fill : 1;
      _mode = zoomingIn ? _Mode.fill : _Mode.fit;
    } else if (fillMode && _scale <= fill * 1.25) {
      // Just past filling: a pinch rarely stops exactly there.
      target = fill;
      _mode = _Mode.fill;
    } else {
      target = _scale.clamp(1, _maxScale(box));
      _mode = _Mode.zoom;
    }
    _animateTo(target, _clampOffset(_offset, target, box));
    if (_pinched) {
      _say(switch (_mode) {
        _Mode.fit => l.zoomOriginal,
        _Mode.fill => l.zoomFill,
        _Mode.zoom => l.zoomFactor(target.toStringAsFixed(1)),
      });
    }
  }

  /// A new size (the phone turned): keep showing everything, or keep filling.
  void _resize(Size box) {
    if (_box == box) return;
    _box = box;
    _settle.stop();
    switch (_mode) {
      case _Mode.fit:
        _scale = 1;
        _offset = Offset.zero;
      case _Mode.fill:
        if (_fillIsAMode(box)) {
          _scale = _fillScale(box);
        } else {
          _scale = 1;
          _mode = _Mode.fit;
        }
        _offset = Offset.zero;
      case _Mode.zoom:
        _scale = _scale.clamp(1, _maxScale(box));
        _offset = _clampOffset(_offset, _scale, box);
    }
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
            child: SizedBox.fromSize(
              size: box,
              child: Stack(
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
