import 'package:intl/intl.dart';

import '../l10n/l10n.dart';

/// Sizes keep their units in every language.
String formatBytes(int bytes) {
  const gb = 1024 * 1024 * 1024;
  const mb = 1024 * 1024;
  if (bytes >= gb) return '${(bytes / gb).toStringAsFixed(1)} GB';
  if (bytes >= mb) return '${(bytes / mb).toStringAsFixed(0)} MB';
  return '${(bytes / 1024).toStringAsFixed(0)} KB';
}

/// "3 s", "4 min 10 s", "2 h 5 min", "31 days".
String formatSpan(AppLocalizations l, Duration d) {
  final s = d.inSeconds.abs();
  if (s < 60) return l.spanSeconds(s);
  if (s < 3600) return l.spanMinutes(s ~/ 60, s % 60);
  if (s < 86400) return l.spanHours(s ~/ 3600, (s % 3600) ~/ 60);
  return l.spanDays(s ~/ 86400);
}

String _two(int n) => n.toString().padLeft(2, '0');

/// Times and dates as numbers read the same in every language.
String formatClock(DateTime t) =>
    '${_two(t.hour)}:${_two(t.minute)}:${_two(t.second)}';

String formatDateTime(DateTime t) =>
    '${t.year}-${_two(t.month)}-${_two(t.day)} ${formatClock(t)}';

/// "Wed 11 Nov 2026", in the user's language.
String formatDay(AppLocalizations l, DateTime t) =>
    DateFormat(l.dayPattern, l.localeName).format(t);
