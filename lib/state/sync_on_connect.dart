import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

final syncOnConnectProvider = NotifierProvider<SyncOnConnectController, bool>(
  SyncOnConnectController.new,
);

/// Whether the camera's clock is set to the phone's every time the app connects. On by
/// default: the camera loses its clock when it loses power. The Sync time button on the
/// home page works either way. Kept between launches.
class SyncOnConnectController extends Notifier<bool> {
  static const _key = 'sync_on_connect';
  final _loaded = Completer<bool>();

  /// The stored choice, once it has been read.
  Future<bool> get ready => _loaded.future;

  @override
  bool build() {
    Future.microtask(_load);
    return true;
  }

  Future<void> _load() async {
    var value = true;
    try {
      final prefs = await SharedPreferences.getInstance();
      value = prefs.getBool(_key) ?? true;
    } catch (_) {
      // Storage unavailable: keep the default.
    }
    if (ref.mounted) state = value;
    if (!_loaded.isCompleted) _loaded.complete(value);
  }

  Future<void> set(bool value) async {
    state = value;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_key, value);
    } catch (_) {}
  }
}
