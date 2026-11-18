import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../l10n/l10n.dart';

/// What the page on screen allows for picture-in-picture.
class PipConfig {
  const PipConfig({
    required this.available,
    required this.autoEnter,
    this.aspectWidth = 16,
    this.aspectHeight = 9,
    this.actions = const [],
  });

  /// The page has something to show in a floating window.
  final bool available;

  /// Go into the window by itself when the user leaves the app.
  final bool autoEnter;
  final int aspectWidth;
  final int aspectHeight;

  /// Buttons in the window: `play`, `pause`, `rewind`, `forward`.
  final List<String> actions;
}

sealed class PipEvent {
  const PipEvent();
}

/// The window opened, or went away; [closed] when the user dismissed it rather than
/// expanding it back to full screen.
class PipChanged extends PipEvent {
  const PipChanged({required this.inPip, required this.closed});
  final bool inPip;
  final bool closed;
}

class PipAction extends PipEvent {
  const PipAction(this.name);
  final String name;
}

/// Android's picture-in-picture. Faked in tests.
abstract class PipPlatform {
  Future<bool> supported();
  Future<void> configure(PipConfig config);

  /// Shrinks the app into the window now. False if Android refused (for example when
  /// picture-in-picture is turned off for the app in Android settings).
  Future<bool> enter();
  Stream<PipEvent> get events;
}

class MethodChannelPipPlatform implements PipPlatform {
  MethodChannelPipPlatform() {
    _channel.setMethodCallHandler((call) async {
      switch (call.method) {
        case 'changed':
          final m = (call.arguments as Map).cast<String, Object?>();
          _events.add(
            PipChanged(inPip: m['inPip'] == true, closed: m['closed'] == true),
          );
        case 'action':
          _events.add(PipAction(call.arguments as String));
      }
    });
  }

  static const _channel = MethodChannel('ncam/pip');
  final _events = StreamController<PipEvent>.broadcast();

  @override
  Stream<PipEvent> get events => _events.stream;

  @override
  Future<bool> supported() async {
    try {
      return await _channel.invokeMethod<bool>('supported') ?? false;
    } catch (_) {
      return false;
    }
  }

  @override
  Future<void> configure(PipConfig config) async {
    try {
      await _channel.invokeMethod<void>('configure', {
        'available': config.available,
        'autoEnter': config.autoEnter,
        'aspectWidth': config.aspectWidth,
        'aspectHeight': config.aspectHeight,
        'actions': config.actions,
      });
    } catch (_) {}
  }

  @override
  Future<bool> enter() async {
    try {
      return await _channel.invokeMethod<bool>('enter') ?? false;
    } catch (_) {
      return false;
    }
  }
}

/// Records what the app asks of picture-in-picture; tests drive [emit].
class FakePipPlatform implements PipPlatform {
  final configs = <PipConfig>[];
  int enterCalls = 0;
  bool allowEnter = true;
  final _events = StreamController<PipEvent>.broadcast();

  PipConfig? get last => configs.isEmpty ? null : configs.last;

  void emit(PipEvent event) => _events.add(event);

  @override
  Stream<PipEvent> get events => _events.stream;

  @override
  Future<bool> supported() async => true;

  @override
  Future<void> configure(PipConfig config) async => configs.add(config);

  @override
  Future<bool> enter() async {
    enterCalls++;
    if (!allowEnter) return false;
    emit(const PipChanged(inPip: true, closed: false));
    return true;
  }
}

final pipPlatformProvider = Provider<PipPlatform>(
  (ref) => MethodChannelPipPlatform(),
);

final pipAutoEnterProvider = NotifierProvider<PipAutoEnterController, bool>(
  PipAutoEnterController.new,
);

/// Whether Live view and a playing clip go into a floating window by themselves when
/// the user leaves the app. On by default; kept between launches.
class PipAutoEnterController extends Notifier<bool> {
  static const _key = 'pip_auto_enter';

  @override
  bool build() {
    Future.microtask(_load);
    return true;
  }

  Future<void> _load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final value = prefs.getBool(_key);
      if (value != null && ref.mounted) state = value;
    } catch (_) {}
  }

  Future<void> set(bool value) async {
    state = value;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_key, value);
    } catch (_) {}
  }
}

/// One page that can go into the window, and what it wants from it.
class PipRequest {
  PipRequest({
    required this.autoEnter,
    this.aspectWidth = 16,
    this.aspectHeight = 9,
    this.actions = const [],
    this.onAction,
    this.onClosed,
  });

  bool autoEnter;
  int aspectWidth;
  int aspectHeight;
  List<String> actions;
  void Function(String action)? onAction;
  VoidCallback? onClosed;
}

class PipState {
  const PipState({this.inPip = false});
  final bool inPip;
}

final pipProvider = NotifierProvider<PipController, PipState>(
  PipController.new,
);

/// Keeps Android's picture-in-picture in step with the page on screen. Pages register
/// with [PipHost]; the most recently opened one is in charge.
class PipController extends Notifier<PipState> {
  final List<PipRequest> _requests = [];
  late PipPlatform _platform;

  @override
  PipState build() {
    _platform = ref.watch(pipPlatformProvider);
    final sub = _platform.events.listen(_onEvent);
    ref.onDispose(sub.cancel);
    ref.listen(pipAutoEnterProvider, (_, _) => _push());
    return const PipState();
  }

  void _onEvent(PipEvent event) {
    final top = _requests.isEmpty ? null : _requests.last;
    switch (event) {
      case PipChanged(:final inPip, :final closed):
        state = PipState(inPip: inPip);
        if (closed) top?.onClosed?.call();
      case PipAction(:final name):
        top?.onAction?.call(name);
    }
  }

  void register(PipRequest request) {
    _requests.add(request);
    _push();
  }

  void unregister(PipRequest request) {
    _requests.remove(request);
    _push();
  }

  /// Call after changing a registered request.
  void update() => _push();

  Future<bool> enter() => _platform.enter();

  void _push() {
    final top = _requests.isEmpty ? null : _requests.last;
    _platform.configure(
      PipConfig(
        available: top != null,
        autoEnter:
            top != null && top.autoEnter && ref.read(pipAutoEnterProvider),
        aspectWidth: top?.aspectWidth ?? 16,
        aspectHeight: top?.aspectHeight ?? 9,
        actions: top?.actions ?? const [],
      ),
    );
  }
}

/// Lets the page below it go into a floating window. While in the window, [pipChild]
/// (just the picture) is shown instead of [child].
class PipHost extends ConsumerStatefulWidget {
  const PipHost({
    super.key,
    required this.child,
    required this.pipChild,
    this.autoEnter = true,
    this.aspectRatio = 16 / 9,
    this.actions = const [],
    this.onAction,
    this.onClosed,
  });

  final Widget child;
  final Widget pipChild;
  final bool autoEnter;
  final double aspectRatio;
  final List<String> actions;
  final void Function(String action)? onAction;

  /// The user dismissed the window: stop what was playing.
  final VoidCallback? onClosed;

  @override
  ConsumerState<PipHost> createState() => _PipHostState();
}

class _PipHostState extends ConsumerState<PipHost> {
  late final PipController _controller;
  late final PipRequest _request;

  void _copy() {
    final ratio = widget.aspectRatio.isFinite && widget.aspectRatio > 0
        ? widget.aspectRatio
        : 16 / 9;
    _request
      ..autoEnter = widget.autoEnter
      ..aspectWidth = (ratio * 1000).round()
      ..aspectHeight = 1000
      ..actions = widget.actions
      ..onAction = widget.onAction
      ..onClosed = widget.onClosed;
  }

  @override
  void initState() {
    super.initState();
    _controller = ref.read(pipProvider.notifier);
    _request = PipRequest(autoEnter: widget.autoEnter);
    _copy();
    _controller.register(_request);
  }

  @override
  void didUpdateWidget(PipHost old) {
    super.didUpdateWidget(old);
    final changed =
        old.autoEnter != widget.autoEnter ||
        old.aspectRatio != widget.aspectRatio ||
        old.actions.join(',') != widget.actions.join(',');
    _copy();
    if (changed) _controller.update();
  }

  @override
  void dispose() {
    _controller.unregister(_request);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final inPip = ref.watch(pipProvider.select((s) => s.inPip));
    return inPip ? widget.pipChild : widget.child;
  }
}

/// App-bar button that shrinks the page into the window.
class PipButton extends ConsumerWidget {
  const PipButton({super.key, this.color});
  final Color? color;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = context.l10n;
    return IconButton(
      tooltip: l.pipTooltip,
      color: color,
      icon: const Icon(Icons.picture_in_picture_alt_outlined),
      onPressed: () async {
        final messenger = ScaffoldMessenger.maybeOf(context);
        final ok = await ref.read(pipProvider.notifier).enter();
        if (!ok) {
          messenger?.showSnackBar(SnackBar(content: Text(l.pipUnavailable)));
        }
      },
    );
  }
}
