import 'dart:async';
import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../camera/recordings.dart';

/// Longest name the app accepts.
const clipNameMaxLength = 60;

final clipNamesProvider =
    NotifierProvider<ClipNamesController, Map<String, String>>(
      ClipNamesController.new,
    );

/// The name the user gave [r], if any.
String? clipName(Map<String, String> names, Recording r) {
  for (final f in r.files) {
    final name = names[f.name];
    if (name != null) return name;
  }
  return null;
}

/// Names the user gives recordings, kept in the app (the files keep their camera
/// names, which the app relies on to pair front and rear and to match them with the
/// camera's copies). Stored per file, so a name follows a recording whichever of
/// its clips is on the phone. Kept between launches.
class ClipNamesController extends Notifier<Map<String, String>> {
  static const _key = 'clip_names';
  final _loaded = Completer<void>();

  /// The stored names, once they have been read.
  Future<void> get ready => _loaded.future;

  @override
  Map<String, String> build() {
    Future.microtask(_load);
    return const {};
  }

  Future<void> _load() async {
    var names = <String, String>{};
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_key);
      if (raw != null) {
        names = (jsonDecode(raw) as Map<String, dynamic>).map(
          (file, name) => MapEntry(file, name as String),
        );
      }
    } catch (_) {
      // Unreadable or unavailable: start without names.
    }
    if (ref.mounted) state = Map.unmodifiable(names);
    if (!_loaded.isCompleted) _loaded.complete();
  }

  Future<void> _save(Map<String, String> names) async {
    state = Map.unmodifiable(names);
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_key, jsonEncode(names));
    } catch (_) {}
  }

  /// Names [r]; an empty [name] removes it.
  Future<void> rename(Recording r, String name) async {
    await ready;
    final clean = name.trim().replaceAll(RegExp(r'\s+'), ' ');
    final names = Map.of(state);
    for (final f in r.files) {
      if (clean.isEmpty) {
        names.remove(f.name);
      } else {
        names[f.name] = clean.length > clipNameMaxLength
            ? clean.substring(0, clipNameMaxLength)
            : clean;
      }
    }
    await _save(names);
  }

  /// Drops the names of files that are no longer on the phone.
  Future<void> forget(Iterable<String> fileNames) async {
    await ready;
    final names = Map.of(state);
    var changed = false;
    for (final f in fileNames) {
      changed |= names.remove(f) != null;
    }
    if (changed) await _save(names);
  }
}
