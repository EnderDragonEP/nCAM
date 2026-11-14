import 'dart:async';

import 'package:shared_preferences/shared_preferences.dart';

/// Runs before every test file: settings that the app keeps in shared preferences
/// (appearance, auto-connect) start out empty, in memory, instead of waiting for the
/// Android storage that tests do not have.
Future<void> testExecutable(FutureOr<void> Function() testMain) async {
  SharedPreferences.setMockInitialValues({});
  await testMain();
}
