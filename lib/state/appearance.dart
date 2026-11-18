import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Where the app's colours come from.
enum ColorChoice {
  /// The phone's wallpaper colours (Android 12 and later). Blue where not available.
  wallpaper(Color(0xFF1565C0)),
  blue(Color(0xFF1565C0)),
  teal(Color(0xFF00796B)),
  green(Color(0xFF2E7D32)),
  orange(Color(0xFFEF6C00)),
  red(Color(0xFFC62828)),
  purple(Color(0xFF6A1B9A));

  const ColorChoice(this.seed);

  /// Seed for the colour scheme; for [wallpaper] this is only the fallback.
  final Color seed;
}

enum AppearanceMode {
  system,
  light,
  dark,

  /// Dark with true black backgrounds, which saves power on OLED screens.
  black,
}

class Appearance {
  const Appearance({
    this.color = ColorChoice.wallpaper,
    this.mode = AppearanceMode.system,
  });

  final ColorChoice color;
  final AppearanceMode mode;

  Appearance copyWith({ColorChoice? color, AppearanceMode? mode}) =>
      Appearance(color: color ?? this.color, mode: mode ?? this.mode);
}

final appearanceProvider = NotifierProvider<AppearanceController, Appearance>(
  AppearanceController.new,
);

/// The user's colour and light/dark choice, kept between launches.
class AppearanceController extends Notifier<Appearance> {
  static const _colorKey = 'appearance_color';
  static const _modeKey = 'appearance_mode';

  @override
  Appearance build() {
    Future.microtask(_load);
    return const Appearance();
  }

  Future<void> _load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final color = ColorChoice.values.asNameMap()[prefs.getString(_colorKey)];
      final mode = AppearanceMode.values.asNameMap()[prefs.getString(_modeKey)];
      if (!ref.mounted) return;
      state = state.copyWith(color: color, mode: mode);
    } catch (_) {
      // Keep the defaults.
    }
  }

  Future<void> setColor(ColorChoice color) async {
    state = state.copyWith(color: color);
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_colorKey, color.name);
    } catch (_) {}
  }

  Future<void> setMode(AppearanceMode mode) async {
    state = state.copyWith(mode: mode);
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_modeKey, mode.name);
    } catch (_) {}
  }
}
