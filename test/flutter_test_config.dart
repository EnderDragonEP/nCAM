import 'dart:async';

import 'package:intl/date_symbol_data_local.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Runs before every test file: settings that the app keeps in shared preferences
/// (appearance, auto-connect) start out empty, in memory, instead of waiting for the
/// Android storage that tests do not have. Date names are loaded for every language,
/// as the app's localizations do when it starts.
Future<void> testExecutable(FutureOr<void> Function() testMain) async {
  SharedPreferences.setMockInitialValues({});
  await initializeDateFormatting();
  await testMain();
}
