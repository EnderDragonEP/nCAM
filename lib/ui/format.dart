String formatBytes(int bytes) {
  const gb = 1024 * 1024 * 1024;
  const mb = 1024 * 1024;
  if (bytes >= gb) return '${(bytes / gb).toStringAsFixed(1)} GB';
  if (bytes >= mb) return '${(bytes / mb).toStringAsFixed(0)} MB';
  return '${(bytes / 1024).toStringAsFixed(0)} KB';
}

/// "3 s", "4 min 10 s", "2 h 5 min", "31 days".
String formatSpan(Duration d) {
  final s = d.inSeconds.abs();
  if (s < 60) return '$s s';
  if (s < 3600) return '${s ~/ 60} min ${s % 60} s';
  if (s < 86400) return '${s ~/ 3600} h ${(s % 3600) ~/ 60} min';
  final days = s ~/ 86400;
  return days == 1 ? '1 day' : '$days days';
}

String _two(int n) => n.toString().padLeft(2, '0');

String formatClock(DateTime t) =>
    '${_two(t.hour)}:${_two(t.minute)}:${_two(t.second)}';

String formatDateTime(DateTime t) =>
    '${t.year}-${_two(t.month)}-${_two(t.day)} ${formatClock(t)}';
