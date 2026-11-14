import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Which side of the floating dock the record button sits on.
enum RecordButtonSide {
  left('Left'),
  right('Right');

  const RecordButtonSide(this.label);
  final String label;
}

final recordButtonSideProvider =
    NotifierProvider<RecordButtonSideController, RecordButtonSide>(
      RecordButtonSideController.new,
    );

/// Right by default: easiest to reach with the right thumb. Kept between launches.
class RecordButtonSideController extends Notifier<RecordButtonSide> {
  static const _key = 'record_button_side';

  @override
  RecordButtonSide build() {
    Future.microtask(_load);
    return RecordButtonSide.right;
  }

  Future<void> _load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final side = RecordButtonSide.values.asNameMap()[prefs.getString(_key)];
      if (side != null && ref.mounted) state = side;
    } catch (_) {
      // Storage unavailable: keep the default.
    }
  }

  Future<void> set(RecordButtonSide side) async {
    state = side;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_key, side.name);
    } catch (_) {}
  }
}
