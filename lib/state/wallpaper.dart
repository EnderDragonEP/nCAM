import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Reads the phone's wallpaper accent colour (Android 12+), or null where Android has
/// none. Overridden in tests.
final wallpaperColorReaderProvider = Provider<Future<Color?> Function()>(
  (ref) => () async {
    try {
      final argb = await const MethodChannel('ncam/camera')
          .invokeMethod<int>('wallpaperColor');
      return argb == null ? null : Color(argb);
    } catch (_) {
      return null;
    }
  },
);

/// The wallpaper accent colour. Re-read when the app comes back to the screen, so a
/// new wallpaper shows without restarting.
final wallpaperColorProvider = FutureProvider<Color?>(
  (ref) => ref.watch(wallpaperColorReaderProvider)(),
);
